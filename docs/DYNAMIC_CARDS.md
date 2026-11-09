# Dynamic cards: guide for backend developers

How the console defines the cards the assistant shows in a customer's app, and what the
backend must store, validate and send so the mobile SDK can draw them.

Matches SDK `0.4.0` (`zehn_intelligence`, `main`). Related documents:

- `docs/MOBILE_INTEGRATION.md`: the turn protocol (`/v1/turns`, SSE events, tool results).
- `docs/design/server-proxy.md`: the full SDK design (tool requests, chat settings).

---

## 1. In one minute

A **dynamic card** is a small piece of UI (a cinema card, a parking card, a store card) that the
assistant shows inside the chat. The customer app has **no code** for it:

1. In the console, someone defines a card **template**: plain JSON that says "an image, then a
   title, then two chips, then a button".
2. During a conversation, when the assistant wants to show a card, the backend sends a
   `mount_component` event with the card's **name**, its **data** (usually a tool result) and
   its **template**.
3. The SDK fills the template with the data and draws it with real native widgets, in the app's
   colours and font. The theme (colours, font) comes with the chat's starter suggestions
   (`GET /v1/suggestions`), each time the chat opens.

```
Console ──(templates, theme)──► Backend (stores and caches them)
                                   │
   chat opens ───────────────────► │ ──GET /v1/suggestions → {suggestions, chat: {theme, …}}──► SDK
   model wants a card ───────────► │ ──SSE: mount_component {component, props, surface}──► SDK draws it
```

The phone keeps no templates: a card published in the console works on the next message, with no
app release and no cache to refresh.

Templates never contain code. The SDK has a fixed list of building blocks (the **catalog**); a
template can only arrange those blocks and point them at data. Anything the SDK does not know is
simply not drawn.

---

## 2. Vocabulary

| Word | Meaning |
|---|---|
| **Component** | A card the console defines, identified by a `name` such as `cinema_details`. |
| **Kind** | How a component is shown: `inline` (in the chat), `sheet` (a bottom sheet over the chat), or `route` (open a screen of the app). |
| **Surface** | The JSON template of an `inline` or `sheet` component. Its shape is borrowed from Google's open A2UI format. |
| **Block** | One element inside a surface: `Text`, `Image`, `Button`, and so on (see section 7). |
| **Props / data** | The JSON the card shows, sent in `mount_component.props`. |
| **Theme** | Colours, text sizes, corner radii and font name, shared by all cards of an app. |

---

## 3. What the backend stores

Per app (and per published spec version, like tools today):

| Item | Type | Notes |
|---|---|---|
| Components | map `name → definition` | Definition = `kind` plus either `surface` (inline/sheet) or `route` (route). |
| Theme | JSON object | Section 9. One per app. |
| Welcome copy | per-language strings | Optional, shown on the chat's first screen (section 10). |

The backend sends these to the phone as they are needed (sections 4 and 5); it can cache them as
it likes.

A component name should match `^[a-z][a-z0-9_]{1,47}$`, the same style as tool names.

**Recommended:** link each component to the tool whose result it shows (for example
`cinema_details` ← `cinemas.list`). The SDK does not need this link, but the backend and the
model do, to know which data to put in `props`.

---

## 4. Showing a card: the `mount_component` event

Sent in the turn's SSE stream (`MOBILE_INTEGRATION.md`), with the template inline:

```
event: mount_component
data: {"turn_id":"7b2e…","seq":9,"call_id":"m_1","component":"cinema_details","kind":"inline","props":{ …data… },"surface":{"createSurface":{ …section 6… }}}
```

```
event: mount_component
data: {"turn_id":"7b2e…","seq":10,"call_id":"m_2","component":"venue_page","kind":"route","props":{"id":"a1"},"route":"/venues/{id}"}
```

