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
| 2 | At start-up a new endpoint gives the SDK every tool's customer endpoint and headers. During a turn the server sends `tool + args`; the SDK builds and makes the request. | User |
| 4 | Login for the customer API: the app passes its own `Dio` (`client:`), **or** callbacks (`accessToken:`, `onUnauthorized:`). Both are supported. | User |
| 5 | User identity is postponed. The SDK takes a Zehn user token from the app if it gives one (`userToken:` / `setUser`); otherwise it uses an anonymous token per install, from a new backend endpoint. | User (postponed), install token is our call |
| 8 | Components: a fixed catalog of native widgets in the SDK, drawn from A2UI-shaped JSON templates (flat components with ids, data paths, actions) and theme tokens from the console. Pages become route links. | User chose our recommendation; spike in `spikes/dynamic_card_spike` |

Our calls (the user can revisit them):

- **Writes ask first.** Tools may use `GET`, `POST`, `PUT`, `PATCH` or `DELETE`. Every
  non-`GET` tool asks the user in the chat ("Allow" / "Cancel") before the SDK calls the
  customer API, unless the console sets `confirm: false`. (Changed 2026-11-09: the first version
  was GET-only.)
- **Escape hatch.** `registerTool` / `registerComponent` stay. An in-app handler or builder
  wins over the console's definition. TCM keeps working unchanged while it migrates.
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
  apiBaseUrl: null,                    // overrides the console's base URL (callbacks mode)
  userToken: null,                     // a Zehn user token, if the customer backend makes one
  openRoute: (route) => AppRouter.router.push(route),
  onOpenRoute: null,                   // legacy: still accepted for registered route components
);
```

- `client` wins over `accessToken` / `onUnauthorized`; passing both prints a debug warning.
- With neither, tools that need login answer `not_signed_in` without a request.
- `init` never throws for a network problem: it loads the cached start-up data and keeps
  retrying in the background. It throws `ZiConfigException` only when there is no app key.
- `ZehnAiButton` opens the new chat sheet.
- `setLanguage`, `setUser`, `clearUser`, `signedIn`, `signedOut`, `registerTool`,
  `registerComponent`, `isInitialized` keep their names and now work.

## Start-up data: `GET /v1/bootstrap` (new backend endpoint)

Headers: `X-ZI-App-Key`, `X-ZI-Package`, `X-ZI-App-Version`, `X-ZI-SDK-Version`,
`X-ZI-Platform`. No user token: this is app-level data. The server picks the latest
published spec for the key's track.

```json
{
  "format": 1,
  "spec_version": "1.0.3",
  "track": "prod",
  "services": ["llm", "stt", "tts"],
  "languages": ["uz", "ru", "en"],
  "default_language": "uz",
  "api": {
    "base_url": "https://api.example.uz",
    "allowed_hosts": ["api.example.uz"],
    "auth": { "header": "Authorization", "scheme": "Bearer" },
    "headers": { "Accept-Language": "{language}" }
  },
  "tools": {
    "stores.list": {
      "method": "GET",
      "path": "/location/venues",
      "params": [
        { "name": "page", "in": "query" },
        { "name": "category_id", "in": "query", "key": "category" }
      ],
      "headers": {},
      "auth": false,
      "result": { "root": "/results", "fields": ["public_id", "name", "floor"], "max_items": 10 }
    },
    "locations.get": {
      "method": "GET",
      "path": "/location/venues/{id}",
      "params": [{ "name": "id", "in": "path" }],
      "auth": false
    },
    "parking.reserve": {
      "method": "POST",
      "path": "/parking/reservations",
      "params": [
        { "name": "zone_id", "in": "body" },
        { "name": "hours", "in": "body", "key": "duration_hours" }
      ],
      "auth": true,
      "confirm": {
        "title": { "uz": "{zone_id}-zonada joy band qilinsinmi?", "ru": "Забронировать место в зоне {zone_id}?", "en": "Reserve a place in zone {zone_id}?" }
      }
    }
  },
  "components": {
    "cinema_details": { "kind": "inline", "surface": { "createSurface": { "...": "..." } } },
    "loyalty_page": { "kind": "route", "route": "/loyalty" }
  },
  "theme": { "font": "CeraPro", "colors": {}, "text": {}, "radius": {} }
}
```

Rules the SDK applies:

- `method` is `GET`, `POST`, `PUT`, `PATCH` or `DELETE`; anything else leaves the tool out.
- `params[].in` is `path`, `query`, `header` or `body`. `body` params go into a JSON body under
  `key` (default the argument name), keeping their JSON types; they are not allowed on `GET`.
- `confirm`: `true`, `false`, or `{"title": {lang: text}}` (which means `true`). It defaults to
  `true` for every method but `GET`. `{name}` placeholders in the title are filled from the call's
  arguments; without a title the chat asks "Allow this action?".
- `path` must start with `/`. A path that is a full URL is refused (`host_not_allowed`).
- Path parameters are URL-encoded, so `../admin` cannot change the path.
- In callbacks mode the request goes to `apiBaseUrl ?? api.base_url`, and its host must be in
  `allowed_hosts` (the base URL's host always is). In `client` mode the app's `Dio` decides.
- Header values may use `{language}`, `{app_version}`, `{platform}`. They are never secrets:
  anyone can read them from the phone.
- `auth` (login header) is added only in callbacks mode. In `client` mode the app's own
  interceptors add it.
- `result`: keep the JSON at `root` (a `/`-path, default the whole body); if it is a list,
  keep the first `max_items` (default 10); from each object keep only `fields` (`/`-paths,
  e.g. `category/name`; default all). The trimmed result must be at most 32 KB.
- The SDK caches the whole response in the app's support folder and uses the cache when the
  network fails. It fetches again at every start, and once per turn when the server names a
  tool or component the cached data does not have.
- Unknown fields are ignored. A tool with a broken definition is left out, not the whole list.

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
  `X-ZI-Spec-Version` (from start-up data, else the config file), `X-ZI-SDK-Version`,
  `X-ZI-Platform`.
- One turn at a time. `turn.started` gives the `conversation_id` for the next question.
- `client_api_request`: when the round's stream ends with `turn.paused`, the SDK runs all
  its calls at once, each through: in-app handler → console HTTP tool → error
  `handler_not_registered`. Each call has 20 s; results over 32 KB become `result_too_large`.
  All results go in one `tool-results` request.
- A tool that needs confirmation first shows a card in the chat. The 20 s start after the user
  allows it. A "Cancel", or no answer until 5 s before the round's `turn.paused` deadline,
  becomes `user_declined` and no request is made. In-app handlers never ask.
- Proxy errors the model reads: `user_declined`, `not_signed_in`, `host_not_allowed`, `method_not_allowed`,
  `invalid_args` (a path parameter missing), `http_error` (message names the status),
  `network_error`, `timeout`, `handler_failed`, `result_too_large`.
- A 401 from the customer API: in callbacks mode call `onUnauthorized` once and retry once;
  still 401 → `not_signed_in`. In `client` mode the app's interceptors already refreshed, so
  a 401 is `not_signed_in` at once.
- `mount_component`: in-app builder → console component → nothing (logged). `inline` draws
  in the chat; `sheet` opens a bottom sheet; `route` closes the chat sheet and calls
  `openRoute` with the route, `{name}` placeholders filled from `props`.
- `audio`: queued and played in `seq` order; a new question or closing the chat stops it.
- `suggestions` and `GET /v1/suggestions` show as chips; a tap sends the text.
- Errors follow the doc's table: token errors retry once with a new token; conversation
  errors (`conversation_not_found`, `conversation_spec_changed`, `conversation_full`) resend
  once with `conversation_id: null`; `stream_interrupted` after 45 s without a ping; others are
  shown, with "try again" only when retryable.
- Voice: the mic shows only when start-up data has `stt`; spoken replies only with `tts`.
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

Backend endpoints (`/v1/bootstrap`, `/v1/installs`, components in `mount_component`), the
analyzer, the console editor, the history screen, deleting the old engine, TCM's migration.

## Done means

- Unit and widget tests for each new piece pass (`flutter test`), and `flutter analyze` is clean.
- A mock server (`dart run zehn_intelligence:mock_server`) serves start-up data, install
  tokens, scripted turns and a fake customer API; an example app on the iOS simulator asks a
  question, the SDK calls the fake customer API, and a console-made card is drawn.
