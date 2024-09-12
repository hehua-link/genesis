import 'dart:io';

import 'package:flutter/material.dart';
import 'package:genesis/common_utils.dart';

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
  bool _isPythonInstalled = true;
  bool _isFrpInstalled = true;

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
    final envDir = await CommonUtils.createDirectory(userDir, _envDirName);
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
    final supported = cpuArch != CpuArch.unknown && cpuArch != CpuArch.arm;
    setState(() {
      _isCpuArchSupported = supported;
    });

    return supported;
  }

  ///
  /// Check whether python3 is installed, if not execute installation.
  ///
  Future<bool> _checkAndInstallPython() async {
    // Check whether python3 is installed.
    final isInstalled = await _checkPythonInstallation();
    setState(() {
      _isPythonInstalled = isInstalled;
    });

    if (!isInstalled) {
      // Install python3.
    }
  }

  _startEnvCreation() async {
    setState(() {
      _isEnvCreationStarted = true;
    });

    if (_checkCpuArch() && await _checkAndCreateEnvDirectory()) {
      setState(() {
        _isEnvReady = true;
      });
    }

    setState(() {
      _isEnvCreationStarted = false;
    });
  }

  void _checkFlashingEnv() async {
    _resetChecking();
    setState(() {
      _isInChecking = true;
    });

    Future.delayed(const Duration(seconds: 3), () async {
      var result = await CommonUtils.checkPythonInstallation();
      if (!result) {
        setState(() {
          _isEnvChecked = true;
          _isPythonInstalled = false;
          _isEnvReady = false;
        });
      } else {
        // TODO
      }

      setState(() {
        _isInChecking = false;
      });
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
