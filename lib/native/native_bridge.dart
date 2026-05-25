import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

final class _BridgeBindings {
  _BridgeBindings(DynamicLibrary dylib)
    : bridgeVersion = dylib
          .lookupFunction<_BridgeVersionNative, _BridgeVersionDart>(
            'bridge_version',
          ),
      bridgeStatusToCstr = dylib
          .lookupFunction<_BridgeStatusToCstrNative, _BridgeStatusToCstrDart>(
            'bridge_status_to_cstr',
          ),
      bridgeEchoAlloc = dylib
          .lookupFunction<_BridgeEchoAllocNative, _BridgeEchoAllocDart>(
            'bridge_echo_alloc',
          ),
      bridgeLlamaRuntimeInfoAlloc = dylib
          .lookupFunction<
            _BridgeLlamaRuntimeInfoAllocNative,
            _BridgeLlamaRuntimeInfoAllocDart
          >('bridge_llama_runtime_info_alloc'),
      bridgeStringFree = dylib
          .lookupFunction<_BridgeStringFreeNative, _BridgeStringFreeDart>(
            'bridge_string_free',
          ),
      bridgeSessionCreate = dylib
          .lookupFunction<_BridgeSessionCreateNative, _BridgeSessionCreateDart>(
            'bridge_session_create',
          ),
      bridgeSessionDestroy = dylib
          .lookupFunction<
            _BridgeSessionDestroyNative,
            _BridgeSessionDestroyDart
          >('bridge_session_destroy'),
      bridgeSessionSetTag = dylib
          .lookupFunction<_BridgeSessionSetTagNative, _BridgeSessionSetTagDart>(
            'bridge_session_set_tag',
          ),
      bridgeSessionEchoAlloc = dylib
          .lookupFunction<
            _BridgeSessionEchoAllocNative,
            _BridgeSessionEchoAllocDart
          >('bridge_session_echo_alloc'),
      bridgeSessionStream = dylib
          .lookupFunction<_BridgeSessionStreamNative, _BridgeSessionStreamDart>(
            'bridge_session_stream',
          ),
      bridgeSessionLoadModel = dylib
          .lookupFunction<
            _BridgeSessionLoadModelNative,
            _BridgeSessionLoadModelDart
          >('bridge_session_load_model'),
      bridgeSessionUnloadModel = dylib
          .lookupFunction<
            _BridgeSessionUnloadModelNative,
            _BridgeSessionUnloadModelDart
          >('bridge_session_unload_model'),
      bridgeSessionModelInfoAlloc = dylib
          .lookupFunction<
            _BridgeSessionModelInfoAllocNative,
            _BridgeSessionModelInfoAllocDart
          >('bridge_session_model_info_alloc'),
      bridgeSessionAbortStream = dylib
          .lookupFunction<
            _BridgeSessionAbortStreamNative,
            _BridgeSessionAbortStreamDart
          >('bridge_session_abort_stream');

  final _BridgeVersionDart bridgeVersion;
  final _BridgeStatusToCstrDart bridgeStatusToCstr;
  final _BridgeEchoAllocDart bridgeEchoAlloc;
  final _BridgeLlamaRuntimeInfoAllocDart bridgeLlamaRuntimeInfoAlloc;
  final _BridgeStringFreeDart bridgeStringFree;
  final _BridgeSessionCreateDart bridgeSessionCreate;
  final _BridgeSessionDestroyDart bridgeSessionDestroy;
  final _BridgeSessionSetTagDart bridgeSessionSetTag;
  final _BridgeSessionEchoAllocDart bridgeSessionEchoAlloc;
  final _BridgeSessionStreamDart bridgeSessionStream;
  final _BridgeSessionLoadModelDart bridgeSessionLoadModel;
  final _BridgeSessionUnloadModelDart bridgeSessionUnloadModel;
  final _BridgeSessionModelInfoAllocDart bridgeSessionModelInfoAlloc;
  final _BridgeSessionAbortStreamDart bridgeSessionAbortStream;
}

typedef _BridgeVersionNative = Pointer<Utf8> Function();
typedef _BridgeVersionDart = Pointer<Utf8> Function();

typedef _BridgeStatusToCstrNative = Pointer<Utf8> Function(Int32);
typedef _BridgeStatusToCstrDart = Pointer<Utf8> Function(int);

typedef _BridgeEchoAllocNative =
    Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>);
typedef _BridgeEchoAllocDart =
    int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>);

typedef _BridgeLlamaRuntimeInfoAllocNative =
    Int32 Function(Pointer<Pointer<Utf8>>);
typedef _BridgeLlamaRuntimeInfoAllocDart = int Function(Pointer<Pointer<Utf8>>);

