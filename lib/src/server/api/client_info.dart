/// Who is calling: sent as the `X-ZI-*` headers on every console call.
class ZiClientInfo {
  const ZiClientInfo({
    required this.appKey,
    required this.packageName,
    required this.appVersion,
    required this.sdkVersion,
    required this.platform,
  });

  /// `zi_test_…` or `zi_prod_…`. Not a secret: it ships in the app.
  final String appKey;

  /// Android package name or iOS bundle id, matched exactly by the server.
  final String packageName;

  /// The app's own version, e.g. `1.2.0+5`.
  final String appVersion;
  final String sdkVersion;

  /// `android` or `ios`.
  final String platform;
}
