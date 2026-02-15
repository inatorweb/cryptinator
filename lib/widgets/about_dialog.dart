import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as path;

/// About dialog showing app information and cryptographic details
class AboutDialog extends StatelessWidget {
  const AboutDialog({super.key});

  Future<void> _openLicenseFile(String filename) async {
    // Get the directory where the exe is located
    final exeDir = path.dirname(Platform.resolvedExecutable);
    final filePath = path.join(exeDir, filename);
    
    final file = File(filePath);
    if (await file.exists()) {
      // Open with default text editor
      if (Platform.isWindows) {
        await Process.run('notepad', [filePath]);
      } else if (Platform.isMacOS) {
        await Process.run('open', [filePath]);
      } else if (Platform.isLinux) {
        await Process.run('xdg-open', [filePath]);
      }
    }
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
                'Version 1.0.0',
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
                      onPressed: () => _openLicenseFile('LICENSE.txt'),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      child: Text('GPL v3 License', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _openLicenseFile('LICENSES.txt'),
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
                '© 2024-2025 Inator Ltd',
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
