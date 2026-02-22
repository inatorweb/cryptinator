import 'dart:io';

/// Context menu integration for Windows, macOS, and Linux
class ContextMenuService {
  /// Check if context menu is installed
  Future<bool> isInstalled() async {
    try {
      if (Platform.isWindows) {
        return await _isInstalledWindows();
      } else if (Platform.isMacOS) {
        return await _isInstalledMacOS();
      } else if (Platform.isLinux) {
        return await _isInstalledLinux();
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Install context menu integration
  Future<bool> install() async {
    try {
      if (Platform.isWindows) {
        return await _installWindows();
      } else if (Platform.isMacOS) {
        return await _installMacOS();
      } else if (Platform.isLinux) {
        return await _installLinux();
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Uninstall context menu integration
  Future<bool> uninstall() async {
    try {
      if (Platform.isWindows) {
        return await _uninstallWindows();
      } else if (Platform.isMacOS) {
        return await _uninstallMacOS();
      } else if (Platform.isLinux) {
        return await _uninstallLinux();
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // ===== WINDOWS IMPLEMENTATION =====

  Future<bool> _isInstalledWindows() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKEY_CURRENT_USER\Software\Classes\*\shell\Cryptinator',
      ]);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _installWindows() async {
    final exePath = Platform.resolvedExecutable;

    // Add main menu entry for all files
    var result = await Process.run('reg', [
      'add',
      r'HKEY_CURRENT_USER\Software\Classes\*\shell\Cryptinator',
      '/ve',
      '/d',
      'Encrypt with Cryptinator',
      '/f',
    ]);

    if (result.exitCode != 0) return false;

    // Add icon
    await Process.run('reg', [
      'add',
      r'HKEY_CURRENT_USER\Software\Classes\*\shell\Cryptinator',
      '/v',
      'Icon',
      '/d',
      exePath,
      '/f',
    ]);

    // Add encrypt command
    result = await Process.run('reg', [
      'add',
      r'HKEY_CURRENT_USER\Software\Classes\*\shell\Cryptinator\command',
      '/ve',
      '/d',
      '"$exePath" "%1"',
      '/f',
    ]);

    if (result.exitCode != 0) return false;

    // Register .crypt file type
    await Process.run('reg', [
      'add',
      r'HKEY_CURRENT_USER\Software\Classes\.crypt',
      '/ve',
      '/d',
      'Cryptinator.EncryptedFile',
      '/f',
    ]);

    // Add decrypt menu for .crypt files
    result = await Process.run('reg', [
      'add',
      r'HKEY_CURRENT_USER\Software\Classes\.crypt\shell\Cryptinator',
      '/ve',
      '/d',
      'Decrypt with Cryptinator',
      '/f',
    ]);

    if (result.exitCode != 0) return false;

    // Add icon for .crypt
    await Process.run('reg', [
      'add',
      r'HKEY_CURRENT_USER\Software\Classes\.crypt\shell\Cryptinator',
      '/v',
      'Icon',
      '/d',
      exePath,
      '/f',
    ]);

    // Add decrypt command
    result = await Process.run('reg', [
      'add',
      r'HKEY_CURRENT_USER\Software\Classes\.crypt\shell\Cryptinator\command',
      '/ve',
      '/d',
      '"$exePath" "%1"',
      '/f',
    ]);

    // Add folder encryption support
    await Process.run('reg', [
      'add',
      r'HKEY_CURRENT_USER\Software\Classes\Directory\shell\Cryptinator',
      '/ve',
      '/d',
      'Encrypt folder with Cryptinator',
      '/f',
    ]);

    await Process.run('reg', [
      'add',
      r'HKEY_CURRENT_USER\Software\Classes\Directory\shell\Cryptinator',
      '/v',
      'Icon',
      '/d',
      exePath,
      '/f',
    ]);

    await Process.run('reg', [
      'add',
      r'HKEY_CURRENT_USER\Software\Classes\Directory\shell\Cryptinator\command',
      '/ve',
      '/d',
      '"$exePath" "%1"',
      '/f',
    ]);

    return result.exitCode == 0;
  }

  Future<bool> _uninstallWindows() async {
    // Remove main menu
    await Process.run('reg', [
      'delete',
      r'HKEY_CURRENT_USER\Software\Classes\*\shell\Cryptinator',
      '/f',
    ]);

    // Remove .crypt menu
    await Process.run('reg', [
      'delete',
      r'HKEY_CURRENT_USER\Software\Classes\.crypt\shell\Cryptinator',
      '/f',
    ]);

    // Remove folder menu
    await Process.run('reg', [
      'delete',
      r'HKEY_CURRENT_USER\Software\Classes\Directory\shell\Cryptinator',
      '/f',
    ]);

    return true;
  }

  // ===== MACOS IMPLEMENTATION =====

  /// Escape a file path for safe embedding in a shell script
  String _shellEscape(String path) {
    // Replace single quotes with '\'' (end quote, escaped quote, start quote)
    return path.replaceAll("'", "'\\''");
  }

  /// Escape a string for safe embedding in XML/plist content
  String _xmlEscape(String value) {
    return value
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }

  Future<bool> _isInstalledMacOS() async {
    try {
      final home = Platform.environment['HOME'];
      final servicePath = '$home/Library/Services/Encrypt with Cryptinator.workflow';
      return await Directory(servicePath).exists();
    } catch (e) {
      return false;
    }
  }

  Future<bool> _installMacOS() async {
    try {
      final home = Platform.environment['HOME'];
      final exePath = _xmlEscape(_shellEscape(Platform.resolvedExecutable));
      final servicesDir = '$home/Library/Services';

      // Create Services directory if needed
      await Directory(servicesDir).create(recursive: true);

      // Create Encrypt workflow
      final encryptWorkflowPath = '$servicesDir/Encrypt with Cryptinator.workflow/Contents';
      await Directory(encryptWorkflowPath).create(recursive: true);

      // Create Info.plist for encrypt
      await File('$encryptWorkflowPath/Info.plist').writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict>
                <key>default</key>
                <string>Encrypt with Cryptinator</string>
            </dict>
            <key>NSMessage</key>
            <string>runWorkflowAsService</string>
            <key>NSSendFileTypes</key>
            <array>
                <string>public.item</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
''');

      // Create document.wflow for encrypt
      // Uses single-quoted path with proper escaping to prevent shell injection
      await File('$encryptWorkflowPath/document.wflow').writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AMApplicationBuild</key>
    <string>523</string>
    <key>AMApplicationVersion</key>
    <string>2.10</string>
    <key>actions</key>
    <array>
        <dict>
            <key>action</key>
            <dict>
                <key>AMActionVersion</key>
                <string>1.0.2</string>
                <key>AMApplication</key>
                <array>
                    <string>Automator</string>
                </array>
                <key>ActionBundlePath</key>
                <string>/System/Library/Automator/Run Shell Script.action</string>
                <key>ActionName</key>
                <string>Run Shell Script</string>
                <key>ActionParameters</key>
                <dict>
                    <key>COMMAND_STRING</key>
                    <string>'$exePath' "\$@"</string>
                    <key>CheckedForUserDefaultShell</key>
                    <true/>
                    <key>inputMethod</key>
                    <integer>1</integer>
                    <key>shell</key>
                    <string>/bin/zsh</string>
                    <key>source</key>
                    <string></string>
                </dict>
            </dict>
        </dict>
    </array>
</dict>
</plist>
''');

      // Refresh services
      await Process.run('/System/Library/CoreServices/pbs', ['-update']);

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _uninstallMacOS() async {
    try {
      final home = Platform.environment['HOME'];

      // Remove encrypt workflow
      final encryptPath = '$home/Library/Services/Encrypt with Cryptinator.workflow';
      if (await Directory(encryptPath).exists()) {
        await Directory(encryptPath).delete(recursive: true);
      }

      // Remove decrypt workflow
      final decryptPath = '$home/Library/Services/Decrypt with Cryptinator.workflow';
      if (await Directory(decryptPath).exists()) {
        await Directory(decryptPath).delete(recursive: true);
      }

      // Refresh services
      await Process.run('/System/Library/CoreServices/pbs', ['-update']);

      return true;
    } catch (e) {
      return false;
    }
  }

  // ===== LINUX IMPLEMENTATION =====

  Future<bool> _isInstalledLinux() async {
    try {
      final home = Platform.environment['HOME'];
      final desktopFile = File('$home/.local/share/applications/cryptinator.desktop');
      return await desktopFile.exists();
    } catch (e) {
      return false;
    }
  }

  Future<bool> _installLinux() async {
    try {
      final home = Platform.environment['HOME'];
      final exePath = Platform.resolvedExecutable;

      // Create applications directory
      final appsDir = '$home/.local/share/applications';
      await Directory(appsDir).create(recursive: true);

      // Create .desktop file
      await File('$appsDir/cryptinator.desktop').writeAsString('''[Desktop Entry]
Name=Cryptinator
Comment=Encrypt and decrypt files securely
Exec="$exePath" %F
Icon=security-high
Terminal=false
Type=Application
Categories=Utility;Security;
MimeType=application/x-cryptinator;
Actions=encrypt;decrypt;

[Desktop Action encrypt]
Name=Encrypt with Cryptinator
Exec="$exePath" %F

[Desktop Action decrypt]
Name=Decrypt with Cryptinator
Exec="$exePath" %F
''');

      // Create MIME type directory
      final mimeDir = '$home/.local/share/mime/packages';
      await Directory(mimeDir).create(recursive: true);

      // Register .crypt MIME type
      await File('$mimeDir/cryptinator.xml').writeAsString('''<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
    <mime-type type="application/x-cryptinator">
        <comment>Cryptinator Encrypted File</comment>
        <glob pattern="*.crypt"/>
        <icon name="security-high"/>
    </mime-type>
</mime-info>
''');

      // Update MIME database
      await Process.run('update-mime-database', ['$home/.local/share/mime']);

      // Update desktop database
      await Process.run('update-desktop-database', [appsDir]);

      // Create Nautilus script (for GNOME Files)
      // Passes all selected files as arguments to a single Cryptinator instance
      final nautilusDir = '$home/.local/share/nautilus/scripts';
      await Directory(nautilusDir).create(recursive: true);

      await File('$nautilusDir/Encrypt with Cryptinator').writeAsString('''#!/bin/bash
# Pass all selected files as arguments to a single Cryptinator instance
FILES=()
while IFS= read -r file; do
    [ -n "\$file" ] && FILES+=("\$file")
done <<< "\$NAUTILUS_SCRIPT_SELECTED_FILE_PATHS"
if [ \${#FILES[@]} -gt 0 ]; then
    "$exePath" "\${FILES[@]}"
fi
''');

      // Make script executable
      await Process.run('chmod', ['+x', '$nautilusDir/Encrypt with Cryptinator']);

      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _uninstallLinux() async {
    try {
      final home = Platform.environment['HOME'];

      // Remove .desktop file
      final desktopFile = File('$home/.local/share/applications/cryptinator.desktop');
      if (await desktopFile.exists()) {
        await desktopFile.delete();
      }

      // Remove MIME type
      final mimeFile = File('$home/.local/share/mime/packages/cryptinator.xml');
      if (await mimeFile.exists()) {
        await mimeFile.delete();
        await Process.run('update-mime-database', ['$home/.local/share/mime']);
      }

      // Remove Nautilus script
      final scriptFile = File('$home/.local/share/nautilus/scripts/Encrypt with Cryptinator');
      if (await scriptFile.exists()) {
        await scriptFile.delete();
      }

      // Update desktop database
      await Process.run('update-desktop-database', ['$home/.local/share/applications']);

      return true;
    } catch (e) {
      return false;
    }
  }
}
