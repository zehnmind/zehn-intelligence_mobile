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
| 2 | During a turn the server sends `tool + args` and the customer request it built for them (`client_api_request.request`); the SDK checks it, adds the user's login and makes it. (Changed 2026-11-09: the first version fetched every tool's endpoint at start-up from `GET /v1/bootstrap`; that endpoint is gone, and the backend caches instead. The backend's `CARDS_FOR_MOBILE.md` fixed the field names.) | User, backend |
| 4 | Login for the customer API: the app passes its own `Dio` (`client:`), **or** callbacks (`accessToken:`, `onUnauthorized:`). Both are supported. | User |
| 5 | User identity is postponed. The SDK takes a Zehn user token from the app if it gives one (`userToken:` / `setUser`); otherwise the user is known only by the install id it makes (`X-ZI-Install-Id`), with no `Authorization` header. | User (postponed), backend |
| 8 | Components: a fixed catalog of native widgets in the SDK, drawn from A2UI-shaped JSON templates (flat components with ids, data paths, actions) and theme tokens from the console. Pages become route links. | User chose our recommendation; spike in `spikes/dynamic_card_spike` |

Our calls (the user can revisit them):

- **Writes ask first.** Tools may use `GET`, `POST`, `PUT`, `PATCH` or `DELETE`. Before a
  write the server sends a `confirm` card; the user's tap is a new turn, and only after Confirm
  does the server send the request, carrying that card's `action_id`. The SDK makes a write
  only for an action the user confirmed in this chat, once. (Changed 2026-11-09: the first
  version was GET-only; the second asked inside the tool round.)
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
- `init` waits for no network call: it starts `GET /v1/config` in the background and keeps
  nothing from the console on the phone but the install id. It throws `ZiConfigException`
  only when there is no app key.
- `ZehnAiButton` opens the new chat sheet. It is hidden while the console answers
  `404 spec_not_found` (nothing published yet).
- `setLanguage`, `setUser`, `clearUser`, `signedIn`, `signedOut`, `registerTool`,
  `registerComponent`, `isInitialized` keep their names and now work.

## Tool requests: `client_api_request.request`

The backend keeps each tool's customer endpoint (from the analyzer) and builds the request for
every call. It sends it with the call:

```
event: client_api_request
data: {"turn_id":"t1","seq":3,"call_id":"c_1","tool":"cinemas.list","args":{},"request":{"method":"GET","path":"/cinematica/","query":{}}}
```

A write carries the `action_id` of the confirm card the user tapped Confirm on (below), on the
event or inside `request`:

```json
{
  "method": "POST",
  "path": "/parking/reservations",
  "query": { "tag": ["a", "b"] },
  "body": { "zone_id": 7, "duration_hours": 2 },

  "headers": { "Accept-Language": "uz" },
  "auth": true,
  "auth_header": "Authorization",
  "auth_scheme": "Bearer",
  "result": { "root": "/results", "fields": ["public_id", "name", "floor"], "max_items": 10 },
  "base_url": "https://api.example.uz"
}
```

The backend's contract sends `method`, `path`, `query` and `body`. The fields after the blank
line are optional; the SDK uses them when they are there (and the backend has not confirmed it
sends them yet):

- `method` is `GET`, `POST`, `PUT`, `PATCH` or `DELETE`; anything else is `method_not_allowed`.
- `path` starts with `/`, with path parameters already filled and URL-encoded by the server. A
  full URL or `//host` is refused (`host_not_allowed`).
- `query` values are sent as strings; a list repeats its key (`?tag=a&tag=b`). `headers` keep
  string values only. Header values are never secrets: anyone can read them from the phone.
- `body` is sent as JSON, keeping its types; a `GET` with a body is `invalid_request`.
- **A write** (any method but `GET`) is made only when its `action_id` is one the user confirmed
  in this chat, and only once; otherwise it is `not_confirmed` and nothing is sent.
- `auth: true` means the call needs the user's login. In callbacks mode the SDK adds
  `<auth_header>: <auth_scheme> <token>` (defaults `Authorization` / `Bearer`; an empty scheme
  sends the bare token). In `client` mode the app's own interceptors add it. A signed-out user
  (`isSignedIn` false, or no token) gets `not_signed_in` and no request is made. Without
  `auth`, the SDK cannot tell, and a guest's call through the app's Dio may set off the app's
  own sign-out on a 401.
- `base_url` is used only in callbacks mode without `apiBaseUrl`. It must be `https`, or `http`
  to this machine (`localhost`, `127.0.0.1`, `::1`); otherwise `host_not_allowed`, so the user's
  token never travels in clear text because of server data. In `client` mode the app's `Dio`
  decides the base URL. Without `base_url` or `apiBaseUrl`, callbacks mode cannot make requests.
- `result`: keep the JSON at `root` (a `/`-path, default the whole body); if it is a list,
  keep the first `max_items` (default 10); from each object keep only `fields` (`/`-paths,
  e.g. `category/name`; default all). The trimmed result must be at most 32 KB.
- A call with no `request` and no in-app handler is `handler_not_registered`. Unknown fields
  are ignored.

## Confirm cards: the `confirm` event

