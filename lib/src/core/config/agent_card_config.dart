part of 'agent_remote_config.dart';

/// The blocks and formats this build draws. The manifest records them as
/// `plugin.cards`, so a dashboard offers only what each app version can draw.
abstract final class AgentCardVocabulary {
  static const List<String> blocks = [
    'header',
    'image',
    'text',
    'rows',
    'badge',
    'buttons',
    'divider',
  ];

  /// Only dates take a format. Numbers and money are grouped with spaces,
  /// and money adds its unit.
  static const List<String> dateFormats = ['date', 'time', 'datetime'];
}

/// A card the dashboard added, built from the plugin's blocks.
///
/// It stands beside a coded card, [base]: it shares that card's ids and
/// allowlist, its pack and its sentence, and draws only the fields that
/// card's code declares. The model may use it in place of [base] when [use]
/// fits the question. The phone checks it again against its own code before
/// showing it to the model (see `AgentCardCheck`).
class AgentCardSpec {
  const AgentCardSpec({
    required this.type,
    required this.base,
    required this.use,
    required this.blocks,
    this.tap,
  });

  static final RegExp _type = RegExp(r'^[a-z][a-z0-9_]{1,47}$');

  /// A card with any problem is left out whole: half a card is worse than
  /// the coded one. A key this build does not know is noted and ignored, as
  /// anywhere in the config.
  static AgentCardSpec? _read(
    _Reader r,
    String type,
    Object? value,
    String path,
  ) {
    final before = r.serious;
    if (!_type.hasMatch(type)) {
      r.problem(path, 'is not a card type: use lower_snake_case');
    } else if (type == 'text') {
      r.problem(path, 'is the built-in text card');
    }
    final map = r.map(value, path);
    if (map != null) {
      r.known(map, path, const {'for', 'use', 'blocks', 'tap'});
    }
    final base = map == null ? null : _base(r, map['for'], '$path.for');
    final use = map == null ? null : _use(r, map['use'], '$path.use');
    final blocks = map == null ? null : _blocks(r, map['blocks'], path);
    final tapMap = map == null ? null : r.map(map['tap'], '$path.tap');
    if (tapMap != null) {
      r.known(tapMap, '$path.tap', const {'open', 'run', 'args'});
    }
    final tap = CardAction._read(r, tapMap, '$path.tap');

    if (r.serious > before ||
        base == null ||
        use == null ||
        blocks == null ||
        (map?['tap'] != null && tap == null)) {
      if (map != null || r.serious > before) r.problem(path, 'is left out');
      return null;
    }
    return AgentCardSpec(
      type: type,
      base: base,
      use: use,
      blocks: blocks,
      tap: tap,
    );
  }

  static String? _base(_Reader r, Object? value, String path) {
    if (value == null) {
      r.problem(path, 'is missing');
      return null;
    }
    if (value is! String || !_type.hasMatch(value)) {
      r.problem(path, 'is not a card type');
      return null;
    }
    return value;
  }

  static String? _use(_Reader r, Object? value, String path) {
    if (value == null) {
      r.problem(path, 'is missing');
      return null;
    }
    final use = r.text(value, path, AgentConfigCaps.componentUse);
    if (use != null && use.trim().isEmpty) {
      r.problem(path, 'is blank');
      return null;
    }
    return use;
  }

  static List<CardBlock>? _blocks(_Reader r, Object? value, String card) {
    final path = '$card.blocks';
    if (value == null) {
      r.problem(path, 'is missing');
      return null;
    }
    if (value is! List) {
      r.problem(path, 'is not a list');
      return null;
    }
    if (value.isEmpty) {
      r.problem(path, 'is empty');
      return null;
    }
    if (value.length > AgentConfigCaps.cardBlocks) {
      r.problem(path, 'has more than ${AgentConfigCaps.cardBlocks} items');
      return null;
    }
    final out = <CardBlock>[];
    for (var i = 0; i < value.length; i++) {
      final block = CardBlock._read(r, value[i], '$path[$i]');
      if (block != null) out.add(block);
    }
    return out.length == value.length ? out : null;
  }