| Field | Rule |
|---|---|
| `component` | The component's name. The SDK uses it only to find an app widget with that name (below). |
| `kind` | `inline`, `sheet` or `route`; anything else counts as `inline`. |
| `props` | The data the template reads (section 6.2). Any JSON object. |
| `surface` | `inline` and `sheet`: the component's template (section 6). |
| `route` | `route`: an app route (a path the app's router understands, starting with `/`), not a URL. `{name}` placeholders are filled from the props, URL-encoded: `/venues/{id}` with `props: {"id": "a1"}` opens `/venues/a1`. |
| `call_id` | Any unique string; history uses it. |

What the SDK does:

| `kind` | Result |
|---|---|
| `inline` | Draws the surface in the chat, under the assistant's text. |
| `sheet` | Opens a bottom sheet over the chat with the surface. |
| `route` | Closes the chat and asks the app to open the route. |

An `inline` or `sheet` event without a `surface`, or a `route` event without a `route`, shows
nothing (unless the app has its own widget, below).

**Where `props` come from.** Normally from the tool result the phone just posted to
`/v1/turns/{id}/tool-results`: the server already has that JSON. Send it, or a subset of it, as
`props`. Keep `props` under **32 KB**, the same limit as tool results.

**The app can override a card.** If the app registered its own Flutter widget under the same name
(`ZehnIntelligence.registerComponent`), the SDK draws the app's widget instead of the template.
The backend does not need to know; it sends the same event.

---

## 5. Theme and welcome text: `GET /v1/suggestions`

The SDK asks for starter suggestions each time the chat opens empty. The same answer carries the
chat's settings in a `chat` field:

```json
{
  "suggestions": ["Kinoteatr haqida aytib ber", "Kartamda nechta ball bor?"],
  "chat": {
    "theme": { "...": "see section 9" },
    "welcome_title": "Qanday yordam bera olaman?",
    "welcome_subtitle": "Do‘konlar, restoranlar, aksiyalar va boshqalar.",
    "services": ["llm", "stt", "tts"],
    "languages": ["uz", "ru", "en"],
    "default_language": "uz",
    "spec_version": "1.0.3"
  }
}
```

| Field | Meaning |
|---|---|
| `theme` | Section 9. Used by the chat and by every card. |
| `welcome_title`, `welcome_subtitle` | The chat's first screen, already in the `language` of the request (section 10). |
| `services` | `stt` shows the mic, `tts` asks for spoken replies. |
| `languages`, `default_language` | Which languages the assistant speaks; the SDK picks the phone's language if it is listed, else the default. |
| `spec_version` | Optional; the SDK sends it back as `X-ZI-Spec-Version`. |

Every field is optional: a missing one uses the SDK's own default (no mic, the SDK's colours and
words). A `chat` field that is missing altogether keeps the settings the SDK already has.

---

## 6. The template format (the surface)

### 6.1 Shape

```json
{
  "createSurface": {
    "surfaceId": "cinema_details",
    "catalogId": "zehn.basic.v0",
    "root": "root",
    "components": [
      { "id": "root",  "component": "Box",    "color": "surface", "radius": "card", "padding": 16, "child": "body" },
      { "id": "body",  "component": "Column", "gap": 12, "children": ["title", "hours"] },
      { "id": "title", "component": "Text",   "style": "display", "text": { "path": "/name" } },
      { "id": "hours", "component": "Text",   "style": "body",    "text": { "path": "/working_hours" } }
    ]
  }
}
```

- `components` is a **flat list**. Blocks point to each other by `id` (`child`, `children`), so
  there is no nesting in the JSON itself.
- Every block needs a unique string `id` and a `component` (the block type, section 7).
- `root` is the id of the outermost block (default `"root"`). It must exist.
- `catalogId` is always `"zehn.basic.v0"` for now. `surfaceId` is informational.
- Blocks can be nested at most 32 levels deep.
- Unknown keys are ignored, so you can add notes such as `"_note"`.

### 6.2 Values: literals, data paths, languages