```
event: confirm
data: {"turn_id":"…","seq":7,"call_id":"c2","action_id":"6f1d…","tool":"parking.reserve","method":"POST","surface":{"createSurface":{…}},"props":{…},"confirm_label":"Reserve","expires_in":600}
```

- The chat draws `surface` with `props` like any card (`docs/DYNAMIC_CARDS.md`), then Cancel and
  Confirm. Confirm's word is `confirm_label`, else the SDK's; for `DELETE` it is in a warning
  colour. One tap answers the card; it is disabled while a turn runs.
- A tap is a new turn: `POST /v1/turns` with
  `"input": {"type": "action", "action_id": "…", "decision": "confirm" | "cancel"}`. No user
  bubble is added; the card shows "Confirmed" or "Cancelled".
- After `expires_in` seconds (default 600), or when the tap's turn answers `action_used`,
  `action_expired` or `action_not_found`, the card shows as expired; no error message.

## Chat settings: `GET /v1/config`

Asked for in the background at start-up and again each time the chat opens (calls under way
are shared). No user token.

```json
{
  "spec_version": "1.2.0",
  "assistant_name": "Mall guide",
  "app_name": "Tashkent City Mall",
  "languages": ["uz", "ru", "en"],
  "default_language": "uz",
  "services": ["llm", "stt"],
  "theme": { "font": "CeraPro", "colors": {}, "text": {}, "radius": {} },
  "copy": {
    "welcome_title": { "uz": "Qanday yordam bera olaman?", "en": "How can I help you?" },
    "welcome_subtitle": "Find stores, restaurants, offers and more."
  }
}
```

- `assistant_name` is the chat's title (an app's own `openChat(title:)` wins).
- `copy.welcome_*` is one string or a language map: the user's language, else
  `default_language`, else `en`, else the first.
- The language the SDK uses: the app's `setLanguage`, else the phone's if listed in
  `languages`, else `default_language`, else the first listed.
- `services`: `stt` shows the mic, `tts` asks for spoken replies.
- `404 spec_not_found`: nothing is published; `ZehnAiButton` hides and `openChat` does
  nothing. Any other failure keeps the last settings (the SDK's defaults at first).
- `spec_version` is not sent back: the SDK never sends `X-ZI-Spec-Version`, which would make
  the server treat the build as one that pins a spec (no cards, no writes).

`GET /v1/suggestions` gives only the starter chips.

## Install id: `X-ZI-Install-Id`

The SDK makes a random id once (16 bytes, 32 hex characters), keeps it in its support folder
(an id an older SDK saved is kept), and sends it on every console call. With no `userToken`
there is no `Authorization` header. A token error with no user token is not retried. There is no
`/v1/installs`.

## A turn

As `MOBILE_INTEGRATION.md`, with these SDK specifics:

- Headers on every call: `Authorization: Bearer <user token>` (only with one), `X-ZI-App-Key`,
  `X-ZI-Package` (Android package name / iOS bundle id), `X-ZI-App-Version`,
  `X-ZI-SDK-Version`, `X-ZI-Platform`, `X-ZI-Install-Id`. Never `X-ZI-Spec-Version`.
- One turn at a time. `turn.started` gives the `conversation_id` for the next question.
- `client_api_request`: when the round's stream ends with `turn.paused`, the SDK runs all
  its calls at once, each through: in-app handler → the call's `request` → error
  `handler_not_registered`. Each call has 20 s; results over 32 KB become `result_too_large`.
  All results go in one `tool-results` request.
- `confirm`: a card with Cancel and Confirm (section above); writes wait for it. In-app
  handlers never ask.
- Proxy errors the model reads: `not_confirmed`, `not_signed_in`, `host_not_allowed`, `method_not_allowed`,
  `invalid_request` (a broken `request`), `http_error` (message names the status),
  `network_error`, `timeout`, `handler_failed`, `result_too_large`.
- A 401 from the customer API: in callbacks mode call `onUnauthorized` once and retry once;
  still 401 → `not_signed_in`. In `client` mode the app's interceptors already refreshed, so
  a 401 is `not_signed_in` at once.
- `mount_component`: in-app builder → the event's `surface` (or `route`) → nothing (logged).
  `inline` draws in the chat; `sheet` opens a bottom sheet; `route` closes the chat sheet and
  calls `openRoute` with the event's `route` exactly as sent (the server filled and escaped it).
  See `docs/DYNAMIC_CARDS.md`.
- `audio`: queued and played in `seq` order; a new question or closing the chat stops it.
- `suggestions` and `GET /v1/suggestions` show as chips; a tap sends the text.
- Errors follow the doc's table: token errors retry once with a new user token (none without
  one); conversation
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

Backend work (built on the backend's `feat/proxy-sdk` branch, not deployed yet), the
analyzer, the console editor, the history screen, deleting the old engine, TCM's migration.

## Done means

- Unit and widget tests for each new piece pass (`flutter test`), and `flutter analyze` is clean.
- A mock server (`dart run zehn_intelligence:mock_server [--app file.json]`) plays the backend:
  `/v1/config`, scripted turns with inline requests, cards, routes and confirm cards, action
  turns, and a fake customer API; an example app on the iOS simulator asks a
  question, the SDK calls the fake customer API, and a console-made card is drawn.