typedef _BridgeStringFreeNative = Void Function(Pointer<Utf8>);
typedef _BridgeStringFreeDart = void Function(Pointer<Utf8>);

final class BridgeSessionPointer extends Opaque {}

typedef _BridgeSessionCreateNative = Pointer<BridgeSessionPointer> Function();
typedef _BridgeSessionCreateDart = Pointer<BridgeSessionPointer> Function();

typedef _BridgeSessionDestroyNative =
    Void Function(Pointer<BridgeSessionPointer>);
typedef _BridgeSessionDestroyDart =
    void Function(Pointer<BridgeSessionPointer>);

typedef _BridgeSessionSetTagNative =
    Int32 Function(Pointer<BridgeSessionPointer>, Pointer<Utf8>);
typedef _BridgeSessionSetTagDart =
    int Function(Pointer<BridgeSessionPointer>, Pointer<Utf8>);

typedef _BridgeSessionEchoAllocNative =
    Int32 Function(
      Pointer<BridgeSessionPointer>,
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
    );
typedef _BridgeSessionEchoAllocDart =
    int Function(
      Pointer<BridgeSessionPointer>,
      Pointer<Utf8>,
      Pointer<Pointer<Utf8>>,
    );

typedef _BridgeTokenCallbackNative =
    Void Function(Pointer<Utf8>, Pointer<Void>);
typedef _BridgeSessionStreamNative =
    Int32 Function(
      Pointer<BridgeSessionPointer>,
      Pointer<Utf8>,
      Pointer<NativeFunction<_BridgeTokenCallbackNative>>,
      Pointer<Void>,
    );
typedef _BridgeSessionStreamDart =
    int Function(
      Pointer<BridgeSessionPointer>,
      Pointer<Utf8>,
      Pointer<NativeFunction<_BridgeTokenCallbackNative>>,
      Pointer<Void>,
    );

typedef _BridgeSessionLoadModelNative =
    Int32 Function(Pointer<BridgeSessionPointer>, Pointer<Utf8>, Int32, Int32);
typedef _BridgeSessionLoadModelDart =
    int Function(Pointer<BridgeSessionPointer>, Pointer<Utf8>, int, int);

typedef _BridgeSessionUnloadModelNative =
    Int32 Function(Pointer<BridgeSessionPointer>);
typedef _BridgeSessionUnloadModelDart =
    int Function(Pointer<BridgeSessionPointer>);

typedef _BridgeSessionModelInfoAllocNative =
    Int32 Function(Pointer<BridgeSessionPointer>, Pointer<Pointer<Utf8>>);
typedef _BridgeSessionModelInfoAllocDart =
    int Function(Pointer<BridgeSessionPointer>, Pointer<Pointer<Utf8>>);

typedef _BridgeSessionAbortStreamNative =
    Int32 Function(Pointer<BridgeSessionPointer>);
typedef _BridgeSessionAbortStreamDart =
    int Function(Pointer<BridgeSessionPointer>);

typedef _TokenSink = void Function(String token);
final Map<int, _TokenSink> _activeTokenSinks = <int, _TokenSink>{};
int _nextTokenStreamId = 1;

final Pointer<NativeFunction<_BridgeTokenCallbackNative>>
_nativeTokenCallbackPointer = Pointer.fromFunction<_BridgeTokenCallbackNative>(
  _nativeTokenCallback,
);

@pragma('vm:entry-point')
void _nativeTokenCallback(Pointer<Utf8> tokenPtr, Pointer<Void> userData) {
  if (tokenPtr == nullptr || userData == nullptr) {
    return;
  }
  final streamId = userData.cast<Int64>().value;
  final sink = _activeTokenSinks[streamId];
  if (sink == null) {
    return;
  }
  sink(tokenPtr.toDartString());
}

DynamicLibrary _openNativeLibrary() {
  if (Platform.isAndroid) {
    return DynamicLibrary.open('libllama_bridge.so');
  }
  if (Platform.isIOS || Platform.isMacOS) {
    // iOS does not support loading arbitrary dynamic libraries from app storage.
    // Symbols must be linked into the process image.
    return DynamicLibrary.process();
  }
  throw UnsupportedError('Native bridge is not available on this platform.');
}

class NativeBridge {
  NativeBridge._() : _bindings = _BridgeBindings(_openNativeLibrary());

  static final NativeBridge instance = NativeBridge._();

  final _BridgeBindings _bindings;

  String bridgeVersion() {
    final versionPtr = _bindings.bridgeVersion();
    return versionPtr.toDartString();
  }

