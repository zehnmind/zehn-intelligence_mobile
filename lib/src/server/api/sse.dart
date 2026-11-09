import 'dart:async';
import 'dart:convert';

/// One server-sent event. A comment line (`: ping`) becomes a frame whose
/// [event] is `ping`, so a watchdog can see the server is still there.
class SseFrame {
  const SseFrame({required this.event, required this.data, this.id});

  final String event;
  final String data;
  final String? id;

  bool get isPing => event == 'ping';
}

/// Splits a `text/event-stream` body into frames.
Stream<SseFrame> parseSse(Stream<List<int>> bytes) async* {
  String? event;
  String? id;
  final data = <String>[];
  var comment = false;

  await for (final line in bytes.transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) {
      if (data.isNotEmpty || event != null) {
        yield SseFrame(event: event ?? 'message', data: data.join('\n'), id: id);
      } else if (comment) {
        yield const SseFrame(event: 'ping', data: '');
      }
      event = null;
      id = null;
      data.clear();
      comment = false;
      continue;
    }
    if (line.startsWith(':')) {
      comment = true;
      continue;
    }
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'event':
        event = value;
      case 'data':
        data.add(value);
      case 'id':
        id = value;
    }
  }
}