Every property that shows something (`text`, `label`, `title`, `src`, action arguments, `visible`)
accepts one of these forms:

| Form | Example | Meaning |
|---|---|---|
| Literal | `"Buy ticket"`, `16`, `true` | Shown as is. |
| Data path | `{ "path": "/cinema/name" }` | Reads `props.cinema.name`. Paths use `/`; list items by index: `/movies/0/title`. |
| Language map | `{ "uz": "Chipta", "ru": "Билет", "en": "Ticket" }` | Picks the user's language, then `en`, then the first value. Keys may only be `uz`, `ru`, `en`. |
| Placeholder string | `"Floor {/floor}"` | `{…}` is replaced by the value at that path. No spaces inside the braces. |
| Language map with placeholders | `{ "uz": "{/floor}-qavat", "en": "Floor {/floor}" }` | Both together. |

**Localized data is picked automatically.** If a path points at an object whose keys are only
`uz`/`ru`/`en` (such as `"description": {"uz": "…", "ru": "…", "en": "…"}` from the customer's
API), the SDK shows the user's language. You don't need to pre-select it on the server.

A path that leads nowhere shows as empty text, not an error.

### 6.3 Lists: repeating a block

`children` can be a list of ids **or** a template that repeats over a list in the data:

```json
{ "id": "movies", "component": "Row", "scroll": true, "gap": 10,
  "children": { "componentId": "movie_card", "path": "/movies" } },
{ "id": "movie_card", "component": "Column", "width": 136, "gap": 6, "children": ["poster", "title"] },
{ "id": "poster", "component": "Image", "src": { "path": "image" }, "height": 196, "radius": "image" },
{ "id": "title",  "component": "Text",  "style": "title", "text": { "path": "title" } }
```

Inside the repeated block, paths **without** a leading `/` (`"image"`, `"title"`) read the current
list item. Paths with `/` still read from the top of `props`.

### 6.4 Hiding a block: `visible`

```json
{ "id": "category", "component": "Chip", "text": { "path": "/category_name" }, "visible": { "path": "/category_name" } }
```

The block is skipped when `visible` resolves to `null`, `false` or `""`. Use it for optional data.

---

## 7. Block catalog (`zehn.basic.v0`)

Properties every block accepts:

| Property | Type | Meaning |
|---|---|---|
| `id` | string | Required, unique. |
| `component` | string | Required, one of the blocks below. |
| `visible` | value | Section 6.4. |
| `width`, `height` | number | Fixed size in logical pixels. |
| `flex` | number | Shares the free width with sibling blocks. **Use only on children of a non-scrolling `Row`.** |
| `action` | object | Makes the block tappable (section 8). `Header`, `InfoRow` and `Button` show their own tap feedback. |

The blocks:

| Block | Properties | Draws |
|---|---|---|
| `Box` | `child` (id), `color` (colour), `radius` (radius), `padding` (number), `border` (colour) | A container. Use it as the card's root, with `color: "surface"`. |
| `Column` | `children`, `gap` (number), `align` (`start`·`center`·`end`·`stretch`, default `start`) | Blocks stacked top to bottom. |
| `Row` | `children`, `gap`, `align` (default `center`; `start` when scrolling), `scroll` (bool) | Blocks left to right. `scroll: true` scrolls sideways (carousels). |
| `Image` | `src` (value: an `https://` URL; `http://` also loads but avoid it), `width`, `height`, `radius` | A network image, cropped to fill. Full width unless `width` is set. Any other scheme shows a placeholder icon. |
| `Text` | `text` (value), `style` (text style), `color` (colour, default `on_surface`), `maxLines` (number) | Text. Cut with "…" after `maxLines`. |
| `Chip` | `text`, `icon`, `color` (background, default `chip`) | A small rounded label (floor, rating, category). |
| `Header` | `title`, `icon`, `action` | A section title with an icon tile; a chevron when it has an action. |
| `InfoRow` | `text`, `icon`, `action` | An icon and a line of text with a divider under it (hours, phone, website); a chevron when it has an action. |
| `Button` | `label`, `icon`, `variant` (`primary` default, or `secondary`), `action` | A full-width 50px button. Primary uses `accent`, secondary uses `chip`. |
| `Divider` | — | A 1px line in `border` colour. |

