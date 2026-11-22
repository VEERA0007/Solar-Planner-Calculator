import 'package:http/http.dart' as http;

/// Lets the Cancel button stop a running download.
class UpdateCancel {
  bool cancelled = false;
  http.Client? client;
  void cancel() {
    cancelled = true;
    client?.close();
  }
}
