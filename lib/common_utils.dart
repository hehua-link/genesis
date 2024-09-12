import 'dart:async';
import 'dart:convert';
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

enum ServiceStatusCode {
  successRunning,
  alreadyExists,
  otherError,
}

class ServiceStatus {
  final int? pid;
  final ServiceStatusCode code;
  String? description;

  ServiceStatus({required this.pid, required this.code, this.description});
}

class CommandResult {
  final bool isSuccess;
  final dynamic output;

  const CommandResult({required this.isSuccess, required this.output});
}

class CommonUtils {
  // Pid or null, null indicates the command execution failure.
  static final StreamController<ServiceStatus> _frpcAsyncExecStream =
      StreamController.broadcast();

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

  static Future<bool> checkEspDeviceDriverInstallation(
      {required String? baseDir}) async {
    if (baseDir == null) {
      return false;
    }

    final driverDir = Directory(path.join(baseDir, 'cp210x'));
    if (!(await driverDir.exists())) {
      return false;
    }

    final result = await _runProcess('pnputil', ['/enum-drivers']);
    if (result.isSuccess &&
        result.output is String &&
        (result.output as String).contains('slabvcp.inf')) {
      return true;
    }

    return false;
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

    return (await _runProcess(pythonExecPath, [espRfcServerScriptPath, '-h']))
        .isSuccess;
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

    return (await _runProcess(file.path, ['--version'])).isSuccess;
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

    return (await _runProcess(file.path, ['--version'])).isSuccess;
  }