**Icons** (`icon`) are a fixed list: `theaters`, `layers`, `schedule`, `phone`, `language`,
`movie`, `ticket`, `map`, `parking`, `star`, `info`. With an unknown name, `Header` and `InfoRow`
show a neutral default icon, and `Chip` and `Button` show none. New icons need an SDK release.

**Colours** (`color`, `border`) are a theme token name (`"surface"`, `"muted"`, …, section 9) or a
literal `"#RRGGBB"` / `"#AARRGGBB"`. Prefer tokens, so a theme change restyles every card.

**Radii** (`radius`) are a theme token (`"card"`, `"image"`, …) or a number.

**Text styles** (`style`) are a theme token: `display`, `title`, `body`, `caption`. Default
`body`.

---

## 8. Actions

```json
"action": { "name": "open_route", "args": { "route": "/venues/{/public_id}" } }
```

Only three actions exist. Anything else is ignored by the SDK (and logged in debug builds).

| `name` | `args` | What happens |
|---|---|---|
| `open_route` | `route`: a path starting with `/` | Closes the chat and asks the app's router to open it. |
| `ask` | `text` | Sends `text` as the user's next question, as if typed. |
| `open_url` | `url`: `https:`, `tel:` or `mailto:` only | Opens the browser, the dialer or the mail app. |

Each argument is a value (section 6.2), so it can use data:
`{"url": {"path": "/website"}}`, `{"url": "tel:{/phone}"}`, `{"text": {"uz": "Bugun qanday filmlar bor?", "en": "What's on today?"}}`.

Careful with URLs: if the data already contains `https://`, use the path directly. Don't build
`"https://{/website}"` or you get `https://https://…`.

---

## 9. Theme

One per app, sent in `GET /v1/suggestions` → `chat.theme` (section 5). Cards and the chat itself
both read it.

```json
{
  "font": "CeraPro",
  "colors": {
    "surface":    "#FF19212F",
    "on_surface": "#E6FFFFFF",
    "muted":      "#99FFFFFF",
    "chip":       "#0DFFFFFF",
    "image_bg":   "#08FFFFFF",
    "border":     "#0DFFFFFF",
    "accent":     "#FFBE7C6C",
    "on_accent":  "#FFFFFFFF"
  },
  "text": {
    "display": { "size": 30, "weight": 500, "height": 1.15 },
    "title":   { "size": 17, "weight": 500, "height": 1.25 },
    "body":    { "size": 15, "weight": 400, "height": 1.4 },
    "caption": { "size": 13, "weight": 400, "height": 1.3 }
  },
  "radius": { "card": 24, "image": 20, "chip": 100, "button": 16 }
}
```

| Token | Used for |
|---|---|
| `font` | A font family **the app already ships** (it is not downloaded). Missing: the app's default font. |
| `colors.surface` | Card background (set it on the root `Box`). |
| `colors.on_surface` | Default text colour. |
| `colors.muted` | Secondary text, chip text, icons. |
| `colors.chip` | Chip and secondary-button background, `Header` icon tile. |
| `colors.image_bg` | Behind images while they load. |
| `colors.border` | `InfoRow` and `Divider` lines. |
| `colors.accent`, `colors.on_accent` | Primary buttons, and the chat's send button and links. |
| `text.*` | `size` (px), `weight` (100–900), `height` (line height as a multiple). |
| `radius.*` | Corner radii in px. `chip` and `button` are used by those blocks. |

Send **all** colour tokens. The SDK's built-in fallbacks are meant for dark cards, so a missing
token can produce, for example, white text on a white card.

