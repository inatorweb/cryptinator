import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

/// About dialog showing app information and cryptographic details
class AboutDialog extends StatelessWidget {
  const AboutDialog({super.key});

  bool get _isMobile => Platform.isAndroid || Platform.isIOS;

  Future<void> _openLicenseFile(BuildContext context, String filename) async {
    if (_isMobile) {
      // On mobile, show license text in a new dialog
      await _showLicenseInApp(context, filename);
    } else {
      // On desktop, open with default text editor
      final exeDir = path.dirname(Platform.resolvedExecutable);
      final filePath = path.join(exeDir, filename);
      
      final file = File(filePath);
      if (await file.exists()) {
        if (Platform.isWindows) {
          await Process.run('notepad', [filePath]);
        } else if (Platform.isMacOS) {
          await Process.run('open', [filePath]);
        } else if (Platform.isLinux) {
          await Process.run('xdg-open', [filePath]);
        }
      }
    }
  }

  Future<void> _showLicenseInApp(BuildContext context, String filename) async {
    String content;
    try {
      content = await rootBundle.loadString('assets/$filename');
    } catch (_) {
      content = 'License file not found.';
    }

    if (!context.mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              filename == 'LICENSE.txt' ? 'GPL v3 License' : 'Open Source Licenses',
              style: TextStyle(fontSize: 16),
            ),
            backgroundColor: Color(0xFF0369a1),
            foregroundColor: Colors.white,
          ),
          body: SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: Text(
              content,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lock, color: Color(0xFF0369a1), size: 24),
          SizedBox(width: 8),
          Text('About Cryptinator', style: TextStyle(fontSize: 18)),
        ],
      ),
      content: SizedBox(
        width: 320,
        height: 320,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cryptinator',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Version 1.0.1',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
              SizedBox(height: 12),
              Text(
                'Secure file and folder encryption.',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 16),
              
              // Cryptographic specifications
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Security',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    SizedBox(height: 6),
                    _buildSpec('Encryption', 'XChaCha20-Poly1305'),
                    _buildSpec('Key Derivation', 'Argon2id'),
                    _buildSpec('Memory', '64 MB / 10 iterations'),
                    _buildSpec('Key Size', '256-bit'),
                  ],
                ),
              ),
              
              SizedBox(height: 16),
              
              // License links
              Text(
                'Licenses',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _openLicenseFile(context, 'LICENSE.txt'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text('GPL v3 License', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _openLicenseFile(context, 'LICENSES.txt'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text('Open Source', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
              
              SizedBox(height: 16),
              
              Text(
                '© 2024-2026 Inator Ltd',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
              Text(
                'www.inatorweb.com',
                style: TextStyle(fontSize: 10, color: Color(0xFF0369a1)),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Close'),
        ),
      ],
    );
  }

  Widget _buildSpec(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

/// Show the about dialog
void showAboutCryptinator(BuildContext context) {
  showDialog(
    context: context,
    builder: (context) => AboutDialog(),
  );
}
