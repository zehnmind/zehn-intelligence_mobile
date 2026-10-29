# config

`ZiConfig`: the app key, track, package name, server URL and languages, read from the config file
the app is built with (`--dart-define-from-file`). `ZehnIntelligence.init()` checks it at start: the
package name must match the running app, and a `test` key refuses to start in a release build.

Task: P1-SDK-01.
