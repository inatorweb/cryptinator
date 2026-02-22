import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../services/encryption_service.dart';
import '../services/context_menu_service.dart';
import '../widgets/password_dialog.dart';
import '../widgets/about_dialog.dart';
import 'package:path/path.dart' as path;

class MainScreen extends StatefulWidget {
  final List<String> initialFilePaths;
  
  const MainScreen({super.key, this.initialFilePaths = const []});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // Single file selection
  String? _selectedFilePath;
  String? _selectedFileName;
  
  // Multiple file selection
  List<String> _selectedFiles = [];
  
  String _fileStatusText = '';
  String _statusMessage = 'Ready';
  bool _isOperationInProgress = false;
  bool _isDragging = false;
  bool _contextMenuInstalled = false;
  bool _isFolder = false;

  final _encryptionService = EncryptionService();
  final _contextMenuService = ContextMenuService();
  
  // Share sheet listener (mobile only)
  StreamSubscription? _shareIntentSubscription;

  // Android method channel for saving to Downloads via MediaStore
  static const _storageChannel = MethodChannel('com.inatorweb.cryptinator/storage');

  bool get _isDesktop => Platform.isWindows || Platform.isMacOS || Platform.isLinux;
  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  /// Human-readable save location for status messages
  String get _saveLocationName {
    if (Platform.isIOS) return 'Files';
    if (Platform.isAndroid || Platform.isMacOS) return 'Downloads';
    return '';
  }

  /// Whether the output goes to a separate folder (not next to source)
  bool get _savesToSeparateLocation => Platform.isMacOS || _isMobile;

  /// On macOS (sandboxed), output goes to Downloads. Elsewhere, same directory as input.
  String _getOutputPath(String inputPath, {required bool encrypting}) {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      final downloadsDir = '$home/Downloads';
      final baseName = path.basenameWithoutExtension(inputPath);
      final ext = path.extension(inputPath);
      
      String outputPath;
      if (encrypting) {
        outputPath = path.join(downloadsDir, '$baseName$ext.crypt');
      } else {
        outputPath = path.join(downloadsDir, baseName);
      }
      
      // Handle collisions
      int counter = 1;
      String finalPath = outputPath;
      while (File(finalPath).existsSync() || Directory(finalPath).existsSync()) {
        if (encrypting) {
          finalPath = path.join(downloadsDir, '${baseName}_$counter$ext.crypt');
        } else {
          final outBaseName = path.basenameWithoutExtension(outputPath);
          final outExt = path.extension(outputPath);
          finalPath = path.join(downloadsDir, '${outBaseName}_$counter$outExt');
        }
        counter++;
      }
      return finalPath;
    }
    
