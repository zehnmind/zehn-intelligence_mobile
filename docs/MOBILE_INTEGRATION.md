# Zehn Intelligence: Mobile SDK API

What the SDK calls on our backend and how to handle each answer.
Updated 2026-11-06, from the backend's `main` branch.

## The basics

- The SDK talks to **one server**: `zi_console_url` from the config file. All paths are under `/v1`.
  - Prod: `https://zi-console-api.zehnmind.com`
  - Local: `http://10.0.2.2:8040` from the Android emulator
- Chat, voice (speech to text and text to speech), history and suggestions **all go through this server**.
- **The SDK never calls zehn/api (`api.zehnmind.com`) itself.**
  - The app key is not a zehn/api key, so zehn/api answers `401`.
  - Our server runs the model, the app's tools, the limits, the history and the usage records. A direct call skips all of them.
- **No `zi_server_` key in the app, ever.** Only the customer's backend holds it.

## Config file

The developer downloads `zehn-intelligence.<test|prod>.json` from the console and builds with
`--dart-define-from-file=...`. There is no endpoint to fetch it at run time.

| Field | Example | Used for |
|---|---|---|
| `zi_console_url` | `https://zi-console-api.zehnmind.com` | Base URL of every call |
| `zi_app_key` | `zi_test_` + 48 hex | Header `X-ZI-App-Key` |
| `zi_package_name` / `zi_bundle_id` | `com.example.app` | Header `X-ZI-Package` (Android / iOS) |
| `zi_spec_version` | `1.2.0` | Header `X-ZI-Spec-Version` |
| `zi_services` | `llm,stt,tts` | `stt`: show the mic. `tts`: offer spoken answers. |
| `zi_languages` | `uz,ru,en` | Languages the assistant supports |
| `zi_app_id`, `zi_track`, `zi_config_format` | | Informational |

## Auth: the user token

```
App → customer's backend → POST /v1/user-tokens (zi_server_ key) → JWT → App
```

The customer's backend calls this, not the SDK:

```http
POST /v1/user-tokens
Authorization: Bearer zi_server_...

{ "external_user_id": "usr_42", "claims": { "language": "uz" } }
```

```json
{ "token": "eyJ...", "token_type": "Bearer", "expires_at": "2026-11-06T15:00:00Z", "expires_in": 3600 }
```

- The token is valid for 1 hour.
- On `401 user_token_expired`, the SDK asks the app for a new token (`onTokenExpired()`) and retries the same request **once**.

## Headers on every SDK call

```
Authorization:      Bearer <user token>
X-ZI-App-Key:       zi_test_...         (zi_app_key)
X-ZI-Package:       com.example.app     (package name on Android, bundle id on iOS; exact match)
X-ZI-App-Version:   1.2.0+5
X-ZI-Spec-Version:  1.2.0               (zi_spec_version)
X-ZI-SDK-Version:   0.3.0
X-ZI-Platform:      android | ios
```

Every call is checked against these headers first, including history and suggestions.

## Endpoints

| Call | What it does |
|---|---|
| `POST /v1/turns` | Send a question, typed or spoken. The answer comes back as an SSE stream. |
| `POST /v1/turns/{turn_id}/tool-results` | Send the results of the app's tools. The answer continues as a new SSE stream. |
| `GET /v1/conversations?page=1&size=20` | The user's past chats, latest first. `size` is at most 50. |
| `GET /v1/conversations/{id}` | One chat, as it was shown: messages and widgets. |
| `DELETE /v1/conversations/{id}` | Delete a chat. Answers `204`. |
| `GET /v1/suggestions?language=uz` | Starter questions for an empty chat, at most 4. |

## 1. Ask a question: `POST /v1/turns`

Typed:

```json
{
  "conversation_id": null,
  "input": { "type": "text", "text": "find me a city tour" },
  "language": "uz",
  "utc_offset_minutes": 300,
  "voice_reply": false
}
```

