import '../protocol/turn.dart';
import '../tools/tool_registry.dart';
import '../tools/tool_result.dart';
import 'agent_transport.dart';

/// Plans without a model, from each tool's example questions (`ToolDoc`):
/// the tool whose examples share the most words with what the user typed
/// runs — if it needs no arguments. Enough for "show my cards" with no key
/// and no network; anything else gets the help line.
///
/// Words are compared by their first four letters, so "kartalarimni" meets
/// "Kartalarim". Like every transport, it only proposes: the gate still decides.
class ExampleTransport implements AgentTransport {
  ExampleTransport(this._tools);

  /// Read on every turn, so tools added or removed at run time count.
  final AgentToolRegistry Function() _tools;

  /// Question words every example shares, which say nothing about the tool.
  static const Set<String> _generic = {
    'show',
    'what',
    'where',
    'which',
    'when',
    'much',
    'many',
    'please',
    'give',
    'tell',
    'find',
    'list',
    'need',
    'want',
    'have',
    'does',
    'with',
    'from',
    'this',
    'that',
    'there',
    'about',
    'korsat',
    'korsating',
    'qancha',
    'qayerda',
    'qaysi',
    'qani',
    'qanday',
    'menga',
    'mening',
    'kerak',
    'pokazhi',
    'pokazhite',
    'skolko',
    'kakoy',
    'kakaya',
    'kakie',
    'gde',
    'moya',
    'moi',
    'moy',
    'mne',
    'pozhaluysta',
    'est',
  };

  static List<String> _words(String text) => [
    for (final word
        in text
            .toLowerCase()
            .replaceAll(RegExp("[‘’ʻʼ`´']"), '')
            .split(RegExp(r'[^a-zA-Z0-9\u0400-\u04FF]+')))
      if (word.length >= 3 && !_generic.contains(word)) word,
  ];

  static bool _same(String a, String b) {
    final shorter = a.length < b.length ? a : b;
    final longer = a.length < b.length ? b : a;
    if (shorter.length < 4) return longer == shorter;
    return longer.startsWith(shorter.substring(0, 4));
  }

  @override
  Future<AgentDecision> decide(AgentTurnRequest request) async {
    final asked = _words(request.userText);
    if (asked.isEmpty) return const AgentDecision.none();
    final tools = _tools();
    String? best;
    var bestScore = 0;
    for (final entry in request.toolCatalog) {
      final name = entry['name'];
      final tool = name is String ? tools[name] : null;
      if (tool == null || tool.args.values.any((arg) => arg.isRequired)) {
        continue;
      }
      for (final examples in tools.examplesOf(tool.name).values) {
        for (final example in examples) {
          final words = _words(example);
          final score = asked
              .where((a) => words.any((w) => _same(a, w)))
              .length;
          if (score > bestScore) {
            best = name as String;
            bestScore = score;
          }
        }
      }
    }
    return best == null
        ? const AgentDecision.none()
        : AgentDecision(tool: best);
  }

  /// Never writes a reply: the engine renders the result from the tool's own
  /// lead line and cards.
  @override
  Future<AgentReply> render(
    AgentTurnRequest request,
    ToolResult? result,
  ) async => const AgentReply.empty();
}