  /// The card's type, which the model names: `event_prices_card`.
  final String type;

  /// The coded card this one stands beside: `event_card`.
  final String base;

  /// When to show it, as the model is told.
  final String use;
  final List<CardBlock> blocks;

  /// What a tap on the card does. Null leaves it inert.
  final CardAction? tap;

  /// Every action the card can take: its tap, then its buttons.
  Iterable<CardAction> get actions sync* {
    if (tap case final tap?) yield tap;
    for (final block in blocks) {
      if (block is ButtonsBlock) {
        for (final item in block.items) {
          yield item.action;
        }
      }
    }
  }

  Map<String, Object?> toJson() => {
    'for': base,
    'use': use,
    'blocks': [for (final block in blocks) block.toJson()],
    if (tap != null) 'tap': tap!.toJson(),
  };
}

/// Shows a block only while a flag field is true, or, with `!`, false.
class CardCondition {
  const CardCondition(this.field, {this.negated = false});

  static final RegExp _shape = RegExp(r'^(!?)([a-zA-Z][a-zA-Z0-9_]*)$');

  static CardCondition? _read(_Reader r, Object? value, String path) {
    if (value == null) return null;
    final match = value is String ? _shape.firstMatch(value) : null;
    if (match == null) {
      r.problem(path, 'is not a field name');
      return null;
    }
    return CardCondition(match.group(2)!, negated: match.group(1) == '!');
  }

  final String field;
  final bool negated;

  String toJson() => '${negated ? '!' : ''}$field';

  @override
  bool operator ==(Object other) =>
      other is CardCondition &&
      other.field == field &&
      other.negated == negated;

  @override
  int get hashCode => Object.hash(field, negated);
}

/// One block of a dashboard card.
sealed class CardBlock {
  const CardBlock({this.when});

  static final RegExp _field = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');

  static CardBlock? _read(_Reader r, Object? value, String path) {
    final map = r.map(value, path);
    if (map == null) {
      if (value == null) r.problem(path, 'is not an object');
      return null;
    }
    final name = map['block'];
    if (name is! String) {
      r.problem('$path.block', name == null ? 'is missing' : 'is not text');
      return null;
    }
    final before = r.serious;
    final when = CardCondition._read(r, map['when'], '$path.when');
    void known(Set<String> keys) =>
        r.known(map, path, {'block', 'when', ...keys});

    final CardBlock? block;
    switch (name) {
      case 'header':
        known(const {'image', 'title', 'line'});
        block = HeaderBlock(
          image: _fieldName(r, map['image'], '$path.image', required: false),
          title: CardText._read(r, map['title'], '$path.title'),
          line: CardText._read(r, map['line'], '$path.line', required: false),
          when: when,
        );
      case 'image':
        known(const {'field', 'shape'});
        final shape = _choice(r, map['shape'], '$path.shape', const [
          'wide',
          'square',
        ]);
        block = ImageBlock(
          field: _fieldName(r, map['field'], '$path.field') ?? '',
          shape: shape == null ? null : CardImageShape.values.byName(shape),
          when: when,
        );
      case 'text':
        known(const {'text', 'style'});
        final style = _choice(r, map['style'], '$path.style', const [
          'body',
          'strong',
          'secondary',
          'caption',
        ]);
        block = TextBlock(
          text: CardText._read(r, map['text'], '$path.text'),
          style: style == null ? null : CardTextStyle.values.byName(style),
          when: when,
        );
      case 'rows':
        known(const {'items', 'from', 'label', 'value', 'only'});
        block = _rows(r, map, path, when);
      case 'badge':
        known(const {'text', 'tone'});
        final tone = _choice(r, map['tone'], '$path.tone', const [
          'neutral',
          'accent',
          'success',
          'warning',
        ]);
        block = BadgeBlock(
          text: CardText._read(
            r,
            map['text'],
            '$path.text',
            cap: AgentConfigCaps.cardLabel,
          ),
          tone: tone == null ? null : CardTone.values.byName(tone),
          when: when,
        );
      case 'buttons':
        known(const {'items'});
        block = _buttons(r, map['items'], '$path.items', when);
      case 'divider':
        known(const {});
        block = DividerBlock(when: when);
      default:
        r.problem('$path.block', '"$name" is not a block this build draws');
        return null;
    }
    return r.serious > before ? null : block;
  }

