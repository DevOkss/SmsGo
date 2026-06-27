/// Returns a user-friendly error message.
/// Shows "Connection Failed" for network errors, raw message otherwise.
String friendlyError(Object e) {
  final msg = e.toString();
  if (msg.contains('ClientException') ||
      msg.contains('SocketException') ||
      msg.contains('Connection refused') ||
      msg.contains('Connection reset') ||
      msg.contains('Connection timed out') ||
      msg.contains('Network is unreachable') ||
      msg.contains('No address associated') ||
      msg.contains('Failed host lookup') ||
      msg.contains('ERR_CONNECTION') ||
      msg.contains('XMLHttpRequest error')) {
    return 'Connection Failed. Please check your internet and try again.';
  }
  return msg.replaceAll('Exception: ', '');
}
