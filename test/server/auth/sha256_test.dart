import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/auth/sha256.dart';

void main() {
  String hash(String text) => ziSha256Hex(utf8.encode(text));

  // FIPS 180-4 and NIST's example messages.
  test('the standard test vectors', () {
    expect(hash(''), 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    expect(hash('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(
      hash('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'),
      '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
    );
    expect(hash('a' * 1000000), 'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0');
  });

  test('a message at the edges of a block: 55, 56 and 64 bytes', () {
    // 55 bytes fit one block with the padding; 56 need a second.
    expect(hash('a' * 55), '9f4390f8d30c2dd92ec9f095b65e2b9ae9b0a925a5258e241c9f1e910f734318');
    expect(hash('a' * 56), 'b35439a4ac6f0948b6d6f9e3c6af0f5f590ce20f1bde7090ef7970686ec6738a');
    expect(hash('a' * 64), 'ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb');
  });

  test('bytes, not characters', () {
    expect(hash('Toshkent ‘ўзбек’'), hash('Toshkent ‘ўзбек’'));
    expect(hash('é'), isNot(hash('e')));
    expect(ziSha256Hex(const [0xc3, 0xa9]), hash('é'));
  });
}
