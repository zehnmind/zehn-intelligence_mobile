# Server Flow and API Proxy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The SDK talks only to the Zehn console backend through its turn flow, runs tool calls as a proxy against the customer's API from start-up data, and draws console-made components, so an app needs only `ZehnIntelligence.init` and `ZehnAiButton`.

**Architecture:** A new module `lib/src/server/` sits beside the old on-device engine and does not use it. Layers, bottom up: API client and SSE stream → tokens → turn client → start-up data → proxy executor and tool runner → surface renderer → chat cubit → chat sheet UI → `ZehnIntelligence.init` wiring. A mock server and an example app prove it end to end.

**Tech Stack:** Flutter 3.47.5 (fvm), Dart ^3.9, `dio`, `flutter_bloc`, `record`, `audioplayers`, `path_provider`, `package_info_plus`; new: `flutter_markdown_plus`, `url_launcher`. Tests: `flutter_test`, `bloc_test`, `mocktail`, real `dart:io` `HttpServer` fakes.

**Spec:** `docs/superpowers/specs/2026-11-09-server-proxy-design.md`. The turn protocol itself is `MOBILE_INTEGRATION.md` (2026-11-06), copied to `docs/MOBILE_INTEGRATION.md` in Task 1.

## Global Constraints

- Run Flutter as `fvm flutter …` from the repo root (`.fvmrc` pins 3.47.5).
- `flutter analyze` must stay clean under `analysis_options.yaml` (strict-casts, strict-raw-types, avoid_dynamic_calls, unawaited_futures, prefer_single_quotes).
- New code never calls `api.zehnmind.com`. The only Zehn host is the console URL, default `https://zi-console-api.zehnmind.com`.
- SDK version becomes `0.4.0` (`lib/src/version.dart`, `pubspec.yaml`); it is sent as `X-ZI-SDK-Version`.
- New dependencies: only `flutter_markdown_plus` and `url_launcher` (latest versions that resolve with Flutter 3.47.5).
- Limits from the spec/doc: tool result ≤ 32768 bytes (UTF-8 JSON), per-call timeout 20 s, ping timeout 45 s, results-retry delay 1 s, recording ≤ 1 MiB, typed question ≤ 4000 chars, `max_items` default 10.
- Proxy: `GET` only; path must start with `/`; path params URL-encoded; in callbacks mode host must be in `allowed_hosts` (base URL host always allowed).
- Surface actions allowed: `open_route`, `ask`, `open_url` (`https`, `tel`, `mailto`).
- Old engine files are not edited except where a task says so. `ZehnIntelligence.start` gets `@Deprecated('Use ZehnIntelligence.init')`.
- Work on branch `feat/server-proxy`; commit after each task.

## Review Focus

1. The customer API answers non-JSON (an HTML error page) or an empty body: the call returns `http_error`/`handler_failed`, never crashes the turn. → Task 6 test `non-JSON body becomes handler_failed`.
2. One of several tool calls in a round is slow: the others finish, the slow one becomes `timeout` at 20 s, and all results go in one request. → Task 6 test `slow call times out without blocking others`.
3. The user closes the chat mid-turn: the stream is cancelled, audio stops, and nothing is emitted after `close()`. → Task 8 test `close during stream does not throw`.
4. The cached start-up file is corrupt: it is ignored and refetched. → Task 5 test `corrupt cache is ignored`.
5. The language changes between questions: the next turn and the card use the new language. → Task 8 test `language is read per turn`.

## File Structure

```
lib/src/server/
  api/client_info.dart        ZiClientInfo — app key, package, versions, platform
  api/api_client.dart         ZiApiClient, ZiApiException — console HTTP + error mapping
  api/sse.dart                SseFrame, parseSse — bytes → frames
  api/turn_events.dart        TurnEvent (sealed) — frames → typed events
  api/turn_client.dart        ZiTurnClient, TurnInput, ToolCallResult — /v1/turns legs
  auth/file_store.dart        ZiFileStore — JSON files in the support folder
  auth/token_source.dart      ZiTokenSource, CallbackTokenSource, InstallTokenSource
  bootstrap/bootstrap.dart    ZiBootstrap + ZiApiSettings, ZiHttpTool, ZiParam, ZiResultRule, ZiComponentDef
  bootstrap/bootstrap_repository.dart  ZiBootstrapRepository — fetch, cache, refresh
  proxy/request_builder.dart  ZiRequestContext, ZiHttpRequest, buildRequest
  proxy/result_trimmer.dart   trimResult
  proxy/proxy_executor.dart   ZiProxyExecutor — makes the customer API call
  proxy/tool_runner.dart      ZiToolRunner — in-app handler → proxy → error, size cap, timeout
  surface/surface.dart        ZiSurface, ZiTheme, parseColor (from the spike)
  surface/surface_view.dart   ZiSurfaceView, ZiSurfaceAction (from the spike, fixed)
  chat/chat_state.dart        ZiChatState, ZiChatItem (sealed)
  chat/audio_queue.dart       ZiAudioQueue, AudioPlayerQueue
  chat/chat_cubit.dart        ZiChatCubit — runs turns
  ui/strings.dart             ZiStrings (uz/ru/en)
  ui/chat_sheet.dart          ZiChatSheet — list, cards, chips, composer, mic
  runtime.dart                ZiRuntime, resolveInitConfig — what init builds
lib/src/ui/zehn_intelligence.dart   modify: new init, wiring of static API
lib/src/ui/zehn_integrator.dart     modify: ZehnAiButton opens ZiChatSheet
lib/src/voice/voice_recorder.dart   modify: AAC option
lib/zehn_intelligence.dart          modify: export new public types
bin/mock_server.dart                mock console + fake customer API
example/                            Flutter app for the end-to-end check
test/support/fake_server.dart       FakeServer for tests
test/server/**                      one test file per lib file above
```