  String echo(String input) {
    final inputPtr = input.toNativeUtf8();
    final outPtr = calloc<Pointer<Utf8>>();
    try {
      final status = _bindings.bridgeEchoAlloc(inputPtr, outPtr);
      _throwIfError(status, operation: 'bridge_echo_alloc');
      return _readAndFreeNativeUtf8(outPtr.value);
    } finally {
      calloc.free(outPtr);
      malloc.free(inputPtr);
    }
  }

  NativeBridgeSession createSession() {
    final pointer = _bindings.bridgeSessionCreate();
    if (pointer == nullptr) {
      throw StateError('Failed to create native bridge session.');
    }
    return NativeBridgeSession._(_bindings, pointer);
  }

  String llamaRuntimeInfo() {
    final outPtr = calloc<Pointer<Utf8>>();
    try {
      final status = _bindings.bridgeLlamaRuntimeInfoAlloc(outPtr);
      _throwIfError(status, operation: 'bridge_llama_runtime_info_alloc');
      return _readAndFreeNativeUtf8(outPtr.value);
    } finally {
      calloc.free(outPtr);
    }
  }

  void _throwIfError(int status, {required String operation}) {
    if (status == 0) {
      return;
    }
    final messagePtr = _bindings.bridgeStatusToCstr(status);
    final statusLabel = messagePtr.toDartString();
    throw BridgeNativeException(
      operation: operation,
      statusCode: status,
      statusLabel: statusLabel,
    );
  }

  String _readAndFreeNativeUtf8(Pointer<Utf8> ptr) {
    if (ptr == nullptr) {
      throw const BridgeNativeException(
        operation: 'native_output',
        statusCode: -1,
        statusLabel: 'native_returned_null_output',
      );
    }
    try {
      return ptr.toDartString();
    } finally {
      _bindings.bridgeStringFree(ptr);
    }
  }
}

class NativeBridgeSession {
  NativeBridgeSession._(this._bindings, this._pointer);

  final _BridgeBindings _bindings;
  Pointer<BridgeSessionPointer> _pointer;
  bool _isDisposed = false;
  bool _isClosing = false;
  int _activeStreams = 0;

  bool get isDisposed => _isDisposed;
  bool get isClosing => _isClosing;

  void setTag(String tag) {
    _ensureActive();
    final tagPtr = tag.toNativeUtf8();
    try {
      final result = _bindings.bridgeSessionSetTag(_pointer, tagPtr);
      if (result != 0) {
        _bridgeThrow(result, operation: 'bridge_session_set_tag');
      }
    } finally {
      malloc.free(tagPtr);
    }
  }

  String echo(String input) {
    _ensureActive();
    final inputPtr = input.toNativeUtf8();
    final outPtr = calloc<Pointer<Utf8>>();
    try {
      final status = _bindings.bridgeSessionEchoAlloc(
        _pointer,
        inputPtr,
        outPtr,
      );
      if (status != 0) {
        _bridgeThrow(status, operation: 'bridge_session_echo_alloc');
      }
      final outputPtr = outPtr.value;
      if (outputPtr == nullptr) {
        throw const BridgeNativeException(
          operation: 'bridge_session_echo_alloc',
          statusCode: -1,
          statusLabel: 'native_returned_null_output',
        );
      }
      try {
        return outputPtr.toDartString();
      } finally {
        _bindings.bridgeStringFree(outputPtr);
      }
    } finally {
      calloc.free(outPtr);
      malloc.free(inputPtr);
    }
  }

  Stream<String> streamEcho(String input) {
    _ensureActive();

    if (_activeStreams > 0) {
      throw StateError('Only one active stream is supported per session.');
    }

    late StreamController<String> controller;

    controller = StreamController<String>(sync: true);

    final inputPtr = input.toNativeUtf8();

    final userData = calloc<Int64>();

    final streamId = _nextTokenStreamId++;

    userData.value = streamId;

    _activeTokenSinks[streamId] = (token) {
      if (controller.isClosed) {
        return;
      }

      controller.add(token);
    };

    _activeStreams += 1;

    Future.microtask(() {
      try {
        final status = _bindings.bridgeSessionStream(
          _pointer,
          inputPtr,
          _nativeTokenCallbackPointer,
          userData.cast<Void>(),
        );

        if (status != 0) {
          _bridgeThrow(status, operation: 'bridge_session_stream');
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) {
          controller.addError(error, stackTrace);
        }
      } finally {
        _activeTokenSinks.remove(streamId);

        calloc.free(userData);

        malloc.free(inputPtr);

        _activeStreams -= 1;

        if (_isClosing && _activeStreams == 0) {
          _doDispose();
        }

        if (!controller.isClosed) {
          controller.close();
        }
      }
    });

    return controller.stream;
  }

