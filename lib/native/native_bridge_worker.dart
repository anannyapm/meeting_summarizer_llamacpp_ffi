import 'dart:async';
import 'dart:isolate';

import 'package:ffi_learn/native/native_bridge.dart';

const String _kTypeReady = 'ready';
const String _kTypeResponse = 'response';
const String _kTypeStreamToken = 'stream_token';
const String _kTypeStreamDone = 'stream_done';
const String _kTypeStreamError = 'stream_error';

const String _kCmdBridgeVersion = 'bridgeVersion';
const String _kCmdLlamaRuntimeInfo = 'llamaRuntimeInfo';
const String _kCmdCreateSession = 'createSession';
const String _kCmdDestroySession = 'destroySession';
const String _kCmdSetTag = 'setTag';
const String _kCmdEcho = 'echo';
const String _kCmdStreamEcho = 'streamEcho';
const String _kCmdStreamChat = 'streamChat';
const String _kCmdStreamCancel = 'streamCancel';
const String _kCmdLoadModel = 'loadModel';
const String _kCmdUnloadModel = 'unloadModel';
const String _kCmdModelInfo = 'modelInfo';
const String _kCmdAbortStream = 'abortStream';
const String _kCmdShutdown = 'shutdown';

class NativeBridgeWorkerException implements Exception {
  const NativeBridgeWorkerException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NativeBridgeWorkerClient {
  NativeBridgeWorkerClient._(
    this._isolate,
    this._eventPort,
    this._commandPort,
    this._eventSubscription,
  );

  final Isolate _isolate;
  final ReceivePort _eventPort;
  final SendPort _commandPort;
  final StreamSubscription<dynamic> _eventSubscription;

  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final Map<int, StreamController<String>> _streamControllers =
      <int, StreamController<String>>{};

  int _nextRequestId = 1;
  bool _isClosed = false;

  static Future<NativeBridgeWorkerClient> start() async {
    final eventPort = ReceivePort();
    final readyCompleter = Completer<SendPort>();
    late final StreamSubscription<dynamic> subscription;
    subscription = eventPort.listen((dynamic message) {
      if (message is Map<String, Object?> && message['type'] == _kTypeReady) {
        final commandPort = message['commandPort'];
        if (!readyCompleter.isCompleted && commandPort is SendPort) {
          readyCompleter.complete(commandPort);
        }
      }
    });

    final isolate = await Isolate.spawn(
      _nativeBridgeWorkerMain,
      eventPort.sendPort,
      debugName: 'native_bridge_worker',
    );
    final commandPort = await readyCompleter.future;

    final client = NativeBridgeWorkerClient._(
      isolate,
      eventPort,
      commandPort,
      subscription,
    );
    client._attachEventRouter();
    return client;
  }

  Future<String> bridgeVersion() async {
    final result = await _sendRequest(_kCmdBridgeVersion);
    return result as String;
  }

  Future<String> llamaRuntimeInfo() async {
    final result = await _sendRequest(_kCmdLlamaRuntimeInfo);
    return result as String;
  }

  Future<void> loadModel({
    required String modelPath,
    required int nCtx,
    required int nGpuLayers,
  }) async {
    await _sendRequest(
      _kCmdLoadModel,
      payload: <String, Object?>{
        'modelPath': modelPath,
        'nCtx': nCtx,
        'nGpuLayers': nGpuLayers,
      },
    );
  }

  Future<void> unloadModel() async {
    await _sendRequest(_kCmdUnloadModel);
  }

  Future<String> modelInfo() async {
    final result = await _sendRequest(_kCmdModelInfo);
    return result as String;
  }

  /// Sends an abort signal to the native session so an in-progress
  /// bridge_session_stream call stops at the next decode boundary.
  Future<void> abortStream() async {
    if (_isClosed) {
      return;
    }
    await _sendRequest(_kCmdAbortStream);
  }

  Future<void> createSession({required String tag}) async {
    await _sendRequest(
      _kCmdCreateSession,
      payload: <String, Object?>{'tag': tag},
    );
  }

  Future<void> destroySession() async {
    await _sendRequest(_kCmdDestroySession);
  }

  Future<void> setTag(String tag) async {
    await _sendRequest(_kCmdSetTag, payload: <String, Object?>{'tag': tag});
  }

  Future<String> echo(String input) async {
    final result = await _sendRequest(
      _kCmdEcho,
      payload: <String, Object?>{'input': input},
    );
    return result as String;
  }

  Stream<String> streamEcho(String input, {int maxTokens = 512}) {
    return _startStreamCommand(
      command: _kCmdStreamEcho,
      payload: <String, Object?>{
        'input': input,
        'maxTokens': maxTokens,
      },
    );
  }

  Stream<String> streamChat({
    required String systemPrompt,
    required String userPrompt,
    int maxTokens = 512,
  }) {
    return _startStreamCommand(
      command: _kCmdStreamChat,
      payload: <String, Object?>{
        'systemPrompt': systemPrompt,
        'userPrompt': userPrompt,
        'maxTokens': maxTokens,
      },
    );
  }

  Stream<String> _startStreamCommand({
    required String command,
    required Map<String, Object?> payload,
  }) {
    if (_isClosed) {
      return Stream<String>.error(
        const NativeBridgeWorkerException('Worker is closed.'),
      );
    }

    final requestId = _allocateRequestId();
    final startCompleter = Completer<Object?>();
    _pending[requestId] = startCompleter;

    final controller = StreamController<String>(
      onCancel: () async {
        _streamControllers.remove(requestId);
        try {
          await _sendRequest(
            _kCmdStreamCancel,
            payload: <String, Object?>{'streamId': requestId},
          );
        } catch (_) {
          // Ignore cancel race errors while closing.
        }
      },
    );
    _streamControllers[requestId] = controller;

    _commandPort.send(<String, Object?>{
      'id': requestId,
      'command': command,
      ...payload,
    });

    unawaited(() async {
      try {
        await startCompleter.future;
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
          await controller.close();
        }
        _streamControllers.remove(requestId);
      }
    }());

    return controller.stream;
  }

