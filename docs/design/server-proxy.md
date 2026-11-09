# Server flow and API proxy for the mobile SDK — design

Date: 2026-11-09. Scope: the Flutter SDK (`zehn_intelligence`) only. The backend pieces it
needs are written down here as a contract; building them is separate work.

## Why

Today every customer app carries generated glue (`lib/zehn_intelligence/`: tool handlers
that call the app's repositories, component builders, a token fetcher). TCM has about
1,600 lines of it. We want the app to call one `init` in `main.dart` and nothing else:

- The console's analyzer reads the app's code and finds every real API call (method, path,
  where each parameter goes, whether login is needed).
- The backend turns each tool call into a request description, and the SDK makes that
  request to the customer's API itself, as a proxy, with the user's own login.
- Components are drawn by the SDK from templates made in the console, in the app's colors
  and font.

The SDK also breaks the backend's rule today: it calls `api.zehnmind.com` for chat and
voice. `MOBILE_INTEGRATION.md` (2026-11-06) says the SDK talks only to `zi_console_url`.

## Decisions

| # | Decision | Source |
|---|---|---|
| 1 | The SDK uses the server's turn flow (`/v1/turns`, SSE, `tool-results`) exactly as `MOBILE_INTEGRATION.md` describes. No call to `api.zehnmind.com`. | User |
| 2 | During a turn the server sends `tool + args` and the customer request it built for them (`client_api_request.http`); the SDK checks it, adds the user's login and makes it. (Changed 2026-11-09: the first version fetched every tool's endpoint at start-up from `GET /v1/bootstrap`; that endpoint is gone, and the backend caches instead.) | User |
| 4 | Login for the customer API: the app passes its own `Dio` (`client:`), **or** callbacks (`accessToken:`, `onUnauthorized:`). Both are supported. | User |
| 5 | User identity is postponed. The SDK takes a Zehn user token from the app if it gives one (`userToken:` / `setUser`); otherwise it uses an anonymous token per install, from a new backend endpoint. | User (postponed), install token is our call |
| 8 | Components: a fixed catalog of native widgets in the SDK, drawn from A2UI-shaped JSON templates (flat components with ids, data paths, actions) and theme tokens from the console. Pages become route links. | User chose our recommendation; spike in `spikes/dynamic_card_spike` |

Our calls (the user can revisit them):

- **Writes ask first.** Tools may use `GET`, `POST`, `PUT`, `PATCH` or `DELETE`. Every
  non-`GET` tool asks the user in the chat ("Allow" / "Cancel") before the SDK calls the
  customer API, unless the console sets `confirm: false`. (Changed 2026-11-09: the first version
  was GET-only.)
- **Escape hatch.** `registerTool` / `registerComponent` stay. An in-app handler or builder
  wins over what the server sends. TCM keeps working unchanged while it migrates.
- **Old engine stays.** The on-device engine (`ZehnIntelligence.start`, transports, packs)
  is left in place and marked deprecated; `init` no longer uses it. Deleting it is later work.
- **History screen** (`/v1/conversations`) is not part of this change. Suggestions are.
- **The app key** comes from `init(token:)`; if it is missing, from the config file or
  `--dart-define` as today, so existing builds keep working.

## Public API

```dart
await ZehnIntelligence.init(
  token: 'zi_prod_…',                  // app key; falls back to the config file / dart-define
  consoleUrl: null,                    // default https://zi-console-api.zehnmind.com
  // Customer API login: one of these two ways.
  client: di<Dio>(),                   // the app's own Dio: its base URL, auth and refresh
  accessToken: () => storage.read('ACCESS_TOKEN'),
  onUnauthorized: () async => refreshSession(),   // true when a new token is ready
  apiBaseUrl: null,                    // overrides the request's base_url (callbacks mode)
  userToken: null,                     // a Zehn user token, if the customer backend makes one
  openRoute: (route) => AppRouter.router.push(route),
  onOpenRoute: null,                   // legacy: still accepted for registered route components
);
```

- `client` wins over `accessToken` / `onUnauthorized`; passing both prints a debug warning.
- With neither, tools that need login answer `not_signed_in` without a request.
- `init` makes no network call and keeps nothing from the console on the phone. It throws
  `ZiConfigException` only when there is no app key.
- `ZehnAiButton` opens the new chat sheet.
- `setLanguage`, `setUser`, `clearUser`, `signedIn`, `signedOut`, `registerTool`,
  `registerComponent`, `isInitialized` keep their names and now work.