  static CardBlock? _rows(
    _Reader r,
    Map<String, Object?> map,
    String path,
    CardCondition? when,
  ) {
    final items = map['items'];
    final from = map['from'];
    if (items != null && from != null) {
      r.problem(path, 'has both items and from; rows take one');
      return null;
    }
    if (items == null && from == null) {
      r.problem(path, 'needs items or from');
      return null;
    }
    if (from != null) {
      return ListRowsBlock(
        from: _fieldName(r, from, '$path.from') ?? '',
        label: CardText._read(r, map['label'], '$path.label'),
        value: CardText._read(r, map['value'], '$path.value'),
        only: CardCondition._read(r, map['only'], '$path.only'),
        when: when,
      );
    }
    for (final key in const ['label', 'value', 'only']) {
      if (map[key] != null) {
        r.problem('$path.$key', 'goes with from, not items');
      }
    }
    final list = _list(r, items, '$path.items', AgentConfigCaps.cardRows);
    if (list == null) return null;
    final rows = <CardRow>[];
    for (var i = 0; i < list.length; i++) {
      final itemPath = '$path.items[$i]';
      final row = r.map(list[i], itemPath);
      if (row == null) {
        if (list[i] == null) r.problem(itemPath, 'is not an object');
        continue;
      }
      r.known(row, itemPath, const {'label', 'value'});
      rows.add(
        CardRow(
          label: CardText._read(
            r,
            row['label'],
            '$itemPath.label',
            cap: AgentConfigCaps.cardLabel,
          ),
          value: CardText._read(r, row['value'], '$itemPath.value'),
        ),
      );
    }
    return RowsBlock(items: rows, when: when);
  }

  static CardBlock? _buttons(
    _Reader r,
    Object? value,
    String path,
    CardCondition? when,
  ) {
    final list = _list(r, value, path, AgentConfigCaps.cardButtons);
    if (list == null) return null;
    final buttons = <CardButton>[];
    for (var i = 0; i < list.length; i++) {
      final itemPath = '$path[$i]';
      final item = r.map(list[i], itemPath);
      if (item == null) {
        if (list[i] == null) r.problem(itemPath, 'is not an object');
        continue;
      }
      r.known(item, itemPath, const {'label', 'open', 'run', 'args'});
      final label = CardText._read(
        r,
        item['label'],
        '$itemPath.label',
        cap: AgentConfigCaps.cardLabel,
      );
      final action = CardAction._read(r, item, itemPath);
      if (action != null) buttons.add(CardButton(label: label, action: action));
    }
    return ButtonsBlock(items: buttons, when: when);
  }

  static List<Object?>? _list(
    _Reader r,
    Object? value,
    String path,
    int count,
  ) {
    if (value == null) {
      r.problem(path, 'is missing');
      return null;
    }
    if (value is! List) {
      r.problem(path, 'is not a list');
      return null;
    }
    if (value.isEmpty) {
      r.problem(path, 'is empty');
      return null;
    }
    if (value.length > count) {
      r.problem(path, 'has more than $count items');
      return null;
    }
    return value;
  }

  static String? _fieldName(
    _Reader r,
    Object? value,
    String path, {
    bool required = true,
  }) {
    if (value == null) {
      if (required) r.problem(path, 'is missing');
      return null;
    }
    if (value is String && _field.hasMatch(value)) return value;
    r.problem(path, 'is not a field name');
    return null;
  }

  static String? _choice(
    _Reader r,
    Object? value,
    String path,
    List<String> values,
  ) {
    if (value == null) return null;
    if (value is String && values.contains(value)) return value;
    r.problem(path, 'is not one of ${values.join(', ')}');
    return null;
  }

