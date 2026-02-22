import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptinator/services/encryption_service.dart';

void main() {
  late EncryptionService service;
  late Directory tempDir;

  setUp(() async {
    service = EncryptionService();
    tempDir = await Directory.systemTemp.createTemp('cryptinator_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('EncryptionService — file encryption', () {
    test('encrypt and decrypt round-trip preserves file content', () async {
      // Create a test file with known content
      final inputFile = File('${tempDir.path}/test_input.txt');
      final originalContent = 'Hello, Cryptinator! This is a test file.';
      await inputFile.writeAsString(originalContent);

      final encryptedPath = '${tempDir.path}/test_input.txt.crypt';
      final decryptedPath = '${tempDir.path}/test_input.txt';

      // Encrypt
      final encryptSuccess = await service.encryptFile(
        inputPath: inputFile.path,
        outputPath: encryptedPath,
        password: 'TestPassword123!',
      );
      expect(encryptSuccess, isTrue);
      expect(await File(encryptedPath).exists(), isTrue);

      // Delete the original so we can verify decryption produces it
      await inputFile.delete();

      // Decrypt
      final decryptedOutputPath = '${tempDir.path}/decrypted_output.txt';
      final decryptSuccess = await service.decryptFile(
        inputPath: encryptedPath,
        outputPath: decryptedOutputPath,
        password: 'TestPassword123!',
      );
      expect(decryptSuccess, isTrue);

      // Verify content matches
      final decryptedContent = await File(decryptedOutputPath).readAsString();
      expect(decryptedContent, equals(originalContent));
    });

    test('decrypt with wrong password returns false', () async {
      final inputFile = File('${tempDir.path}/test_wrong_pw.txt');
      await inputFile.writeAsString('Secret content');

      final encryptedPath = '${tempDir.path}/test_wrong_pw.txt.crypt';

      final encryptSuccess = await service.encryptFile(
        inputPath: inputFile.path,
        outputPath: encryptedPath,
        password: 'CorrectPassword1',
      );
      expect(encryptSuccess, isTrue);

      final decryptSuccess = await service.decryptFile(
        inputPath: encryptedPath,
        outputPath: '${tempDir.path}/should_not_exist.txt',
        password: 'WrongPassword!!1',
      );
      expect(decryptSuccess, isFalse);
    });

    test('encrypted file has correct magic bytes and version', () async {
      final inputFile = File('${tempDir.path}/test_header.txt');
      await inputFile.writeAsString('Header check test');

      final encryptedPath = '${tempDir.path}/test_header.txt.crypt';

      await service.encryptFile(
        inputPath: inputFile.path,
        outputPath: encryptedPath,
        password: 'TestPassword123!',
      );

      final bytes = await File(encryptedPath).readAsBytes();

      // Check magic bytes: "CRYP" = [0x43, 0x52, 0x59, 0x50]
      expect(bytes[0], equals(0x43));
      expect(bytes[1], equals(0x52));
      expect(bytes[2], equals(0x59));
      expect(bytes[3], equals(0x50));

      // Check version byte = 6
      expect(bytes[4], equals(6));

      // Check minimum file size: 4 (magic) + 1 (version) + 16 (salt) + 24 (nonce) + 1 (content type) + 16 (MAC) = 62
      expect(bytes.length, greaterThanOrEqualTo(62));
    });

    test('each encryption produces different ciphertext (unique salt/nonce)', () async {
      final inputFile = File('${tempDir.path}/test_unique.txt');
      await inputFile.writeAsString('Same content, different output');

      final encryptedPath1 = '${tempDir.path}/unique1.crypt';
      final encryptedPath2 = '${tempDir.path}/unique2.crypt';

      await service.encryptFile(
        inputPath: inputFile.path,
        outputPath: encryptedPath1,
        password: 'SamePassword123!',
      );

      await service.encryptFile(
        inputPath: inputFile.path,
        outputPath: encryptedPath2,
        password: 'SamePassword123!',
      );

      final bytes1 = await File(encryptedPath1).readAsBytes();
      final bytes2 = await File(encryptedPath2).readAsBytes();

      // Salt (bytes 5-20) should differ
      final salt1 = bytes1.sublist(5, 21);
      final salt2 = bytes2.sublist(5, 21);
      expect(salt1, isNot(equals(salt2)));
    });

    test('empty file encrypts and decrypts correctly', () async {
      final inputFile = File('${tempDir.path}/empty.txt');
      await inputFile.writeAsBytes([]);

      final encryptedPath = '${tempDir.path}/empty.txt.crypt';
      final decryptedPath = '${tempDir.path}/empty_decrypted.txt';

      final encryptSuccess = await service.encryptFile(
        inputPath: inputFile.path,
        outputPath: encryptedPath,
        password: 'TestPassword123!',
      );
      expect(encryptSuccess, isTrue);

      final decryptSuccess = await service.decryptFile(
        inputPath: encryptedPath,
        outputPath: decryptedPath,
        password: 'TestPassword123!',
      );
      expect(decryptSuccess, isTrue);

      final decryptedBytes = await File(decryptedPath).readAsBytes();
      expect(decryptedBytes, isEmpty);
    });

    test('binary file round-trip preserves content', () async {
      // Create file with all byte values 0-255
      final inputFile = File('${tempDir.path}/binary_test.bin');
      final binaryContent = Uint8List.fromList(
        List.generate(256, (i) => i),
      );
      await inputFile.writeAsBytes(binaryContent);

      final encryptedPath = '${tempDir.path}/binary_test.bin.crypt';
      final decryptedPath = '${tempDir.path}/binary_decrypted.bin';

      await service.encryptFile(
        inputPath: inputFile.path,
        outputPath: encryptedPath,
        password: 'TestPassword123!',
      );

      await service.decryptFile(
        inputPath: encryptedPath,
        outputPath: decryptedPath,
        password: 'TestPassword123!',
      );

      final decryptedBytes = await File(decryptedPath).readAsBytes();
      expect(decryptedBytes, equals(binaryContent));
    });
  });

  group('EncryptionService — folder encryption', () {
    test('folder encrypt and decrypt round-trip preserves files', () async {
      // Create a test folder with files
      final testFolder = Directory('${tempDir.path}/test_folder');
      await testFolder.create();
      await File('${testFolder.path}/file1.txt').writeAsString('Content 1');
      await File('${testFolder.path}/file2.txt').writeAsString('Content 2');

      final subFolder = Directory('${testFolder.path}/subfolder');
      await subFolder.create();
      await File('${subFolder.path}/file3.txt').writeAsString('Content 3');

      final encryptedPath = '${tempDir.path}/test_folder.crypt';
      final decryptedPath = '${tempDir.path}/test_folder_decrypted';

      final encryptSuccess = await service.encryptFile(
        inputPath: testFolder.path,
        outputPath: encryptedPath,
        password: 'FolderPass12345!',
      );
      expect(encryptSuccess, isTrue);

      final decryptSuccess = await service.decryptFile(
        inputPath: encryptedPath,
        outputPath: decryptedPath,
        password: 'FolderPass12345!',
      );
      expect(decryptSuccess, isTrue);

      // Verify extracted files
      expect(await File('$decryptedPath/file1.txt').readAsString(), equals('Content 1'));
      expect(await File('$decryptedPath/file2.txt').readAsString(), equals('Content 2'));
      expect(await File('$decryptedPath/subfolder/file3.txt').readAsString(), equals('Content 3'));
    });
  });

  group('EncryptionService — rate limiting', () {
    test('failed attempts increment counter', () async {
      final inputFile = File('${tempDir.path}/rate_test.txt');
      await inputFile.writeAsString('Rate limit test');

      final encryptedPath = '${tempDir.path}/rate_test.txt.crypt';

      await service.encryptFile(
        inputPath: inputFile.path,
        outputPath: encryptedPath,
        password: 'CorrectPass1234!',
      );

      expect(service.failedAttempts, equals(0));

      // Fail once
      await service.decryptFile(
        inputPath: encryptedPath,
        outputPath: '${tempDir.path}/fail1.txt',
        password: 'WrongPassword!!1',
      );
      expect(service.failedAttempts, equals(1));

      // Fail again
      await service.decryptFile(
        inputPath: encryptedPath,
        outputPath: '${tempDir.path}/fail2.txt',
        password: 'WrongPassword!!2',
      );
      expect(service.failedAttempts, equals(2));
    });

    test('successful decrypt resets failed counter', () async {
      final inputFile = File('${tempDir.path}/reset_test.txt');
      await inputFile.writeAsString('Reset test');

      final encryptedPath = '${tempDir.path}/reset_test.txt.crypt';

      await service.encryptFile(
        inputPath: inputFile.path,
        outputPath: encryptedPath,
        password: 'CorrectPass1234!',
      );

      // Fail twice
      await service.decryptFile(
        inputPath: encryptedPath,
        outputPath: '${tempDir.path}/fail.txt',
        password: 'WrongPassword!!1',
      );
      await service.decryptFile(
        inputPath: encryptedPath,
        outputPath: '${tempDir.path}/fail2.txt',
        password: 'WrongPassword!!2',
      );
      expect(service.failedAttempts, equals(2));

      // Succeed — should reset
      await service.decryptFile(
        inputPath: encryptedPath,
        outputPath: '${tempDir.path}/success.txt',
        password: 'CorrectPass1234!',
      );
      expect(service.failedAttempts, equals(0));
    });
  });

  group('EncryptionService — output path generation', () {
    test('generates unique paths for collisions', () async {
      final basePath = '${tempDir.path}/test.txt';
      await File(basePath).writeAsString('exists');

      final outputPath = service.generateOutputPath(basePath, encrypting: true);
      expect(outputPath, endsWith('.crypt'));

      // Create the first output so the next call generates a different one
      await File(outputPath).writeAsString('exists too');

      final outputPath2 = service.generateOutputPath(basePath, encrypting: true);
      expect(outputPath2, isNot(equals(outputPath)));
      expect(outputPath2, contains('_1'));
    });
  });

  group('EncryptionService — edge cases', () {
    test('decrypting a non-crypt file returns false', () async {
      final fakeFile = File('${tempDir.path}/fake.crypt');
      await fakeFile.writeAsString('This is not an encrypted file');

      final result = await service.decryptFile(
        inputPath: fakeFile.path,
        outputPath: '${tempDir.path}/output.txt',
        password: 'AnyPassword12345',
      );
      expect(result, isFalse);
    });

    test('decrypting a truncated file returns false', () async {
      // Create a valid encrypted file, then truncate it
      final inputFile = File('${tempDir.path}/trunc_input.txt');
      await inputFile.writeAsString('Truncation test');

      final encryptedPath = '${tempDir.path}/trunc.crypt';
      await service.encryptFile(
        inputPath: inputFile.path,
        outputPath: encryptedPath,
        password: 'TestPassword123!',
      );

      // Truncate to just the header
      final bytes = await File(encryptedPath).readAsBytes();
      await File(encryptedPath).writeAsBytes(bytes.sublist(0, 20));

      final result = await service.decryptFile(
        inputPath: encryptedPath,
        outputPath: '${tempDir.path}/trunc_output.txt',
        password: 'TestPassword123!',
      );
      expect(result, isFalse);
    });
  });
}
