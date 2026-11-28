/// One inverter login attempt, kept on the device. The password is never stored.
class InverterLoginItem {
  final DateTime at;
  final String brand;
  final String authMode; // website | api
  final String account; // username, or a masked API key. Never the password.
  final bool ok;
  final String message;

  const InverterLoginItem({
    required this.at,
    required this.brand,
    required this.authMode,
    required this.account,
    required this.ok,
    required this.message,
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
      };

  factory InverterLoginItem.fromJson(Map<String, dynamic> j) => InverterLoginItem(
        at: DateTime.tryParse((j['at'] as String?) ?? '') ?? DateTime.now(),
        brand: (j['brand'] as String?) ?? '',
        authMode: (j['authMode'] as String?) ?? 'website',
        account: (j['account'] as String?) ?? '',
        ok: (j['ok'] as bool?) ?? false,
        message: (j['message'] as String?) ?? '',
      );
}
