class LlamaBridgeException implements Exception {
  const LlamaBridgeException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => 'LlamaBridgeException($message)';
}
