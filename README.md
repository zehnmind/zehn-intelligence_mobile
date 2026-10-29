# Zehn Intelligence SDK for Flutter

An AI assistant that a company adds to its own Flutter app. The app's user asks for something in
their own words ("find a 3-day Samarkand tour under 300 dollars and book it for 2"). The Zehn
Intelligence server plans the answer and asks the app to run the app's own code and to show the
app's own widgets: the tours come from the app's own backend, the booking happens in the app's own
booking sheet.

This repository holds the **SDK**, the Flutter package `zehn_intelligence` that goes into the app,
and an **example app**, Tour Explorer, that the SDK will be built and demonstrated against. The
server (`zehn-intelligence_backend`) and the developer console (`zehn-intelligence_frontend`) are in
their own repositories.

> **Status: skeleton.** The package has its layout, lints and tests, and the example app runs, but
> the SDK has no features and exports nothing yet. The [What it does](#what-it-does) table shows
> what comes when.

## Contents

- [What it does](#what-it-does)
- [How it works](#how-it-works)
- [Repository layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Quick start: run the example](#quick-start-run-the-example)
- [Adding the SDK to an app](#adding-the-sdk-to-an-app)
- [Tests](#tests)
- [Platforms](#platforms)
- [Code conventions](#code-conventions)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## What it does

| Part | What it will do | Folder | Task | State |
|---|---|---|---|---|
| Config and start-up | Read the app key and settings built into the app; refuse to start when they don't match the running app, or when a test key is in a release build | `lib/src/config/` | P1-SDK-01 | not started |
| Transport and protocol | Talk to the server: requests, streamed answers (SSE), typed errors | `lib/src/transport/`, `lib/src/protocol/` | P1-SDK-02 | not started |
| User token | Hold the signed-in user's token; ask the app for a new one when it expires | `lib/src/auth/` | P1-SDK-03 | not started |
| Tools and components | The app registers its handlers and widgets; every call and every mount is checked first | `lib/src/registry/` | P1-SDK-04 | not started |
| Turns | Run one question end to end: stream, run the app's tools in parallel, show its widgets | `lib/src/turn/` | P1-SDK-05 | not started |
| Chat UI | The AI button, the chat sheet, the app's widgets inline, errors in the user's language | `lib/src/chat/`, `lib/src/ui/` | P1-SDK-06 | not started |
| Preflight, telemetry | Report the registrations on the test track; report tool and widget outcomes without user data | `lib/src/preflight/`, `lib/src/telemetry/` | P2-SDK-01, P2-SDK-02 | phase 2 |
| Voice | Hold to speak, hear the answer | `lib/src/voice/` | P2-SDK-04 | waiting for the speech service |
| Example integration | Tour Explorer answers with its own tours, cards and booking sheet | `example/` | P1-SDK-07 | not started |

Each folder under `lib/src/` has a short `README.md` that says what will live there.

## How it works

This is the design the SDK is built to. None of it is implemented yet.

```
 end user                                      Zehn Intelligence server
    │                                          (zehn-intelligence_backend)
    ▼                                                  ▲          ▲
 ┌──────────────────────────────────────┐   /v1:       │          │ /v1/user-tokens
 │ the company's Flutter app            │   app key +  │          │ (server key)
 │  + this SDK: AI button, chat,        │──user token──┘          │
 │    the app's tool handlers, widgets  │                ┌────────┴─────────────┐
 └───────────────────┬──────────────────┘                │ the company's backend│
                     └── the app's own API calls, ──────▶│ (its own login)      │
                         with the user's session         └──────────────────────┘
```

- **Who the user is.** The company's backend trades its server key for a token per signed-in user
  and hands it to the app. The SDK stores the token and sends it with every request; it never reads it.
- **One question, one turn.** The SDK sends the user's message and reads the answer as a stream.
  When the server needs data, it asks the SDK to run one of the app's registered tools, by name and
  with arguments (never a URL). The app's handler calls the app's own backend with the user's own
  session and returns only the fields it chooses. The SDK posts the results and the answer continues.
- **The app's own widgets.** The answer can show the app's widgets (a tour card, a booking sheet)
  with checked properties. Anything that changes data happens only when the user confirms in the
  app's own UI.
- **The server never calls the company's backend.**

## Repository layout

```
zehn-intelligence_mobile/
├── lib/
│   ├── zehn_intelligence.dart   the public API: exports only (none yet)
│   └── src/                     the SDK's code, one folder per area, each with a README:
│                                config, auth, transport, protocol, registry, turn, chat, ui,
│                                preflight, telemetry, voice
├── test/                        the package's tests
├── example/                     Tour Explorer, the example app (Android, iOS, web)
│   ├── lib/                     models, mock data, logic, screens, widgets, theme
│   ├── test/                    the app's unit and widget tests
│   └── android/ ios/ web/       platform folders
├── pubspec.yaml                 the package: name, Dart and Flutter versions, dependencies
├── analysis_options.yaml        lints (flutter_lints, the same rules as the example)
└── CHANGELOG.md                 changes per version
```

## Prerequisites

| Tool | Version | Used for |
|---|---|---|
| [Flutter](https://docs.flutter.dev/get-started/install) | **3.47.6**, stable channel (Dart 3.13.5) | the SDK and the example. The package accepts Flutter 3.47.0 or newer with Dart 3.13 or newer |
| Android SDK, with an emulator or a device | platform 36 (`flutter doctor` shows it) | running the example on Android |
| JDK | 21 (`flutter config --jdk-dir` sets it) | the example's Android build (Gradle 9.3, Android Gradle plugin 9.1) |
| Google Chrome | current | running the example on the web |
| macOS with Xcode | — | iOS builds only; see [Platforms](#platforms) |
| Docker | — | the Trivy scan before a pull request |
| git, with access to the `zehnmind` organization | — | cloning, and the git dependency (the repository is private) |

The repository doesn't use a Flutter version manager (fvm). The version is pinned by the
`environment` section of `pubspec.yaml` and by this table. Check yours with `flutter --version`.

## Quick start: run the example

Tour Explorer is a tour catalog on mock data: no backend, no accounts. It does not use the SDK yet;
it depends on it through `path: ../`, so every `flutter pub get` also checks that the SDK resolves in
a real app.

1. **Check the Flutter version.**
   ```bash
   flutter --version
   ```
   The first line starts with `Flutter 3.47.6 • channel stable`, the last one with
   `Tools • Dart 3.13.5`.

2. **Clone the repository.**
   ```bash
   git clone https://github.com/zehnmind/zehn-intelligence_mobile.git
   cd zehn-intelligence_mobile
   ```

3. **Get the dependencies.** In the repository root:
   ```bash
   flutter pub get
   ```
   It resolves the package, then the example: the last lines are
   ``Resolving dependencies in `./example`...`` and ``Got dependencies in `./example`.``

4. **Start a device.** List what is available, and start an emulator if there is none:
   ```bash
   flutter devices
   flutter emulators                         # lists the emulators you have
   flutter emulators --launch <emulator id>
   ```

5. **Run the example.**
   ```bash
   cd example
   flutter run                               # asks which device if there are several
   ```
   The app opens on **Explore**: "Where to next?", a search box, featured destinations and popular
   tours with photos. The bottom bar has Explore, Search and Favorites. Press `q` in the terminal to
   stop.

6. **Or run it in Chrome,** without an Android device:
   ```bash
   flutter run -d chrome
   ```

7. **Or build an APK** to install by hand:
   ```bash
   flutter build apk --debug
   ```
   The file is `example/build/app/outputs/flutter-apk/app-debug.apk`.

## Adding the SDK to an app

There is nothing to call yet: the public API arrives with the phase 1 tasks. The SDK is not
published; an app depends on it through git:

```yaml
# the app's pubspec.yaml
dependencies:
  zehn_intelligence:
    git:
      url: https://github.com/zehnmind/zehn-intelligence_mobile.git
      ref: main          # a release tag once versions are released
```

```bash
flutter pub get
```

The repository is private, so `git` on that machine must be able to clone it (a credential helper
or a token for HTTPS). How the SDK is published and versioned for customers is decided in task
P4-SDK-01.

## Tests

From the repository root:

```bash
flutter analyze                  # the package and the example (the root run covers example/)
flutter test                     # the package's tests
(cd example && flutter test)     # the example's tests
```

They need only the Flutter SDK: no device, no network, no server. The package has one test so far,
which checks that the public library loads. The example has 53 unit and widget tests.

`flutter test` in `example/` prints a stack trace that starts with
`Loading tours failed: Bad state: offline`, and a `Warning: A call to tap() … would not hit test`.
Both are expected and the run ends with `All tests passed!`: one test fails the first load on
purpose to check the retry, and the other taps a tour's title while it is partly covered.

## Platforms

| Platform | In the example | Checked on our Linux machines |
|---|---|---|
| Android | yes | built (`flutter build apk --debug`) and run on an emulator (Android 15, API 35) |
| Web | yes | built (`flutter build web`) |
| iOS | yes (`example/ios/`) | **not checked**: iOS builds need macOS with Xcode. On Linux `flutter build ios` doesn't exist |
| Linux, macOS, Windows desktop | no | — |

The example's ids are its own and differ per platform: `com.zehnmind.tour_explorer` on Android,
`com.zehnmind.tourExplorer` on iOS.

## Code conventions

These are the rules a review checks.

- `lib/zehn_intelligence.dart` holds exports only. All code lives in `lib/src/<area>/`, in the
  folders above; an app never imports from `src/`.
- State uses `ChangeNotifier`, like the example app. No state-management package, no code
  generation.
- Few dependencies. Each one comes with the task that needs it, because every dependency of the SDK
  ends up in the company's app.
- The SDK runs only the handlers the app registered, with checked arguments, and sends back only
  what the handler returns. It sends nothing else from the app.
- A component is the app's own widget, with checked properties. Changing data happens only when the
  user confirms in the app's own UI.
- Every error the server can return has a short message in the user's language.
- Keys never enter the repository. An app's config file is built in with `--dart-define-from-file`
  and is git-ignored (`example/config/*.json` here).
- Comments explain the intent and the non-obvious rules.
- `flutter analyze` reports no issues and `flutter test` passes, in the root and in `example/`.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `Because zehn_intelligence requires Flutter SDK version >=3.47.0, version solving failed.` | The Flutter SDK is older than the one the SDK supports | Switch to Flutter 3.47.6: in the Flutter SDK's folder, `git checkout 3.47.6`, then `flutter --version` |
| `flutter pub get` in an app fails with `fatal: could not read Username for 'https://github.com': terminal prompts disabled` | The repository is private and git has no credentials for it | Set up a git credential helper or a token for github.com, then `git ls-remote https://github.com/zehnmind/zehn-intelligence_mobile.git` must work |
| `Could not find a subcommand named "ios" for "flutter build".` | iOS builds exist only on macOS | Build iOS on a Mac with Xcode |
| The Android build prints `This version only understands SDK XML versions up to 3 but an SDK XML file of version 4 was encountered` | The Android command-line tools are older than other parts of the Android SDK | Harmless, the build continues. Update the command-line tools in the Android SDK Manager to silence it |
| `flutter doctor` says `Some Android licenses not accepted` | The SDK licences were never accepted on this machine | `flutter doctor --android-licenses`, then accept each one |
| `flutter test` in `example/` prints a stack trace with `Bad state: offline` | Expected: a test fails the first load on purpose | Nothing to fix if the run ends with `All tests passed!` |
| Photos in the example show a gradient with an icon instead | The device is offline; the photos load from public image CDNs | Connect the device or emulator to the internet |

## Contributing

1. **Branch from `main`** and open the pull request against `main`. One pull request, one purpose.
2. **Title it** in the conventional-commit style the org uses (`feat(config): …`, `fix(turn): …`,
   `docs: …`). It becomes the commit when the pull request is squash-merged.
3. **Before opening it**, run the checks from the repository root:
   ```bash
   flutter analyze
   flutter test
   (cd example && flutter test)
   docker run --rm -v trivy-cache:/root/.cache -v $PWD:/src:ro aquasec/trivy fs /src \
     --scanners vuln,secret,misconfig --severity HIGH,CRITICAL \
     --skip-dirs /src/.dart_tool --skip-dirs /src/build \
     --skip-dirs /src/example/.dart_tool --skip-dirs /src/example/build
   ```
   Analyze must report no issues, the tests must pass, and Trivy must report no HIGH or CRITICAL
   finding that has a fix. Trivy reads `example/pubspec.lock`, which lists the SDK's dependencies too.
4. **Dependencies:** add one only when a task needs it, with `flutter pub add <package>` in the
   root, then `flutter pub get` (which updates the example as well). Commit `pubspec.yaml` and
   `example/pubspec.lock`. The root `pubspec.lock` is git-ignored, as for every Dart library.
5. **A change to the public API** gets a line in `CHANGELOG.md`.
6. **The example app** keeps its own tests passing; a change to it comes with its tests.
7. **Never commit** keys, config files with keys, keystores, or `.env` files.
