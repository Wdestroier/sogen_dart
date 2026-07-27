final class SogenException implements Exception {
  const SogenException(this.message, {this.status});

  final String message;
  final int? status;

  @override
  String toString() => status == null
      ? 'SogenException: $message'
      : 'SogenException($status): $message';
}

final class SogenCallbackException implements Exception {
  const SogenCallbackException(this.hookKey, this.error, this.stackTrace);

  final String hookKey;
  final Object error;
  final StackTrace stackTrace;

  @override
  String toString() => "Sogen callback '$hookKey' failed: $error";
}
