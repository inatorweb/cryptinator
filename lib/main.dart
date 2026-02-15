import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'screens/main_screen.dart';

void main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Get file paths from command-line arguments (context menu / Nautilus / share)
  List<String> initialFilePaths = [];
  for (final arg in args) {
    if (File(arg).existsSync() || Directory(arg).existsSync()) {
      initialFilePaths.add(arg);
    }
  }
  
  // Desktop window configuration
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    await windowManager.ensureInitialized();
    
    WindowOptions windowOptions = WindowOptions(
      size: Size(480, 560),
      minimumSize: Size(420, 520),
      center: true,
      backgroundColor: Colors.transparent,
      titleBarStyle: TitleBarStyle.normal,
      title: 'Cryptinator',
    );
    
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }
  
  runApp(CryptinatorApp(initialFilePaths: initialFilePaths));
}

class CryptinatorApp extends StatelessWidget {
  final List<String> initialFilePaths;
  
  const CryptinatorApp({super.key, this.initialFilePaths = const []});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cryptinator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: MainScreen(initialFilePaths: initialFilePaths),
    );
  }
}
