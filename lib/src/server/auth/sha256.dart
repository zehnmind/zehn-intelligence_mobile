/// SHA-256 of [message] as 64 lower-case hex characters.
///
/// What the SDK keeps of a user is only a fingerprint (`ZiSignOutWatch`), so
/// that no token or user id is ever written to a file. It is small enough to
/// carry here rather than a dependency for one call.
String ziSha256Hex(List<int> message) {
  final words = List<int>.filled(64, 0);
  final state = [..._initial];

  // The message, a 1 bit, zeros to 56 bytes of a 64-byte block, and its length in bits.
  final padded = <int>[...message, 0x80];
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  final bits = message.length * 8;
  for (var shift = 56; shift >= 0; shift -= 8) {
    padded.add((bits >> shift) & 0xff);
  }

  for (var block = 0; block < padded.length; block += 64) {
    for (var i = 0; i < 16; i++) {
      final at = block + i * 4;
      words[i] = (padded[at] << 24) | (padded[at + 1] << 16) | (padded[at + 2] << 8) | padded[at + 3];
    }
    for (var i = 16; i < 64; i++) {
      final a = words[i - 15];
      final b = words[i - 2];
      final s0 = _rotr(a, 7) ^ _rotr(a, 18) ^ (a >> 3);
      final s1 = _rotr(b, 17) ^ _rotr(b, 19) ^ (b >> 10);
      words[i] = (words[i - 16] + s0 + words[i - 7] + s1) & _mask;
    }
    var [a, b, c, d, e, f, g, h] = state;
    for (var i = 0; i < 64; i++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final choose = (e & f) ^ (~e & _mask & g);
      final t1 = (h + s1 + choose + _k[i] + words[i]) & _mask;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + majority) & _mask;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & _mask;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & _mask;
    }
    final next = [a, b, c, d, e, f, g, h];
    for (var i = 0; i < 8; i++) {
      state[i] = (state[i] + next[i]) & _mask;
    }
  }
  return [for (final word in state) word.toRadixString(16).padLeft(8, '0')].join();
}

const _mask = 0xffffffff;

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & _mask;

const _initial = [
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19, //
];

const _k = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, //
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, //
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, //
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, //
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, //
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3, //
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2, //
];