  /// Shown only while this flag holds. Null: always.
  final CardCondition? when;

  /// The block's name in the config: `header`, `rows`, …
  String get name;

  Map<String, Object?> _body();

  Map<String, Object?> toJson() => {
    'block': name,
    ..._body(),
    if (when != null) 'when': when!.toJson(),
  };
}

/// An image beside a title and one line, as in a list.
final class HeaderBlock extends CardBlock {
  const HeaderBlock({required this.title, this.image, this.line, super.when});

  /// An `image` field. Null: no picture.
  final String? image;
  final CardText title;
  final CardText? line;

  @override
  String get name => 'header';

  @override
  Map<String, Object?> _body() => {
    'image': ?image,
    'title': title.toJson(),
    if (line != null) 'line': line!.toJson(),
  };
}

enum CardImageShape { wide, square }

/// A picture across the card.
final class ImageBlock extends CardBlock {
  const ImageBlock({required this.field, this.shape, super.when});

  /// An `image` field.
  final String field;

  /// Null: wide.
  final CardImageShape? shape;

  CardImageShape get effectiveShape => shape ?? CardImageShape.wide;

  @override
  String get name => 'image';

  @override
  Map<String, Object?> _body() => {
    'field': field,
    if (shape != null) 'shape': shape!.name,
  };
}

enum CardTextStyle { body, strong, secondary, caption }

/// A line of text.
final class TextBlock extends CardBlock {
  const TextBlock({required this.text, this.style, super.when});

  final CardText text;

  /// Null: body.
  final CardTextStyle? style;

  CardTextStyle get effectiveStyle => style ?? CardTextStyle.body;

  @override
  String get name => 'text';

  @override
  Map<String, Object?> _body() => {
    'text': text.toJson(),
    if (style != null) 'style': style!.name,
  };
}

/// Fixed label and value rows.
final class RowsBlock extends CardBlock {
  const RowsBlock({required this.items, super.when});

  final List<CardRow> items;

  @override
  String get name => 'rows';

  @override
  Map<String, Object?> _body() => {
    'items': [
      for (final row in items)
        {'label': row.label.toJson(), 'value': row.value.toJson()},
    ],
  };
}

/// One row per item of a `list` field, its templates over the item's own
/// fields.
final class ListRowsBlock extends CardBlock {
  const ListRowsBlock({
    required this.from,
    required this.label,
    required this.value,
    this.only,
    super.when,
  });

  /// A `list` field.
  final String from;
  final CardText label;
  final CardText value;

  /// Keeps only the items whose flag holds. Null: every item.
  final CardCondition? only;

  @override
  String get name => 'rows';

  @override
  Map<String, Object?> _body() => {
    'from': from,
    'label': label.toJson(),
    'value': value.toJson(),
    if (only != null) 'only': only!.toJson(),
  };
}

class CardRow {
  const CardRow({required this.label, required this.value});

  final CardText label;
  final CardText value;
}

enum CardTone { neutral, accent, success, warning }

/// A short label, coloured by tone.
final class BadgeBlock extends CardBlock {
  const BadgeBlock({required this.text, this.tone, super.when});

  final CardText text;

  /// Null: neutral.
  final CardTone? tone;

  CardTone get effectiveTone => tone ?? CardTone.neutral;

  @override
  String get name => 'badge';

  @override
  Map<String, Object?> _body() => {
    'text': text.toJson(),
    if (tone != null) 'tone': tone!.name,
  };
}

/// One or two buttons, each opening a destination or running a read.
final class ButtonsBlock extends CardBlock {
  const ButtonsBlock({required this.items, super.when});

  final List<CardButton> items;

  @override
  String get name => 'buttons';

  @override
  Map<String, Object?> _body() => {
    'items': [
      for (final item in items)
        {'label': item.label.toJson(), ...item.action.toJson()},
    ],
  };
}

class CardButton {
  const CardButton({required this.label, required this.action});

  final CardText label;
  final CardAction action;
}

