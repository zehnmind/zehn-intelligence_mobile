# Zehn Intelligence for Flutter

An AI assistant inside your Flutter app, with voice. Your users type or hold to speak; the
assistant answers, opens your screens, and shows cards and forms in the chat, with your app's
data, fetched through your app's own API and sign-in.

The assistant is set up in the Zehn Intelligence console, not in your code. The console reads
your app, drafts what the assistant can do (its tools, its cards, the screens it may open) and
publishes it. The SDK draws what the server sends, so the assistant learns new things without a
new release of your app.

This guide is for the developer adding the SDK to an app. What the SDK sends to the server and
how it handles each answer is in [docs/MOBILE_INTEGRATION.md](docs/MOBILE_INTEGRATION.md); the
card and form format is in [docs/DYNAMIC_CARDS.md](docs/DYNAMIC_CARDS.md).

## Requirements

- Flutter 3.35 or newer, Dart 3.9 or newer; Android and iOS.
- Your app talks to its API with [Dio](https://pub.dev/packages/dio). The assistant's requests go
  through that Dio, with your base URL, your sign-in header and your token refresh.
- Your app's screens can be opened by path, as a deep link opens them (go_router, auto_route,
  beamer, or `MaterialApp` named routes).
- iOS: `NSMicrophoneUsageDescription` in `ios/Runner/Info.plist` (the setup command adds it).
  Without it the SDK hides the microphone, because iOS ends an app that records without one.
  Android needs nothing: the microphone permission comes with the SDK.

## Install

### With the setup command (recommended)

In the console, open your app's **Integration** tab. It shows one line with a one-time code
(valid for 10 minutes). Run it in your app's folder:

```bash
flutter pub add zehn_intelligence --git-url=https://github.com/zehnmind/zehn-intelligence_mobile.git --git-ref=v0.7.0 \
  && dart run zehn_intelligence:setup K7Q2-9XMD --server https://<the console>
```

The command:

1. downloads your app's file and saves it as `assets/zehn-intelligence.json`, after checking that
   its package name and bundle id are your app's;
2. adds the file to `assets:` in `pubspec.yaml`, and the microphone's purpose string to
   `Info.plist` when it has none;
3. adds the start line before `runApp(` in your `main`, with your app's Dio, and its import;
4. runs `dart analyze` on the files it changed.