  ///
  /// Return the cp210x driver directory.
  /// TODO: If user not install driver, prompt user to install
  ///       using this function, after user installed successfully,
  ///       prompt user to click driver installed button,
  ///       then continue the normal components installation
  ///       procedure.
  ///
  static Future<String?> installEspDeviceDriver(
      {required CpuArch cpuArch, required String baseDir}) async {
    final targetDir = await createDirectory(baseDir: baseDir, name: 'cp210x');
    if (targetDir == null) {
      return null;
    }

    if (await checkEspDeviceDriverInstallation(baseDir: baseDir)) {
      return targetDir;
    }

    // TODO: Download from genesis backend.
    const downloadUrl =
        'https://www.silabs.com/documents/public/software/CP210x_Windows_Drivers.zip';
    if (!(await downloadFile(downloadUrl, baseDir, 'cp210x.zip'))) {
      return null;
    }

    // Create unzipped directory and Unzip.
    final sourceZipFilePath = path.join(baseDir, 'cp210x.zip');
    if (!(await unzipFile(sourceZipFilePath, targetDir))) {
      return null;
    }
    // Delete the zip file.
    await deleteFileOrDirectory(path: sourceZipFilePath);

    String driverInstaller = 'CP210xVCPInstaller_x64.exe';
    switch (cpuArch) {
      case CpuArch.amd64:
      case CpuArch.arm64:
        break;
      default:
        return null;
    }

    String installerPath = path.join(targetDir, driverInstaller);
    //final process = await _runProcessAsync(installerPath, []);
    //final stdoutSub = process.stdout.transform(utf8.decoder).listen((data) {
    //  print('data ==== $data');
    //});
    final result = await _runInstaller(installerPath, runAsAdmin: true);

    return targetDir;
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
            workingDir: esptoolBaseDir))
        .isSuccess) {
      return null;
    }

    // Ensure the esp rfc server is available.
    final espRfcServerScriptPath = path.join(
        baseDir, 'esptool', 'esptool-master', 'esp_rfc2217_server.py');
    if (!(await _runProcess(pythonExecPath, [espRfcServerScriptPath, '-h']))
        .isSuccess) {
      return null;
    }

    return targetDir;
  }

  static Future<ServiceStatus?> startEspRfcServer(
      {required String baseDir}) async {
    if (!(await checkEsptoolInstallation(baseDir: baseDir))) {
      return null;
    }

    final serverScriptPath = path.join(
        baseDir, 'esptool', 'esptool-master', 'esp_rfc2217_server.py');

    final process =
        await _runProcessAsync(serverScriptPath, ['-p', '7077', '/dev']);
    final stdoutSub = process.stdout.transform(utf8.decoder).listen((data) {
      if (data.contains('error')) {
        if (data.contains('already exists')) {
          _frpcAsyncExecStream.add(
              ServiceStatus(pid: null, code: ServiceStatusCode.alreadyExists));
        } else {
          _frpcAsyncExecStream.add(ServiceStatus(
              pid: null,
              code: ServiceStatusCode.otherError,
              description: data));
        }
      } else if (data.contains('start proxy success')) {
        _frpcAsyncExecStream.add(ServiceStatus(
            pid: process.pid, code: ServiceStatusCode.successRunning));
      }
    });

    final serviceStatus = await _frpcAsyncExecStream.stream.first;
    // Stop subscription.
    stdoutSub.cancel();
    if (serviceStatus.pid == null) {
      process.kill();
    }

    return serviceStatus;
  }

  static Future<ServiceStatus?> startFrpc({required String baseDir}) async {
    if (!(await checkFrpInstallation(baseDir: baseDir))) {
      return null;
    }

    final frpcPath =
        path.join(baseDir, 'frp', 'frp_0.60.0_windows_amd64', 'frpc.exe');
    final frpcConfigFilePath =
        path.join(baseDir, 'frp', 'frp_0.60.0_windows_amd64', 'frpc.toml');

    final process =
        await _runProcessAsync(frpcPath, ['-c', frpcConfigFilePath]);
    final stdoutSub = process.stdout.transform(utf8.decoder).listen((data) {
      if (data.contains('error')) {
        if (data.contains('already exists')) {
          _frpcAsyncExecStream.add(
              ServiceStatus(pid: null, code: ServiceStatusCode.alreadyExists));
        } else {
          _frpcAsyncExecStream.add(ServiceStatus(
              pid: null,
              code: ServiceStatusCode.otherError,
              description: data));
        }
      } else if (data.contains('start proxy success')) {
        _frpcAsyncExecStream.add(ServiceStatus(
            pid: process.pid, code: ServiceStatusCode.successRunning));
      }
    });

    final serviceStatus = await _frpcAsyncExecStream.stream.first;
    // Stop subscription.
    stdoutSub.cancel();
    if (serviceStatus.pid == null) {
      process.kill();
    }

    return serviceStatus;
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
            ['--version']))
        .isSuccess) {
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
            [path.join(baseDir, 'get_pip.py')]))
        .isSuccess) {
      return null;
    }
    // Ensure the pip is available.
    if (!(await _runProcess(
            path.join(targetDir, 'python.exe'), ['-m', 'pip', '--version']))
        .isSuccess) {
      return null;
    }

    // Install Setuptools.
    if (!(await _runProcess(path.join(targetDir, 'python.exe'),
            ['-m', 'pip', 'install', 'setuptools']))
        .isSuccess) {
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

  static Future<CommandResult> _runInstaller(String installerPath,
      {bool runAsAdmin = false}) async {
    try {
      var result = runAsAdmin
          //? await Process.run(
          //   'runas', ['/user:Administrator', 'cmd /c $installerPath'])
          ? await Process.run(
              'powershell', ['Start-Process', installerPath, '-Verb', 'runAs'])
          : await Process.run(installerPath, []);
      return CommandResult(isSuccess: result.exitCode == 0, output: null);
    } catch (e) {
      return const CommandResult(isSuccess: false, output: null);
    }
  }

  static Future<CommandResult> _runProcess(String command, List<String> args,
      {String? workingDir}) async {
    try {
      var result = workingDir == null
          ? await Process.run(command, args)
          : await Process.run(command, args, workingDirectory: workingDir);
      return CommandResult(
          isSuccess: result.exitCode == 0, output: result.stdout);
    } catch (e) {
      return const CommandResult(isSuccess: false, output: null);
    }
  }

  static Future<Process> _runProcessAsync(String command, List<String> args,
      {String? workingDir}) async {
    return workingDir == null
        ? await Process.start(command, args)
        : await Process.start(command, args, workingDirectory: workingDir);

    //? Process.run(command, args).then((result) {
    //    _commandAsyncExecStream.add(result);
    //  }).onError((e, _) {
    //    print(e.toString());
    //    _commandAsyncExecStream.add(null);
    //  }).catchError((e) {
    //    print(e.toString());
    //    _commandAsyncExecStream.add(null);
    //  }).whenComplete(() {
    //    print('dsdsadasadsads');
    //  })
    //: Process.run(command, args, workingDirectory: workingDir)
    //    .then((result) {
    //    _commandAsyncExecStream.add(result);
    //  }).onError((e, _) {
    //    print(e.toString());
    //    _commandAsyncExecStream.add(null);
    //  }).catchError((e) {
    //    print(e.toString());
    //    _commandAsyncExecStream.add(null);
    //  });
  }
}
