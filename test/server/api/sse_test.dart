import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zehn_intelligence/src/server/api/sse.dart';

Future<List<SseFrame>> parse(List<String> chunks) =>
    parseSse(Stream.fromIterable(chunks.map(utf8.encode))).toList();

void main() {
  test('parses frames split across chunks', () async {
    final frames = await parse(['event: text.delta\nid: 3\nda', 'ta: {"a":1}\n\n']);
    expect(frames, hasLength(1));
    expect(frames.single.event, 'text.delta');
    expect(frames.single.id, '3');
    expect(frames.single.data, '{"a":1}');
  });

  test('joins multi-line data with newline', () async {
    final frames = await parse(['event: x\ndata: one\ndata: two\n\n']);
    expect(frames.single.data, 'one\ntwo');
  });

  test('accepts CRLF', () async {
    final frames = await parse(['event: done\r\ndata: {}\r\n\r\n']);
    expect(frames.single.event, 'done');
    expect(frames.single.data, '{}');
  });

  test('comment line is a ping frame', () async {
    final frames = await parse([': ping\n\n', 'event: done\ndata: {}\n\n']);
    expect(frames.first.isPing, isTrue);
    expect(frames.first.event, 'ping');
    expect(frames.last.isPing, isFalse);
  });

  test('frame without event is message', () async {
    final frames = await parse(['data: hi\n\n']);
    expect(frames.single.event, 'message');
  });

  test('a UTF-8 character split across chunks survives', () async {
    final bytes = utf8.encode('event: t\ndata: Купить\n\n');
    final frames = await parseSse(Stream.fromIterable([bytes.sublist(0, 18), bytes.sublist(18)])).toList();
    expect(frames.single.data, 'Купить');
  });
}