---

## 10. Welcome copy (optional)

`chat.welcome_title` and `chat.welcome_subtitle` in `GET /v1/suggestions` (section 5): plain
strings for the chat's first screen (the "How can I help you?" card), in the `language` the request
asked for. Store them per language in the console and send the one asked for. Missing: the SDK's
own neutral text.

---

## 11. Validation the backend should do on publish

The SDK never crashes on a bad template; it just draws less. Catch problems in the console instead:

1. `createSurface.components` is a list; every item has a unique string `id` and a `component`.
2. `component` is one of the 10 blocks in section 7.
3. `root` exists; every `child` / `children` id exists; no cycles; depth ≤ 32.
4. `icon` values are from the icon list; `style` is a text token; colours are tokens or `#hex`.
5. `action.name` is `open_route` / `ask` / `open_url`, with the matching argument.
6. Literal `src` values are `https://` URLs; literal `open_url` values use `https:`, `tel:` or `mailto:`.
7. Every data path the template uses exists in a sample of the linked tool's (trimmed) result:
   catches typos like `/workng_hours`.
8. `route` components: the route starts with `/`, and every `{name}` placeholder is a key the
   props will have.
9. The total template size stays small (aim under 16 KB).

A JSON Schema for checks 1–6 is in the appendix.

---

## 12. Full example: TCM's cinema card

