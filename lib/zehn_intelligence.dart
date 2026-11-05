/// An in-app AI assistant for Flutter apps, with voice.
///
/// The model only proposes. Your app validates every proposal, asks before
/// any write, runs its own repositories and draws its own widgets. Users
/// type or hold to speak; spoken questions get spoken replies (Zehn speech,
/// which serves Uzbek in both directions).
library;

export 'src/core/cards/card_check.dart';
export 'src/core/cards/card_values.dart';
export 'src/core/config/agent_config_client.dart';
export 'src/core/config/agent_config_sync.dart';
export 'src/core/config/agent_remote_config.dart';
export 'src/core/config/config_caps.dart';
export 'src/core/engine/agent_engine.dart';
export 'src/core/engine/agent_state.dart';
export 'src/core/engine/component_catalog.dart';
export 'src/core/engine/fallback_renderer.dart';
export 'src/core/entities/entity_store.dart';
export 'src/core/log.dart';
export 'src/core/model/agent_message.dart';
export 'src/core/model/component_spec.dart';
export 'src/core/model/confirmation.dart';
export 'src/core/protocol/agent_json.dart';
export 'src/core/protocol/turn.dart';
export 'src/core/schema/prop_schema.dart';
export 'src/core/text/agent_text.dart';
export 'src/core/text/default_copy.dart';
export 'src/core/text/localized_text.dart';
export 'src/core/tools/agent_tool.dart';
export 'src/core/tools/tool_registry.dart';
export 'src/core/tools/tool_result.dart';
export 'src/core/transport/agent_transport.dart';
export 'src/core/transport/example_transport.dart';
export 'src/core/transport/fallback_transport.dart';
export 'src/core/transport/openai_compatible_transport.dart';
export 'src/core/transport/rule_based_transport.dart';
export 'src/core/transport/zehn.dart';
export 'src/ui/chat/agent_chat_bloc.dart';
export 'src/ui/components/agent_component.dart';
export 'src/ui/components/agent_component_registry.dart';
export 'src/ui/components/agent_entity.dart';
export 'src/ui/components/agent_field.dart';
export 'src/ui/components/agent_pack.dart';
export 'src/ui/destinations/agent_destination.dart';
export 'src/ui/destinations/agent_link.dart';
export 'src/ui/scope/agent_scope.dart';
export 'src/ui/speech/agent_speech_output.dart';
export 'src/ui/theme/agent_strings.dart';
export 'src/ui/theme/agent_theme.dart';
export 'src/ui/widgets/agent_button.dart';
export 'src/ui/widgets/agent_chat_view.dart';
export 'src/ui/widgets/agent_composer.dart';
export 'src/ui/widgets/agent_confirm_card.dart';
export 'src/ui/widgets/agent_dashboard_card.dart';
export 'src/ui/widgets/agent_fallback_text.dart';
export 'src/ui/widgets/agent_message_list.dart';
export 'src/ui/widgets/agent_text_block.dart';
export 'src/ui/widgets/agent_voice_replies.dart';
export 'src/ui/zehn_intelligence.dart';
export 'src/version.dart';
export 'src/voice/voice_input_cubit.dart';
export 'src/voice/voice_recorder.dart';
export 'src/voice/voice_strings.dart';
export 'src/voice/voice_theme.dart';
export 'src/voice/widgets/agent_voice_composer.dart';
export 'src/voice/widgets/hold_to_speak_bar.dart';
export 'src/voice/widgets/hold_to_speak_detector.dart';
export 'src/voice/widgets/recording_panel.dart';
export 'src/voice/widgets/voice_waveform.dart';
export 'src/voice/zehn_speaker.dart';
export 'src/voice/zehn_speech_client.dart';
export 'src/voice/zehn_voice.dart';