## Tool requests: `client_api_request.http`

The backend keeps each tool's customer endpoint (from the analyzer) and builds the request for
every call. It sends it with the call:

```
event: client_api_request
data: {"turn_id":"t1","seq":3,"call_id":"c_1","tool":"parking.reserve","args":{"zone_id":7,"hours":2},"http":{ … }}
```

```json
{
  "method": "POST",
  "path": "/parking/reservations",
  "query": { "lang": "uz" },
  "headers": { "Accept-Language": "uz" },
  "body": { "zone_id": 7, "duration_hours": 2 },
  "auth": true,
  "auth_header": "Authorization",
  "auth_scheme": "Bearer",
  "result": { "root": "/results", "fields": ["public_id", "name", "floor"], "max_items": 10 },
  "confirm": { "title": "Zona 7 da joy band qilinsinmi?" },
  "base_url": "https://api.example.uz"
}
```

Only `method` and `path` are required. Rules the SDK applies:

- `method` is `GET`, `POST`, `PUT`, `PATCH` or `DELETE`; anything else is `method_not_allowed`.
- `path` starts with `/`, with path parameters already filled and URL-encoded by the server. A
  full URL or `//host` is refused (`host_not_allowed`).
- `query` values are sent as strings; `headers` keep string values only. Header values are never
  secrets: anyone can read them from the phone.
- `body` is sent as JSON, keeping its types; a `GET` with a body is `invalid_request`.
- `auth: true` means the call needs the user's login. In callbacks mode the SDK adds
  `<auth_header>: <auth_scheme> <token>` (defaults `Authorization` / `Bearer`; an empty scheme
  sends the bare token). In `client` mode the app's own interceptors add it. A signed-out user
  (`isSignedIn` false, or no token) gets `not_signed_in` and no request is made.
- `confirm`: `true`, `false`, or `{"title": text}` (which means `true`), the title already in the
  user's language and filled in. It defaults to `true` for every method but `GET`. Without a
  title the chat asks "Allow this action?".
- `base_url` is used only in callbacks mode without `apiBaseUrl`. It must be `https`, or `http`
  to this machine (`localhost`, `127.0.0.1`, `::1`); otherwise `host_not_allowed`, so the user's
  token never travels in clear text because of server data. An app that wants plain HTTP (a dev
  server) passes `apiBaseUrl` itself. In `client` mode the app's `Dio` decides the base URL.
- `result`: keep the JSON at `root` (a `/`-path, default the whole body); if it is a list,
  keep the first `max_items` (default 10); from each object keep only `fields` (`/`-paths,
  e.g. `category/name`; default all). The trimmed result must be at most 32 KB.
- A call with no `http` and no in-app handler is `handler_not_registered`. Unknown fields are
  ignored.

## Chat settings: `GET /v1/suggestions` → `chat`

The SDK asks for starter suggestions each time the chat opens empty. The same answer carries
the chat's settings, so the phone needs no start-up call and keeps no copy:

```json
{
  "suggestions": ["Kinoteatr haqida aytib ber"],
  "chat": {
    "services": ["llm", "stt", "tts"],
    "languages": ["uz", "ru", "en"],
    "default_language": "uz",
    "theme": { "font": "CeraPro", "colors": {}, "text": {}, "radius": {} },
    "welcome_title": "Qanday yordam bera olaman?",
    "welcome_subtitle": "Do‘konlar, restoranlar va boshqalar.",
    "spec_version": "1.0.3"
  }
}
```

- Every field is optional; a missing one uses the SDK's default (no mic, the SDK's colours and
  words, languages `uz`/`ru`/`en`). A missing `chat` keeps the settings the SDK already has.
- `welcome_*` are already in the request's `language`.
- The language the SDK uses: the app's `setLanguage`, else the phone's if listed in
  `languages`, else `default_language`, else the first listed.
- `spec_version`, when present, is sent back as `X-ZI-Spec-Version`; otherwise the config
  file's value, if any.
- Settings that arrive while the chat is open apply at once. They live in memory for the app's
  run; the first chat of a run starts with the SDK's defaults until the answer arrives.

## Anonymous install token: `POST /v1/installs` (new backend endpoint)

Used only when the app gives no `userToken`. Same app headers as above.

