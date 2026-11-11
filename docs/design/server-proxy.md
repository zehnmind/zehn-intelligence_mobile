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
- **History.** The landing's history button opens the user's conversations
  (`GET /v1/conversations`, 20 a page, latest first). Tap one to reopen it as the chat showed
  it (`GET /v1/conversations/{id}`): text, `inline` cards and confirm cards with their status.
  A `sheet` or `route` was opened, not shown, so it is left out and never opened again. One with
  `can_continue: true` takes the next question with its `conversation_id`; one with `false` is
  read-only, with a note and a "New chat" button where the input was, and its unanswered
  confirm cards show as expired. Swipe left to delete (`DELETE`); a refusal keeps the row and
  says so. History is per install, so `clearUser()` (sign-out) makes a new install id and the
  next person on the phone sees none of it.
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
  nothing from the console on the phone but the install id and the last good config (see
  [Where the button shows](#where-the-button-shows-button)). It throws `ZiConfigException`
  only when there is no app key.
- `ZehnAiButton` opens the new chat sheet. It is hidden while the console answers
  `404 spec_not_found` (nothing published yet). The SDK's own floating button (`start`) also
  follows `button` of the config.
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
  "assistant_name": "Mall guide",
  "app_name": "Tashkent City Mall",
  "languages": ["uz", "ru", "en"],
  "default_language": "uz",
  "theme": { "font": "CeraPro", "colors": {}, "text": {}, "radius": {} },
  "copy": {
    "welcome_title": { "uz": "Qanday yordam bera olaman?", "en": "How can I help you?" },
    "welcome_subtitle": "Find stores, restaurants, offers and more."
  },
  "button": { "show_on": "except", "paths": ["/", "/auth", "/signin"] }
}
```

- `assistant_name` is the chat's title (an app's own `openChat(title:)` wins).
- `copy.welcome_*` is one string or a language map: the user's language, else
  `default_language`, else `en`, else the first.
- The language the SDK uses: the app's `setLanguage`, else the phone's if listed in
  `languages`, else `default_language`, else the first listed.
- `404 spec_not_found`: nothing is published; `ZehnAiButton` hides and `openChat` does
  nothing, and the kept config is deleted. Any other failure keeps the last settings (the kept
  config, or the SDK's defaults at first).
- No spec version either way: the server picks it. The SDK never sends `X-ZI-Spec-Version`,
  which would make the server treat the build as one that pins a spec (no cards, no writes).

`GET /v1/suggestions` gives only the starter chips.

### Where the button shows: `button`

`button` says on which screens the SDK's own floating button shows. The server always sends it
(an app published before it existed gets `all`).

| `show_on` | The button shows |
|---|---|
| `all` | on every screen (`paths` is `[]`) |
| `only` | only on the screens in `paths` |
| `except` | on every screen except those in `paths` |

A path is the app's route as its router writes it: `/`, `/auth`, `/movies/:id`, `/orders/{id}`.
A publish hides the button on the screens before sign-in the analysis found (splash, onboarding,
sign-in, OTP, password reset, PIN); the developer changes it in the console ("Where the button
shows").

- **Reading.** A missing or unknown `show_on` counts as `all`; so does `only` or `except` with no
  path (the server never sends that), so a broken rule can't hide the button everywhere.
- **The open screen** is followed at every change, with no code in the app and no dependency on
  its router package:
  - An app with a `Router` (`MaterialApp.router`: go_router, auto_route, beamer): the location the
    router reports to its `routeInformationProvider`. A go_router `push` counts: the screen on top
    is read from the `imperativeMatches` of the state it reports.
  - An app with the Navigator's named routes (and GetX): the name of the top route.
  - A sheet or a dialog over a screen keeps that screen's path.
  - A screen pushed as a widget with no name is not known: the button **shows**.
- **Matching** is segment by segment. A `:name` or `{name}` segment matches any one segment. The
  query, a fragment and a trailing slash are left out. `/` matches only `/`.

  | Open screen | Path in `paths` | Match |
  |---|---|---|
  | `/movies/42?day=1` | `/movies/:id` | yes |
  | `/orders/7/` | `/orders/{id}` | yes |
  | `/movies` | `/movies/:id` | no |
  | `/home` | `/` | no |

- **While the chat is open** the button stays hidden.

### The kept config

Without a kept config the button would flash on the splash at every start and show on the login
screen when the phone is offline. So the SDK keeps the last good config in a file (`ZiFileStore`,
like the install id), tied to the console URL and a fingerprint of the app key (another key, the
test one then the production one, never reads it; the key itself isn't written).

- **Start:** the kept config is used at once; the fresh one replaces it in the background.
- **No kept config** (a first start, a reinstall): the button stays hidden until a config
  arrives. Without our server the chat can't answer anyway.
- **The config can't load** (offline, a 5xx, a bad body): the kept one stays. It is asked for
  again when the app comes back to the foreground, not only when the chat opens: with the button
  hidden, the chat can't open.
- **`404 spec_not_found`:** the button hides and the kept config is deleted.

## Install id: `X-ZI-Install-Id`

The SDK makes a random id once (16 bytes, 32 hex characters), keeps it in its support folder
(an id an older SDK saved is kept), and sends it on every console call. With no `userToken`
there is no `Authorization` header. A token error with no user token is not retried. There is no
`/v1/installs`.

### A sign-out is noticed from the app's Dio

History is per install, so the next person on the phone must not keep the last one's install id.
`start(dio:)` adds **one interceptor at the end of the app's Dio** (`ZiSignOutWatch`). It never
changes or stops the app's requests: it sees each one with the `Authorization` the app's own
interceptors set.

- **Who a request is for:** no `Authorization`, nobody; a JWT, its user claim (`sub`, `user_id`,
  `uid` or `id`, read without checking the signature, so a refreshed token is the same person);
  any other token, the token itself. Only a SHA-256 fingerprint is kept, in memory and in a file
  (`user.json`), so a change between two launches is noticed too.
- **A sign-out** is somebody, then somebody else, or then nobody. It makes a new install id at
  once, stops the running turn, and empties the chat; the history is the new install's, so
  empty.
- **The check:** before the chat opens, the SDK sends a request through the Dio that its own
  interceptor answers itself (`204`): the app's interceptors add their header, nothing leaves
  the phone. It waits at most 3 s (an interceptor may refresh a token first) and never blocks the
  chat. If an interceptor was added after ours, the check moves ours to the end first.
- **"Nobody" is decided by the check alone.** A request of the app's own with no `Authorization`
  says nothing: apps send public requests (a catalog, a splash config) while somebody is signed
  in. So a sign-out with nobody signing in after it is noticed when the chat next opens, which
  is the first time it could matter. Somebody else signing in is noticed at their first request.
- **A caveat:** a token that is not a JWT is the person itself, as the contract says, so an app
  whose access token is opaque and changes on refresh looks like a new person at each refresh.
  JWTs are fine.

`ZehnIntelligence.signedOut()` and `clearUser()` still do the same at once, for an app that wants
to say so itself.

## A turn

As `MOBILE_INTEGRATION.md`, with these SDK specifics:

- Headers on every call: `Authorization: Bearer <user token>` (only with one), `X-ZI-App-Key`,
  `X-ZI-Package` (Android package name / iOS bundle id), `X-ZI-App-Version`,
  `X-ZI-SDK-Version`, `X-ZI-Platform`, `X-ZI-Install-Id`. Never `X-ZI-Spec-Version`.
- One turn at a time. `turn.started` gives the `conversation_id` for the next question.
- `client_api_request`: when the round's stream ends with `turn.paused`, the SDK runs all
  its calls at once, each through: in-app handler → the call's `request` → error
  `handler_not_registered`. Each call has the pause's `expires_in − 5 s` (at least one second;
  60 s unless the event says otherwise), and a result over the pause's `max_result_bytes` (32 KB
  unless it says otherwise) becomes `result_too_large`. All results go in one `tool-results`
  request.
- `confirm`: one card, the template with Cancel and Confirm inside its frame (section above);
  writes wait for it. In-app handlers never ask.
- Proxy errors the model reads: `not_confirmed`, `host_not_allowed`, `method_not_allowed`,
  `invalid_request` (a broken `request`), `timeout`, `result_too_large`, and for what the app's
  server answered (`docs/sdk.md` §5.1): `not_signed_in` (401, 403), `not_found` (404),
  `handler_failed` (another 4xx with its short `message` or `detail`; a 5xx with only its
  status; no answer; a body that is not JSON).
- The SDK's requests carry `options.extra['zi'] = true`; the app's interceptors still run.
- A 401 from the customer API: in callbacks mode call `onUnauthorized` once and retry once;
  still 401 → `not_signed_in`. In `client` mode the app's interceptors already refreshed, so
  a 401 is `not_signed_in` at once.
- `mount_component`: in-app builder → the event's `surface` (or `route`) → nothing (logged).
  `inline` draws in the chat; `sheet` opens a bottom sheet; `route` closes the chat sheet and
  calls `openRoute` with the event's `route` exactly as sent (the server filled and escaped it).
  See `docs/DYNAMIC_CARDS.md`.
- `audio`: every answer is spoken. Clips are queued and played in `seq` order; a new question
  or closing the chat stops them (the rest of that answer stays quiet). Each turn's clips are
  kept in memory, for the last 20 answers, so a speaker under the turn's last text part plays
  it again (a tap while it plays stops it). They are dropped on New chat, on opening another
  conversation, and on `clearUser()`; nothing is written to disk or asked of the server. An
  answer with no clips held (from the history, or whose speech failed) has no speaker.
- `suggestions` and `GET /v1/suggestions` show as chips; a tap sends the text.
- Errors follow the doc's table: token errors retry once with a new user token (none without
  one); conversation
  errors (`conversation_not_found`, `conversation_spec_changed`, `conversation_full`) resend
  once with `conversation_id: null`; `stream_interrupted` after 45 s without a ping; others are
  shown, with "try again" only when retryable.
- Voice: the mic is always shown. Recordings are AAC in `.m4a`, sent whole, at most 1 MiB.

## Components

The spike's renderer moves into the SDK with two fixes:

- Action `args` are resolved one value at a time, so an argument named `path` is not taken as
  a data path (the spike's bug).
- Allowed actions are `open_route {route}`, `ask {text}` and `open_url {url}` (`https`,
  `tel`, `mailto` only). Anything else is ignored and logged.

Catalog `zehn.basic.v0`: `Box`, `Column`, `Row` (with `scroll`), `Image`, `Text`, `Chip`,
`Header`, `InfoRow`, `Button` (`primary`/`secondary`), `Divider`. Values are literals,
`{"path": "/a/b"}` (relative paths read the current list item), language maps
`{"uz": …, "ru": …, "en": …}`, and strings with `{/a/b}` placeholders; a path can name a
format (`{/a|time}`, `{"path": "/a", "format": "money:UZS"}`; `docs/DYNAMIC_CARDS.md` §6.2).
`catalog/zehn.basic.json` lists what this build draws, for the analyzer. A component the
catalog lacks draws nothing in release builds and a red note in debug builds. The theme's
`font` names a font family the app already ships; nothing is downloaded.

## Not in this change

Backend work (built on the backend's `feat/proxy-sdk` branch, not deployed yet), the
analyzer, the console editor, deleting the old engine, TCM's migration.

## Done means

- Unit and widget tests for each new piece pass (`flutter test`), and `flutter analyze` is clean.
- A mock server (`dart run zehn_intelligence:mock_server [--app file.json]`) plays the backend:
  `/v1/config`, scripted turns with inline requests, cards, routes and confirm cards, action
  turns, and a fake customer API; an example app on the iOS simulator asks a
  question, the SDK calls the fake customer API, and a console-made card is drawn.
