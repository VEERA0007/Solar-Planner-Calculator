import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:calculator/core/usc.dart';
import 'package:calculator/core/usc_http.dart';

void main() {
  group('captcha image', () {
    test('accepts a data URL', () {
      final bytes = decodeCaptchaImage('data:image/png;base64,${base64Encode([1, 2, 3])}');
      expect(bytes, [1, 2, 3]);
    });

    test('accepts plain base64', () {
      expect(decodeCaptchaImage(base64Encode([9, 8])), [9, 8]);
    });

    test('returns null for empty or broken text', () {
      expect(decodeCaptchaImage(''), isNull);
      expect(decodeCaptchaImage('data:image/png;base64,@@@'), isNull);
    });
  });

  test('only TGSPDCL asks for a captcha', () {
    final src = HttpUscSource('https://example.invalid');
    expect(src.needsCaptcha(discomByCode('TGSPDCL')!), isTrue);
    expect(src.needsCaptcha(discomByCode('TGNPDCL')!), isFalse);
  });
}
