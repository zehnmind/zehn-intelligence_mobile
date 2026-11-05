import '../config/agent_remote_config.dart';

/// One field's value for one entity, as a dashboard card draws it. The app's
/// own getters produce these from its own data; nothing here comes from the
/// model.
sealed class CardValue {
  const CardValue();
}

final class CardTextValue extends CardValue {
  const CardTextValue(this.text);

  final String text;
}

final class CardNumberValue extends CardValue {
  const CardNumberValue(this.number);

  final num number;
}

/// An amount and its unit in the reader's language: `so'm`, `UZS`.
final class CardMoneyValue extends CardValue {
  const CardMoneyValue(this.amount, {this.unit = ''});

  final num amount;
  final String unit;
}

/// A wall-clock time, shown as given: no zone conversion.
final class CardDateValue extends CardValue {
  const CardDateValue(this.date);

  final DateTime date;
}

final class CardImageValue extends CardValue {
  const CardImageValue(this.url);

  final String url;
}

final class CardFlagValue extends CardValue {
  const CardFlagValue(this.flag);

  final bool flag;
}

/// A list's items, each with its own fields.
final class CardListValue extends CardValue {
  const CardListValue(this.items);

  final List<Map<String, CardValue?>> items;
}

/// Turns templates and values into the words a card shows.
abstract final class CardFill {
  /// [template] with every slot filled, or null when a field it names is
  /// empty, blank or missing: the slot's text is then left out whole.
  static String? template(
    CardTemplate template,
    Map<String, CardValue?> values, {
    String languageCode = 'en',
  }) {
    final out = StringBuffer();
    for (final segment in template.segments) {
      switch (segment) {
        case CardLiteral(:final text):
          out.write(text);
        case CardFieldRef(:final field, :final format):
          final value = values[field];
          if (!holds(value)) return null;
          final shown = _show(value!, format, languageCode);
          if (shown == null) return null;
          out.write(shown);
      }
    }
    return out.toString();
  }

  /// [text] in [languageCode], else in [fallbackLanguage], filled.
  static String? text(
    CardText text,
    Map<String, CardValue?> values, {
    required String languageCode,
    required String fallbackLanguage,
  }) {
    final template = text.pick(languageCode, fallbackLanguage);
    return template == null
        ? null
        : CardFill.template(template, values, languageCode: languageCode);
  }

  /// Whether [value] has something to show: text that isn't blank, a true
  /// flag, a finite number, a list with items, an https picture.
  static bool holds(CardValue? value) => switch (value) {
    null => false,
    CardTextValue(:final text) => text.trim().isNotEmpty,
    // An average over nothing is NaN: there is no number to show.
    CardNumberValue(:final number) => number.isFinite,
    CardMoneyValue(:final amount) => amount.isFinite,
    CardFlagValue(:final flag) => flag,
    CardListValue(:final items) => items.isNotEmpty,
    CardImageValue(:final url) => Uri.tryParse(url)?.isScheme('https') ?? false,
    _ => true,
  };

  static String? _show(CardValue value, CardFormat? format, String language) =>
      switch (value) {
        CardTextValue(:final text) => text,
        CardNumberValue(:final number) => grouped(number, language),
        CardMoneyValue(:final amount, :final unit) =>
          unit.trim().isEmpty
              ? grouped(amount, language)
              : '${grouped(amount, language)} ${unit.trim()}',
        CardDateValue(:final date) => switch (format ?? CardFormat.date) {
          CardFormat.date => '${_two(date.day)}.${_two(date.month)}',
          CardFormat.time => '${_two(date.hour)}:${_two(date.minute)}',
          CardFormat.datetime =>
            '${_two(date.day)}.${_two(date.month)} '
                '${_two(date.hour)}:${_two(date.minute)}',
        },
        // The check keeps these out of text; drawing never asks.
        CardImageValue() || CardFlagValue() || CardListValue() => null,
      };

  /// [number] grouped by threes with a space, with up to two decimals in
  /// [language]'s mark: `1 234 567`, `2 500.5` in English, `2 500,5` else.
  static String grouped(num number, String language) {
    final negative = number < 0;
    final rounded = (number.abs() * 100).round();
    final whole = rounded ~/ 100;
    final cents = rounded % 100;
    final digits = '$whole';
    final groups = <String>[];
    for (var end = digits.length; end > 0; end -= 3) {
      groups.insert(0, digits.substring(end - 3 < 0 ? 0 : end - 3, end));
    }
    var out = groups.join(' ');
    if (cents != 0) {
      final decimals = _two(cents).replaceFirst(RegExp(r'0$'), '');
      out += '${language == 'en' ? '.' : ','}$decimals';
    }
    return negative ? '−$out' : out;
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
