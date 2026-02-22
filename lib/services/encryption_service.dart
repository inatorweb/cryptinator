import 'dart:io';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as path;

/// Secure file encryption using XChaCha20-Poly1305 and Argon2id
class EncryptionService {
  // Cryptographic parameters
  static const int saltSize = 16; // 128 bits
  static const int keySize = 32; // 256 bits
  static const int nonceSize = 24; // 192 bits for XChaCha20

  // Argon2id parameters
  static const int argon2Memory = 65536; // 64 MB in KB
  static const int argon2Iterations = 10;
  static const int argon2Parallelism = 4;

  // File format markers
  static final Uint8List fileMarker = Uint8List.fromList([0x43, 0x52, 0x59, 0x50]); // "CRYP"
  static const int fileVersion = 6; // Version 6 = v5 + content-type prefix

  // Content type prefixes (prepended to plaintext before encryption)
  static const int contentTypeFile = 0x00;
  static const int contentTypeFolder = 0x01;

  // Maximum file size (2 GB)
  static const int maxFileSize = 2147483648; // 2 GB

  // Rate limiting for decryption attempts
  int _failedAttempts = 0;
  static const int _maxAttemptsBeforeDelay = 3;
  static const int _baseDelaySeconds = 2;

  // Use Flutter's native implementations for better performance
  late final Xchacha20 _cipher;
  late final Argon2id _argon2;

  EncryptionService() {
    // Initialize with Flutter's native implementations
    FlutterCryptography.enable();
    _cipher = Xchacha20.poly1305Aead();
    _argon2 = Argon2id(
      memory: argon2Memory,
      iterations: argon2Iterations,
      parallelism: argon2Parallelism,
      hashLength: keySize,
    );
  }

  /// Generate cryptographically secure random bytes
  Uint8List _generateRandomBytes(int length) {
    final data = SecretKeyData.random(length: length);
    final bytes = Uint8List.fromList(data.bytes);
    data.destroy();
    return bytes;
  }

  /// Zero out a byte array to clear sensitive data from memory
  void _zeroOut(List<int> data) {
    for (int i = 0; i < data.length; i++) {
      data[i] = 0;
    }
  }

  /// Check and enforce rate limiting for decryption
  Future<void> _enforceRateLimit() async {
    if (_failedAttempts >= _maxAttemptsBeforeDelay) {
      // Exponential backoff: 2s, 4s, 8s, 16s... capped at 30s
      final delaySeconds = (_baseDelaySeconds *
              (1 << (_failedAttempts - _maxAttemptsBeforeDelay)))
          .clamp(0, 30);
      await Future.delayed(Duration(seconds: delaySeconds));
    }
  }

  /// Reset rate limiting after successful decryption
  void _resetRateLimit() {
    _failedAttempts = 0;
  }

  /// Record a failed decryption attempt
  void _recordFailedAttempt() {
    _failedAttempts++;
  }

  /// Get the current rate limit delay in seconds (for UI display)
  int get rateLimitDelay {
    if (_failedAttempts < _maxAttemptsBeforeDelay) return 0;
    return (_baseDelaySeconds *
            (1 << (_failedAttempts - _maxAttemptsBeforeDelay)))
        .clamp(0, 30);
  }

  /// Get the number of failed attempts
  int get failedAttempts => _failedAttempts;

