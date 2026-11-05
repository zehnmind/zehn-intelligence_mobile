import '../config/agent_remote_config.dart';

/// What a field holds, as a dashboard card can use it.
enum CardFieldType { text, number, money, date, image, flag, list }

/// One field a coded card exposes to dashboard cards: its name, its type,
/// and for a list, its items' own fields.
class CardFieldSchema {
  const CardFieldSchema(this.name, this.type, {this.fields = const []});

  final String name;
  final CardFieldType type;

  /// A list's item fields. Empty for every other type.
  final List<CardFieldSchema> fields;

  /// Reads the `fields` a manifest records for a card. A field of a type
  /// this build does not know is left out. Null when [json] is not a list.
  static List<CardFieldSchema>? listFromJson(Object? json) {
    if (json is! List) return null;
    return [for (final item in json) ?_fromJson(item)];
  }

  static CardFieldSchema? _fromJson(Object? json) {
    if (json is! Map) return null;
    final name = json['name'];
    final type = CardFieldType.values.asNameMap()[json['type']];
    if (name is! String || type == null) return null;
    return CardFieldSchema(
      name,
      type,
      fields: type == CardFieldType.list
          ? listFromJson(json['fields']) ?? const []
          : const [],
    );
  }
}

/// A destination or a tool a dashboard card may name: its arguments, and
/// whether a card may run it.
class CardTarget {
  const CardTarget({
    this.args = const {},
    this.required = const {},
    this.read = true,
  });

  final Set<String> args;
  final Set<String> required;

  /// Only reads run from a card. A destination is always true.
  final bool read;
}

/// Checks a dashboard card against what an app's code declares: the card it
/// stands beside and that card's fields, the destinations, the tools.
///
/// Pure Dart, so the phone, a backend's publish warnings (fed the
/// manifest) and tests all run the same check.
abstract final class AgentCardCheck {
  /// What is wrong with [card], or nothing.
  ///
  /// [cards] maps every coded card type to its declared fields (null when
  /// it declares none).
  static List<String> problems(
    AgentCardSpec card, {
    required Map<String, List<CardFieldSchema>?> cards,
    required Map<String, CardTarget> destinations,
    required Map<String, CardTarget> tools,
  }) {
    final path = 'cards.${card.type}';
    if (cards.containsKey(card.type)) {
      return ['$path is a card the app already has'];
    }
    if (!cards.containsKey(card.base)) {
      return ['$path.for ${card.base} is not a card of this app'];
    }
    final fields = cards[card.base];
    if (fields == null || fields.isEmpty) {
      return ['$path.for ${card.base} declares no fields in this app version'];
    }
    final check = _Check(destinations, tools);
    final scope = _Scope(card.base, fields);
    for (var i = 0; i < card.blocks.length; i++) {
      check.block(card.blocks[i], '$path.blocks[$i]', scope);
    }
    if (card.tap case final tap?) check.action(tap, '$path.tap', scope);
    return check.problems.toList();
  }

  /// [problems], against what an app version's manifest records: its cards
  /// and their fields, its destinations and its tools. What a backend warns
  /// about when publishing, and what `register` reports.
  static List<String> againstManifest(
    AgentCardSpec card,
    Map<String, Object?> manifest,
  ) {
    List<Map<Object?, Object?>> items(String key) => [
      for (final item in (manifest[key] as List?) ?? const [])
        if (item is Map) item,
    ];
    CardTarget target(Map<Object?, Object?> item, {bool read = true}) {
      final args = item['args'] is Map ? item['args']! as Map : const {};
      return CardTarget(
        args: {for (final name in args.keys) '$name'},
        required: {
          for (final MapEntry(:key, :value) in args.entries)
            if (value is Map && value['required'] == true) '$key',
        },
        read: read,
      );
    }

    return problems(
      card,
      cards: {
        for (final component in items('components'))
          '${component['type']}': component['entity'] == true
              ? CardFieldSchema.listFromJson(component['fields'])
              : null,
      },
      destinations: {
        for (final screen in items('destinations'))
          '${screen['id']}': target(screen),
      },
      tools: {
        for (final tool in items('tools'))
          '${tool['name']}': target(tool, read: tool['kind'] == 'read'),
      },
    );
  }
}

class _Scope {
  _Scope(this.name, List<CardFieldSchema> fields)
    : fields = {for (final field in fields) field.name: field};

  _Scope._(this.name, this.fields);

  /// What the problems call it: the card it stands beside, or a list.
  final String name;
  final Map<String, CardFieldSchema> fields;

  /// This scope with the card's own `{id}`, which only arguments take: an
  /// id is the app's key for a thing, not something users read.
  _Scope withId() => _Scope._(name, {
    'id': const CardFieldSchema('id', CardFieldType.text),
    ...fields,
  });
}

class _Check {
  _Check(this.destinations, this.tools);

  final Map<String, CardTarget> destinations;
  final Map<String, CardTarget> tools;

