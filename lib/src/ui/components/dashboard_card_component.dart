import 'package:flutter/widgets.dart';

import '../../core/cards/card_values.dart';
import '../../core/config/agent_remote_config.dart';
import '../../core/engine/component_catalog.dart';
import '../../core/entities/entity_store.dart';
import '../../core/model/component_spec.dart';
import '../widgets/agent_dashboard_card.dart';
import '../widgets/agent_fallback_text.dart';
import 'agent_component.dart';
import 'agent_field.dart';

/// A card the dashboard added, as the registry holds it: its contract taken
/// from the coded card it stands beside, its drawing from the plugin's
/// blocks over the fields that card declares.
///
/// `ZehnIntelligence.applyConfig` makes these after checking each card against the
/// app's code (`AgentCardCheck`); nothing else creates one.
class DashboardCardComponent extends AgentComponent {
  DashboardCardComponent({
    required this.spec,
    required this.base,
    required this.data,
    required this.defaultLanguage,
    this.idOnly = const {},
  });

  final AgentCardSpec spec;

  /// The coded card it stands beside.
  final AgentComponent base;
  final AgentCardData data;

  /// The app's default language, for words the dashboard wrote in some
  /// languages only.
  final String defaultLanguage;

  /// Destinations whose only argument is `id`: opening one with no
  /// arguments passes the card's own id.
  final Set<String> idOnly;

  @override
  String get type => spec.type;

  @override
  Set<String> get opens => {
    for (final action in spec.actions)
      if (action is CardOpen) action.destination,
  };

  @override
  Set<String> get invokes => {
    for (final action in spec.actions)
      if (action is CardRun) action.tool,
  };

  @override
  ComponentContract contract(EntityStore entities) {
    final coded = base.contract(entities);
    final describe = coded.describe;
    return ComponentContract(
      type: spec.type,
      use: spec.use,
      example: {'component': spec.type, 'id': '<id of a ${base.type} result>'},
      props: {'id': coded.props['id']!},
      // The coded card's own sentence, so voice, screen readers and saved
      // chats keep the app's words.
      describe: describe == null
          ? null
          : (card, language) => describe(
              ComponentSpec(type: base.type, props: card.props),
              language,
            ),
      baseType: base.type,
    );
  }

  Map<String, CardValue?>? _values(
    String id,
    String language,
    EntityStore entities,
  ) {
    final values = data.valuesFor(id, language, entities);
    return values == null ? null : {...values, 'id': CardTextValue(id)};
  }

  @override
  Widget build(AgentBuildContext ctx) {
    final values = _values(ctx.entityId, ctx.languageCode, ctx.entities);
    // A resumed conversation: the entity is gone, the saved sentence stays.
    if (values == null) return AgentFallbackText(ctx.spec.fallbackText);
    return AgentDashboardCard(
      spec: spec,
      values: values,
      languageCode: ctx.languageCode,
      fallbackLanguage: defaultLanguage,
      fallbackText: ctx.spec.fallbackText,
      onTap: ctx.onTap,
      onButton: (button) {
        final label = CardFill.text(
          button.label,
          values,
          languageCode: ctx.languageCode,
          fallbackLanguage: defaultLanguage,
        );
        final tap = _tap(button.action, values, label: label);
        return tap == null ? null : ctx.resolveTap?.call(tap);
      },
    );
  }

  @override
  AgentTap? tapFor(ComponentSpec card, EntityStore entities) {
    final action = spec.tap;
    if (action == null) return null;
    final id = card.stringProp('id') ?? '';
    final values = _values(id, defaultLanguage, entities);
    return values == null ? null : _tap(action, values);
  }

  /// [action] with its arguments filled from [values]; null when one of
  /// them is empty. A slot that is a whole field passes the field's own
  /// value — a number stays a number — so the target's schema checks it.
  AgentTap? _tap(
    CardAction action,
    Map<String, CardValue?> values, {
    String? label,
  }) {
    final args = <String, Object?>{};
    if (action is CardOpen &&
        action.args.isEmpty &&
        idOnly.contains(action.destination)) {
      args['id'] = (values['id']! as CardTextValue).text;
    }
    for (final MapEntry(key: name, value: template) in action.args.entries) {
      final value = switch (template.segments) {
        [CardFieldRef(:final field, format: null)] => _raw(values[field]),
        _ => CardFill.template(template, values),
      };
      if (value == null) return null;
      args[name] = value;
    }
    return switch (action) {
      CardOpen(:final destination) => AgentTap.open(destination, args: args),
      CardRun(:final tool) => AgentTap.invoke(tool, args: args, label: label),
    };
  }

  static Object? _raw(CardValue? value) {
    if (value is CardFlagValue) return value.flag;
    if (!CardFill.holds(value)) return null;
    return switch (value!) {
      CardTextValue(:final text) => text,
      CardNumberValue(:final number) => number,
      CardMoneyValue(:final amount) => amount,
      CardFlagValue(:final flag) => flag,
      CardDateValue(:final date) => date.toIso8601String(),
      CardImageValue() || CardListValue() => null,
    };
  }
}
