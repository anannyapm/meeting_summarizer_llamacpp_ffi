import 'dart:async';
import 'dart:developer';

import 'package:ffi_learn/native/native_bridge_worker.dart';
import 'package:flutter/material.dart';

class HomePage extends StatefulWidget {
  const HomePage({required this.initialModelPath, super.key});

  final String initialModelPath;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _tagController = TextEditingController(
    text: 'alpha',
  );
  final TextEditingController _inputController = TextEditingController(
    text: 'Hello from session',
  );
  late final TextEditingController _modelPathController;
  final TextEditingController _ctxController = TextEditingController(
    text: '256',
  );
  final TextEditingController _gpuLayersController = TextEditingController(
    text: '0',
  );
  NativeBridgeWorkerClient? _worker;

  String _bridgeVersion = '';
  String _llamaRuntimeInfo = '';
  String _output = '';
  String? _error;
  bool _sessionActive = false;
  StreamSubscription<String>? _streamSubscription;
  bool _isStreaming = false;
  bool _isInitializing = true;
  bool _isBusy = false;
  bool _isModelLoaded = false;
  String _modelInfo = '';

  @override
  void initState() {
    super.initState();
    _modelPathController = TextEditingController(text: widget.initialModelPath);
    unawaited(_initializeWorker());
  }

  Future<void> _initializeWorker() async {
    setState(() {
      _error = null;
      _isInitializing = true;
    });
    try {
      final worker = await NativeBridgeWorkerClient.start();
      final version = await worker.bridgeVersion();
      if (!mounted) {
        await worker.close();
        return;
      }
      setState(() {
        _worker = worker;
        _bridgeVersion = version;
        _isInitializing = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Failed reading bridge version: $e';
        _isInitializing = false;
      });
    }
  }

  @override
  void dispose() {
    unawaited(_streamSubscription?.cancel());
    final worker = _worker;
    if (worker != null) {
      unawaited(worker.close());
    }
    _tagController.dispose();
    _inputController.dispose();
    _modelPathController.dispose();
    _ctxController.dispose();
    _gpuLayersController.dispose();
    super.dispose();
  }