  // Stream<String> streamEcho(String input) {
  //   _ensureActive();
  //   if (_activeStreams > 0) {
  //     throw StateError('Only one active stream is supported per session.');
  //   }

  //   final controller = StreamController<String>(sync: true);
  //   final inputPtr = input.toNativeUtf8();
  //   final userData = calloc<Int64>();
  //   final streamId = _nextTokenStreamId++;
  //   userData.value = streamId;
  //   _activeTokenSinks[streamId] = (token) {
  //     if (!controller.isClosed) {
  //       scheduleMicrotask(() {
  //         if (!controller.isClosed) {
  //           controller.add(token);
  //         }
  //       });
  //     }
  //   };
  //   _activeStreams += 1;

  //   Future<void>(() {
  //     try {
  //       final status = _bindings.bridgeSessionStream(
  //         _pointer,
  //         inputPtr,
  //         _nativeTokenCallbackPointer,
  //         userData.cast<Void>(),
  //       );
  //       if (status != 0) {
  //         _bridgeThrow(status, operation: 'bridge_session_stream');
  //       }
  //     } catch (error, stackTrace) {
  //       if (!controller.isClosed) {
  //         controller.addError(error, stackTrace);
  //       }
  //     } finally {
  //       _activeTokenSinks.remove(streamId);
  //       calloc.free(userData);
  //       malloc.free(inputPtr);
  //       _activeStreams -= 1;
  //       if (_isClosing && _activeStreams == 0) {
  //         _doDispose();
  //       }
  //       controller.close();
  //     }
  //   });

  //   return controller.stream;
  // }

  void dispose() {
    if (_isDisposed || _isClosing) {
      return;
    }
    if (_activeStreams > 0) {
      _isClosing = true;
      return;
    }
    _doDispose();
  }

  void loadModel({
    required String modelPath,
    required int nCtx,
    required int nGpuLayers,
  }) {
    _ensureActive();
    final pathPtr = modelPath.toNativeUtf8();
    try {
      final status = _bindings.bridgeSessionLoadModel(
        _pointer,
        pathPtr,
        nCtx,
        nGpuLayers,
      );
      if (status != 0) {
        _bridgeThrow(status, operation: 'bridge_session_load_model');
      }
    } finally {
      malloc.free(pathPtr);
    }
  }

  void unloadModel() {
    _ensureActive();
    final status = _bindings.bridgeSessionUnloadModel(_pointer);
    if (status != 0) {
      _bridgeThrow(status, operation: 'bridge_session_unload_model');
    }
  }

  /// Signals the native generation loop to stop at its next decode step.
  /// This is safe to call from any isolate while [streamEcho] is in progress.
  void abortStream() {
    if (_isDisposed || _isClosing || _pointer == nullptr) {
      return;
    }
    _bindings.bridgeSessionAbortStream(_pointer);
  }

  String modelInfo() {
    _ensureActive();
    final outPtr = calloc<Pointer<Utf8>>();
    try {
      final status = _bindings.bridgeSessionModelInfoAlloc(_pointer, outPtr);
      if (status != 0) {
        _bridgeThrow(status, operation: 'bridge_session_model_info_alloc');
      }
      final infoPtr = outPtr.value;
      if (infoPtr == nullptr) {
        throw const BridgeNativeException(
          operation: 'bridge_session_model_info_alloc',
          statusCode: -1,
          statusLabel: 'native_returned_null_output',
        );
      }
      try {
        return infoPtr.toDartString();
      } finally {
        _bindings.bridgeStringFree(infoPtr);
      }
    } finally {
      calloc.free(outPtr);
    }
  }

  void _ensureActive() {
    if (_isDisposed || _isClosing || _pointer == nullptr) {
      throw StateError('Bridge session is already disposed.');
    }
  }

  Never _bridgeThrow(int status, {required String operation}) {
    final messagePtr = _bindings.bridgeStatusToCstr(status);
    final statusLabel = messagePtr.toDartString();
    throw BridgeNativeException(
      operation: operation,
      statusCode: status,
      statusLabel: statusLabel,
    );
  }

  void _doDispose() {
    if (_isDisposed || _pointer == nullptr) {
      return;
    }
    _bindings.bridgeSessionDestroy(_pointer);
    _pointer = nullptr.cast<BridgeSessionPointer>();
    _isClosing = false;
    _isDisposed = true;
  }
}

class BridgeNativeException implements Exception {
  const BridgeNativeException({
    required this.operation,
    required this.statusCode,
    required this.statusLabel,
  });

  final String operation;
  final int statusCode;
  final String statusLabel;

  @override
  String toString() {
    return 'BridgeNativeException(operation: $operation, '
        'statusCode: $statusCode, statusLabel: $statusLabel)';
  }
}