  /// Encrypt a file or folder with XChaCha20-Poly1305
  Future<bool> encryptFile({
    required String inputPath,
    required String outputPath,
    required String password,
    void Function(String)? onProgress,
  }) async {
    Uint8List? dataToEncrypt;
    Uint8List? salt;
    Uint8List? nonce;
    SecretKey? secretKey;

    try {
      final inputEntity = FileSystemEntity.typeSync(inputPath);
      int contentType;
      String actualOutputPath = outputPath;

      if (inputEntity == FileSystemEntityType.directory) {
        // Compress folder to ZIP first
        onProgress?.call('Compressing folder...');
        dataToEncrypt = await _compressFolder(inputPath, onProgress);
        contentType = contentTypeFolder;
      } else {
        // Check file size before reading
        final fileSize = await File(inputPath).length();
        if (fileSize > maxFileSize) {
          throw Exception(
              'File too large. Maximum size is ${_formatSize(maxFileSize)}.');
        }

        // Read file directly
        onProgress?.call('Reading file...');
        dataToEncrypt = await File(inputPath).readAsBytes();
        contentType = contentTypeFile;
      }

      // Ensure output has .crypt extension
      if (!actualOutputPath.endsWith('.crypt')) {
        actualOutputPath = '$actualOutputPath.crypt';
      }

      // Prepend content type byte to plaintext
      final prefixedData = Uint8List(1 + dataToEncrypt.length);
      prefixedData[0] = contentType;
      prefixedData.setRange(1, prefixedData.length, dataToEncrypt);

      // Clear original data buffer
      _zeroOut(dataToEncrypt);
      dataToEncrypt = prefixedData;

      onProgress?.call('Deriving key...');

      // Generate random salt and nonce
      salt = _generateRandomBytes(saltSize);
      nonce = _generateRandomBytes(nonceSize);

      // Derive key using Argon2id
      secretKey = await _argon2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );

      onProgress?.call('Encrypting...');

      // Encrypt with XChaCha20-Poly1305
      final secretBox = await _cipher.encrypt(
        dataToEncrypt,
        secretKey: secretKey,
        nonce: nonce,
      );

      // Clear plaintext from memory
      _zeroOut(dataToEncrypt);

      // Write encrypted file
      onProgress?.call('Writing file...');
      await _writeEncryptedFile(
        actualOutputPath,
        salt,
        nonce,
        Uint8List.fromList(secretBox.cipherText),
        Uint8List.fromList(secretBox.mac.bytes),
      );

      onProgress?.call('Done!');
      return true;
    } catch (e) {
      onProgress?.call('Encryption failed');
      return false;
    } finally {
      // Clear sensitive data from memory
      if (dataToEncrypt != null) _zeroOut(dataToEncrypt);
      if (salt != null) _zeroOut(salt);
      if (nonce != null) _zeroOut(nonce);
      if (secretKey != null) {
        try {
          secretKey.destroy();
        } catch (_) {}
      }
    }
  }

  /// Decrypt a .crypt file
  Future<bool> decryptFile({
    required String inputPath,
    required String outputPath,
    required String password,
    void Function(String)? onProgress,
  }) async {
    SecretKey? secretKey;
    Uint8List? plaintextBytes;

    try {
      // Enforce rate limiting
      await _enforceRateLimit();

      onProgress?.call('Reading encrypted file...');

      // Check file size before reading
      final fileSize = await File(inputPath).length();
      if (fileSize > maxFileSize + 1024) {
        // Allow small overhead for headers
        throw Exception(
            'File too large. Maximum size is ${_formatSize(maxFileSize)}.');
      }

      // Read and parse encrypted file
      final fileData = await File(inputPath).readAsBytes();

      // Verify file marker
      final headerSize = fileMarker.length + 1 + saltSize + nonceSize;
      if (fileData.length < headerSize + 16) {
        throw Exception('File too small or corrupted');
      }

      final marker = fileData.sublist(0, fileMarker.length);
      if (!_listEquals(marker, fileMarker)) {
        throw Exception('Invalid file format - not a Cryptinator file');
      }

      // Read version
      final version = fileData[fileMarker.length];
      if (version != fileVersion) {
        throw Exception('Unsupported file version: $version');
      }

      // Extract components
      int offset = fileMarker.length + 1;
      final salt = fileData.sublist(offset, offset + saltSize);
      offset += saltSize;
      final nonce = fileData.sublist(offset, offset + nonceSize);
      offset += nonceSize;

      // The rest is ciphertext + MAC (last 16 bytes is MAC)
      final encryptedData = fileData.sublist(offset);
      final cipherText = encryptedData.sublist(0, encryptedData.length - 16);
      final mac = encryptedData.sublist(encryptedData.length - 16);

      onProgress?.call('Deriving key...');

      // Derive key using same parameters
      secretKey = await _argon2.deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );

      onProgress?.call('Decrypting...');

      // Decrypt
      List<int> plaintext;
      try {
        final secretBox = SecretBox(
          cipherText,
          nonce: nonce,
          mac: Mac(mac),
        );

        plaintext = await _cipher.decrypt(
          secretBox,
          secretKey: secretKey,
        );
      } catch (e) {
        // Wrong password or corrupted file
        _recordFailedAttempt();
        return false;
      }

      // Successful decryption — reset rate limit
      _resetRateLimit();

      plaintextBytes = Uint8List.fromList(plaintext);

      // Determine content type from version 6 prefix byte
      if (plaintextBytes.isEmpty) {
        throw Exception('Decrypted data is empty');
      }

      final contentType = plaintextBytes[0];
      final contentData = plaintextBytes.sublist(1);
      final isFolder = (contentType == contentTypeFolder);

      if (isFolder) {
        onProgress?.call('Extracting folder...');
        await _extractZip(contentData, outputPath);
      } else {
        onProgress?.call('Writing file...');
        await File(outputPath).writeAsBytes(contentData);
      }

      // Clear plaintext from memory
      _zeroOut(plaintextBytes);

      onProgress?.call('Done!');
      return true;
    } catch (e) {
      // Clean up any partial output on failure
      try {
        if (await Directory(outputPath).exists()) {
          await Directory(outputPath).delete(recursive: true);
        } else if (await File(outputPath).exists()) {
          await File(outputPath).delete();
        }
      } catch (_) {}
      onProgress?.call('Decryption failed');
      return false;
    } finally {
      // Clear sensitive data from memory
      if (plaintextBytes != null) _zeroOut(plaintextBytes);
      if (secretKey != null) {
        try {
          secretKey.destroy();
        } catch (_) {}
      }
    }
  }

  /// Compress a folder to ZIP bytes
  Future<Uint8List> _compressFolder(
      String folderPath, void Function(String)? onProgress) async {
    final archive = Archive();
    final directory = Directory(folderPath);
    final basePath = directory.path;
    int totalSize = 0;

    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        final fileSize = await entity.length();
        totalSize += fileSize;

        // Check total size doesn't exceed limit
        if (totalSize > maxFileSize) {
          throw Exception(
              'Folder contents too large. Maximum total size is ${_formatSize(maxFileSize)}.');
        }

        final relativePath = path.relative(entity.path, from: basePath);

        // Validate relative path doesn't escape (defence in depth)
        if (relativePath.startsWith('..') ||
            path.isAbsolute(relativePath)) {
          continue; // Skip suspicious paths
        }

        onProgress?.call('Adding: $relativePath');

        final fileBytes = await entity.readAsBytes();
        final archiveFile =
            ArchiveFile(relativePath, fileBytes.length, fileBytes);
        archive.addFile(archiveFile);
      }
    }

    if (archive.files.isEmpty) {
      throw Exception('Folder is empty - nothing to encrypt');
    }

    final zipData = ZipEncoder().encode(archive);
    return Uint8List.fromList(zipData!);
  }

  /// Extract ZIP bytes to a folder — with Zip Slip protection
  Future<void> _extractZip(Uint8List zipData, String outputPath) async {
    final archive = ZipDecoder().decodeBytes(zipData);

    // ZIP bomb protection: check total decompressed size before extracting
    int totalDecompressedSize = 0;
    for (final file in archive) {
      if (file.isFile) {
        totalDecompressedSize += file.size;
        if (totalDecompressedSize > maxFileSize) {
          throw Exception(
              'Decompressed folder too large. Maximum total size is ${_formatSize(maxFileSize)}.');
        }
      }
    }

    // Resolve the canonical output directory path
    final outputDir = Directory(outputPath);
    await outputDir.create(recursive: true);
    final canonicalOutputPath =
        outputDir.resolveSymbolicLinksSync() + Platform.pathSeparator;

    for (final file in archive) {
      final filename = file.name;

      // Zip Slip protection: reject entries with path traversal
      if (filename.contains('..') || path.isAbsolute(filename)) {
        // Skip malicious entries silently
        continue;
      }

      final filePath = path.join(outputPath, filename);

      // Double-check: resolved path must stay within output directory
      if (file.isFile) {
        final outputFile = File(filePath);
        await outputFile.create(recursive: true);

        // Verify the created file is actually inside the output dir
        final canonicalFilePath = outputFile.resolveSymbolicLinksSync();
        if (!canonicalFilePath.startsWith(canonicalOutputPath)) {
          // Path escaped — delete and skip
          await outputFile.delete();
          continue;
        }

        await outputFile.writeAsBytes(file.content as List<int>);
      } else {
        final dir = Directory(filePath);
        await dir.create(recursive: true);

        // Verify directory is inside output dir
        final canonicalDirPath = dir.resolveSymbolicLinksSync();
        if (!canonicalDirPath.startsWith(canonicalOutputPath)) {
          await dir.delete(recursive: true);
          continue;
        }
      }
    }
  }

  /// Write encrypted file
  /// Format: [Marker 4B][Version 1B][Salt 16B][Nonce 24B][Ciphertext][MAC 16B]
  Future<void> _writeEncryptedFile(
    String outputPath,
    Uint8List salt,
    Uint8List nonce,
    Uint8List ciphertext,
    Uint8List mac,
  ) async {
    final output = File(outputPath);
    final sink = output.openWrite();

    sink.add(fileMarker);
    sink.add([fileVersion]);
    sink.add(salt);
    sink.add(nonce);
    sink.add(ciphertext);
    sink.add(mac);

    await sink.flush();
    await sink.close();

    // Verify the write completed with correct size
    final expectedSize = fileMarker.length + 1 + salt.length + nonce.length +
        ciphertext.length + mac.length;
    final actualSize = await output.length();
    if (actualSize != expectedSize) {
      // Clean up corrupt output
      try {
        await output.delete();
      } catch (_) {}
      throw Exception('Write verification failed — disk may be full');
    }
  }

  /// Compare two byte arrays in constant time
  bool _listEquals(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  /// Format file size for display
  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Generate unique output path to avoid overwriting
  String generateOutputPath(String inputPath, {bool encrypting = true}) {
    final dir = path.dirname(inputPath);
    final baseName = path.basenameWithoutExtension(inputPath);
    final ext = path.extension(inputPath);

    String outputPath;
    if (encrypting) {
      outputPath = path.join(dir, '$baseName$ext.crypt');
    } else {
      // Remove .crypt extension
      outputPath = path.join(dir, baseName);
    }

    // Add number if file exists
    int counter = 1;
    String finalPath = outputPath;
    while (File(finalPath).existsSync() || Directory(finalPath).existsSync()) {
      if (encrypting) {
        finalPath = path.join(dir, '${baseName}_$counter$ext.crypt');
      } else {
        final outBaseName = path.basenameWithoutExtension(outputPath);
        final outExt = path.extension(outputPath);
        finalPath = path.join(dir, '${outBaseName}_$counter$outExt');
      }
      counter++;
    }

    return finalPath;
  }
}
