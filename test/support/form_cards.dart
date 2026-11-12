import 'package:zehn_intelligence/src/server/surface/surface.dart';

/// A surface of [components] whose root has the id `root`.
ZiSurface card(List<Map<String, Object?>> components) => ZiSurface.parse({
  'createSurface': {
    'surfaceId': 'test',
    'catalogId': 'zehn.basic.v1',
    'root': 'root',
    'components': components,
  },
});

const bookCard = <String, Object?>{
  'createSurface': {
    'surfaceId': 'book_table',
    'catalogId': 'zehn.basic.v1',
    'root': 'root',
    'components': [
      {
        'id': 'root',
        'component': 'Column',
        'gap': 12,
        'children': ['name', 'phone', 'send'],
      },
      {
        'id': 'name',
        'component': 'TextField',
        'field': 'name',
        'label': 'Your name',
        'checks': [
          {'rule': 'required'},
        ],
      },
      {
        'id': 'phone',
        'component': 'TextField',
        'field': 'phone',
        'label': 'Phone',
        'input': 'phone',
      },
      {
        'id': 'send',
        'component': 'Button',
        'label': 'Book',
        'action': {'name': 'submit'},
      },
    ],
  },
};