Spoken:

```json
{
  "conversation_id": "6f1c...",
  "input": { "type": "audio", "format": "m4a", "data": "<base64>" },
  "language": "uz",
  "utc_offset_minutes": 300,
  "voice_reply": true
}
```

| Field | Rules |
|---|---|
| `conversation_id` | Required. `null` starts a new chat. Otherwise send the id from `turn.started`. |
| `input.text` | 1 to 4000 characters, after trimming. |
| `input.format` | `m4a` (recommended: AAC on both platforms), `aac`, `mp3`, `wav`, `ogg`, `opus`, `webm` or `flac`. |
| `input.data` | The whole recording, base64. At most 1 MiB decoded, about a minute of AAC at 64 kbit/s. |
| `language` | The app's current UI language: `uz`, `ru`, `en`... |
| `utc_offset_minutes` | The phone's offset from UTC. Tashkent is `300`. Optional. |
| `voice_reply` | `true` speaks the answer (`audio` events). It stays on for the whole turn: no need to send it again with tool results. |

The answer is `200 text/event-stream`, with the header `X-ZI-Turn-Id`.

## 2. Send tool results: `POST /v1/turns/{turn_id}/tool-results`

When the model needs the app's data, the stream sends `client_api_request` events, then pauses (`turn.paused`).
The SDK runs the handlers and posts **all results of that round in one request**:

```json
{
  "results": [
    { "call_id": "c_1", "ok": true, "data": { "tours": [ ... ] } },
    { "call_id": "c_2", "ok": false, "error": { "code": "not_signed_in", "message": "Ask the user to sign in" } }
  ]
}
```

- `data` can be any JSON, up to 32 KB.
- `error.code` is `^[a-z][a-z0-9_]{0,63}$`. `message` is at most 500 characters. The model reads it, so never put secrets there.
- Send the results before the deadline: 60 s, given in `turn.paused`.
- Retry only if there was **no HTTP status** at all (a network failure): once, after 1 s, and only while the deadline hasn't passed.
- The answer is a new SSE stream for the same turn.

Error codes the SDK sets itself:

| Code | When |
|---|---|
| `handler_not_registered` | The app has no handler for this tool |
| `invalid_args` | The arguments are wrong |
| `handler_failed` | The handler threw an error |
| `timeout` | The handler didn't finish in time |
| `result_too_large` | The result is over 32 KB |

The app can also throw its own code, e.g. `ZiToolError('not_signed_in', 'Ask the user to sign in')`.

## 3. The SSE stream

Each event:

```
event: text.delta
id: 3
data: {"turn_id":"7b2e...","seq":3,"text":"Here are some"}

```

- Every `data` has `turn_id` and `seq`. `seq` keeps counting across the legs of one turn.
- `: ping` is sent every 15 s while the server is quiet. If nothing arrives for 45 s, treat the stream as dropped.
- **Each stream ends with exactly one of `turn.paused`, `done` or `error`.**
- **Ignore any event type the SDK doesn't know.** Ignore unknown fields too.

| Event | Fields | What the SDK does |
|---|---|---|
| `turn.started` | `conversation_id`, `conversation_new` | Always first. Save `conversation_id` for the next question. |
| `transcript` | `text`, `language` | Spoken question only. This is what we heard: show it as the user's bubble. |
| `text.delta` | `text` | Append to the assistant's bubble. The text can contain **Markdown**: render it. |
| `client_api_request` | `call_id`, `tool`, `args` | Run the registered handler for `tool`. |
| `mount_component` | `call_id`, `component`, `kind`, `props` | Show the registered widget. `kind`: `inline` (in the chat), `sheet` (bottom sheet) or `route` (a full screen: close the chat sheet first). |
| `audio` | `format`, `text`, `data` | `voice_reply` only. One clip of the spoken answer, base64 (`mp3`). Queue the clips and play them in `seq` order. |
| `suggestions` | `items` | Up to 3 follow-up questions, sent just before `done`. Show them as chips. A tap sends the chip as a typed question. |
| `turn.paused` | `call_ids`, `deadline`, `expires_in`, `max_result_bytes` | Ends this stream. Post the results of `call_ids` (section 2). |
| `done` | `outcome` | Ends the turn. `outcome` is `answered`, `refused` or `limit` (the round limit was hit). |
| `error` | `error {code, i18n_key, params, message}`, `retryable` | Ends the turn. Nothing of it is saved. Show the error, with "try again" only if `retryable`. |

