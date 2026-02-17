package com.inatorweb.cryptinator

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.inatorweb.cryptinator/storage"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveToDownloads" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    val fileName = call.argument<String>("fileName")
                    if (sourcePath != null && fileName != null) {
                        try {
                            val savedPath = saveToDownloads(sourcePath, fileName)
                            result.success(savedPath)
                        } catch (e: Exception) {
                            result.error("SAVE_ERROR", e.message, null)
                        }
                    } else {
                        result.error("INVALID_ARGS", "sourcePath and fileName required", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun saveToDownloads(sourcePath: String, fileName: String): String {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists()) {
            throw Exception("Source file not found: $sourcePath")
        }

        // Determine a unique file name to avoid collisions
        val finalFileName = getUniqueFileName(fileName)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            // Android 10+ use MediaStore
            val contentValues = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, finalFileName)
                put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }

            val resolver = contentResolver
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, contentValues)
                ?: throw Exception("Failed to create MediaStore entry")

            resolver.openOutputStream(uri)?.use { outputStream ->
                sourceFile.inputStream().use { inputStream ->
                    inputStream.copyTo(outputStream)
                }
            } ?: throw Exception("Failed to open output stream")

            contentValues.clear()
            contentValues.put(MediaStore.Downloads.IS_PENDING, 0)
            resolver.update(uri, contentValues, null, null)

            return finalFileName
        } else {
            // Android 9 and below — direct file copy
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val destFile = File(downloadsDir, finalFileName)
            sourceFile.copyTo(destFile, overwrite = false)
            return destFile.absolutePath
        }
    }

    private fun getUniqueFileName(fileName: String): String {
        val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)

        // Check if file already exists
        if (!File(downloadsDir, fileName).exists()) {
            return fileName
        }

        // Handle collision naming: file.txt.crypt → file_1.txt.crypt
        val isCrypt = fileName.endsWith(".crypt")
        val nameWithoutCrypt = if (isCrypt) fileName.removeSuffix(".crypt") else fileName
        val lastDot = nameWithoutCrypt.lastIndexOf('.')
        val baseName = if (lastDot > 0) nameWithoutCrypt.substring(0, lastDot) else nameWithoutCrypt
        val innerExt = if (lastDot > 0) nameWithoutCrypt.substring(lastDot) else ""
        val outerExt = if (isCrypt) ".crypt" else ""

        var counter = 1
        var candidate: String
        do {
            candidate = "${baseName}_$counter$innerExt$outerExt"
            counter++
        } while (File(downloadsDir, candidate).exists())

        return candidate
    }
}