  Future<void> close() async {
    if (_isClosed) {
      return;
    }

    try {
      await _sendRequest(_kCmdShutdown);
    } catch (_) {
      // Isolate may already be dead.
    }

    _isClosed = true;

    for (final entry in _streamControllers.entries) {
      if (!entry.value.isClosed) {
        await entry.value.close();
      }
    }
    _streamControllers.clear();

    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const NativeBridgeWorkerException('Worker closed before response.'),
        );
      }
    }
    _pending.clear();

    await _eventSubscription.cancel();
    _eventPort.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  void _attachEventRouter() {
    _eventSubscription.onData((dynamic message) {
      if (message is! Map<String, Object?>) {
        return;
      }
      final type = message['type'];
      if (type == _kTypeResponse) {
        _handleResponse(message);
        return;
      }
      if (type == _kTypeStreamToken) {
        final id = message['id'];
        final token = message['token'];
        if (id is int && token is String) {
          final controller = _streamControllers[id];
          if (controller != null && !controller.isClosed) {
            controller.add(token);
          }
        }
        return;
      }
      if (type == _kTypeStreamDone) {
        final id = message['id'];
        if (id is int) {
          final controller = _streamControllers.remove(id);
          if (controller != null && !controller.isClosed) {
            controller.close();
          }
        }
        return;
      }
      if (type == _kTypeStreamError) {
        final id = message['id'];
        final error = message['error'];
        if (id is int) {
          final controller = _streamControllers.remove(id);
          if (controller != null && !controller.isClosed) {
            controller.addError(
              NativeBridgeWorkerException(
                error?.toString() ?? 'Unknown stream error.',
              ),
            );
            controller.close();
          }
        }
      }
    });
  }

  void _handleResponse(Map<String, Object?> message) {
    final id = message['id'];
    if (id is! int) {
      return;
    }
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) {
      return;
    }

    final ok = message['ok'] == true;
    if (ok) {
      completer.complete(message['result']);
      return;
    }
    final error = message['error']?.toString() ?? 'Unknown worker error.';
    completer.completeError(NativeBridgeWorkerException(error));
  }

  Future<Object?> _sendRequest(
    String command, {
    Map<String, Object?> payload = const <String, Object?>{},
  }) {
    if (_isClosed) {
      throw const NativeBridgeWorkerException('Worker is closed.');
    }

    final id = _allocateRequestId();
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _commandPort.send(<String, Object?>{
      'id': id,
      'command': command,
      ...payload,
    });
    return completer.future;
  }

  int _allocateRequestId() {
    return _nextRequestId++;
  }
}