    return _encryptionService.generateOutputPath(inputPath, encrypting: encrypting);
  }

  @override
  void initState() {
    super.initState();
    if (_isDesktop) {
      _checkContextMenuStatus();
    }
    if (_isMobile) {
      _initShareIntent();
    }
    // Load initial files from command-line arguments (context menu / Nautilus)
    if (widget.initialFilePaths.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.initialFilePaths.length == 1) {
          _handleDroppedFile(widget.initialFilePaths.first);
        } else {
          _handleMultipleFiles(widget.initialFilePaths);
        }
      });
    }
  }

  @override
  void dispose() {
    _shareIntentSubscription?.cancel();
    super.dispose();
  }

  void _initShareIntent() {
    // Handle files shared while app is running
    _shareIntentSubscription = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> files) {
      if (files.isNotEmpty) {
        final paths = files.map((f) => f.path).toList();
        if (paths.length == 1) {
          _handleDroppedFile(paths.first);
        } else {
          _handleMultipleFiles(paths);
        }
      }
    });

    // Handle files shared when app was closed
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> files) {
      if (files.isNotEmpty) {
        final paths = files.map((f) => f.path).toList();
        if (paths.length == 1) {
          _handleDroppedFile(paths.first);
        } else {
          _handleMultipleFiles(paths);
        }
      }
    });
  }

  Future<void> _checkContextMenuStatus() async {
    final installed = await _contextMenuService.isInstalled();
    setState(() {
      _contextMenuInstalled = installed;
    });
  }

  void _handleDroppedFile(String filePath) {
    final file = File(filePath);
    final dir = Directory(filePath);
    final isDir = dir.existsSync() && !file.existsSync();
    
    setState(() {
      _selectedFilePath = filePath;
      _selectedFileName = path.basename(filePath);
      _selectedFiles = [];
      _isFolder = isDir;
      
      if (isDir) {
        _fileStatusText = 'Folder selected';
      } else if (filePath.endsWith('.crypt')) {
        final fileSize = file.lengthSync();
        _fileStatusText = 'Encrypted file • ${_formatFileSize(fileSize)}';
      } else {
        final fileSize = file.lengthSync();
        _fileStatusText = _formatFileSize(fileSize);
      }
      _statusMessage = 'File selected';
    });
  }

  void _handleMultipleFiles(List<String> filePaths) {
    if (filePaths.length == 1) {
      _handleDroppedFile(filePaths.first);
      return;
    }
    
    int totalSize = 0;
    for (final filePath in filePaths) {
      final file = File(filePath);
      if (file.existsSync()) {
        totalSize += file.lengthSync();
      }
    }
    
    setState(() {
      _selectedFiles = filePaths;
      _selectedFilePath = null;
      _selectedFileName = null;
      _isFolder = false;
      _fileStatusText = '${filePaths.length} files • ${_formatFileSize(totalSize)}';
      _statusMessage = 'Multiple files selected';
    });
  }

  Future<void> _browseFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null && result.files.isNotEmpty) {
      final paths = result.files
          .where((f) => f.path != null)
          .map((f) => f.path!)
          .toList();
      
      if (paths.length == 1) {
        _handleDroppedFile(paths.first);
      } else if (paths.length > 1) {
        _handleMultipleFiles(paths);
      }
    }
  }

  Future<void> _browseFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result != null) {
      _handleDroppedFile(result);
    }
  }

  Future<void> _browse() async {
    // Combined browse for mobile - files only (no folder selection on mobile)
    if (_isMobile) {
      await _browseFile();
    }
  }

  Future<String?> _showMultiFileDialog() async {
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Encrypt ${_selectedFiles.length} Files'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('How would you like to encrypt these files?'),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop('bundle'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF16a34a),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('Bundle Together'),
            ),
            SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop('individual'),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 12),
              ),
              child: Text('Encrypt Individually'),
            ),
            SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveMobileOutput(String filePath) async {
    // If it's a directory (decrypted bundle), save each file individually
    if (await Directory(filePath).exists()) {
      final dir = Directory(filePath);
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          final fileName = path.basename(entity.path);
          await _saveToDownloads(entity.path, fileName);
        }
      }
      // Clean up the temp folder
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    } else {
      final fileName = path.basename(filePath);
      await _saveToDownloads(filePath, fileName);
    }
  }

  Future<void> _saveToDownloads(String filePath, String fileName) async {
    try {
      if (Platform.isAndroid) {
        // Use native MediaStore API via method channel
        await _storageChannel.invokeMethod('saveToDownloads', {
          'sourcePath': filePath,
          'fileName': fileName,
        });
      } else if (Platform.isIOS) {
        // iOS - use documents directory
        final downloadsDir = await getApplicationDocumentsDirectory();
        
        if (await downloadsDir.exists()) {
          final fileDir = path.dirname(filePath);
          if (fileDir == downloadsDir.path) return;
          
          String destPath = path.join(downloadsDir.path, fileName);
          String finalFileName = fileName;
          
          // Handle collisions
          if (await File(destPath).exists() || await Directory(destPath).exists()) {
            int counter = 1;
            final isCrypt = fileName.endsWith('.crypt');
            final nameWithoutCrypt = isCrypt
                ? fileName.substring(0, fileName.length - 6)
                : fileName;
            final innerBase = path.basenameWithoutExtension(nameWithoutCrypt);
            final innerExt = path.extension(nameWithoutCrypt);
            final outerExt = isCrypt ? '.crypt' : '';
            
            while (await File(destPath).exists() || await Directory(destPath).exists()) {
              finalFileName = '${innerBase}_$counter$innerExt$outerExt';
              destPath = path.join(downloadsDir.path, finalFileName);
              counter++;
            }
          }
          
          await File(filePath).copy(destPath);
        } else {
          throw Exception('Documents folder not found');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save file. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _encrypt() async {
    // Handle multiple files
    if (_selectedFiles.isNotEmpty) {
      final choice = await _showMultiFileDialog();
      if (choice == null) return;
      
      final password = await showPasswordDialog(
        context: context,
        isEncrypting: true,
        fileName: '${_selectedFiles.length} files',
      );
      
      if (password == null) return;
      
      if (choice == 'bundle') {
        await _encryptMultipleAsBundled(password);
      } else {
        await _encryptMultipleIndividually(password);
      }
      return;
    }
    
    // Single file/folder encryption
    if (_selectedFilePath == null) return;

    final password = await showPasswordDialog(
      context: context,
      isEncrypting: true,
      fileName: _selectedFileName,
    );

    if (password == null) return;

    setState(() {
      _isOperationInProgress = true;
      _statusMessage = 'Encrypting...';
    });

    try {
      final outputPath = _getOutputPath(
        _selectedFilePath!,
        encrypting: true,
      );

      final success = await _encryptionService.encryptFile(
        inputPath: _selectedFilePath!,
        outputPath: outputPath,
        password: password,
        onProgress: (msg) {
          setState(() {
            _statusMessage = msg;
          });
        },
      );

      if (success) {
        setState(() {
          _statusMessage = _savesToSeparateLocation
              ? '✓ Encrypted successfully — saved to $_saveLocationName'
              : '✓ Encrypted successfully';
        });

        // On mobile, copy to Downloads/Files
        if (_isMobile) {
          await _saveMobileOutput(outputPath);
        }

        // Auto-load the output file (skip when saved to separate location)
        if (!_savesToSeparateLocation) {
          _handleDroppedFile(outputPath);
        }
      } else {
        setState(() {
          _statusMessage = '✗ Encryption failed';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '✗ Operation failed. Please try again.';
      });
    } finally {
      setState(() {
        _isOperationInProgress = false;
      });
    }
  }

  Future<void> _encryptMultipleIndividually(String password) async {
    setState(() {
      _isOperationInProgress = true;
    });

    int successCount = 0;
    int failCount = 0;
    
    for (int i = 0; i < _selectedFiles.length; i++) {
      final filePath = _selectedFiles[i];
      final fileName = path.basename(filePath);
      
      setState(() {
        _statusMessage = 'Encrypting ${i + 1}/${_selectedFiles.length}: $fileName';
      });

      final outputPath = _getOutputPath(
        filePath,
        encrypting: true,
      );

      final success = await _encryptionService.encryptFile(
        inputPath: filePath,
        outputPath: outputPath,
        password: password,
        onProgress: null,
      );

      if (success) {
        successCount++;
        // On mobile, save each encrypted file to Downloads
        if (_isMobile) {
          try {
            await _saveToDownloads(outputPath, path.basename(outputPath));
          } catch (_) {}
        }
      } else {
        failCount++;
      }
    }

    setState(() {
      _isOperationInProgress = false;
      if (failCount == 0) {
        _statusMessage = _savesToSeparateLocation
            ? '✓ Encrypted $successCount files — saved to $_saveLocationName'
            : '✓ Encrypted $successCount files successfully';
      } else {
        _statusMessage = '⚠ Encrypted $successCount, failed $failCount';
      }
      _selectedFiles = [];
      _fileStatusText = '';
    });
  }

  Future<void> _encryptMultipleAsBundled(String password) async {
    setState(() {
      _isOperationInProgress = true;
      _statusMessage = 'Creating bundle...';
    });

    Directory? tempDir;

    try {
      tempDir = await Directory.systemTemp.createTemp('cryptinator_bundle_');

      for (final filePath in _selectedFiles) {
        final fileName = path.basename(filePath);
        await File(filePath).copy(path.join(tempDir.path, fileName));
      }

      final firstFileDir = path.dirname(_selectedFiles.first);
      final firstName = path.basenameWithoutExtension(_selectedFiles.first);
      final otherCount = _selectedFiles.length - 1;
      final bundleName = '${firstName}_and_${otherCount}_more';
      final outputPath = _getOutputPath(
        path.join(firstFileDir, bundleName),
        encrypting: true,
      );

      final success = await _encryptionService.encryptFile(
        inputPath: tempDir.path,
        outputPath: outputPath,
        password: password,
        onProgress: (msg) {
          setState(() {
            _statusMessage = msg;
          });
        },
      );

      if (success) {
        setState(() {
          _statusMessage = _savesToSeparateLocation
              ? '✓ Bundle encrypted — saved to $_saveLocationName'
              : '✓ Bundle encrypted successfully';
        });

        // On mobile, copy to Downloads/Files
        if (_isMobile) {
          await _saveMobileOutput(outputPath);
        }

        // Auto-load the output file (skip when saved to separate location)
        if (!_savesToSeparateLocation) {
          _handleDroppedFile(outputPath);
        }
      } else {
        setState(() {
          _statusMessage = '✗ Bundle encryption failed';
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '✗ Operation failed. Please try again.';
      });
    } finally {
      // Always clean up temp directory to avoid leaving unencrypted copies on disk
      if (tempDir != null && await tempDir.exists()) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
      setState(() {
        _isOperationInProgress = false;
      });
    }
  }

  Future<void> _decrypt() async {
    if (_selectedFilePath == null) return;

    final password = await showPasswordDialog(
      context: context,
      isEncrypting: false,
      fileName: _selectedFileName,
    );

    if (password == null) return;

    setState(() {
      _isOperationInProgress = true;
      _statusMessage = 'Decrypting...';
    });

    try {
      final outputPath = _getOutputPath(
        _selectedFilePath!,
        encrypting: false,
      );

      final success = await _encryptionService.decryptFile(
        inputPath: _selectedFilePath!,
        outputPath: outputPath,
        password: password,
        onProgress: (msg) {
          setState(() {
            _statusMessage = msg;
          });
        },
      );

      if (success) {
        setState(() {
          _statusMessage = _savesToSeparateLocation
              ? '✓ Decrypted successfully — saved to $_saveLocationName'
              : '✓ Decrypted successfully';
        });

        // On mobile, copy to Downloads/Files
        if (_isMobile) {
          await _saveMobileOutput(outputPath);
        }

        // Auto-load the output file (skip when saved to separate location)
        if (!_savesToSeparateLocation) {
          _handleDroppedFile(outputPath);
        }
      } else {
        final delay = _encryptionService.rateLimitDelay;
        final attempts = _encryptionService.failedAttempts;
        setState(() {
          if (delay > 0) {
            _statusMessage = '✗ Wrong password ($attempts failed attempts, ${delay}s delay)';
          } else {
            _statusMessage = '✗ Decryption failed - wrong password?';
          }
        });
      }
    } catch (e) {
      setState(() {
        _statusMessage = '✗ Operation failed. Please try again.';
      });
    } finally {
      setState(() {
        _isOperationInProgress = false;
      });
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _showHowToUse() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('How to Use Cryptinator'),
        content: SingleChildScrollView(
          child: Text(
            _isDesktop
                ? '1. Drag a file or folder into the drop zone\n'
                  '   (or click Browse Files/Folder)\n\n'
                  '2. Click Encrypt and enter a password\n\n'
                  '3. Your encrypted file (.crypt) is created\n\n'
                  '4. To decrypt, select the .crypt file\n'
                  '   and click Decrypt\n\n'
                  'Multiple files:\n'
                  '   Select multiple files and choose to\n'
                  '   encrypt individually or bundle together\n\n'
                  '⚠️ Remember your password!\n'
                  'Lost passwords cannot be recovered.'
                : '1. Tap the box to browse for files\n'
                  '   (or share files to Cryptinator)\n\n'
                  '2. Tap Encrypt and enter a password\n\n'
                  '3. Your encrypted file (.crypt) is created\n\n'
                  '4. To decrypt, select the .crypt file\n'
                  '   and tap Decrypt\n\n'
                  '⚠️ Remember your password!\n'
                  'Lost passwords cannot be recovered.',
            style: TextStyle(fontSize: 12),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Got it'),
          ),
        ],
      ),
    );
  }

  void _showToolsMenu() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tools'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isDesktop && !Platform.isMacOS)
              ListTile(
                leading: Icon(
                  _contextMenuInstalled ? Icons.check_circle : Icons.add_circle_outline,
                  color: _contextMenuInstalled ? Colors.green : Colors.grey,
                ),
                title: Text(_contextMenuInstalled
                    ? 'Uninstall Context Menu'
                    : 'Install Context Menu'),
                subtitle: Text(_contextMenuInstalled
                    ? 'Remove right-click integration'
                    : 'Add right-click "Encrypt with Cryptinator"'),
                onTap: () async {
                  final scaffoldMessenger = ScaffoldMessenger.of(this.context);
                  Navigator.pop(context);
                  
                  bool success;
                  if (_contextMenuInstalled) {
                    success = await _contextMenuService.uninstall();
                  } else {
                    success = await _contextMenuService.install();
                  }
                  
                  if (success) {
                    await _checkContextMenuStatus();
                    if (mounted) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(_contextMenuInstalled
                              ? 'Context menu installed'
                              : 'Context menu uninstalled'),
                        ),
                      );
                    }
                  }
                },
              ),
            if (!_isDesktop || Platform.isMacOS)
              ListTile(
                leading: Icon(Icons.info_outline),
                title: Text(Platform.isMacOS
                    ? 'Context menu not available'
                    : 'No tools available'),
                subtitle: Text(Platform.isMacOS
                    ? 'Not supported in sandboxed macOS apps'
                    : 'Desktop tools are not available on mobile'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  void _clearSelection() {
    setState(() {
      _selectedFilePath = null;
      _selectedFileName = null;
      _selectedFiles = [];
      _fileStatusText = '';
      _statusMessage = 'Ready';
      _isFolder = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isEncryptedFile = _selectedFilePath?.endsWith('.crypt') ?? false;
    final bool hasSelection = _selectedFilePath != null || _selectedFiles.isNotEmpty;
    final bool canEncrypt = hasSelection && !_isOperationInProgress && !isEncryptedFile;
    final bool canDecrypt = _selectedFilePath != null && !_isOperationInProgress && isEncryptedFile;

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: Color(0xFF0369a1),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  Icon(Icons.lock, color: Colors.white, size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cryptinator',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Secure File Encryption',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.help_outline, color: Colors.white, size: 22),
                    onPressed: _showHowToUse,
                    tooltip: 'How to use',
                  ),
                  if (_isDesktop)
                    IconButton(
                      icon: Icon(Icons.build_outlined, color: Colors.white, size: 22),
                      onPressed: _showToolsMenu,
                      tooltip: 'Tools',
                    ),
                  IconButton(
                    icon: Icon(Icons.info_outline, color: Colors.white, size: 22),
                    onPressed: () => showAboutCryptinator(context),
                    tooltip: 'About',
                  ),
                ],
              ),
            ),
          ),

          // Main content
          Expanded(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  // Selection zone
                  Expanded(
                    child: _isDesktop ? _buildDesktopDropZone(hasSelection) : _buildMobileSelectZone(hasSelection),
                  ),

                  SizedBox(height: 12),

                  // Browse buttons (desktop only)
                  if (_isDesktop) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isOperationInProgress ? null : _browseFile,
                            icon: Icon(Icons.file_open, size: 18),
                            label: Text('Browse Files'),
                          ),
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isOperationInProgress ? null : _browseFolder,
                            icon: Icon(Icons.folder_open, size: 18),
                            label: Text('Browse Folder'),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                  ],

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: canEncrypt ? _encrypt : null,
                          icon: Icon(Icons.lock, size: 18),
                          label: Text('Encrypt'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFF16a34a),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: canDecrypt ? _decrypt : null,
                          icon: Icon(Icons.lock_open, size: 18),
                          label: Text('Decrypt'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Color(0xFFea580c),
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Status bar
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              border: Border(
                top: BorderSide(color: Colors.blue.shade100),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  if (_isOperationInProgress) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        fontSize: 11,
                        color: _statusMessage.startsWith('✓')
                            ? Colors.green.shade700
                            : _statusMessage.startsWith('✗')
                                ? Colors.red.shade700
                                : Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopDropZone(bool hasSelection) {
    return DropTarget(
      onDragDone: (details) {
        if (details.files.length == 1) {
          _handleDroppedFile(details.files.first.path);
        } else if (details.files.length > 1) {
          _handleMultipleFiles(
            details.files.map((f) => f.path).toList(),
          );
        }
      },
      onDragEntered: (_) {
        setState(() {
          _isDragging = true;
        });
      },
      onDragExited: (_) {
        setState(() {
          _isDragging = false;
        });
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _isDragging
              ? Color(0xFF0369a1).withOpacity(0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _isDragging
                ? Color(0xFF0369a1)
                : Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: !hasSelection
            ? _buildEmptyDropZone()
            : _selectedFiles.isNotEmpty
                ? _buildMultipleFilesSelected()
                : _buildFileSelected(),
      ),
    );
  }

  Widget _buildMobileSelectZone(bool hasSelection) {
    return GestureDetector(
      onTap: _isOperationInProgress ? null : _browseFile,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.grey.shade300,
            width: 2,
          ),
        ),
        child: !hasSelection
            ? _buildEmptyMobileZone()
            : _selectedFiles.isNotEmpty
                ? _buildMultipleFilesSelected()
                : _buildFileSelected(),
      ),
    );
  }

  Widget _buildEmptyDropZone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.cloud_upload_outlined,
          size: 40,
          color: _isDragging ? Color(0xFF0369a1) : Colors.grey,
        ),
        SizedBox(height: 10),
        Text(
          _isDragging ? 'Drop files here' : 'Drag & drop files or folder here',
          style: TextStyle(
            fontSize: 13,
            color: _isDragging ? Color(0xFF0369a1) : Colors.grey.shade600,
            fontWeight: _isDragging ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'or use the browse buttons below',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyMobileZone() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.touch_app_outlined,
          size: 40,
          color: Colors.grey,
        ),
        SizedBox(height: 10),
        Text(
          'Tap to select files',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: 4),
        Text(
          'or share files to Cryptinator',
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade500,
          ),
        ),
      ],
    );
  }

  Widget _buildFileSelected() {
    final bool isEncryptedFile = _selectedFilePath?.endsWith('.crypt') ?? false;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          _isFolder
              ? Icons.folder
              : isEncryptedFile
                  ? Icons.lock
                  : Icons.insert_drive_file,
          size: 40,
          color: isEncryptedFile ? Color(0xFFea580c) : Color(0xFF0369a1),
        ),
        SizedBox(height: 10),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _selectedFileName ?? '',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ),
        SizedBox(height: 4),
        Text(
          _fileStatusText,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: 10),
        TextButton(
          onPressed: _isOperationInProgress ? null : _clearSelection,
          child: Text('Clear', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Widget _buildMultipleFilesSelected() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.file_copy,
          size: 40,
          color: Color(0xFF0369a1),
        ),
        SizedBox(height: 10),
        Text(
          '${_selectedFiles.length} files selected',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 4),
        Text(
          _fileStatusText,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey.shade600,
          ),
        ),
        SizedBox(height: 6),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            _selectedFiles.take(3).map((f) => path.basename(f)).join(', ') +
                (_selectedFiles.length > 3 ? '...' : ''),
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(height: 10),
        TextButton(
          onPressed: _isOperationInProgress ? null : _clearSelection,
          child: Text('Clear', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}
