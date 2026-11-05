/// Defaults for the Zehn gateway: one project key turns on chat, speech
/// recognition and speech synthesis.
///
/// The key is never a default. Pass it at build time (`--dart-define`) or,
/// for anything shipped to real users, keep it on a backend and point
/// `baseUrl` there.
abstract final class Zehn {
  static const String baseUrl = 'https://api.zehnmind.com/v1/';
}
