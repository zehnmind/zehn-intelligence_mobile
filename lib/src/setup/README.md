# setup

The setup command, `dart run zehn_intelligence:setup <code> --server <console>` (`bin/setup.dart`):
it adds the SDK to the app in the current folder the way docs/sdk.md §1.1 says, so the developer
types nothing.

Pure Dart (`dart:io`), run on the developer's machine; nothing here is exported, and an app never
imports it.

| File | What |
|---|---|
| `setup.dart` | The command: options, the code traded for the file and the analysis's line (`POST /api/v1/setup`), the id check, the edits, `dart analyze`, the summary, `--remove` |
| `dart_source.dart` | A Dart file with its comments and strings blanked, so a brace or `runApp(` found is code; where a statement and its function start; adding an import |
| `main_edit.dart` | The start line before `runApp(` (the analysis's line when it still holds it, else the first), its imports, `main` made async when it isn't; taking it out |
| `dio_finder.dart` | Guesses at the app's Dio (get_it, a global or static one, how the app's DI makes it), and where a name is declared |
| `project_files.dart` | The `assets:` line in pubspec.yaml, the dependency, and the ids in android/ and ios/ |
| `undo.dart` | The record of a run (`.dart_tool/zehn_intelligence/setup.json`) and undoing its edits in a file edited since |

## What it does

1. `POST {server}/api/v1/setup {"code"}` answers the app's file (format 3) and `integration`, the
   console's analysis of the app: `file`, `line`, `code`, `imports`, `main_async`, `sure`, `notes`.
   `--file` takes a downloaded file instead (no analysis then).
2. The file's package name and bundle id against `android/app/build.gradle(.kts)` and
   `ios/Runner.xcodeproj` (`--skip-id-check` goes on anyway), then `assets/zehn-intelligence.json`.
3. The `assets:` line in pubspec.yaml, when no entry covers the file, and
   `NSMicrophoneUsageDescription` in `ios/Runner/Info.plist` when it has none: iOS ends an app that
   records without it, and the SDK records a spoken question when the assistant has `stt`.
4. The line. With an analysis that is `sure`: its `code`, before the `runApp(` on its `line` of its
   `file` (found again when the line moved), with the `imports` the file lacks, `main` made async when
   it isn't. Otherwise (no analysis, `sure` false, its `<your app's Dio>`): the Dio found in `lib/` or
   typed by the developer (`--dio` wins over both); with none, the line is printed for the developer
   to finish and nothing is put in. A file that starts the SDK already is left alone.
5. `dart analyze` on the changed Dart files: an import it asks for in a line the command wrote is
   added (once), an error left in those lines is reported, the app's own errors aren't.

No button anywhere: the SDK draws its own. `WidgetsFlutterBinding.ensureInitialized()` isn't added
either: `start()` makes the binding itself.

## `--remove`

Each run keeps, for each file it changed, the text before the first run and after the last
(`.dart_tool/zehn_intelligence/setup.json`). `--remove`:

- puts a file the command left as it was back **exactly** (the start line, its imports, `main`'s
  header, the `assets:` line, the microphone's purpose string), deletes the file it made, and the
  record;
- in a file edited since, undoes each of its edits where it still stands as written and keeps the
  developer's own lines; a line of the command's that changed since is named, never guessed at;
- without the record (`flutter clean`), takes out the start line, the SDK's import when unused and
  the `assets:` line; `main` stays async then.

`--dry-run` shows what either would change and writes nothing.

## The rules

Only add lines, never change or delete the app's own (only `void main()` becomes
`Future<void> main() async`); when a line can't be placed safely, say where it goes and leave it to the
developer.