```json
{ "install_id": "9f2c…32 hex" }
→ { "token": "eyJ…", "token_type": "Bearer", "expires_at": "…", "expires_in": 2592000 }
```

The SDK makes `install_id` once (random, 16 bytes) and keeps it and the token in its support
folder. On `user_token_expired` / `user_token_required` it gets a new token and retries once,
the same way it asks `userToken` again.

## A turn

As `MOBILE_INTEGRATION.md`, with these SDK specifics:

- Headers on every call: `Authorization: Bearer <user or install token>`, `X-ZI-App-Key`,
  `X-ZI-Package` (Android package name / iOS bundle id), `X-ZI-App-Version`,
  `X-ZI-Spec-Version` (from the chat settings, else the config file; optional), `X-ZI-SDK-Version`,
  `X-ZI-Platform`.
- One turn at a time. `turn.started` gives the `conversation_id` for the next question.
- `client_api_request`: when the round's stream ends with `turn.paused`, the SDK runs all
  its calls at once, each through: in-app handler → the call's `http` request → error
  `handler_not_registered`. Each call has 20 s; results over 32 KB become `result_too_large`.
  All results go in one `tool-results` request.
- A tool that needs confirmation first shows a card in the chat. The 20 s start after the user
  allows it. A "Cancel", or no answer until 5 s before the round's `turn.paused` deadline,
  becomes `user_declined` and no request is made. In-app handlers never ask.
- Proxy errors the model reads: `user_declined`, `not_signed_in`, `host_not_allowed`, `method_not_allowed`,
  `invalid_request` (a broken `http`), `http_error` (message names the status),
  `network_error`, `timeout`, `handler_failed`, `result_too_large`.
- A 401 from the customer API: in callbacks mode call `onUnauthorized` once and retry once;
  still 401 → `not_signed_in`. In `client` mode the app's interceptors already refreshed, so
  a 401 is `not_signed_in` at once.
- `mount_component`: in-app builder → the event's `surface` (or `route`) → nothing (logged).
  `inline` draws in the chat; `sheet` opens a bottom sheet; `route` closes the chat sheet and
  calls `openRoute` with the event's `route`, `{name}` placeholders filled from `props`. See
  `docs/DYNAMIC_CARDS.md`.
- `audio`: queued and played in `seq` order; a new question or closing the chat stops it.
- `suggestions` and `GET /v1/suggestions` show as chips; a tap sends the text.
- Errors follow the doc's table: token errors retry once with a new token; conversation
  errors (`conversation_not_found`, `conversation_spec_changed`, `conversation_full`) resend
  once with `conversation_id: null`; `stream_interrupted` after 45 s without a ping; others are
  shown, with "try again" only when retryable.
- Voice: the mic shows only when the chat settings have `stt`; spoken replies only with `tts`.
  Recordings are AAC in `.m4a`, sent whole, at most 1 MiB.

## Components

The spike's renderer moves into the SDK with two fixes:

- Action `args` are resolved one value at a time, so an argument named `path` is not taken as
  a data path (the spike's bug).
- Allowed actions are `open_route {route}`, `ask {text}` and `open_url {url}` (`https`,
  `tel`, `mailto` only). Anything else is ignored and logged.

Catalog `zehn.basic.v0`: `Box`, `Column`, `Row` (with `scroll`), `Image`, `Text`, `Chip`,
`Header`, `InfoRow`, `Button` (`primary`/`secondary`), `Divider`. Values are literals,
`{"path": "/a/b"}` (relative paths read the current list item), language maps
`{"uz": …, "ru": …, "en": …}`, and strings with `{/a/b}` placeholders. A component the
catalog lacks draws nothing in release builds and a red note in debug builds. The theme's
`font` names a font family the app already ships; nothing is downloaded.

## Not in this change

Backend work (`http` in `client_api_request`, `surface`/`route` in `mount_component`, `chat`
in `/v1/suggestions`, `/v1/installs`), the analyzer, the console editor, the history screen, deleting the old engine, TCM's migration.

## Done means

- Unit and widget tests for each new piece pass (`flutter test`), and `flutter analyze` is clean.
- A mock server (`dart run zehn_intelligence:mock_server [--app file.json]`) plays the backend:
  install tokens, chat settings, scripted turns with inline requests and cards, and a fake
  customer API; an example app on the iOS simulator asks a
  question, the SDK calls the fake customer API, and a console-made card is drawn.