**Tool result** the phone posted for `cinemas.list` (`GET /cinematica/` on TCM's API, trimmed):

```json
{
  "name": "CINEMATICA",
  "floor": "4",
  "category_name": { "uz": "Kinoteatr", "ru": "Кинотеатр", "en": "Cinema" },
  "description": { "uz": "…", "ru": "…", "en": "CINEMATICA is a large-format cinematographic system…" },
  "working_hours": { "uz": "…", "ru": "…", "en": "Mon-Thu: 10:00–23:00, Fri-Sun: 10:00–00:00" },
  "phone": "+998 33 635 90 00",
  "website": "https://cinematica.uz",
  "photo_url": "https://…/cinematica.png"
}
```

**Template** the console stores for `cinema_details` (kind `inline`); the backend sends its
`surface` with the card:

```json
{
  "kind": "inline",
  "surface": {
    "createSurface": {
      "surfaceId": "cinema_details",
      "catalogId": "zehn.basic.v0",
      "root": "root",
      "components": [
        { "id": "root", "component": "Box", "color": "surface", "radius": "card", "padding": 16, "child": "body" },
        { "id": "body", "component": "Column", "gap": 16, "children": ["photo", "intro", "contacts", "buy"] },

        { "id": "photo", "component": "Image", "src": { "path": "/photo_url" }, "height": 170, "radius": "image" },

        { "id": "intro", "component": "Column", "gap": 8, "children": ["chips", "name", "description"] },
        { "id": "chips", "component": "Row", "gap": 8, "children": ["category", "floor"] },
        { "id": "category", "component": "Chip", "icon": "theaters",
          "text": { "path": "/category_name" }, "visible": { "path": "/category_name" } },
        { "id": "floor", "component": "Chip", "icon": "layers",
          "text": { "uz": "{/floor}-qavat", "ru": "Этаж {/floor}", "en": "Floor {/floor}" } },
        { "id": "name", "component": "Text", "style": "display", "text": { "path": "/name" } },
        { "id": "description", "component": "Text", "style": "body", "maxLines": 4, "text": { "path": "/description" } },

        { "id": "contacts", "component": "Column", "gap": 0, "children": ["hours", "phone", "site"] },
        { "id": "hours", "component": "InfoRow", "icon": "schedule", "text": { "path": "/working_hours" } },
        { "id": "phone", "component": "InfoRow", "icon": "phone", "text": { "path": "/phone" },
          "action": { "name": "open_url", "args": { "url": "tel:{/phone}" } } },
        { "id": "site", "component": "InfoRow", "icon": "language", "text": { "path": "/website" },
          "action": { "name": "open_url", "args": { "url": { "path": "/website" } } } },

        { "id": "buy", "component": "Button", "icon": "ticket",
          "label": { "uz": "Chipta sotib olish", "ru": "Купить билет", "en": "Buy Ticket" },
          "action": { "name": "open_route", "args": { "route": "/explore_page" } } }
      ]
    }
  }
}
```

**Event** the backend sends after the tool result:

```
event: text.delta
data: {"turn_id":"t1","seq":4,"text":"Here's **Cinematica**:"}

event: mount_component
data: {"turn_id":"t1","seq":5,"call_id":"m_1","component":"cinema_details","kind":"inline","props":{ …the tool result above… },"surface":{ …the template's surface above… }}
```

**The user sees:** a dark rounded card with the cinema photo, a "Cinema" chip and a "Floor 4"
chip (in their language), "CINEMATICA" in large type, four lines of description, the hours, a
tappable phone row (opens the dialer), a tappable website row (opens the browser), and a coral
"Buy Ticket" button that opens the app's explore screen. All of it is in TCM's colours and CeraPro
font, drawn natively.

---

## 13. What the SDK does when something is wrong

| Problem | Result for the user |
|---|---|
| `inline` / `sheet` event without `surface`, and no app widget | Nothing is drawn for that card. |
| Surface JSON broken (no `createSurface`, missing `root`, duplicate ids) | Nothing is drawn for that card. |
| Unknown block type, or a `child` id that doesn't exist | That block is skipped (a red note in debug builds only). |
| Path leads nowhere | Empty text. |
| Image fails to load, or `src` isn't `http(s)` | A small placeholder icon. |
| Unknown action, or `open_url` with another scheme | The tap does nothing. |
| `route` event without `route` (or not starting with `/`), and no app widget | Nothing happens. |

Nothing in a template can crash the app or run code. A tap can only open an app route, ask a
question, or open an `https:`, `tel:` or `mailto:` link; images load only over `http(s)`.

---

## 14. Testing without the real backend

The SDK repository has a mock console that plays the backend for an app description file:

```bash
dart run zehn_intelligence:mock_server --app path/to/app.json
```

- Put the app's `api`, `tools`, `components`, `theme`, `copy` and `services` in the file (TCM's
  is at `tcm_mobile-new-backend/zehn_test/bootstrap.json`). The mock sends each card's `surface`
  in `mount_component`, each tool's built request in `client_api_request.http`, and the theme
  and welcome text in `GET /v1/suggestions`, as the backend should.
- The mock answers "cinema"/"kino"/"кино" questions with `cinemas.list` and mounts
  `cinema_details`, and "loyalty" with the `loyalty_page` route.
- Run any app with `ZehnIntelligence.init(consoleUrl: Uri.parse('http://127.0.0.1:8787'), …)`.

---

## 15. FAQ

**Why JSON blocks and not HTML?** Native widgets look and scroll like the rest of the app, use its
font, respect accessibility settings, and can't run scripts. App stores accept server-driven
layouts built from code that ships in the app; they don't accept downloaded code.

**Can the model generate a template on the fly?** Not in this version: the model picks a published
card and fills it with data. Templates are made (or drafted by the analyzer) and reviewed in the
console.

**Isn't sending the template with every card wasteful?** A template is a few KB (aim under 16 KB)
and gzips well. In return the phone keeps nothing that can go stale: a fix in the console shows up
on the next card. Cache templates on the backend, not on the phone.

**How do I add a new block or icon?** That's an SDK change (a new catalog version). Keep templates
on `zehn.basic.v0` until then.

**Do I need to localize data on the server?** No. Send the `{uz, ru, en}` objects as they come from
the customer's API; the SDK picks the user's language.

---