---

### Task 1: Test support, API client and errors

**Files:**
- Create: `test/support/fake_server.dart`, `lib/src/server/api/client_info.dart`, `lib/src/server/api/api_client.dart`, `docs/MOBILE_INTEGRATION.md` (copy of `/Users/doni/Desktop/MOBILE_INTEGRATION (1).md`)
- Modify: `lib/src/version.dart` (`'0.4.0'`), `pubspec.yaml` (version `0.4.0`)
- Test: `test/server/api/api_client_test.dart`

**Interfaces:**
- Produces:
  - `class FakeServer { static Future<FakeServer> start(); Uri get url; void on(String method, String path, FutureOr<void> Function(HttpRequest req) handler); List<RecordedRequest> get requests; Future<void> close(); }` with `RecordedRequest { String method; String path; Map<String,String> query; Map<String,String> headers (lower-case keys); String body; }`. Paths match exactly; `on` with a path ending in `/*` matches a prefix. Unmatched → 404.
  - `class ZiClientInfo { const ZiClientInfo({required String appKey, required String packageName, required String appVersion, required String sdkVersion, required String platform}); }`
  - `class ZiApiException implements Exception { final String code; final int? status; final Map<String,Object?> params; final String message; final bool retryable; factory ZiApiException.fromResponse(int status, Object? body); }`
  - `class ZiApiClient { ZiApiClient({required Uri baseUrl, required ZiClientInfo info, Dio? dio}); String? specVersion; Map<String,String> headers({String? userToken}); Future<Object?> getJson(String path, {Map<String,String>? query, String? userToken}); Future<Object?> postJson(String path, Object body, {String? userToken}); Future<ResponseBody> postStream(String path, Object body, {required String userToken}); }` — `path` is relative to `baseUrl` and starts with `/v1/`.

- [ ] **Step 1:** `git checkout -b feat/server-proxy`.
- [ ] **Step 2: Write the failing tests** in `api_client_test.dart`:
  - `sends every X-ZI header`: GET with `userToken: 't'`, `specVersion = '1.0.3'` → server saw `authorization: Bearer t`, `x-zi-app-key`, `x-zi-package`, `x-zi-app-version`, `x-zi-spec-version: 1.0.3`, `x-zi-sdk-version: 0.4.0`, `x-zi-platform`.
  - `omits spec and auth headers when unknown`: no `userToken`, `specVersion` null → no `authorization`, no `x-zi-spec-version`.
  - `maps error body to code`: 401 `{"code":"user_token_expired","message":"m","params":{}}` → throws `ZiApiException` with `code == 'user_token_expired'`, `status == 401`, `retryable == false`.
  - `422 is invalid_request`, `unknown 5xx is retryable` (`code` from body or `internal_error`), `non-JSON 502 is server_unavailable`, `connection refused is network_error with null status`.
  - `postStream rejects non event-stream`: 200 with `content-type: text/html` → `server_unavailable`.
- [ ] **Step 3:** Run `fvm flutter test test/server/api/api_client_test.dart` — expect FAIL (missing files).
- [ ] **Step 4:** Implement `FakeServer`, `ZiClientInfo`, `ZiApiClient`, `ZiApiException`. Dio with `validateStatus: (_) => true`, map statuses yourself; `postStream` uses `ResponseType.stream`; on non-200 read the stream to a string and map it like JSON errors.
- [ ] **Step 5:** Run the test — expect PASS. Run `fvm flutter analyze` — no issues.
- [ ] **Step 6:** Commit `feat(server): API client with X-ZI headers and error codes`.

### Task 2: SSE parser and turn events

**Files:**
- Create: `lib/src/server/api/sse.dart`, `lib/src/server/api/turn_events.dart`
- Test: `test/server/api/sse_test.dart`, `test/server/api/turn_events_test.dart`

