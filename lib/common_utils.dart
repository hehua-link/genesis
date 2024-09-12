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

  static Future<bool> checkFileOrDirectory({required String? path}) async {
    if (path == null) {
      return false;
    }

    final entity = await FileSystemEntity.type(path);
    if (entity == FileSystemEntityType.notFound) {
      return false;
    }

    return true;
  }

  static Future<void> deleteFileOrDirectory({required String? path}) async {
    if (path == null) {
      return;
    }

    final entity = await FileSystemEntity.type(path);
    if (entity == FileSystemEntityType.notFound) {
      return;
    }

    if (entity == FileSystemEntityType.directory) {
      final dir = Directory(path);
      await dir.delete(recursive: true);
    } else {
      final file = File(path);
      await file.delete(recursive: true);
    }
  }

  static Future<String?> createDirectory(
      {required String? baseDir, required String name}) async {
    if (baseDir == null || baseDir.isEmpty) {
      return null;
    }

    final envDirPath = path.join(baseDir, name);
    final envDir = Directory(envDirPath);
    if (!(await envDir.exists())) {
      // Create env directory.
      await envDir.create();
    }

    return envDir.path;
  }

  static Future<bool> checkEsptoolInstallation(
      {required String? baseDir}) async {
    if (baseDir == null) {
      return false;
    }

    final pythonExecPath = path.join(baseDir, 'python3', 'python.exe');
    final espRfcServerScriptPath = path.join(
        baseDir, 'esptool', 'esptool-master', 'esp_rfc2217_server.py');
    final file = File(espRfcServerScriptPath);
    if (!(await file.exists())) {
      return false;
    }

    return await _runProcess(pythonExecPath, [espRfcServerScriptPath, '-h']);
  }

  static Future<bool> checkFrpInstallation({required String? baseDir}) async {
    if (baseDir == null) {
      return false;
    }

    final file =
        File(path.join(baseDir, 'frp', 'frp_0.60.0_windows_amd64', 'frpc.exe'));
    if (!(await file.exists())) {
      return false;
    }

    return await _runProcess(file.path, ['--version']);
  }

  static Future<bool> checkPythonInstallation(
      {required String? baseDir}) async {
    if (baseDir == null) {
      return false;
    }

    final file = File(path.join(baseDir, 'python3', 'python.exe'));
    if (!(await file.exists())) {
      return false;
    }

    return await _runProcess(file.path, ['--version']);
  }

  ///
  /// Return the esptool directory.
  ///
  static Future<String?> installEsptool({required String baseDir}) async {
    final targetDir = await createDirectory(baseDir: baseDir, name: 'esptool');
    if (targetDir == null) {
      return null;
    }

    if (await checkEsptoolInstallation(baseDir: baseDir)) {
      return targetDir;
    }

    // TODO: Download from genesis backend.
    const downloadUrl =
        'https://github.com/espressif/esptool/archive/refs/heads/master.zip';
    if (!(await downloadFile(downloadUrl, baseDir, 'esptool.zip'))) {
      return null;
    }

    // Create unzipped directory and Unzip.
    final sourceZipFilePath = path.join(baseDir, 'esptool.zip');
    if (!(await unzipFile(sourceZipFilePath, targetDir))) {
      return null;
    }
    // Delete the zip file.
    await deleteFileOrDirectory(path: sourceZipFilePath);

    // Install esptool requirements.
    final pythonExecPath = path.join(baseDir, 'python3', 'python.exe');
    final esptoolBaseDir = path.join(baseDir, 'esptool', 'esptool-master');
    final setupScriptPath = path.join(esptoolBaseDir, 'setup.py');
    if (!(await _runProcess(pythonExecPath, [setupScriptPath, 'install'],
        workingDir: esptoolBaseDir))) {
      return null;
    }

    // Ensure the esp rfc server is available.
    final espRfcServerScriptPath = path.join(
        baseDir, 'esptool', 'esptool-master', 'esp_rfc2217_server.py');
    if (!(await _runProcess(pythonExecPath, [espRfcServerScriptPath, '-h']))) {
      return null;
    }

    return targetDir;
  }

  static Future<bool> startFrpc({required String baseDir}) async {
    if (!(await checkFrpInstallation(baseDir: baseDir))) {
      return false;
    }

    final frpcPath =
        path.join(baseDir, 'frp', 'frp_0.60.0_windows_amd64', 'frpc.exe');
    final frpcConfigFilePath =
        path.join(baseDir, 'frp', 'frp_0.60.0_windows_amd64', 'frpc.toml');
    if (!(await _runProcess(frpcPath, ['-c', frpcConfigFilePath]))) {
      return false;
    }

    return true;
  }

  ///
  /// Return the frp directory.
  ///
  static Future<String?> installFrp(
      {required CpuArch cpuArch, required String baseDir}) async {
    final targetDir = await createDirectory(baseDir: baseDir, name: 'frp');
    if (targetDir == null) {
      return null;
    }

    if (await checkFrpInstallation(baseDir: baseDir)) {
      return targetDir;
    }

    // Download frp from official site.
    // TODO: Download from genesis backend.
    var downloadUrl =
        'https://github.com/fatedier/frp/releases/download/v0.60.0/';
    switch (cpuArch) {
      case CpuArch.amd64:
        downloadUrl += 'frp_0.60.0_windows_amd64.zip';
        break;
      case CpuArch.arm64:
        downloadUrl += 'frp_0.60.0_windows_arm64.zip';
        break;
      default:
        return null;
    }

    if (!(await downloadFile(downloadUrl, baseDir, 'frp.zip'))) {
      return null;
    }

    // Create unzipped directory and Unzip.
    final sourceZipFilePath = path.join(baseDir, 'frp.zip');
    if (!(await unzipFile(sourceZipFilePath, targetDir))) {
      return null;
    }
    // Delete the zip file.
    await deleteFileOrDirectory(path: sourceZipFilePath);

    // Ensure frp is available.
    if (!(await _runProcess(
        path.join(targetDir, 'frp_0.60.0_windows_amd64', 'frpc.exe'),
        ['--version']))) {
      return null;
    }

    return targetDir;
  }

  ///
  /// Return the python directory.
  ///
  static Future<String?> installPython(
      {required CpuArch cpuArch, required String baseDir}) async {
    final targetDir = await createDirectory(baseDir: baseDir, name: 'python3');
    if (targetDir == null) {
      return null;
    }

    if (await checkPythonInstallation(baseDir: baseDir)) {
      return targetDir;
    }

    // Download python3 from official site.
    // TODO: Download from genesis backend.
    var downloadUrl = 'https://www.python.org/ftp/python/3.12.6/';
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

    if (!(await downloadFile(downloadUrl, baseDir, 'python3.zip'))) {
      return null;
    }

    // Create unzipped directory and Unzip.
    final sourceZipFilePath = path.join(baseDir, 'python3.zip');
    if (!(await unzipFile(sourceZipFilePath, targetDir))) {
      return null;
    }
    // Delete the zip file.
    await deleteFileOrDirectory(path: sourceZipFilePath);

    // Modify python312._pth, add a line of 'import site'.
    final pthFile = File(path.join(targetDir, 'python312._pth'));
    if (!(await pthFile.exists())) {
      return null;
    }
    await pthFile.writeAsString('import site', mode: FileMode.append);

    // Before installation, the setup_pip.py should be downloaded first.
    const setupPipScriptUrl = 'https://bootstrap.pypa.io/get-pip.py';
    if (!(await downloadFile(setupPipScriptUrl, baseDir, 'get_pip.py'))) {
      return null;
    }
    // Install pip.
    if (!(await _runProcess(path.join(targetDir, 'python.exe'),
        [path.join(baseDir, 'get_pip.py')]))) {
      return null;
    }
    // Ensure the pip is available.
    if (!(await _runProcess(
        path.join(targetDir, 'python.exe'), ['-m', 'pip', '--version']))) {
      return null;
    }

    // Install Setuptools.
    if (!(await _runProcess(path.join(targetDir, 'python.exe'),
        ['-m', 'pip', 'install', 'setuptools']))) {
      return null;
    }

    return targetDir;
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

  static Future<bool> _runProcess(String command, List<String> args,
      {String? workingDir}) async {
    try {
      var result = workingDir == null
          ? await Process.run(command, args)
          : await Process.run(command, args, workingDirectory: workingDir);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }
}