void _pipeStreamToClient({
  required SendPort eventPort,
  required int requestId,
  required Stream<String> stream,
  required Map<int, StreamSubscription<String>> activeStreams,
}) {
  final sub = stream.listen(
    (token) {
      eventPort.send(<String, Object?>{
        'type': _kTypeStreamToken,
        'id': requestId,
        'token': token,
      });
    },
    onError: (Object error) {
      eventPort.send(<String, Object?>{
        'type': _kTypeStreamError,
        'id': requestId,
        'error': error.toString(),
      });
      activeStreams.remove(requestId);
    },
    onDone: () {
      eventPort.send(<String, Object?>{
        'type': _kTypeStreamDone,
        'id': requestId,
      });
      activeStreams.remove(requestId);
    },
    cancelOnError: true,
  );
  activeStreams[requestId] = sub;
}

@pragma('vm:entry-point')
void _nativeBridgeWorkerMain(SendPort eventPort) {
  final commandPort = ReceivePort();
  final bridge = NativeBridge.instance;
  NativeBridgeSession? session;
  final Map<int, StreamSubscription<String>> activeStreams =
      <int, StreamSubscription<String>>{};

  void sendResponse(
    int requestId, {
    required bool ok,
    Object? result,
    String? error,
  }) {
    eventPort.send(<String, Object?>{
      'type': _kTypeResponse,
      'id': requestId,
      'ok': ok,
      'result': result,
      'error': error,
    });
  }

  Future<void> shutdownWorker(int requestId) async {
    for (final stream in activeStreams.values) {
      await stream.cancel();
    }
    activeStreams.clear();
    session?.dispose();
    session = null;
    sendResponse(requestId, ok: true);
    commandPort.close();
    Isolate.exit();
  }

  eventPort.send(<String, Object?>{
    'type': _kTypeReady,
    'commandPort': commandPort.sendPort,
  });

  commandPort.listen((dynamic message) async {
    if (message is! Map<String, Object?>) {
      return;
    }
    final requestId = message['id'];
    final command = message['command'];
    if (requestId is! int || command is! String) {
      return;
    }

    try {
      switch (command) {
        case _kCmdBridgeVersion:
          sendResponse(requestId, ok: true, result: bridge.bridgeVersion());
          break;
        case _kCmdLlamaRuntimeInfo:
          final currentSession = session;
          if (currentSession == null) {
            throw const NativeBridgeWorkerException(
              'Session is required before requesting llama runtime info.',
            );
          }
          final runtimeInfo = bridge.llamaRuntimeInfo();
          sendResponse(requestId, ok: true, result: runtimeInfo);
          break;
        case _kCmdCreateSession:
          session?.dispose();
          session = bridge.createSession();
          final tag = message['tag'];
          if (tag is String) {
            session!.setTag(tag);
          }
          sendResponse(requestId, ok: true);
          break;
        case _kCmdDestroySession:
          session?.dispose();
          session = null;
          sendResponse(requestId, ok: true);
          break;
        case _kCmdSetTag:
          final currentSession = session;
          if (currentSession == null) {
            throw const NativeBridgeWorkerException('Session is not created.');
          }
          final tag = message['tag'];
          if (tag is! String) {
            throw const NativeBridgeWorkerException('Invalid tag payload.');
          }
          currentSession.setTag(tag);
          sendResponse(requestId, ok: true);
          break;
        case _kCmdEcho:
          final currentSession = session;
          if (currentSession == null) {
            throw const NativeBridgeWorkerException('Session is not created.');
          }
          final input = message['input'];
          if (input is! String) {
            throw const NativeBridgeWorkerException('Invalid echo input.');
          }
          final output = currentSession.echo(input);
          sendResponse(requestId, ok: true, result: output);
          break;
        case _kCmdStreamEcho:
          final currentSession = session;
          if (currentSession == null) {
            throw const NativeBridgeWorkerException('Session is not created.');
          }
          final input = message['input'];
          final maxTokens = message['maxTokens'];
          if (input is! String) {
            throw const NativeBridgeWorkerException('Invalid stream input.');
          }
          final stream = currentSession.streamEcho(
            input,
            maxTokens: maxTokens is int ? maxTokens : 512,
          );
          _pipeStreamToClient(
            eventPort: eventPort,
            requestId: requestId,
            stream: stream,
            activeStreams: activeStreams,
          );
          sendResponse(requestId, ok: true);
          break;
        case _kCmdStreamChat:
          final chatSession = session;
          if (chatSession == null) {
            throw const NativeBridgeWorkerException('Session is not created.');
          }
          final systemPrompt = message['systemPrompt'];
          final userPrompt = message['userPrompt'];
          final chatMaxTokens = message['maxTokens'];
          if (systemPrompt is! String || userPrompt is! String) {
            throw const NativeBridgeWorkerException('Invalid stream chat input.');
          }
          final chatStream = chatSession.streamChat(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            maxTokens: chatMaxTokens is int ? chatMaxTokens : 512,
          );
          _pipeStreamToClient(
            eventPort: eventPort,
            requestId: requestId,
            stream: chatStream,
            activeStreams: activeStreams,
          );
          sendResponse(requestId, ok: true);
          break;
        case _kCmdStreamCancel:
          final streamId = message['streamId'];
          if (streamId is int) {
            final sub = activeStreams.remove(streamId);
            await sub?.cancel();
          }
          sendResponse(requestId, ok: true);
          break;
        case _kCmdLoadModel:
          final currentSession = session;
          if (currentSession == null) {
            throw const NativeBridgeWorkerException('Session is not created.');
          }
          final modelPath = message['modelPath'];
          final nCtx = message['nCtx'];
          final nGpuLayers = message['nGpuLayers'];
          if (modelPath is! String || nCtx is! int || nGpuLayers is! int) {
            throw const NativeBridgeWorkerException(
              'Invalid load model payload.',
            );
          }
          currentSession.loadModel(
            modelPath: modelPath,
            nCtx: nCtx,
            nGpuLayers: nGpuLayers,
          );
          sendResponse(requestId, ok: true);
          break;
        case _kCmdUnloadModel:
          final currentSession = session;
          if (currentSession == null) {
            throw const NativeBridgeWorkerException('Session is not created.');
          }
          currentSession.unloadModel();
          sendResponse(requestId, ok: true);
          break;
        case _kCmdModelInfo:
          final currentSession = session;
          if (currentSession == null) {
            throw const NativeBridgeWorkerException('Session is not created.');
          }
          final info = currentSession.modelInfo();
          sendResponse(requestId, ok: true, result: info);
          break;
        case _kCmdAbortStream:
          // abortStream is fire-and-forget: we call it even when no session
          // exists so the caller does not need to guard.
          session?.abortStream();
          sendResponse(requestId, ok: true);
          break;
        case _kCmdShutdown:
          await shutdownWorker(requestId);
          break;
        default:
          throw NativeBridgeWorkerException('Unknown worker command: $command');
      }
    } catch (error) {
      sendResponse(requestId, ok: false, error: error.toString());
    }
  });
}
