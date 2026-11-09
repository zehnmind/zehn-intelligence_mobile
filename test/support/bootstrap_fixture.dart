/// The spec's start-up data example, with a real surface for the inline card.
Map<String, Object?> bootstrapJson({String baseUrl = 'https://api.example.uz'}) => {
  'format': 1,
  'spec_version': '1.0.3',
  'track': 'prod',
  'services': ['llm', 'stt', 'tts'],
  'languages': ['uz', 'ru', 'en'],
  'default_language': 'uz',
  'api': {
    'base_url': baseUrl,
    'allowed_hosts': [Uri.parse(baseUrl).host],
    'auth': {'header': 'Authorization', 'scheme': 'Bearer'},
    'headers': {'Accept-Language': '{language}'},
  },
  'tools': {
    'stores.list': {
      'method': 'GET',
      'path': '/location/venues',
      'params': [
        {'name': 'page', 'in': 'query'},
        {'name': 'category_id', 'in': 'query', 'key': 'category'},
      ],
      'headers': <String, Object?>{},
      'auth': false,
      'result': {
        'root': '/results',
        'fields': ['public_id', 'name', 'floor'],
        'max_items': 10,
      },
    },
    'locations.get': {
      'method': 'GET',
      'path': '/location/venues/{id}',
      'params': [
        {'name': 'id', 'in': 'path'},
      ],
      'auth': false,
    },
  },
  'components': {
    'cinema_details': {
      'kind': 'inline',
      'surface': {
        'createSurface': {
          'surfaceId': 'cinema_details',
          'catalogId': 'zehn.basic.v0',
          'root': 'root',
          'components': [
            {'id': 'root', 'component': 'Text', 'text': {'path': '/name'}},
          ],
        },
      },
    },
    'loyalty_page': {'kind': 'route', 'route': '/loyalty'},
  },
  'theme': {'font': 'CeraPro', 'colors': <String, Object?>{}, 'text': <String, Object?>{}, 'radius': <String, Object?>{}},
};