/// A hairline between blocks.
final class DividerBlock extends CardBlock {
  const DividerBlock({super.when});

  @override
  String get name => 'divider';

  @override
  Map<String, Object?> _body() => const {};
}

/// What a tap or a button does: open one of the app's destinations, or run
/// one of its read tools. The arguments are templates over the card's
/// fields; the destination's and the tool's own checks still run at tap
/// time.
sealed class CardAction {
  const CardAction({this.args = const {}});

  static final RegExp _name = RegExp(r'^[a-zA-Z][a-zA-Z0-9_.\-]*$');
  static final RegExp _arg = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]*$');

  static CardAction? _read(_Reader r, Map<String, Object?>? map, String path) {
    if (map == null) return null;
    final open = map['open'];
    final run = map['run'];
    if (open != null && run != null) {
      r.problem(path, 'has both open and run; an action takes one');
      return null;
    }
    if (open == null && run == null) {
      r.problem(path, 'needs open or run');
      return null;
    }
    final key = open != null ? 'open' : 'run';
    final target = open ?? run;
    if (target is! String || !_name.hasMatch(target)) {
      r.problem('$path.$key', 'is not a name');
      return null;
    }
    final args = <String, CardTemplate>{};
    final argMap = r.map(map['args'], '$path.args') ?? const {};
    for (final MapEntry(key: name, :value) in argMap.entries) {
      final argPath = '$path.args.$name';
      if (!_arg.hasMatch(name)) {
        r.problem(argPath, 'is not an argument name');
        continue;
      }
      if (value is! String) {
        r.problem(argPath, 'is not text');
        continue;
      }
      final template = CardTemplate._read(
        r,
        value,
        argPath,
        cap: AgentConfigCaps.cardTemplate,
        forUsers: false,
      );
      if (template != null) args[name] = template;
    }
    return open != null
        ? CardOpen(target, args: args)
        : CardRun(target, args: args);
  }

  /// Argument name → template.
  final Map<String, CardTemplate> args;

  Map<String, Object?> _target();

  Map<String, Object?> toJson() => {
    ..._target(),
    if (args.isNotEmpty)
      'args': {for (final e in args.entries) e.key: e.value.source},
  };
}

/// Opens one of the app's registered destinations.
final class CardOpen extends CardAction {
  const CardOpen(this.destination, {super.args});

  final String destination;

  @override
  Map<String, Object?> _target() => {'open': destination};
}

/// Runs one of the app's read tools, as if the user had asked.
final class CardRun extends CardAction {
  const CardRun(this.tool, {super.args});

  final String tool;

  @override
  Map<String, Object?> _target() => {'run': tool};
}

/// Words on a card: one template for every language, or one per language.
class CardText {
  const CardText.plain(CardTemplate this._plain) : byLanguage = const {};

  const CardText.perLanguage(this.byLanguage) : _plain = null;

  /// [cap] is the template's length in characters. Every template's typed
  /// words are text users read: no links, no long numbers.
  static CardText _read(
    _Reader r,
    Object? value,
    String path, {
    bool required = true,
    int cap = AgentConfigCaps.cardTemplate,
  }) {
    const none = CardText.perLanguage({});
    if (value == null) {
      if (required) r.problem(path, 'is missing');
      return none;
    }
    if (value is String) {
      final template = CardTemplate._read(r, value, path, cap: cap);
      return template == null ? none : CardText.plain(template);
    }
    if (value is Map) {
      if (value.isEmpty) {
        r.problem(path, 'is empty');
        return none;
      }
      final out = <String, CardTemplate>{};
      for (final MapEntry(:key, :value) in value.entries) {
        final languagePath = '$path.$key';
        if (r.language(key, languagePath) == null) continue;
        if (value is! String) {
          r.problem(languagePath, 'is not text');
          continue;
        }
        final template = CardTemplate._read(r, value, languagePath, cap: cap);
        if (template != null) out['$key'] = template;
      }
      return CardText.perLanguage(out);
    }
    r.problem(path, 'is not text');
    return none;
  }

  final CardTemplate? _plain;

