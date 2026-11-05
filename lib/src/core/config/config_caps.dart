/// How much the dashboard may set, as the phone enforces it.
///
/// The backend validates against the same numbers before publishing; the
/// phone clamps or ignores anything outside them, so a bad revision degrades
/// to the code's own behaviour rather than breaking the assistant.
abstract final class AgentConfigCaps {
  /// The config schema this build understands.
  static const int schemaVersion = 1;

  static const int copy = 300;
  static const int limitations = 30;
  static const int limitationWhat = 200;
  static const int limitationInstead = 300;
  static const int toolDescription = 2000;
  static const int argDescription = 500;
  static const int toolNotes = 4000;
  static const int examples = 10;
  static const int example = 120;
  static const int leadLine = 200;
  static const int componentUse = 500;

  /// Dashboard cards: how many a config holds, and how big each may be.
  static const int cards = 20;
  static const int cardBlocks = 12;
  static const int cardButtons = 2;
  static const int cardRows = 6;
  static const int cardTemplate = 200;
  static const int cardLabel = 40;

  /// The largest config response the phone reads.
  static const int responseBytes = 256 * 1024;
}