A turn with one round of tools:

```
SDK                                            Server
 POST /v1/turns ─────────────────────────────▶
 ◀─ turn.started   (save conversation_id)
 ◀─ transcript     (spoken question only)
 ◀─ text.delta "Looking..."
 ◀─ client_api_request  tours.search
 ◀─ turn.paused    (stream ends)
 run tours.search
 POST /v1/turns/{turn_id}/tool-results ──────▶
 ◀─ text.delta "Found 3 tours..."
 ◀─ audio …        (voice_reply only)
 ◀─ mount_component  TourCard, inline
 ◀─ suggestions    ["Cheaper ones?", ...]
 ◀─ done           answered
```

## 4. Voice

- **Show the mic only if `zi_services` has `stt`.** Offer spoken answers only if it has `tts`.
  Otherwise the server answers `400 service_not_enabled`, with `params.service` set to `stt` or `tts`.
- Record AAC in `.m4a` and send the whole recording in one request. There is no streaming upload.
- The server transcribes the recording before anything else and sends `transcript`. The turn then continues as if the user had typed that text.
- The text is always complete, even if a clip fails. When a clip fails, the rest of the answer comes without audio.
- When the user sends a new question or closes the chat, stop playback and clear the clip queue.

Voice errors (in the `error` event):

| Code | Meaning | Show |
|---|---|---|
| `speech_not_recognized` | Nothing heard: silence, noise, or too short | "I didn't catch that, try again" |
| `speech_unavailable` | The speech service failed | "Voice is not available, try again", or type |

## 5. History

`GET /v1/conversations`:

```json
{
  "items": [
    {
      "conversation_id": "6f1c...",
      "title": "find me a city tour",
      "created_at": "2026-11-06T09:12:03Z",
      "last_turn_at": "2026-11-06T09:14:40Z",
      "spec_version": "1.2.0",
      "can_continue": true
    }
  ],
  "total": 7, "page": 1, "size": 20
}
```

`GET /v1/conversations/{id}` returns the same fields plus `messages`, in order:

```json
[
  { "role": "user", "type": "text", "text": "find me a city tour", "spoken": true, "turn_id": "...", "at": "..." },
  { "role": "assistant", "type": "text", "text": "Here are three tours...", "turn_id": "...", "at": "..." },
  { "role": "assistant", "type": "component", "component": "TourCard", "kind": "inline", "props": { ... }, "turn_id": "...", "at": "..." }
]
```

- `title` is the first question, cut to 80 characters.
- Fields that don't apply to a message are `null`.
- `spoken: true` means the user said it; `text` is what was heard.
- Tool calls and results are not in the history, only what the user saw.
- When loading history, render `inline` widgets, but **don't open `sheet` or `route` widgets on their own**.
- `can_continue: false` means the chat started on another spec version, or is full. Show it read-only, and send the next question with `conversation_id: null`.
- Only the user's own chats are listed. Another user's id answers `404 conversation_not_found`.
- `DELETE` answers `409 turn_in_progress` while a turn is still running in that chat.

## 6. Suggestions

- **Empty chat:** `GET /v1/suggestions?language=uz` returns `{ "suggestions": ["...", "..."] }`, at most 4. Show them as chips.
- **After an answer:** the `suggestions` event, up to 3, only when the answer finished normally. It may not come: it is best effort, and the console can switch it off.
- A tap on a chip sends its text as a normal typed question.

