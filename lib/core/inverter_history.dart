import 'backend_service.dart';

/// One inverter login attempt, kept on the device. The password is never stored.
class InverterLoginItem {
  final DateTime at;
  final String brand;
  final String authMode; // website | api
  final String account; // username, or a masked API key. Never the password.
  final bool ok;
  final String message;
  /// Account settings used for this attempt (no password, no API secret).
  final InverterConfig? cfg;
  /// Data returned by this attempt, if it succeeded.
  final InverterSnapshot? snap;

  const InverterLoginItem({
    required this.at,
    required this.brand,
    required this.authMode,
    required this.account,
    required this.ok,
    required this.message,
    this.cfg,
    this.snap,
  });

  /// Shows only the last 4 characters of an API key.
  static String maskKey(String key) => key.length <= 4 ? '••••' : '••••${key.substring(key.length - 4)}';

  Map<String, dynamic> toJson() => {
        'at': at.toIso8601String(),
        'brand': brand,
        'authMode': authMode,
        'account': account,
        'ok': ok,
        'message': message,
        'cfg': cfg?.toJson(),
        'snap': snap?.toJson(),
      };

  factory InverterLoginItem.fromJson(Map<String, dynamic> j) => InverterLoginItem(
        at: DateTime.tryParse((j['at'] as String?) ?? '') ?? DateTime.now(),
        brand: (j['brand'] as String?) ?? '',
        authMode: (j['authMode'] as String?) ?? 'website',
        account: (j['account'] as String?) ?? '',
        ok: (j['ok'] as bool?) ?? false,
        message: (j['message'] as String?) ?? '',
        cfg: j['cfg'] is Map ? InverterConfig.fromJson((j['cfg'] as Map).cast<String, dynamic>()) : null,
        snap: j['snap'] is Map ? InverterSnapshot.fromJson((j['snap'] as Map).cast<String, dynamic>()) : null,
      );
}