  /// In order, each once: text per language repeats the same problem.
  final Set<String> problems = {};

  void block(CardBlock block, String path, _Scope scope) {
    if (block.when case final condition?) flag(condition, '$path.when', scope);
    switch (block) {
      case HeaderBlock(:final image, :final title, :final line):
        if (image != null) this.image(image, '$path.image', scope);
        text(title, '$path.title', scope);
        if (line != null) text(line, '$path.line', scope);
      case ImageBlock(:final field):
        image(field, '$path.field', scope);
      case TextBlock(text: final words):
        text(words, '$path.text', scope);
      case BadgeBlock(text: final words):
        text(words, '$path.text', scope);
      case RowsBlock(:final items):
        for (var i = 0; i < items.length; i++) {
          text(items[i].label, '$path.items[$i].label', scope);
          text(items[i].value, '$path.items[$i].value', scope);
        }
      case ListRowsBlock(:final from, :final label, :final value, :final only):
        final list = scope.fields[from];
        if (list == null) {
          problems.add('$path.from $from is not a field of ${scope.name}');
          return;
        }
        if (list.type != CardFieldType.list) {
          problems.add('$path.from $from is not a list field');
          return;
        }
        final items = _Scope(from, list.fields);
        text(label, '$path.label', items);
        text(value, '$path.value', items);
        if (only != null) flag(only, '$path.only', items);
      case ButtonsBlock(:final items):
        for (var i = 0; i < items.length; i++) {
          text(items[i].label, '$path.items[$i].label', scope);
          action(items[i].action, '$path.items[$i]', scope);
        }
      case DividerBlock():
        break;
    }
  }

  void text(CardText words, String path, _Scope scope) {
    for (final template in words.templates) {
      this.template(template, path, scope);
    }
  }

  void template(CardTemplate template, String path, _Scope scope) {
    for (final ref in template.refs) {
      final field = scope.fields[ref.field];
      if (field == null) {
        problems.add(
          ref.field == 'id'
              ? "$path uses {id}, the card's id; ids go only in args"
              : '$path uses {${ref.field}}, which ${scope.name} does not have',
        );
        continue;
      }
      final misplaced = switch (field.type) {
        CardFieldType.list => 'a list; lists go in rows',
        CardFieldType.flag => 'a flag; flags go in when or only',
        CardFieldType.image => 'an image; images go in image and header blocks',
        _ => null,
      };
      if (misplaced != null) {
        problems.add('$path uses {${ref.field}}, $misplaced');
        continue;
      }
      if (ref.format case final format? when field.type != CardFieldType.date) {
        problems.add(
          '$path formats {${ref.field}} as ${_formatNoun[format]}, but it is '
          '${_typeNoun[field.type]}',
        );
      }
    }
  }

  void image(String name, String path, _Scope scope) {
    final field = scope.fields[name];
    if (field == null) {
      problems.add('$path $name is not a field of ${scope.name}');
    } else if (field.type != CardFieldType.image) {
      problems.add('$path $name is not an image field');
    }
  }

  void flag(CardCondition condition, String path, _Scope scope) {
    final field = scope.fields[condition.field];
    if (field == null || field.type != CardFieldType.flag) {
      problems.add('$path ${condition.field} is not a flag of ${scope.name}');
    }
  }

  void action(CardAction action, String path, _Scope scope) {
    final (verb, name, target) = switch (action) {
      CardOpen(:final destination) => (
        'opens',
        destination,
        destinations[destination],
      ),
      CardRun(:final tool) => ('runs', tool, tools[tool]),
    };
    if (target == null) {
      problems.add('$path $verb $name, which this app does not have');
      return;
    }
    if (!target.read) {
      problems.add('$path $verb $name, which is not a read tool');
      return;
    }
    for (final MapEntry(key: arg, value: template) in action.args.entries) {
      if (!target.args.contains(arg)) {
        problems.add('$path.args.$arg is not an argument of $name');
        continue;
      }
      this.template(template, '$path.args.$arg', scope.withId());
    }
    // A screen whose only argument is the id gets the card's own; a lookup
    // names its arguments.
    final idOnly =
        action is CardOpen &&
        action.args.isEmpty &&
        target.args.length == 1 &&
        target.args.single == 'id';
    if (idOnly) return;
    final missing = [
      for (final arg in target.required)
        if (!action.args.containsKey(arg)) arg,
    ];
    if (missing.isNotEmpty) {
      problems.add('$path needs args: ${missing.join(', ')}');
    }
  }

  static const _formatNoun = {
    CardFormat.date: 'a date',
    CardFormat.time: 'a time',
    CardFormat.datetime: 'a date and time',
  };

  static const _typeNoun = {
    CardFieldType.text: 'text',
    CardFieldType.number: 'a number',
    CardFieldType.money: 'money',
    CardFieldType.date: 'a date',
    CardFieldType.image: 'an image',
    CardFieldType.flag: 'a flag',
    CardFieldType.list: 'a list',
  };
}
