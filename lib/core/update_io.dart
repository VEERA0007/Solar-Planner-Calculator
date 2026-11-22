import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'update_cancel.dart';

/// Phones and Windows can download the new build inside the app.
bool get platformCanDownload => Platform.isAndroid || Platform.isWindows || Platform.isIOS;

/// Downloads [url] to a temporary file, reporting (received, total) bytes.
/// Returns the file path, or null when the user cancelled.
Future<String?> platformDownload(String url, int sizeHint, void Function(int got, int total) onProgress, UpdateCancel cancel) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}${Platform.pathSeparator}${Uri.parse(url).pathSegments.last}');
  final client = http.Client();
  cancel.client = client;
  IOSink? sink;
  try {
    final resp = await client.send(http.Request('GET', Uri.parse(url)));
    if (resp.statusCode != 200) throw 'The server answered ${resp.statusCode}';
    final total = (resp.contentLength ?? 0) > 0 ? resp.contentLength! : sizeHint;
    sink = file.openWrite();
    var got = 0;
    await for (final chunk in resp.stream) {
      if (cancel.cancelled) break;
      sink.add(chunk);
      got += chunk.length;
      onProgress(got, total);
    }
    await sink.close();
    sink = null;
    if (cancel.cancelled) {
      try {
        file.deleteSync();
      } catch (_) {}
      return null;
    }
    return file.path;
  } catch (e) {
    try {
      await sink?.close();
    } catch (_) {}
    try {
      file.deleteSync();
    } catch (_) {}
    if (cancel.cancelled) return null;
    rethrow;
  } finally {
    client.close();
  }
}

/// Hands the downloaded file to the system installer (Android), replaces the
/// running copy and restarts (Windows), or opens it (iOS).
Future<String> platformInstall(String path) async {
  if (Platform.isAndroid) {
    final r = await OpenFilex.open(path, type: 'application/vnd.android.package-archive');
    return r.type == ResultType.done ? 'The installer is open. Tap Install to finish updating.' : 'Could not open the installer: ${r.message}';
  }
  if (Platform.isWindows) {
    final exe = Platform.resolvedExecutable;
    final appDir = File(exe).parent.path;
    final tmp = Directory.systemTemp.path;
    final stage = '$tmp\\SolarPlannerUpdate';
    final bat = File('$tmp\\solar_planner_update.bat');
    final lines = [
      '@echo off',
      'timeout /t 2 /nobreak >nul',
      'rmdir /s /q "$stage" 2>nul',
      'powershell -NoProfile -Command "Expand-Archive -Force -LiteralPath \'$path\' -DestinationPath \'$stage\'"',
      'xcopy /E /Y /I /Q "$stage\\*" "$appDir\\" >nul',
      'start "" "$exe"',
    ];
    bat.writeAsStringSync('${lines.join('\r\n')}\r\n');
    await Process.start('cmd', ['/c', bat.path], mode: ProcessStartMode.detached);
    exit(0);
  }
  final r = await OpenFilex.open(path);
  return r.type == ResultType.done ? 'Opened. Install the .ipa with your sideloading tool.' : 'Saved at $path';
}
