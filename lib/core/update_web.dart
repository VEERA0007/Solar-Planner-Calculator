import 'package:url_launcher/url_launcher.dart';
import 'update_cancel.dart';

/// A web page cannot download an installer. It reloads to pick up the new hosted build.
bool get platformCanDownload => false;

Future<String?> platformDownload(String url, int sizeHint, void Function(int got, int total) onProgress, UpdateCancel cancel) async => null;

Future<String> platformInstall(String path) async {
  await launchUrl(Uri.base, webOnlyWindowName: '_self');
  return 'Reloading...';
}
