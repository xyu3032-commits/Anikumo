import 'package:flutter_test/flutter_test.dart';
import 'package:anikumo/utils/crypto.dart';

// Batch 18: the DanDanPlay signature must be computable from
// explicit credentials (the ones the user pastes in 设置 →
// 弹幕设置）, not only from the build-time environment pair —
// with empty credentials the API 403s every danmaku request.
void main() {
  test('signature for explicit credentials matches the reference', () {
    // Reference: base64(sha256('myid' + '1700000000' +
    // '/api/v2/comment/123' + 'mykey')).
    expect(
      generateDandanSignatureFor(
        'myid',
        'mykey',
        '/api/v2/comment/123',
        1700000000,
      ),
      'FHerYvX6vUE8+ZkNGq6F4WsSl7iOVXvspYT+Gtq5Y3s=',
    );
  });

  test('signature depends on every input', () {
    final base = generateDandanSignatureFor('a', 'b', '/p', 1);
    expect(generateDandanSignatureFor('a2', 'b', '/p', 1), isNot(base));
    expect(generateDandanSignatureFor('a', 'b2', '/p', 1), isNot(base));
    expect(generateDandanSignatureFor('a', 'b', '/p2', 1), isNot(base));
    expect(generateDandanSignatureFor('a', 'b', '/p', 2), isNot(base));
  });
}