  Future<void> _createSession() async {
    final worker = _worker;
    if (worker == null || _isBusy || _isInitializing) {
      return;
    }
    setState(() {
      _error = null;
      _isBusy = true;
    });
    try {
      await worker.createSession(tag: _tagController.text);
      final runtimeInfo = await worker.llamaRuntimeInfo();
      if (!mounted) {
        return;
      }
      setState(() {
        _sessionActive = true;
        _llamaRuntimeInfo = runtimeInfo;
        _output = 'Session created.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Create session failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _destroySession() async {
    final worker = _worker;
    if (worker == null || !_sessionActive || _isBusy || _isInitializing) {
      return;
    }
    await _streamSubscription?.cancel();
    _streamSubscription = null;
    setState(() {
      _isBusy = true;
    });
    try {
      await worker.destroySession();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Destroy session failed: $e';
        });
      }
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _sessionActive = false;
      _llamaRuntimeInfo = '';
      _isModelLoaded = false;
      _modelInfo = '';
      _output = 'Session destroyed.';
      _error = null;
      _isStreaming = false;
      _isBusy = false;
    });
  }

  Future<void> _updateTag() async {
    final worker = _worker;
    if (worker == null || !_sessionActive || _isBusy || _isInitializing) {
      setState(() {
        _error = 'Create a session first.';
      });
      return;
    }
    setState(() {
      _isBusy = true;
    });
    try {
      await worker.setTag(_tagController.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _output = 'Session tag updated.';
        _error = null;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Set tag failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _loadModel() async {
    final worker = _worker;
    if (worker == null || !_sessionActive || _isBusy || _isInitializing) {
      return;
    }

    final nCtx = int.tryParse(_ctxController.text.trim());
    final nGpuLayers = int.tryParse(_gpuLayersController.text.trim());
    if (nCtx == null || nCtx <= 0 || nGpuLayers == null) {
      setState(() {
        _error =
            'Invalid model params: n_ctx must be > 0, gpu layers must be int.';
      });
      return;
    }

    setState(() {
      _isBusy = true;
      _error = null;
    });
    final modelPath = _modelPathController.text.trim();
    if (modelPath.isEmpty) {
      setState(() {
        _error = 'Model path is empty.';
        _isBusy = false;
      });
      return;
    }

    setState(() {
      _output = 'Loading $modelPath';
    });
    try {
      await worker.loadModel(
        modelPath: modelPath,
        nCtx: nCtx,
        nGpuLayers: nGpuLayers,
      );
      final info = await worker.modelInfo();
      if (!mounted) {
        return;
      }
      setState(() {
        _isModelLoaded = true;
        _modelInfo = info;
        _output = 'Model loaded successfully.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Load model failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _unloadModel() async {
    final worker = _worker;
    if (worker == null || !_sessionActive || _isBusy || _isInitializing) {
      return;
    }
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      await worker.unloadModel();
      if (!mounted) {
        return;
      }
      setState(() {
        _isModelLoaded = false;
        _modelInfo = '';
        _output = 'Model unloaded.';
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unload model failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  Future<void> _callSessionEcho() async {
    final worker = _worker;
    if (worker == null || _isBusy || _isInitializing) {
      return;
    }
    if (_isStreaming) {
      setState(() {
        _error = 'Wait for streaming to finish first.';
      });
      return;
    }
    setState(() {
      _error = null;
    });
    if (!_sessionActive) {
      setState(() {
        _error = 'Create a session before calling echo.';
      });
      return;
    }
    if (!_isModelLoaded) {
      setState(() {
        _error = 'Load a model before calling echo.';
      });
      return;
    }
    setState(() {
      _isBusy = true;
    });
    try {
      final result = await worker.echo(_inputController.text);
      if (!mounted) {
        return;
      }
      setState(() {
        _output = result;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Session echo failed: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  void _startStream() {
    final worker = _worker;
    if (worker == null || _isBusy || _isInitializing) {
      return;
    }
    if (!_sessionActive) {
      setState(() {
        _error = 'Create a session before starting stream.';
      });
      return;
    }
    if (!_isModelLoaded) {
      setState(() {
        _error = 'Load a model before starting stream.';
      });
      return;
    }
    if (_isStreaming) {
      return;
    }

    _streamSubscription?.cancel();
    setState(() {
      _error = null;
      _output = '';
      _isStreaming = true;
    });

    print(_inputController.text);

    final stream = worker.streamEcho(_inputController.text);
    log('$stream');
    _streamSubscription = stream.listen(
      (token) {
        if (!mounted) {
          return;
        }
        setState(() {
          _output += token;
        });
      },
      onError: (error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _error = 'Stream failed: $error';
          _isStreaming = false;
        });
      },
      onDone: () {
        if (!mounted) {
          return;
        }
        setState(() {
          _isStreaming = false;
        });
      },
      cancelOnError: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter llama.cpp bridge')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          physics: const ClampingScrollPhysics(),
          children: [
            Text(
              'Bridge version: ${_bridgeVersion.isEmpty ? "not loaded" : _bridgeVersion}',
            ),
            const SizedBox(height: 8),
            Text(
              _llamaRuntimeInfo.isEmpty
                  ? 'llama runtime: unavailable (create session first)'
                  : 'llama runtime: ${_llamaRuntimeInfo.split('\n').first}',
            ),
            const SizedBox(height: 16),
            Text(
              _sessionActive ? 'Session: active' : 'Session: not created',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (_isInitializing)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Starting native worker isolate...'),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isInitializing || _isBusy
                        ? null
                        : _createSession,
                    child: const Text('Create Session'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        !_sessionActive ||
                            _isStreaming ||
                            _isBusy ||
                            _isInitializing
                        ? null
                        : _destroySession,
                    child: const Text('Destroy Session'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _isModelLoaded ? 'Model: loaded' : 'Model: not loaded',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelPathController,
              decoration: const InputDecoration(
                labelText: 'Local model path',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Model is pre-downloaded during splash.',
              style: TextStyle(fontSize: 12, color: Colors.white60),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ctxController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'n_ctx',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _gpuLayersController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'n_gpu_layers',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        !_sessionActive ||
                            _isBusy ||
                            _isInitializing ||
                            _isStreaming
                        ? null
                        : _loadModel,
                    child: const Text('Load Model'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed:
                        !_sessionActive ||
                            !_isModelLoaded ||
                            _isBusy ||
                            _isInitializing ||
                            _isStreaming
                        ? null
                        : _unloadModel,
                    child: const Text('Unload Model'),
                  ),
                ),
              ],
            ),
            if (_modelInfo.isNotEmpty) const SizedBox(height: 8),
            if (_modelInfo.isNotEmpty)
              Text(
                _modelInfo,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _tagController,
              decoration: const InputDecoration(
                labelText: 'Session tag',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: !_sessionActive || _isBusy || _isInitializing
                    ? null
                    : _updateTag,
                child: const Text('Update session tag'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _inputController,
              decoration: const InputDecoration(
                labelText: 'Message to native',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isStreaming || _isBusy || _isInitializing
                  ? null
                  : _callSessionEcho,
              child: const Text('Call session echo'),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _isStreaming || _isBusy || _isInitializing
                  ? null
                  : _startStream,
              child: Text(_isStreaming ? 'Streaming...' : 'Stream tokens'),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            if (_error != null) const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 150),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white24),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _output.isEmpty ? 'Native output appears here.' : _output,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