  /// Language code → template. Empty for plain text.
  final Map<String, CardTemplate> byLanguage;

  /// The template for [languageCode]; else [fallback]'s, the app's default
  /// language; else any. Null only for text that was refused.
  CardTemplate? pick(String languageCode, String fallback) =>
      _plain ??
      byLanguage[languageCode] ??
      byLanguage[fallback] ??
      byLanguage.values.firstOrNull;

  Iterable<CardTemplate> get templates =>
      _plain != null ? [_plain] : byLanguage.values;

  Object toJson() =>
      _plain?.source ??
      {for (final e in byLanguage.entries) e.key: e.value.source};
}

/// Typed words and `{field}` slots: `{starts:date} – {ends:date}`.
class CardTemplate {
  const CardTemplate._(this.source, this.segments);

  /// Parses [source] for tests and tools; null when it is broken.
  static CardTemplate? tryParse(String source) {
    final (segments, _) = _parse(source);
    return segments == null ? null : CardTemplate._(source, segments);
  }

  static final RegExp _slot = RegExp(
    r'\{([a-zA-Z][a-zA-Z0-9_]*)(?::([a-z]+))?\}',
  );

  static CardTemplate? _read(
    _Reader r,
    String value,
    String path, {
    required int cap,
    bool forUsers = true,
  }) {
    final source = r.text(value, path, cap);
    if (source == null) return null;
    if (source.trim().isEmpty) {
      r.problem(path, 'is blank');
      return null;
    }
    final (segments, problem) = _parse(source);
    if (segments == null) {
      r.problem(path, problem!);
      return null;
    }
    final template = CardTemplate._(source, segments);
    if (forUsers && _Reader._unsafeForUsers(template.literal)) {
      r.problem(
        path,
        'holds a link or a long number, which users must not see',
      );
      return null;
    }
    return template;
  }

  static (List<CardSegment>?, String?) _parse(String source) {
    const broken = 'has a broken {…}';
    final out = <CardSegment>[];
    var at = 0;
    while (at < source.length) {
      final open = source.indexOf('{', at);
      final close = source.indexOf('}', at);
      if (close != -1 && (open == -1 || close < open)) return (null, broken);
      if (open == -1) {
        out.add(CardLiteral(source.substring(at)));
        break;
      }
      if (open > at) out.add(CardLiteral(source.substring(at, open)));
      final match = _slot.matchAsPrefix(source, open);
      if (match == null) return (null, broken);
      final format = match.group(2);
      if (format != null && !AgentCardVocabulary.dateFormats.contains(format)) {
        return (
          null,
          'uses the format "$format"; formats are '
              '${AgentCardVocabulary.dateFormats.join(', ')}',
        );
      }
      out.add(
        CardFieldRef(
          match.group(1)!,
          format: format == null ? null : CardFormat.values.byName(format),
        ),
      );
      at = match.end;
    }
    return (out, null);
  }

  final String source;
  final List<CardSegment> segments;

  Iterable<CardFieldRef> get refs => segments.whereType<CardFieldRef>();

  /// The typed words alone, the slots left out.
  String get literal =>
      segments.whereType<CardLiteral>().map((s) => s.text).join();
}

/// A piece of a template.
sealed class CardSegment {
  const CardSegment();
}

final class CardLiteral extends CardSegment {
  const CardLiteral(this.text);

  final String text;

  @override
  bool operator ==(Object other) => other is CardLiteral && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'CardLiteral($text)';
}

enum CardFormat { date, time, datetime }

/// A `{field}` or `{field:format}` slot.
final class CardFieldRef extends CardSegment {
  const CardFieldRef(this.field, {this.format});

  final String field;

  /// Only for dates. Null: the field's own form (a date as `date`).
  final CardFormat? format;

  @override
  bool operator ==(Object other) =>
      other is CardFieldRef && other.field == field && other.format == format;

  @override
  int get hashCode => Object.hash(field, format);

  @override
  String toString() =>
      'CardFieldRef($field${format == null ? '' : ':$format'})';
}