## 7. Errors

Before the stream starts, an error is a JSON body with an HTTP status. After the stream starts, it is an `error` event. The body is the same in both cases:

```json
{ "code": "user_token_expired", "i18n_key": "errors.user_token_expired", "params": {}, "message": "..." }
```

**Switch on `code`, never on `message`.** Any `422` (a malformed body) counts as `invalid_request`.

| Code | Status | What the SDK does |
|---|---|---|
| `user_token_expired` | 401 | Get a new token, retry once |
| `user_token_required` | 401 | No token, or a bad one. Get a token once, retry once. If it fails again: "sign in again". |
| `invalid_header`, `invalid_key`, `app_mismatch`, `spec_not_found` | 400 / 401 / 404 | Setup error: wrong config or build |
| `sdk_too_old` | 426 | "Update the app" (`params.min_version`) |
| `key_revoked` | 401 | "Update the app" |
| `app_disabled` | 403 | "The assistant is not available right now" |
| `service_not_enabled` | 400 | The mic or voice reply is not switched on for this app. Hide it. |
| `conversation_not_found`, `conversation_spec_changed`, `conversation_full` | 404 / 409 | Resend once with `conversation_id: null`. For `conversation_full`, also note "starting a new chat". |
| `turn_in_progress` | 409 | A turn is already running. Never send two at once. |
| `turn_expired` | 409 or event | The results came too late. "That took too long, ask again." |
| `turn_not_paused` | 409 | The results were already taken (a retry after a network drop). End the turn as `stream_interrupted`. |
| `turn_not_found`, `invalid_tool_results` | 404 / 400 | SDK bug: unknown or repeated `call_id` |
| `payload_too_large` | 413 | The body is too big (`params.max_bytes`) |
| `llm_unavailable` | 502 or event | "The assistant is not available." Offer "try again" only if `retryable` is true. |
| `speech_not_recognized`, `speech_unavailable` | event | See section 4 |
| `internal_error` | 500 or event | Generic error, retryable |

For a code the SDK doesn't know: a 4xx is not retryable, a 5xx is retryable.

Codes the SDK sets itself:

| Code | When |
|---|---|
| `network_error` | No HTTP status at all |
| `server_unavailable` | Not JSON, or not an event stream (e.g. a proxy page) |
| `stream_interrupted` | The stream closed before its last event, or 45 s with no ping |
| `invalid_response` | A known event with a broken body |

## Limits

| What | Value |
|---|---|
| User token | 1 hour |
| Typed question | 4000 characters |
| Recording | 1 MiB decoded (about 1 min of AAC). The whole body is at most 1.5 MiB. |
| Tool result | 32 KB each. The whole request is at most 1 MB. |
| Deadline for tool results | 60 s |
| Rounds per turn | 8 |
| Tool calls per round | 8 |
| Turns running at once | 1 per conversation |
| History page size | 50 |

## Not built yet

These features don't exist yet, but the SDK should tolerate them when they come:

- Resuming a dropped stream (`Last-Event-ID`) and cancelling a turn. Until then, a dropped stream is a retryable error and the user asks again.
- Quotas and rate limits: `429 quota_exceeded` and `429 user_rate_limited`, with `Retry-After`.
- Blocking an app version (`403 version_disabled`) or a user (`403 user_blocked`).
- Preflight (the SDK reports its registered handlers) and a telemetry endpoint.

## Local testing without a customer backend

The backend repo has a fake customer backend that gives out user tokens:

```bash
ZI_SERVER_KEY=zi_server_... uv run scripts/demo_customer_backend.py
```

It runs on port 8042. From the Android emulator it is at `http://10.0.2.2:8042`.

```
POST /demo/login   { "user_id": "usr_1", "track": "test" }   →   { "token": "eyJ...", "expires_at": "..." }
```