It only adds lines; it never changes or deletes yours (apart from making `main` async when it
isn't). When it cannot place the line safely, it prints it for you to put in.

| Option | What it does |
|---|---|
| `--server <url>` | The console to read the code from. |
| `--file <path>` | Use a `zehn-intelligence.json` you downloaded instead of a code. |
| `--dio <expr>` | Your app's Dio as `main()` can reach it, e.g. `"getIt<Dio>()"`. |
| `--dry-run` | Show what would change; write nothing. |
| `--skip-id-check` | Go on when your app's ids are not the file's. |
| `--no-analyze` | Don't run `dart analyze` afterwards. |
| `--remove` | Put back every file the command changed. |

### By hand

1. Add the SDK, pinned to a release tag (never `main`):

   ```bash
   flutter pub add zehn_intelligence --git-url=https://github.com/zehnmind/zehn-intelligence_mobile.git --git-ref=v0.7.0
   ```

2. Download your app's file from the console and save it as `assets/zehn-intelligence.json`:

   ```yaml
   flutter:
     assets:
       - assets/zehn-intelligence.json
   ```

3. Start the assistant before `runApp`, with the Dio your app already uses:

   ```dart
   import 'package:zehn_intelligence/zehn_intelligence.dart';

   Future<void> main() async {
     // … your own setup (dependency injection, storage, …)
     await ZehnIntelligence.start(dio: () => getIt<Dio>());
     runApp(const MyApp());
   }
   ```

That is the whole integration. There is no button to place, no sign-in code and no tool to
write.

## What the start line does

`ZehnIntelligence.start(dio: …)`:

- **Reads the file.** Debug and profile builds use its test key (the console's test track),
  release builds its production key. One file serves every build.
- **Never throws.** When the assistant can't start (no file, another app's file, no key, a Dio
  that isn't ready), it logs why and your app runs on without the assistant:

  ```
  zehn_intelligence: the assistant is off: <why>
  ```

  When it starts, it logs the track, the platform, the package and the server.
- **Draws its own button.** A floating button above your app, which the user can drag. It keeps
  clear of the keyboard and of a bottom navigation bar. Which screens show it is set in the
  console (every screen, only some, or all but some), by your routes' paths (`/movies/:id`). Until
  you choose, it is hidden on the screens before sign-in the console found (splash, onboarding,
  sign-in, codes) and shown everywhere else.
- **Sends the assistant's requests through your Dio.** Your interceptors add the sign-in header
  and refresh tokens as they always do. A request that changes something (any method but `GET`)
  is sent only after the user taps **Confirm** on the card the assistant shows for it.
- **Opens your screens** the way a deep link does: your router gets the path (`/venues/a1`), with
  no code of yours and no dependency on your router package.
- **Notices a sign-out by itself**, from the requests your Dio makes: when the signed-in user
  changes, the chat and its history are emptied. You don't call anything on sign-out.
- **Looks like your app.** The chat's colours, font, corner radii and welcome words come from the
  console. A font must be one your app ships (listed in its `pubspec.yaml`).

The assistant shows nothing until something has been published for the build's track in the
console; it checks again at the next app start.

## The user and the language

**Language.** The chat speaks the language your app is shown in (your `MaterialApp`'s locale);
an app that never chose one gets the phone's. To set it yourself:

```dart
ZehnIntelligence.setLanguage('uz'); // 'uz', 'ru' or 'en'
```

**The user (optional).** By default each install talks to the assistant anonymously. To keep a
user's conversations across devices, your backend asks the Zehn server for a user token
(`POST /v1/user-tokens` with its server key; the key never goes in the app) and your app passes
it on:

```dart
ZehnIntelligence.setUser(token, onTokenExpired: () => myBackend.zehnToken());
// on sign-out, if you want to forget the user at once:
ZehnIntelligence.clearUser();
```

## Your own tools and widgets (optional)

Most of what the assistant does needs no code: it is a request to your API that the server
builds, sent through your Dio, and a card the server sends. Some things only your app's code can
do, such as reading data that ships with the app, or drawing a widget no card can (a map).
Register those by name, in the same call:

```dart
await ZehnIntelligence.start(
  dio: () => getIt<Dio>(),
  handlers: {'map.route': (args) => getIt<MapTools>().route(args)},
  builders: {'map_route': buildMapRouteCard},
);
```

Or one at a time, before or after `start`, with the words the model reads:

```dart
ZehnIntelligence.registerTool(
  'map.route',
  (args) => mapTools.route(args),
  description: 'Walking directions inside the mall to a shop.',
  args: {
    'to': ZiArg.string('Where to go', required: true),
    'floor': ZiArg.integer('The floor', oneOf: [-1, 1, 2, 3]),
    'accessible': ZiArg.boolean('True for a step-free route'),
  },
  examples: {'en': ['How do I get to Zara?']},
  resultNote: '`card` is what to pass to map_route.',
);

ZehnIntelligence.registerComponent(
  'map_route',
  (context, props, controller) => MapRouteCard(props: props),
  kind: 'inline', // or 'sheet': shown in a bottom sheet
  description: 'The route drawn on the mall map. Show it after map.route.',
  props: {'to': ZiArg.string('`card.to` from map.route', required: true)},
);
```

- **The console decides.** A registered tool or widget reaches the assistant only once it is in
  your app's catalog in the console and published. The console's code analysis drafts it from
  these calls: it reads your source and never runs it, so write names, descriptions and arguments
  as literals.
- **Names.** A tool is dotted lower case, one to four parts, at most 48 characters, not starting
  with `ui` or `zi` (`map.route`). A widget is one lower-case word, at most 40 characters
  (`map_route`). A debug build stops at another name.
- **A tool's handler** gets the call's arguments (checked first against what you declared in
  `args`) and returns JSON, at most 32 KB, which is what the model reads. To tell the model why it
  could not answer, throw `ZiToolError('not_found', 'No such shop')`.
- **A widget's builder** gets the props the model gave. A conversation opened again from the
  history draws it again from the same props, so draw from the props alone.

`ZiArg` has `string`, `integer`, `number` and `boolean`, each with a description and `required`;
`string` and `integer` also take `oneOf`.

## Icons in cards

Cards use a fixed set of icons that ships with the SDK. To draw one of your own, register it by
name; a card then names it as any other icon (a built-in name is replaced):

```dart
ZehnIntelligence.registerIcon('parking', (context, size, color) => SvgPicture.asset(
  'assets/icons/parking.svg', width: size, height: size,
  colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
));
```

An icon name is `lower_snake_case`, 2 to 32 characters.

## Cards and forms

Cards are made and published in the console; the server sends each card's template with the data
it shows, and the SDK draws it with native widgets. Nothing in a card can run code: a tap can only
open one of your screens, ask the assistant a question, or open an `https:`, `tel:` or `mailto:`
link.

From **0.7.0** the assistant can also show a **form** when it needs several details at once (a
name, a date, a phone number): text fields, checkboxes, switches, choices and dates, checked on
the phone with the same rules as on the server, in the user's language. What the user types is
kept while they scroll, switch to voice or close and reopen the chat; a failed send keeps every
value. For a request that changes something, the assistant still shows its **Confirm** card
after the form.

You don't write anything for forms. An app on an older SDK is never offered a form, or a card it
can't draw; it keeps working as before, and gets them once it updates to 0.7.0.

## Updating

Change the tag in `pubspec.yaml` (`ref: v0.7.0`) and run `flutter pub get`. Cards, tools and
screens come from the console, so most of what the assistant learns needs no new SDK; a new SDK
brings new kinds of cards and fields. An app that has not updated keeps working with what its
version can draw.

## Without the console file

To start from code instead of the file (a key from your own configuration, or a token instead of
a Dio), use `init` and place the button yourself:

```dart
await ZehnIntelligence.init(
  token: 'zi_test_…',                  // the app key from the console
  client: getIt<Dio>(),                // or accessToken: / onUnauthorized: / apiBaseUrl:
  isSignedIn: () => auth.isSignedIn,   // keeps sign-in-only tools from a signed-out user
  openRoute: (route) => router.push(route),
);

// in a Scaffold:
floatingActionButton: const ZehnAiButton(),
```

`init` throws `ZiConfigException` when it finds no app key.

## Trying it without a backend

The SDK has a mock server that plays the Zehn server for an app description file, and an example
app that uses it:

```bash
dart run zehn_intelligence:mock_server --app path/to/app.json   # from the SDK's folder
cd example && flutter run
```

The example starts the assistant with `init` against `http://localhost:8787` (use
`http://10.0.2.2:8787` from the Android emulator). What the mock answers is in
[docs/DYNAMIC_CARDS.md §14](docs/DYNAMIC_CARDS.md#14-testing-without-the-real-backend).

## Removing it

```bash
dart run zehn_intelligence:setup --remove
```

It puts back every file the setup command changed (exactly, when you haven't edited them since)
and deletes the file it made. Then remove the dependency with `flutter pub remove zehn_intelligence`.

## When something is off

| What you see | Why, and what to do |
|---|---|
| No button, and `the assistant is off: …` in the log | The log says why: no `assets/zehn-intelligence.json` (or not in `assets:`), a file for another app (its package name or bundle id), no key for this build's track, or the Dio threw. |
| No button, and the log says it started | Nothing is published for this track yet (test for debug builds, production for release builds), or the console hides the button on this screen. |
| The button shows on a screen it shouldn't | Choose the screens in the console. A screen pushed as a widget, with no route name, can't be matched, so the button shows there. |
| No microphone on iOS | `NSMicrophoneUsageDescription` is missing from `Info.plist`. |
| The assistant can't reach your API | Its requests go through the Dio you passed: check that it is the one with your base URL and sign-in interceptor. |
| A screen doesn't open | Your router must handle the path as a deep link would; check the route in the console. |
| A form says "Update the app to answer this." | The card uses a block this SDK version doesn't know: update the SDK. |

## Documents

- [docs/MOBILE_INTEGRATION.md](docs/MOBILE_INTEGRATION.md): the server API the SDK uses: endpoints,
  headers, the stream, errors and limits.
- [docs/DYNAMIC_CARDS.md](docs/DYNAMIC_CARDS.md): the card and form format, block by block, for
  whoever makes cards.
- [docs/design/forms-and-card-builder.md](docs/design/forms-and-card-builder.md): how forms and
  the console's card builder were designed.