**Interfaces:**
- Produces:
  - `class SseFrame { const SseFrame({required String event, required String data, String? id}); bool get isPing; }` — a comment line (`: ping`) yields `SseFrame(event: 'ping', data: '')`.
  - `Stream<SseFrame> parseSse(Stream<List<int>> bytes)`
  - `sealed class TurnEvent { String get turnId; int get seq; static TurnEvent? fromFrame(SseFrame f); }` — `null` for unknown event types; `FormatException` for a known type with a broken body. Subclasses (fields as in the doc's event table): `TurnStarted(conversationId, conversationNew)`, `TranscriptEvent(text, language)`, `TextDelta(text)`, `ClientApiRequest(callId, tool, Map<String,Object?> args)`, `MountComponent(callId, component, kind, Map<String,Object?> props)`, `AudioClip(format, text, data)`, `SuggestionsEvent(List<String> items)`, `TurnPaused(List<String> callIds, DateTime deadline, int maxResultBytes)`, `TurnDone(outcome)`, `TurnFailed(ZiApiException error)`, `PingEvent()`. `TurnFailed` is also what the turn client emits for its own errors.

- [ ] **Step 1: Write the failing tests:**
  - `parses frames split across chunks` (feed `event: text.delta\nid: 3\nda` then `ta: {"a":1}\n\n`) → one frame, `event == 'text.delta'`, `id == '3'`.
  - `joins multi-line data with \n`, `accepts CRLF`, `comment line is a ping frame`, `frame without event is "message"`.
  - Events: `text.delta parses text and seq`; `client_api_request parses args map`; `turn.paused parses deadline as DateTime`; `error event becomes TurnFailed with code and retryable`; `unknown event type returns null`; `unknown fields are ignored`; `text.delta without text throws FormatException`.
- [ ] **Step 2:** Run both test files — FAIL.
- [ ] **Step 3:** Implement with `utf8.decoder` + `LineSplitter`; dispatch a frame on an empty line.
- [ ] **Step 4:** Run — PASS; analyze clean.
- [ ] **Step 5:** Commit `feat(server): SSE parser and typed turn events`.

### Task 3: File store and token sources

**Files:**
- Create: `lib/src/server/auth/file_store.dart`, `lib/src/server/auth/token_source.dart`
- Test: `test/server/auth/token_source_test.dart`

**Interfaces:**
- Consumes: `ZiApiClient.postJson`, `ZiApiException` (Task 1).
- Produces:
  - `class ZiFileStore { ZiFileStore([Future<Directory> Function()? dir]); Future<Map<String,Object?>?> read(String name); Future<void> write(String name, Map<String,Object?> json); Future<void> delete(String name); }` — default dir `getApplicationSupportDirectory()/zehn_intelligence`; a corrupt or missing file reads as `null`.
  - `abstract interface class ZiTokenSource { Future<String> token(); Future<String> refresh(); }`
  - `class CallbackTokenSource implements ZiTokenSource { CallbackTokenSource(FutureOr<String?> Function() fetch); }` — caches the first value; `refresh()` calls `fetch` again; `null`/empty → throws `ZiApiException` with code `user_token_required`.
  - `class InstallTokenSource implements ZiTokenSource { InstallTokenSource({required ZiApiClient api, required ZiFileStore store, DateTime Function()? now}); }` — file `install.json` `{install_id, token, expires_at}`; `install_id` = 32 hex chars from `Random.secure()`, made once; `token()` reuses a token that expires more than 60 s from now, else `POST /v1/installs {"install_id": …}`; `refresh()` always posts.

- [ ] **Step 1: Write the failing tests** (FakeServer for `/v1/installs`, temp dir store):
  - `install token is fetched once and cached` (two `token()` calls → one request; body has 32-hex `install_id`).
  - `install_id survives a new source on the same store` (same id in both requests after `refresh()`).
  - `expired token is fetched again` (`now` 2 h later with `expires_in: 3600`).
  - `callback source caches and refreshes`, `callback null throws user_token_required`.
  - `corrupt file reads as null` (write `{oops` to the file).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run — PASS; analyze clean.
- [ ] **Step 5:** Commit `feat(server): install and callback token sources`.

### Task 4: Turn client

**Files:**
- Create: `lib/src/server/api/turn_client.dart`
- Test: `test/server/api/turn_client_test.dart`

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces:
  - `class TurnInput { TurnInput.text({String? conversationId, required String text, required String language, int? utcOffsetMinutes}); TurnInput.audio({String? conversationId, required String base64, required String format, required String language, int? utcOffsetMinutes, bool voiceReply = true}); TurnInput withConversation(String? id); Map<String,Object?> toJson(); }` — JSON exactly as the doc's `POST /v1/turns` body; `conversation_id` is always present (may be `null`).
  - `class ToolCallResult { ToolCallResult.ok(String callId, Object? data); ToolCallResult.error(String callId, String code, String message); final String callId; final bool ok; Map<String,Object?> toJson(); }`
  - `class ZiTurnClient { ZiTurnClient({required ZiApiClient api, required ZiTokenSource Function() tokens, Duration pingTimeout = const Duration(seconds: 45), Duration retryDelay = const Duration(seconds: 1)}); Stream<TurnEvent> start(TurnInput input); Stream<TurnEvent> sendResults(String turnId, List<ToolCallResult> results, {required DateTime deadline}); }` — `tokens` is a getter so `setUser` can swap the source. Every failure is emitted as a `TurnFailed` event, never thrown. Each returned stream ends after its terminal event (`TurnPaused`, `TurnDone`, `TurnFailed`).

- [ ] **Step 1: Write the failing tests** (FakeServer writing SSE with `text/event-stream`):
  - `streams events of one leg and ends on turn.paused`.
  - `retries once with a refreshed token on user_token_expired` (first 401, second 200; second request has the new bearer).
  - `does not retry twice` (two 401s → one `TurnFailed('user_token_expired')`).
  - `stream closed before a terminal event is stream_interrupted`.
  - `no frame for pingTimeout is stream_interrupted` (pingTimeout 200 ms, server sends nothing).
  - `pings keep the stream alive` (pings every 100 ms for 500 ms with pingTimeout 200 ms, then `done`).
  - `broken known event is invalid_response`.
  - `sendResults retries a network failure once before the deadline` (server closes the socket first time) and `does not retry after an HTTP status` (500 → `TurnFailed`).
  - `sendResults posts all results in one body` (`{"results":[…]}` with both call ids).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement. Watchdog: restart a `Timer(pingTimeout)` on every frame; on fire, cancel the subscription and emit `TurnFailed(stream_interrupted)`.
- [ ] **Step 4:** Run — PASS; analyze clean.
- [ ] **Step 5:** Commit `feat(server): turn client with token retry and stream watchdog`.

### Task 5: Start-up data

**Files:**
- Create: `lib/src/server/bootstrap/bootstrap.dart`, `lib/src/server/bootstrap/bootstrap_repository.dart`
- Test: `test/server/bootstrap/bootstrap_test.dart`, `test/server/bootstrap/bootstrap_repository_test.dart`

**Interfaces:**
- Consumes: `ZiApiClient.getJson`, `ZiFileStore`.
- Produces:
  - `class ZiBootstrap { factory ZiBootstrap.fromJson(Object? json); Map<String,Object?> toJson(); final String? specVersion; final Set<String> services; final List<String> languages; final String? defaultLanguage; final ZiApiSettings api; final Map<String,ZiHttpTool> tools; final Map<String,ZiComponentDef> components; final Map<String,Object?> theme; }` — keeps the raw JSON for `toJson`. Throws `FormatException` only when `json` is not a map.
  - `class ZiApiSettings { final Uri? baseUrl; final Set<String> allowedHosts; final String authHeader /* default Authorization */; final String authScheme /* default Bearer */; final Map<String,String> headers; }`
  - `enum ZiParamIn { path, query, header }` and `class ZiParam { final String name; final ZiParamIn location; final String key /* defaults to name */; }` (a `body` param is not supported under GET-only and makes the tool invalid).
  - `class ZiHttpTool { final String method; final String path; final List<ZiParam> params; final Map<String,String> headers; final bool auth; final ZiResultRule? result; }`
  - `class ZiResultRule { final String? root; final List<String> fields; final int maxItems /* default 10 */; }`
  - `enum ZiComponentKind { inline, sheet, route }` and `class ZiComponentDef { final ZiComponentKind kind; final Map<String,Object?>? surface; final String? route; }` (`route` kind needs `route`; others need `surface`).
  - `class ZiBootstrapRepository { ZiBootstrapRepository({required ZiApiClient api, required ZiFileStore store}); ZiBootstrap? get current; Future<ZiBootstrap?> loadCached(); Future<ZiBootstrap?> refresh(); }` — `refresh` GETs `/v1/bootstrap`, saves `bootstrap.json`, sets `current` and `api.specVersion`; on any failure keeps and returns `current`.

- [ ] **Step 1: Write the failing tests:**
  - `parses the spec example` (the JSON block in the spec's "Start-up data" section; check `tools['locations.get']!.params.single.location == ZiParamIn.path`, `result.maxItems == 10`, `components['loyalty_page']!.route == '/loyalty'`, `api.authScheme == 'Bearer'`).
  - `a broken tool is left out, others stay` (one tool with `path: 5`).
  - `unknown fields are ignored`; `route component without route is left out`.
  - Repository: `refresh saves and sets specVersion`; `network failure keeps cached data` (write cache, server 500 → `current` from cache); `corrupt cache is ignored` (Review Focus 4: write `{oops` → `loadCached()` null, `refresh()` succeeds).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run — PASS; analyze clean.
- [ ] **Step 5:** Commit `feat(server): start-up data model and cached repository`.

### Task 6: Proxy executor and tool runner

**Files:**
- Create: `lib/src/server/proxy/request_builder.dart`, `lib/src/server/proxy/result_trimmer.dart`, `lib/src/server/proxy/proxy_executor.dart`, `lib/src/server/proxy/tool_runner.dart`
- Test: `test/server/proxy/request_builder_test.dart`, `test/server/proxy/result_trimmer_test.dart`, `test/server/proxy/proxy_executor_test.dart`, `test/server/proxy/tool_runner_test.dart`

**Interfaces:**
- Consumes: `ZiHttpTool`, `ZiBootstrap`, `ZiBootstrapRepository` (Task 5); `ToolCallResult`, `ClientApiRequest` (Tasks 2, 4); existing `ZiToolError` (`lib/src/ui/zehn_integrator.dart`).
- Produces:
  - `class ZiRequestContext { const ZiRequestContext({required String language, required String appVersion, required String platform}); }`
  - `class ZiHttpRequest { final String method; final String path; final Map<String,String> query; final Map<String,String> headers; }`
  - `ZiHttpRequest buildRequest(ZiHttpTool tool, Map<String,Object?> args, ZiApiSettings api, ZiRequestContext ctx)` — throws `ZiToolError('method_not_allowed'|'host_not_allowed'|'invalid_args', …)`. Headers = `api.headers` then `tool.headers` then `header` params; `{language}`, `{app_version}`, `{platform}` filled. Missing optional query args are omitted; a missing path param is `invalid_args`.
  - `Object? trimResult(Object? body, ZiResultRule? rule)` — as the spec's `result` rule; `fields` paths like `category/name` produce nested `{category: {name: …}}`.
  - `class ZiProxyExecutor { ZiProxyExecutor({Dio? appClient, FutureOr<String?> Function()? accessToken, FutureOr<bool> Function()? onUnauthorized, Uri? baseUrlOverride, Dio? ownClient, Duration timeout = const Duration(seconds: 20)}); bool get hasLogin; Future<Object?> call(ZiHttpTool tool, Map<String,Object?> args, ZiBootstrap boot, ZiRequestContext ctx); }` — returns the trimmed JSON or throws `ZiToolError` (`not_signed_in`, `http_error`, `network_error`, `timeout`, `handler_failed` for a non-JSON body, plus `buildRequest`'s codes). `ownClient` is for tests; production makes a plain `Dio`.
  - `typedef ZiToolHandler = Future<Map<String,Object?>> Function(Map<String,Object?> args);`
  - `class ZiToolRunner { ZiToolRunner({required Map<String,ZiToolHandler> handlers, required ZiProxyExecutor proxy, required ZiBootstrapRepository bootstrap, required ZiRequestContext Function() context, Duration timeout = const Duration(seconds: 20), int maxResultBytes = 32768}); Future<List<ToolCallResult>> runAll(List<ClientApiRequest> calls); }` — all calls in parallel; in-app handler → proxy tool → `handler_not_registered`; refreshes start-up data at most once per `runAll` when a tool is missing; `ZiToolError` keeps its code, other exceptions are `handler_failed`; over `maxResultBytes` → `result_too_large`. Results keep the input order.

- [ ] **Step 1: Write the failing tests:**
  - Builder: `fills path, query and header params` (`/location/venues/{id}` + `id: 'a/b'` → path `/location/venues/a%2Fb`; `category_id` → query key `category`); `fills header placeholders`; `rejects POST with method_not_allowed`; `rejects a full-URL path with host_not_allowed`; `missing path param is invalid_args`; `omits missing optional query params`.
  - Trimmer: `keeps root, max_items and fields` (`{"results":[12 items]}`, `root: /results`, `fields: [id, category/name]`, `max_items: 10` → 10 items with only those keys); `no rule returns body unchanged`; `object root with fields`.
  - Executor (FakeServer as the customer API): `callbacks mode adds Bearer and Accept-Language`; `401 calls onUnauthorized once then retries`; `401 twice is not_signed_in`; `auth tool without login is not_signed_in with no request`; `host outside allowed_hosts is host_not_allowed` (baseUrlOverride to another host); `client mode uses the app Dio base URL and adds no auth header`; `client mode 401 is not_signed_in without retry`; `non-JSON body becomes handler_failed` (Review Focus 1); `500 is http_error with status in message`.
  - Runner: `in-app handler wins over proxy tool`; `unknown tool refreshes start-up data once then handler_not_registered`; `ZiToolError code is kept`; `result over 32 KB is result_too_large`; `slow call times out without blocking others` (Review Focus 2: timeout 100 ms, one handler waits 1 s → `timeout`, other `ok`, order kept).
- [ ] **Step 2:** Run the four files — FAIL.
- [ ] **Step 3:** Implement.
- [ ] **Step 4:** Run — PASS; analyze clean.
- [ ] **Step 5:** Commit `feat(server): proxy executor and tool runner`.

### Task 7: Surface renderer

**Files:**
- Create: `lib/src/server/surface/surface.dart`, `lib/src/server/surface/surface_view.dart` — start from `/Users/doni/Desktop/Zehnmind/zehn:intelligence/spikes/dynamic_card_spike/lib/renderer.dart`
- Test: `test/server/surface/surface_view_test.dart`

**Interfaces:**
- Produces:
  - `class ZiSurface { factory ZiSurface.parse(Object? json); final String id; final String catalogId; final String root; }` (as the spike).
  - `class ZiTheme { const ZiTheme(Map<String,Object?> json); }` (as the spike).
  - `class ZiSurfaceAction { final String name; final Map<String,Object?> args; }`
  - `class ZiSurfaceView extends StatelessWidget { const ZiSurfaceView({required ZiSurface surface, required Object? data, required ZiTheme theme, required String language, required void Function(ZiSurfaceAction) onAction}); }` — calls `onAction` only for `open_route`, `ask`, `open_url`; logs others with `debugPrint`.

Changes from the spike: resolve `action.args` entry by entry (never treat the args map as a binding); allowed actions per Global Constraints; unknown/missing component → `SizedBox.shrink()` in release, the red note only when `kDebugMode`; drop the spike's `call_tool`.

- [ ] **Step 1: Write the failing widget tests:**
  - `draws text from a data path in the chosen language` (`{"path":"/cinema/name"}` and a `{uz,ru,en}` data value with `language: 'ru'`).
  - `fills {/path} placeholders`; `repeats a template over a list with relative paths`; `hides a component whose visible path is empty`.
  - `button sends open_route with an arg named path intact` (args `{"path": "/x"}` → `onAction` gets `args['path'] == '/x'`).
  - `run_js action is not passed on`.
  - `unknown component draws nothing outside debug` — assert `find.textContaining('not in catalog')` per `kDebugMode` (tests run in debug, so assert it shows; the release branch is a one-line `if`).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Port and fix.
- [ ] **Step 4:** Run — PASS; analyze clean.
- [ ] **Step 5:** Commit `feat(server): console component renderer`.

### Task 8: Chat cubit and audio queue

**Files:**
- Create: `lib/src/server/chat/chat_state.dart`, `lib/src/server/chat/audio_queue.dart`, `lib/src/server/chat/chat_cubit.dart`
- Test: `test/server/chat/chat_cubit_test.dart`

**Interfaces:**
- Consumes: `ZiTurnClient`, `TurnInput`, `TurnEvent`s (Tasks 2, 4); `ZiComponentKind` (Task 5); `ZiToolRunner.runAll` (Task 6); `ZiApiClient.getJson` for `/v1/suggestions`.
- Produces:
  - `sealed class ZiChatItem` with `ZiUserItem(String text, {bool spoken})`, `ZiAssistantItem(String id, String text)`, `ZiComponentItem(String callId, String component, ZiComponentKind kind, Map<String,Object?> props)`, `ZiErrorItem(String code, {bool retryable})`.
  - `class ZiChatState extends Equatable { final List<ZiChatItem> items; final bool busy; final List<String> suggestions; final String? conversationId; }`
  - `abstract interface class ZiAudioQueue { void add(int seq, String base64, String format); Future<void> stop(); }` and `class AudioPlayerQueue implements ZiAudioQueue` (audioplayers, plays in `seq` order, one at a time).
  - `class ZiChatCubit extends Cubit<ZiChatState> { ZiChatCubit({required ZiTurnClient turns, required ZiToolRunner tools, required ZiAudioQueue audio, required String Function() language, Future<List<String>> Function()? starterSuggestions}); Stream<ZiComponentItem> get opens; Future<void> sendText(String text); Future<void> sendAudio(String base64, String format, {required bool voiceReply}); Future<void> retry(); Future<void> loadStarterSuggestions(); void reset(); }` — `opens` emits `sheet`/`route` components (the UI shows them); `inline` ones go into `items`. Text over 4000 chars is cut to 4000.

Turn loop: append the user item and an empty assistant item; listen to `start`; `TurnStarted` → save `conversationId`; `TranscriptEvent` → replace the user item's text, `spoken: true`; `TextDelta` → append; `ClientApiRequest` → collect; `MountComponent` → inline item or `opens`; `AudioClip` → `audio.add`; `SuggestionsEvent` → `suggestions`; `TurnPaused` → `tools.runAll(collected)` then listen to `sendResults(turnId, results, deadline)`; `TurnDone` → not busy; `TurnFailed` → if code is `conversation_not_found|conversation_spec_changed|conversation_full` and not yet retried, resend with `conversationId: null`; else append `ZiErrorItem`. A new send while `busy` is ignored; a new send calls `audio.stop()`.

- [ ] **Step 1: Write the failing tests** (a fake `ZiTurnClient` subclass returning scripted streams, a fake `ZiToolRunner` and `ZiAudioQueue`; `bloc_test` where it fits):
  - `text deltas build one assistant message`; `conversation id is kept for the next turn`.
  - `paused turn runs tools and posts their results` (fake runner gets both `ClientApiRequest`s; `sendResults` receives its results and the deadline).
  - `inline component goes to items, route goes to opens`.
  - `conversation_spec_changed resends once with a null conversation id`.
  - `retryable error shows retry, retry resends the last input`.
  - `send while busy is ignored`.
  - `language is read per turn` (Review Focus 5: change the language callback's value between two sends → `TurnInput.toJson()['language']` differs).
  - `close during stream does not throw` (Review Focus 3: close the cubit while the fake stream is open; then the fake emits more events; no error; `audio.stop` called).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement. Keep the active `StreamSubscription`; cancel it and `audio.stop()` in `close()` and `reset()`; check `isClosed` before every `emit`.
- [ ] **Step 4:** Run — PASS; analyze clean.
- [ ] **Step 5:** Commit `feat(server): chat cubit for the turn flow`.

### Task 9: Chat sheet UI

**Files:**
- Create: `lib/src/server/ui/strings.dart`, `lib/src/server/ui/chat_sheet.dart`
- Modify: `lib/src/voice/voice_recorder.dart` (add `final bool aac` constructor param, default `false`; when true: `AudioEncoder.aacLc`, `bitRate: 64000`, `sampleRate: 44100`, file `.m4a`), `pubspec.yaml` (`flutter_markdown_plus`, `url_launcher`)
- Test: `test/server/ui/chat_sheet_test.dart`

**Interfaces:**
- Consumes: `ZiChatCubit`, `ZiChatState`, `ZiChatItem` (Task 8); `ZiSurfaceView`, `ZiSurface`, `ZiTheme` (Task 7); `ZiBootstrapRepository.current` / `.refresh()` and `ZiBootstrap.components`, `.services`, `.theme` (Task 5); `AgentVoiceRecorder`.
- Produces:
  - `class ZiStrings { static ZiStrings of(String language); String get title, placeholder, send, holdToSpeak, retry, typeInstead; String error(String code); }` — uz/ru/en; `error` groups codes as the doc's table: `network_error`/`stream_interrupted` → connection; `sdk_too_old`/`key_revoked` → update the app; `app_disabled`/`llm_unavailable` → not available now; `turn_expired` → took too long; `speech_not_recognized`; `speech_unavailable`; `user_token_required` → sign in again; anything else → generic.
  - `class ZiChatSheet extends StatefulWidget { static Future<void> show(BuildContext context, {required ZiChatCubit cubit, required ZiBootstrapRepository bootstrap, required String Function() language, required Map<String, Widget Function(BuildContext, Map<String,Object?>, ZiComponentController)> builders, required FutureOr<void> Function(String route)? openRoute, String? title}); }` — `showModalBottomSheet` at 90% height. Inside: message list (user bubbles; assistant text as `MarkdownBody`; inline components: in-app builder first, else `ZiSurfaceView` from `bootstrap.current?.components[name].surface` with `data: props`; if neither has it, call `bootstrap.refresh()` once per component name and redraw, else nothing); error row with "try again" when retryable; suggestion chips (tap → `sendText`); composer (text field, send; mic shown only when `services` has `stt`, hold to record with `AgentVoiceRecorder(aac: true)`, release → base64 → `sendAudio(voiceReply: services.contains('tts'))`, over 1 MiB → `error('payload_too_large')` item without sending). Listens to `cubit.opens`: `sheet` → bottom sheet with the surface; `route` → pop the chat sheet, then `openRoute(route)` with `{name}` filled from props. Surface actions: `ask` → `sendText`; `open_route` → same as a route; `open_url` → `launchUrl` for `https`/`tel`/`mailto`.

- [ ] **Step 1: Write the failing widget tests** (real cubit with the Task 8 fakes):
  - `typing and sending shows the user bubble and the streamed reply` (`**bold**` renders as bold text via `MarkdownBody`).
  - `inline component from start-up data is drawn` (component def with a `Text` surface bound to `props`).
  - `in-app builder wins over start-up data`.
  - `route component closes the sheet and calls openRoute with filled placeholders` (`/explore/cinema/{id}` + props `{id: 1}` → `/explore/cinema/1`).
  - `mic is hidden without stt`; `suggestion chip sends its text`; `retry button appears only for retryable errors`.
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** `fvm flutter pub add flutter_markdown_plus url_launcher`; implement.
- [ ] **Step 4:** Run — PASS; analyze clean.
- [ ] **Step 5:** Commit `feat(server): chat sheet with cards, chips and voice`.

### Task 10: Runtime and public API

**Files:**
- Create: `lib/src/server/runtime.dart`
- Modify: `lib/src/ui/zehn_intelligence.dart` (static API from line 100 to the end of `init`), `lib/src/ui/zehn_integrator.dart` (`ZehnAiButton`), `lib/zehn_intelligence.dart` (exports)
- Test: `test/server/runtime_test.dart`

**Interfaces:**
- Consumes: everything above.
- Produces:
  - `class ZiInitConfig { final String appKey; final Uri consoleUrl; final String? specVersion; }`
  - `ZiInitConfig resolveInitConfig({String? token, Uri? consoleUrl, Map<String,Object?>? fileConfig, Map<String,String> defines = const {}})` — order: argument → file config (`zi_app_key`, `zi_console_url`, `zi_spec_version`) → defines (`zi_app_key`/`ZEHN_API_KEY`, `zi_console_url`/`ZEHN_INTELLIGENCE_CONFIG_URL`) → default console URL `https://zi-console-api.zehnmind.com`; no key → throws `ZiConfigException`.
  - `class ZiRuntime { static ZiRuntime? instance; static Future<ZiRuntime> create({required ZiInitConfig config, required ZiClientInfo info, Dio? client, FutureOr<String?> Function()? accessToken, FutureOr<bool> Function()? onUnauthorized, Uri? apiBaseUrl, FutureOr<String?> Function()? userToken, FutureOr<void> Function(String route)? openRoute, ZiFileStore? store}); String language; void setUserToken(FutureOr<String?> Function()? fetch); Future<void> clearUser(); ZiChatCubit get chat; ZiBootstrapRepository get bootstrap; Future<void> openChat(BuildContext context, {String? title}); }` — `create` sets `api.specVersion = config.specVersion` (file fallback), loads the cache, starts `refresh()` without awaiting it, prints a `debugPrint` warning when both `client` and `accessToken`/`onUnauthorized` are given (the client wins), builds the token source (callback if `userToken`, else install), proxy, runner (handlers = `ZehnIntelligence.registeredTools`), cubit. `language` defaults to the device language if it is in start-up `languages`, else `default_language`, else `en`.
  - `ZehnIntelligence.init({String? token, Uri? consoleUrl, Dio? client, FutureOr<String?> Function()? accessToken, FutureOr<bool> Function()? onUnauthorized, Uri? apiBaseUrl, FutureOr<String?> Function()? userToken, FutureOr<void> Function(String route)? openRoute, FutureOr<void> Function(BuildContext, dynamic)? onOpenRoute, String configPath = 'lib/config/zehn-intelligence.prod.json', String? appName}) → Future<void>` — reads the config file as today (only for fallback values), resolves config, reads `package_info_plus` for package/app version, `Platform.isIOS ? 'ios' : 'android'`, creates `ZiRuntime.instance`. `appName` and `onOpenRoute` are accepted for compatibility; `onOpenRoute` is unused by the new flow (documented).
  - `isInitialized` → `ZiRuntime.instance != null || instance != null`; `setLanguage` → also `ZiRuntime.instance?.language = …`; `setUser(token, {onTokenExpired})` → `setUserToken(() => onTokenExpired != null ? onTokenExpired() : token)` with the first call returning `token`; `signedIn({token})` same when `token != null`; `clearUser`/`signedOut` → `ZiRuntime.instance?.clearUser()` (reset chat, back to install token) plus the old behaviour.
  - `ZehnAiButton.build` → when `ZiRuntime.instance != null`, a `FloatingActionButton` that calls `ZiRuntime.instance!.openChat(context, title: title)`; otherwise the old `AgentButton` path.
  - Exports: `ZiApiException`, `ZiSurfaceView`, `ZiSurface`, `ZiTheme`, `ZiSurfaceAction` (others stay internal under `src/`).

- [ ] **Step 1: Write the failing tests:**
  - `argument key wins over file and defines`; `file config is used when no argument`; `defines are the last fallback`; `default console URL`; `no key throws ZiConfigException`.
  - `create with userToken uses CallbackTokenSource`, `without it uses InstallTokenSource` (inspect via a `@visibleForTesting ZiTokenSource get tokens`).
  - `create does not wait for the network` (FakeServer delays `/v1/bootstrap` 2 s; `create` completes under 500 ms using an empty temp store).
- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement; add `@Deprecated('Use ZehnIntelligence.init')` to `start`.
- [ ] **Step 4:** Run all tests `fvm flutter test` — PASS; analyze clean.
- [ ] **Step 5:** Commit `feat: init builds the server runtime; ZehnAiButton opens the new chat`.

### Task 11: Mock server, example app, end-to-end check

**Files:**
- Create: `bin/mock_server.dart`, `example/` (via `fvm flutter create --platforms=ios --project-name zehn_intelligence_example example`), `example/lib/main.dart`
- Modify: `example/pubspec.yaml` (`zehn_intelligence: {path: ../}`), `example/ios/Runner/Info.plist` (`NSAppTransportSecurity` → `NSAllowsLocalNetworking: true`; `NSMicrophoneUsageDescription`)

**Interfaces:**
- Consumes: the public API from Task 10.
- Produces: `dart run zehn_intelligence:mock_server [--port 8787]` — `dart:io` only, no new dependencies. Routes:
  - `GET /v1/bootstrap` → the spec's example shape with `api.base_url = http://localhost:<port>/customer`, `allowed_hosts: ["localhost"]`, tool `cinemas.list` (`GET /cinematica/`, `auth: false`), tool `loyalty_cards.get` (`GET /loyalty/cards/my`, `auth: true`), component `cinema_details` (inline, the spike's `cinema_details.json` surface with `/cinema` paths rewritten to the props root), component `loyalty_page` (route `/loyalty`), theme = the spike's `theme.json`, `services: ["llm"]`.
  - `POST /v1/installs` → a fixed token, `expires_in: 3600`.
  - `POST /v1/turns` → if the text contains `kino`, `cinema` or `кино`: `turn.started`, `text.delta`, `client_api_request cinemas.list`, `turn.paused`; if it contains `card`/`karta`/`карта`: same with `loyalty_cards.get`; else `turn.started`, `text.delta` echo, `done`.
  - `POST /v1/turns/{id}/tool-results` → for a successful `cinemas.list`: `text.delta`, `mount_component cinema_details inline` with `props` = the result's data, `suggestions`, `done`; for an error: `text.delta` that quotes the error code, `done`.
  - `GET /v1/suggestions` → three starter questions in the asked language.
  - `GET /customer/cinematica/` → the spike's `data.json` `cinema` object; `GET /customer/loyalty/cards/my` → 401 unless `Authorization: Bearer demo`.
  - Every request is logged as one line `METHOD path status`.
- `example/lib/main.dart`: `await ZehnIntelligence.init(token: 'zi_test_mock', consoleUrl: Uri.parse('http://localhost:8787'), accessToken: () => 'demo', openRoute: (r) => debugPrint('route $r'));` then a `Scaffold` with `ZehnAiButton()`.

- [ ] **Step 1:** Write `bin/mock_server.dart`; run it in the background (`dart run zehn_intelligence:mock_server`); `curl -s localhost:8787/v1/bootstrap | head -c 300` shows JSON; `curl -N -X POST localhost:8787/v1/turns -H 'content-type: application/json' -d '{"conversation_id":null,"input":{"type":"text","text":"kino"},"language":"en"}'` prints SSE ending in `turn.paused`.
- [ ] **Step 2:** Create the example app and edit `pubspec.yaml`, `Info.plist`, `main.dart`; `cd example && fvm flutter analyze` clean.
- [ ] **Step 3:** Run the example on the iOS simulator. Check, with screenshots: the button opens the sheet; starter chips show; "Tell me about the cinema" → streamed text, then the cinema card drawn from the console template; mock server log shows `GET /customer/cinematica/ 200`; "Show my card" → mock log shows `GET /customer/loyalty/cards/my 200` with the demo token.
- [ ] **Step 4:** Run `fvm flutter test` and `fvm flutter analyze` at the root — all pass.
- [ ] **Step 5:** Commit `feat: mock server and example app for the server flow`.