## Appendix: JSON Schema for a surface (checks 1–6)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://zehnmind.ai/schemas/zehn.basic.v0/surface.json",
  "type": "object",
  "required": ["createSurface"],
  "properties": {
    "createSurface": {
      "type": "object",
      "required": ["components"],
      "properties": {
        "surfaceId": { "type": "string" },
        "catalogId": { "const": "zehn.basic.v0" },
        "root": { "type": "string", "default": "root" },
        "components": { "type": "array", "minItems": 1, "items": { "$ref": "#/$defs/block" } }
      }
    }
  },
  "$defs": {
    "value": {
      "oneOf": [
        { "type": ["string", "number", "boolean", "null"] },
        { "type": "object", "required": ["path"], "properties": { "path": { "type": "string" } }, "additionalProperties": false },
        {
          "type": "object",
          "minProperties": 1,
          "propertyNames": { "enum": ["uz", "ru", "en"] },
          "additionalProperties": { "type": "string" }
        }
      ]
    },
    "color": { "type": "string", "pattern": "^(#([0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})|[a-z_]+)$" },
    "radius": { "oneOf": [{ "type": "number", "minimum": 0 }, { "type": "string", "pattern": "^[a-z_]+$" }] },
    "icon": { "enum": ["theaters", "layers", "schedule", "phone", "language", "movie", "ticket", "map", "parking", "star", "info"] },
    "children": {
      "oneOf": [
        { "type": "array", "items": { "type": "string" } },
        {
          "type": "object",
          "required": ["componentId", "path"],
          "properties": { "componentId": { "type": "string" }, "path": { "type": "string" } }
        }
      ]
    },
    "action": {
      "oneOf": [
        { "type": "object", "required": ["name", "args"],
          "properties": { "name": { "const": "open_route" },
                          "args": { "type": "object", "required": ["route"], "properties": { "route": { "$ref": "#/$defs/value" } } } } },
        { "type": "object", "required": ["name", "args"],
          "properties": { "name": { "const": "ask" },
                          "args": { "type": "object", "required": ["text"], "properties": { "text": { "$ref": "#/$defs/value" } } } } },
        { "type": "object", "required": ["name", "args"],
          "properties": { "name": { "const": "open_url" },
                          "args": { "type": "object", "required": ["url"], "properties": { "url": { "$ref": "#/$defs/value" } } } } }
      ]
    },
    "block": {
      "type": "object",
      "required": ["id", "component"],
      "properties": {
        "id": { "type": "string", "minLength": 1 },
        "component": { "enum": ["Box", "Column", "Row", "Image", "Text", "Chip", "Header", "InfoRow", "Button", "Divider"] },
        "visible": { "$ref": "#/$defs/value" },
        "width": { "type": "number", "minimum": 0 },
        "height": { "type": "number", "minimum": 0 },
        "flex": { "type": "number", "minimum": 1 },
        "action": { "$ref": "#/$defs/action" },
        "child": { "type": "string" },
        "children": { "$ref": "#/$defs/children" },
        "color": { "$ref": "#/$defs/color" },
        "border": { "$ref": "#/$defs/color" },
        "radius": { "$ref": "#/$defs/radius" },
        "padding": { "type": "number", "minimum": 0 },
        "gap": { "type": "number", "minimum": 0 },
        "align": { "enum": ["start", "center", "end", "stretch"] },
        "scroll": { "type": "boolean" },
        "src": { "$ref": "#/$defs/value" },
        "text": { "$ref": "#/$defs/value" },
        "title": { "$ref": "#/$defs/value" },
        "label": { "$ref": "#/$defs/value" },
        "style": { "enum": ["display", "title", "body", "caption"] },
        "maxLines": { "type": "integer", "minimum": 1 },
        "icon": { "$ref": "#/$defs/icon" },
        "variant": { "enum": ["primary", "secondary"] }
      }
    }
  }
}
```

The schema doesn't check that ids referenced by `root`, `child` and `children` exist, or that
there are no cycles. Do those two checks in code.
