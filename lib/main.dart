import 'dart:io';

import 'package:flutter/material.dart';
import 'package:genesis/common_utils.dart';
import 'package:path/path.dart' as path;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Firmware Flashing Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final _envDirName = "panda_flash_env";
  String? _envDir;

  bool _isEnvChecked = false;
  bool _isInChecking = false;
  bool _isEnvReady = false;

  bool _isCpuArchSupported = true;
  bool _isEnvDirCreated = true;
  bool _isEspDeviceDriverInstalled = true;
  bool _isPythonInstalled = true;
  bool _isEsptoolInstalled = true;
  bool _isFrpInstalled = true;

  CpuArch _cpuArch = CpuArch.unknown;

  String? _espDeviceDriverInstallDir;
  String? _pythonInstallDir;
  String? _esptoolInstallDir;
  String? _frpInstallDir;

  int? _frpcPid;
  int? _espRfcServerPid;

  bool _isEnvCreationStarted = false;

  _resetChecking() {
    setState(() {
      _isEnvChecked = false;
      _isInChecking = false;
      _isEnvReady = false;
      _isPythonInstalled = true;
      _isFrpInstalled = true;
      _isEnvCreationStarted = false;
    });
  }

  ///
  /// Check whether the env directory was created,
  /// if not create the env directory under the user directory.
  ///
  Future<bool> _checkAndCreateEnvDirectory() async {
    // Get current user directory.
    final userDir = Platform.environment['USERPROFILE'];
    final envDir =
        await CommonUtils.createDirectory(baseDir: userDir, name: _envDirName);
    setState(() {
      _isEnvDirCreated = envDir != null;
      _envDir = envDir;
    });

    return envDir != null;
  }

  ///
  /// Check current system cpu architecture.
  /// The only supported arch include:
  /// - amd
  /// - amd64
  /// - arm64
  ///
  bool _checkCpuArch() {
    final cpuArch = CommonUtils.checkCpuArch();
    final supported = cpuArch != CpuArch.unknown &&
        cpuArch != CpuArch.arm &&
        cpuArch != CpuArch.amd;
    setState(() {
      _isCpuArchSupported = supported;
      _cpuArch = cpuArch;
    });

    return supported;
  }

  Future<bool> _checkAndInstallEspDeviceDriver() async {
    String? installPath = await CommonUtils.installEspDeviceDriver(
        cpuArch: _cpuArch, baseDir: _envDir!);
    setState(() {
      _isEspDeviceDriverInstalled = installPath != null;
      _espDeviceDriverInstallDir = installPath;
    });

    return installPath != null;
  }

  ///
  /// Check whether python3 is installed, if not execute installation.
  ///
  Future<bool> _checkAndInstallPython() async {
    String? installPath =
        await CommonUtils.installPython(cpuArch: _cpuArch, baseDir: _envDir!);
    setState(() {
      _isPythonInstalled = installPath != null;
      _pythonInstallDir = installPath;
    });

    return installPath != null;
  }

  Future<bool> _checkAndInstallEsptool() async {
    String? installPath = await CommonUtils.installEsptool(baseDir: _envDir!);
    setState(() {
      _isEsptoolInstalled = installPath != null;
      _esptoolInstallDir = installPath;
    });

    return installPath != null;
  }

  Future<bool> _checkAndInstallFrp() async {
    String? installPath =
        await CommonUtils.installFrp(cpuArch: _cpuArch, baseDir: _envDir!);
    setState(() {
      _isFrpInstalled = installPath != null;
      _frpInstallDir = installPath;
    });

    return installPath != null;
  }

  _cleanEnv() async {
    CommonUtils.deleteFileOrDirectory(path: _envDir);
  }

  _startEnvCreation() async {
    setState(() {
      _isEnvCreationStarted = true;
    });

    if (_checkCpuArch() &&
        await _checkAndCreateEnvDirectory() &&
        await _checkAndInstallEspDeviceDriver() &&
        await _checkAndInstallPython() &&
        await _checkAndInstallEsptool() &&
        await _checkAndInstallFrp()) {
      setState(() {
        _isEnvReady = true;
      });
    } else {
      // The env creation failed, just clean the incomplete env directory.
      _cleanEnv();
    }

    setState(() {
      _isEnvCreationStarted = false;
    });
  }

  void _setEnvCheckFailureStates() {
    setState(() {
      _isEnvChecked = true;
      _isPythonInstalled = false;
      _isEnvReady = false;
      _isInChecking = false;
    });
  }

  void _setEnvCheckSuccessStates(int frpcPid, int espRfcServerPid) {
    setState(() {
      _isEnvChecked = true;
      _isEspDeviceDriverInstalled = true;
      _isPythonInstalled = true;
      _isEsptoolInstalled = true;
      _isFrpInstalled = true;
      _frpcPid = frpcPid;
      _espRfcServerPid = espRfcServerPid;
      _isEnvReady = true;
      _isInChecking = false;
    });
  }

  void _checkFlashingEnv() async {
    _resetChecking();
    setState(() {
      _isInChecking = true;
    });

    Future.delayed(const Duration(seconds: 3), () async {
      final userDir = Platform.environment['USERPROFILE'];
      if (userDir != null) {
        _envDir = path.join(userDir, _envDirName);
        if (await CommonUtils.checkFileOrDirectory(path: _envDir) &&
            await CommonUtils.checkEspDeviceDriverInstallation(
                baseDir: _envDir) &&
            await CommonUtils.checkPythonInstallation(baseDir: _envDir) &&
            await CommonUtils.checkEsptoolInstallation(baseDir: _envDir) &&
            await CommonUtils.checkFrpInstallation(baseDir: _envDir)) {
          // All components are installed,
          // then start the frpc and esp rfc server services.
          //final frpcServiceStatus =
          //    await CommonUtils.startFrpc(baseDir: _envDir!);
          //if (frpcServiceStatus == null || frpcServiceStatus.pid == null) {
          //  // Failed to start frpc.
          //  // TODO: notify user the failure.
          //}

          // Here the frpc is started successfully,
          // then start the esp rfc server.
          //final espRfcServiceStatus =

          _setEnvCheckSuccessStates(-1, -2);
          return;
        }
      }

      _setEnvCheckFailureStates();
    });

    return;
  }

  Widget _buildCheckingProcessIndicator() {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        CircularProgressIndicator(),
        SizedBox(
          height: 15,
        ),
        Text('正在检测烧写环境')
      ],
    );
  }

  Widget _buildFlashingEnvInfoBlock() {
    if (_isEnvChecked) {
      return _isPythonInstalled
          ? const Text('固件烧写环境已就绪')
          : const Text('固件烧写环境没有正确配置');
    } else {
      return const Text('固件烧写环境待检测');
    }
  }

  Widget _buildFlashingEnvCreationBlock() {
    if (!_isEnvCreationStarted) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          const Text('是否现在安装并配置固件烧写环境？'),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                  onPressed: _resetChecking, child: const Text('退出')),
              const SizedBox(width: 10),
              ElevatedButton(
                  onPressed: _startEnvCreation,
                  child: const Text('开始'),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white)),
            ],
          )
        ],
      );
    } else {
      return Text('');
    }
  }

  Widget _buildStartCreateEnvBlock() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(width: 16, height: 16, child: CircularProgressIndicator()),
        SizedBox(width: 10),
        Text('正在安装烧写环境')
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_isInChecking && !_isEnvCreationStarted)
              _buildFlashingEnvInfoBlock(),
            if (_isInChecking) _buildCheckingProcessIndicator(),
            if (_isEnvChecked && !_isEnvReady) _buildFlashingEnvCreationBlock(),
            if (_isEnvCreationStarted) _buildStartCreateEnvBlock(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _checkFlashingEnv,
        tooltip: 'Increment',
        child: const Icon(Icons.flash_on_outlined),
      ), // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
