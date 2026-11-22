import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'update_cancel.dart';
import 'update_web.dart' if (dart.library.io) 'update_io.dart' as plat;

export 'update_cancel.dart';

/// GitHub repository whose Releases hold new builds. Must be public for the check to work.
const String kUpdateRepo = 'VEERA0007/Solar-Planner-Calculator';

class UpdateInfo {
  final int build;
  final String versionName;
  final String? downloadUrl; // direct file for this platform, if any
  final String pageUrl;
  final int size; // bytes of the download, 0 when unknown
  const UpdateInfo(this.build, this.versionName, this.downloadUrl, this.pageUrl, {this.size = 0});

  /// "v0.0.7 · 136" for the update card.
  String get label {
    final v = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(versionName)?.group(1);
    return v == null ? 'build $build' : 'v$v · $build';
  }
}

class UpdateResult {
  final UpdateInfo? update; // non-null when a newer build exists
  final String message;
  final String currentVersion;
  final String currentLabel;
  const UpdateResult(this.update, this.message, this.currentVersion, {this.currentLabel = ''});
}

Future<UpdateResult> checkForUpdate() async {
  String current = '', label = '';
  try {
    final info = await PackageInfo.fromPlatform();
    current = '${info.version} (build ${info.buildNumber})';
    label = 'v${info.version} · ${info.buildNumber}';
    final myBuild = int.tryParse(info.buildNumber) ?? 0;
    final r = await http
        .get(Uri.parse('https://api.github.com/repos/$kUpdateRepo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10));
    if (r.statusCode == 404 || r.statusCode == 403) {
      return UpdateResult(null, 'Update check unavailable (the release page is private).', current, currentLabel: label);
    }
    if (r.statusCode != 200) return UpdateResult(null, 'Update check failed (${r.statusCode}).', current, currentLabel: label);
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String?) ?? '';
    final build = int.tryParse(RegExp(r'(\d+)$').firstMatch(tag)?.group(1) ?? '') ?? 0;
    final name = (j['name'] as String?) ?? tag;
    final page = (j['html_url'] as String?) ?? 'https://github.com/$kUpdateRepo/releases';
    if (build <= myBuild) return UpdateResult(null, 'You are on the latest version.', current, currentLabel: label);

    String? url;
    var size = 0;
    final assets = (j['assets'] as List?) ?? const [];
    final want = _assetMatcher();
    if (want != null) {
      for (final a in assets) {
        final n = ((a as Map)['name'] as String?) ?? '';
        if (want(n.toLowerCase())) {
          url = a['browser_download_url'] as String?;
          size = (a['size'] as num?)?.toInt() ?? 0;
          break;
        }
      }
    }
    return UpdateResult(UpdateInfo(build, name, url, page, size: size), 'Update available: $name', current, currentLabel: label);
  } catch (_) {
    return UpdateResult(null, 'Could not check for updates (offline?).', current, currentLabel: label);
  }
}

bool Function(String)? _assetMatcher() {
  if (kIsWeb) return null;
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      return (n) => n.endsWith('.apk') && !n.contains('arm64');
    case TargetPlatform.windows:
      return (n) => n.contains('windows') && n.endsWith('.zip');
    case TargetPlatform.iOS:
      return (n) => n.endsWith('.ipa');
    default:
      return null;
  }
}

Future<void> openUpdate(UpdateInfo u) async {
  final target = u.downloadUrl ?? u.pageUrl;
  await launchUrl(Uri.parse(target), mode: LaunchMode.externalApplication);
}

/// True when this platform can download and install the update itself.
bool get canDownloadUpdate => plat.platformCanDownload;

Future<String?> downloadUpdate(String url, int sizeHint, void Function(int got, int total) onProgress, UpdateCancel cancel) =>
    plat.platformDownload(url, sizeHint, onProgress, cancel);

Future<String> installUpdate(String path) => plat.platformInstall(path);
