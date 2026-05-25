import 'package:flutter_test/flutter_test.dart';
import 'package:ffi_learn/native/native_bridge_worker.dart';

void main() {
  late NativeBridgeWorkerClient worker;

  const testInput = 'Hello from manual dart test';

  setUpAll(() async {
    // Start native worker
    worker = await NativeBridgeWorkerClient.start();

    // Create session
    await worker.createSession(tag: 'test-session');

    // Load model
    await worker.loadModel(
      modelPath: 'model/phi3.gguf',
      nCtx: 2048,
      nGpuLayers: 0,
    );
  });

  tearDownAll(() async {
    // Cleanup
    await worker.destroySession();
    await worker.close();
  });

  test('callSessionEcho manual input test', () async {
    print('Sending input: $testInput');

    final result = await worker.echo(testInput);

    print('Echo result: $result');

    expect(result, isNotNull);
    expect(result.isNotEmpty, true);
  });
}
