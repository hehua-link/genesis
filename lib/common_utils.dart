import 'dart:io';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

enum CpuArch {
  amd,
  amd64,
  arm,
  arm64,
  unknown,
}

class CommonUtils {
  static CpuArch checkCpuArch() {
    if (Platform.isWindows) {
      String? arch =
          Platform.environment['PROCESSOR_ARCHITECTURE']?.toUpperCase();
      if (arch == null) {
        return CpuArch.unknown;
      }

      if (arch.contains('AMD') || arch.contains('X86')) {
        return arch.contains('64') ? CpuArch.amd64 : CpuArch.amd;
      }
      if (arch.contains('ARM')) {
        return arch.contains('64') ? CpuArch.arm64 : CpuArch.arm;
      }

      return CpuArch.unknown;
    } else {
      // TODO: MacOS/Linux
      return CpuArch.unknown;
    }
  }

  static Future<String?> createDirectory(
      String? baseDir, String dirName) async {
    if (baseDir == null || baseDir.isEmpty) {
      return null;
    }

    final envDirPath = path.join(baseDir, dirName);
    final envDir = Directory(envDirPath);
    if (!(await envDir.exists())) {
      // Create env directory.
      await envDir.create();
    }

    return envDir.path;
  }

  static Future<bool> checkPythonInstallation() async {
    try {
      var result = await Process.run('python', ['--version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  ///
  /// Return the python directory.
  ///
  static Future<String?> installPython(CpuArch cpuArch, String baseDir) async {
    if (await checkPythonInstallation()) {
      return null;
    }

    // Download python3 from official site.
    // TODO: Download from genesis backend.
    String downloadUrl = 'https://www.python.org/ftp/python/3.12.6/';
    switch (cpuArch) {
      case CpuArch.amd:
        downloadUrl += 'python-3.12.6-embed-win32.zip';
        break;
      case CpuArch.amd64:
        downloadUrl += 'python-3.12.6-embed-amd64.zip';
        break;
      case CpuArch.arm64:
        downloadUrl += 'python-3.12.6-embed-arm64.zip';
        break;
      default:
        return null;
    }

    final result = await downloadFile(downloadUrl, baseDir, 'python3.zip');
    if (!result) {
      return null;
    }

    // Create unzipped directory and Unzip.
    final targetDir = await createDirectory(baseDir, 'python3');
    if (targetDir == null) {
      return null;
    }
    final isUnzipped =
        await unzipFile(path.join(baseDir, 'python3.zip'), targetDir);

    return isUnzipped ? targetDir : null;
  }

  static Future<bool> downloadFile(
      String url, String targetDir, String fileName) async {
    final baseDir = Directory(targetDir);
    if (!(await baseDir.exists())) {
      return false;
    }

    try {
      final resp = await http.get(Uri.parse(url));

      if (resp.statusCode == 200) {
        final filePath = path.join(baseDir.path, fileName);
        final file = File(filePath);
        await file.writeAsBytes(resp.bodyBytes);

        return true;
      } else {
        return false;
      }
    } catch (e) {
      return false;
    }
  }

  static Future<bool> unzipFile(String zipFilePath, String targetDir) async {
    if (!(await Directory(targetDir).exists())) {
      return false;
    }
    try {
      final bytes = await File(zipFilePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      for (final file in archive) {
        final fileName = file.name;
        final filePath = path.join(targetDir, fileName);

        if (file.isFile) {
          final outFile = File(filePath);
          await outFile.create(recursive: true);
          await outFile.writeAsBytes(file.content as List<int>);
        } else {
          await Directory(filePath).create(recursive: true);
        }
      }

      return true;
    } catch (e) {
      return false;
    }
  }
}
