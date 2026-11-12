# Dynamic cards: guide for backend developers

How the console defines the cards the assistant shows in a customer's app, and what the
backend must store, validate and send so the mobile SDK can draw them.

Matches SDK `0.7.0` (`zehn_intelligence`, `main`) and the backend's answer,
`CARDS_FOR_MOBILE.md` (branch `feat/proxy-sdk`). Related documents:

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
   colours and font. The theme (colours, font) and welcome words come from `GET /v1/config`,
   asked for at start-up and each time the chat opens.

```
Console ──(templates, theme)──► Backend (stores and caches them)
                                   │
   app starts, chat opens ───────► │ ──GET /v1/config → {theme, copy, …}──────────► SDK
   model wants a card ───────────► │ ──SSE: mount_component {component, props, surface}──► SDK draws it
   model wants a write ──────────► │ ──SSE: confirm {action_id, surface, props}──► SDK asks the user
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
| **Form card** | A card with input fields and a Send button, shown with the `form` event. What the person fills in goes back as their answer in the chat (sections 4 and 7.2). |
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
data: {"turn_id":"7b2e…","seq":10,"call_id":"m_2","component":"venue_page","kind":"route","props":{"venue_id":"a1"},"route":"/venues/a1"}
```

| Field | Rule |
|---|---|
| `component` | The component's name. The SDK uses it only to find an app widget with that name (below). |
| `kind` | `inline`, `sheet` or `route`; anything else counts as `inline`. |
| `props` | The data the template reads (section 6.2). A list card gets `{"items": [...]}` and repeats a block over `/items`; a single card gets one object. |
| `surface` | `inline` and `sheet`: the component's template (section 6). A `route` has none. |
| `route` | `route`: an app route (a path the app's router understands, starting with `/`), not a URL. **Final**: the server fills `{name}` from the props and escapes it (`/venues/{venue_id}` → `/venues/a1`); the SDK opens it exactly as sent. |
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

### Confirm cards: the `confirm` event

Before a write (POST, PUT, PATCH, DELETE), the server sends a card instead of the request:

```
event: confirm
data: {"turn_id":"…","seq":7,"call_id":"c2","action_id":"6f1d…","tool":"parking.reserve","method":"POST","surface":{"createSurface":{…}},"props":{"zone_id":12,"rows":[{"label":"Zone","value":"B1"}]},"confirm_label":"Reserve","expires_in":600}
```

- The SDK draws one card: a frame (`surface` background, 1 px `border`, radius `card`, padding 16)
  around the template drawn with `props` and, 16 below it, **Cancel** and **Confirm** side by
  side. So a confirm template has no framing root `Box` of its own. Confirm's word is
  `confirm_label`, else the SDK's own; for `DELETE` it is in a warning colour. Without a
  `surface` the SDK shows its own "Confirm this?". After the tap a status line takes the
  buttons' place.
- One tap answers the card. It is a new turn:
  `"input": {"type": "action", "action_id": "…", "decision": "confirm" | "cancel"}`.
- After Confirm the server sends the write as a `client_api_request` carrying that
  `action_id`. The SDK makes a write only for an action the user confirmed, once.
- After `expires_in` seconds, or on `action_used` / `action_expired` / `action_not_found`, the
  card shows as expired.

### Form cards: the `form` event

When the assistant needs several details at once (a name, a date, a phone number), it shows a
**form card** for the tool the answers are for. The backend sends it as its own event; an SDK older
than 0.7.0 ignores the event, and the backend does not offer forms to it.

```
event: form
data: {"turn_id":"7b2e…","seq":8,"call_id":"f_1","form_id":"3c9a…","component":"book_table","tool":"bookings.create","surface":{"createSurface":{ …section 6… }},"props":{"form":{"date":"2026-11-14"}}}
```

| Field | Rule |
|---|---|
| `call_id` | Any unique string; history uses it. |
| `form_id` | A UUID. The phone sends it back with the answers, and the backend answers `form_used` for a second send. |
| `component` | The form card's name. |
| `tool` | The tool the answers are for. |
| `surface` | The card's template (sections 6 and 7.2). A form is always `inline`. |
| `props` | `{"form": {…}}`: what is already filled in, by field key (section 6.5). `{"form": {}}` when nothing is. |

What the SDK does:

- Draws the card in the chat, under the assistant's text, with the fields in `props.form` filled in.
  What the person types is kept in the chat, not in the card: it survives scrolling, a switch to
  voice or history and back, and closing and reopening the chat (not the app being killed).
  Reopening the conversation that is already open keeps it too.
- A tap on the form's `submit` button (section 8) checks every visible field (section 7.2). A field
  that fails shows its message under it, and the first one is scrolled into view and focused. If all
  pass, the button shows progress, the fields turn off, and the SDK starts a turn:
  `"input": {"type": "form", "form_id": "…", "values": {"name": "Ali", "guests": 2}}` (the shape,
  the checks and the errors the backend answers with are in `MOBILE_INTEGRATION.md`, sections 1 and 7).
- `values` holds every visible field that has a value, as typed: a text trimmed and nothing else, a
  number as a JSON number, a checkbox or switch as `true` / `false`, a date as `YYYY-MM-DD`, a
  `Select` as its option's `value`, or a list of them when `multiple`. A hidden field, and an empty
  one, is left out. Send is off while the chat is busy.
- Once the server takes the answers, the fields turn into plain label-and-value lines and the button
  becomes the word **Sent**. The assistant then carries on: for a writing tool, with its confirm card
  (so a booking is two taps, Send then Confirm); for a reading tool, with the result.

A form on the phone is in one of four states:

| State | Meaning |
|---|---|
| `pending` | Waiting for answers. |
| `sending` | The answers are on their way; fields are off. |
| `submitted` | Answered. Draws read-only, with **Sent**. |
| `dismissed` | Can no longer be answered. Draws read-only, with **Not answered**, still showing what was typed. |

A form is answered **once**, and what happens to it is fixed:

- Any other turn in the conversation (typed, spoken, a confirm tap, another form) locks every form
  still `pending` as `dismissed`. So does the failure of the turn that showed the form.
- It counts as answered only when the turn its answers started ends `done`. If the send fails for
  any other reason (no network, a timeout, the turn ending in an error), the form is `pending`
  again with everything typed kept and the line "Not sent. Try again.". The chat's own Retry sends
  the same answers again.
- The backend's own refusals: `form_invalid` puts its messages on the fields it names and the form
  stays `pending`; `form_used` takes the state the answer names (`submitted` or `dismissed`);
  `form_not_found` locks it as `dismissed`.
- When the conversation cannot go on (`conversation_full`, `conversation_spec_changed`,
  `conversation_not_found`) the form locks as `dismissed`: a form is not carried into a new chat.

The phone passes every value on exactly as typed, and so does the backend; the model writes the
tool's arguments from them and may reshape them. A writing tool still asks first with its confirm
card, which shows the final arguments.

A form card is `inline` only, has between 1 and 12 fields and exactly one `submit` button, and its
fields are never inside a repeated block. A form card has no `items`, `id`, `max_items` or
`confirm_label`, and a tool has at most one form. The backend refuses a card that breaks these when
it is saved.

---

## 5. Theme and welcome text: `GET /v1/config`

The SDK asks for it in the background at start-up and again each time the chat opens:

```json
{
  "assistant_name": "Mall guide",
  "app_name": "Tashkent City Mall",
  "languages": ["uz", "ru", "en"],
  "default_language": "uz",
  "theme": { "...": "see section 9" },
  "copy": {
    "welcome_title": { "uz": "Qanday yordam bera olaman?", "ru": "Чем могу помочь?", "en": "How can I help you?" },
    "welcome_subtitle": "Find stores, restaurants, offers and more."
  }
}
```

| Field | Meaning |
|---|---|
| `theme` | Section 9. Used by the chat and by every card. |
| `copy.welcome_title`, `copy.welcome_subtitle` | The chat's first screen (section 10). |
| `assistant_name` | The chat's title. |
| `languages`, `default_language` | Which languages the assistant speaks; the SDK picks the phone's language if it is listed, else the default. |

Every field is optional: a missing one uses the SDK's own default (the SDK's colours and
words). The mic is always shown and every answer is spoken. `404 spec_not_found` hides the
assistant button. The SDK never sends or reads a spec version.

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
- `catalogId` is `"zehn.basic.v0"` for a card of the first eleven blocks, and `"zehn.basic.v1"` for
  one that uses a newer block, `position`, the `submit` action or an `equals` value. The backend
  sets it when it saves the card, and sends a `v1` card only to SDK 0.7.0 or newer. `surfaceId` is
  informational.
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
| Placeholder with a format | `"{/start\|time} – {/end\|time}"`, `"{/price\|money:UZS}/soat"` | The value at the path, drawn in that format (below). |
| Data path with a format | `{ "path": "/price", "format": "money:UZS" }` | The same, for a whole value. |
| Comparison | `{ "path": "/form/reason", "equals": "other" }` | `true` or `false`: the value at the path equals the literal (a string, a number or a bool). For showing a block only for one answer (section 6.4). |

**Formats** draw a value in the user's language:

| Format | Input | uz | ru | en |
|---|---|---|---|---|
| `time` | ISO 8601 (or `12:30:00`) | 12:30 | 12:30 | 12:30 |
| `date` | ISO 8601 | 10-noyabr | 10 ноября | Nov 10 |
| `datetime` | ISO 8601 | 10-noyabr, 12:30 | 10 ноября, 12:30 | Nov 10, 12:30 |
| `number` | number or numeric string | 10 000 | 10 000 | 10,000 |
| `money:<CODE>` | same | 10 000 UZS | 10 000 UZS | 10,000 UZS |
| `duration` | minutes | 1 soat 30 daqiqa | 1 ч 30 мин | 1 h 30 min |

A time with a zone shows in the phone's local time; one without, as written. A value that
doesn't parse, and an unknown format, show the raw value. The spaces inside a number and before
a currency code don't break a line.

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

`children` can also carry a `separator`, a block drawn **between** two repeats (a divider, a space),
never before the first or after the last, and not next to a repeat that `visible` hides:

```json
{ "id": "rates", "component": "Column", "children": { "componentId": "rate", "path": "rates", "separator": "line" } },
{ "id": "line",  "component": "Divider", "padding": { "y": 7.5 } }
```

### 6.4 Hiding a block: `visible`

```json
{ "id": "category", "component": "Chip", "text": { "path": "/category_name" }, "visible": { "path": "/category_name" } }
```

The block is skipped when `visible` resolves to `null`, `false` or `""`. Use it for optional data.

A comparison (section 6.2) gives `true` or `false`, so a block can show for one answer only:

```json
{ "id": "other", "component": "TextField", "field": "other_reason", "label": "Tell us more",
  "visible": { "path": "/form/reason", "equals": "other" } }
```

`2` equals `2.0`; a string never equals a number. When the value at the path is a list (a multiple
`Select`), it is `true` when the list contains the literal. There are no other operators.

### 6.5 What a form holds: `/form`

In a form card, the data is `{"form": {…}}`: what the fields hold now, by field key. It starts as
`props.form` (what the assistant filled in) and changes as the person types. Any block can read it
with the paths of section 6.2: `{ "path": "/form/name" }`, or `"Hello, {/form/name}"` in a string.
Those blocks redraw as the person types.

| Field | Value at `/form/<field>` |
|---|---|
| `TextField` | The text as typed; a number for `input: number`. |
| `Checkbox`, `Switch` | `true` or `false`. |
| `Select` | The option's `value`; a list of them when `multiple`. |
| `DateField` | `YYYY-MM-DD`. |

A **hidden** field is one whose own `visible`, or that of any block above it up to the root, resolves
to `null`, `false` or `""` against this data. A hidden field is not checked and not sent. Its value
also counts as absent when other blocks' `visible` is worked out, so a field that only a hidden
field would show is hidden too. A path that leads nowhere (a field with no value yet) is empty, as
everywhere. A card that is not a form has no `/form` data (section 13).

---

## 7. Block catalog (`zehn.basic.v1`)

Everything in `zehn.basic.v0` draws exactly as before; `v1` adds the blocks, properties and
action marked below. A card that uses none of them stays `v0`.

Properties every block accepts:

| Property | Type | Meaning |
|---|---|---|
| `id` | string | Required, unique. |
| `component` | string | Required, one of the blocks below. |
| `visible` | value | Section 6.4. |
| `width`, `height` | number | Fixed size in logical pixels. |
| `flex` | number | Shares the free width with sibling blocks. **Use only on children of a non-scrolling `Row`.** |
| `padding` | number or object | Space inside the block (section 7.1). |
| `action` | object | Makes the block tappable (section 8). `Header`, `InfoRow` and `Button` show their own tap feedback. |
| `position` | `center`, `top`, `bottom`, `start`, `end`, `top_start`, `top_end`, `bottom_start`, `bottom_end` | Places the block over its siblings inside the `Stack` that holds it, with `padding` keeping it off the edge. Any other parent ignores it. (`v1`) |

The blocks:

| Block | Properties | Draws |
|---|---|---|
| `Box` | `child` (id), `color` (colour), `radius` (radius), `border` (colour), `shadow`, `alignment` | A container; `padding` is inside its background. Use it as the card's root, with `color: "surface"`. |
| `Column` | `children`, `gap` (number), `align` (`start`·`center`·`end`·`stretch`, default `start`), `justify` | Blocks stacked top to bottom. |
| `Row` | `children`, `gap`, `align` (default `center`; `start` when scrolling), `justify`, `scroll` (bool) | Blocks left to right. `scroll: true` scrolls sideways (carousels). |
| `Image` | `src` (value: an `https://` URL; `http://` also loads but avoid it), `width`, `height`, `radius`, `fit` | A network image, cropped to fill (or `fit`). Full width unless `width` is set. Any other scheme shows a placeholder icon. |
| `Text` | `text` (value) or `spans`, `style` (text style), `color` (colour, default `on_surface`), `maxLines` (number), `size`, `weight`, `lineHeight`, `letterSpacing`, `font`, `textAlign` | Text. Cut with "…" after `maxLines`. Section 7.1 for the rest. |
| `Icon` | `name` (icon), `size` (number), `color` (colour, default `muted`) | One icon. |
| `Chip` | `text`, `icon`, `color` (background, default `chip`) | A small rounded label (floor, rating, category). |
| `Header` | `title`, `icon`, `action` | A section title with an icon tile; a chevron when it has an action. |
| `InfoRow` | `text`, `icon`, `action` | An icon and a line of text with a divider under it (hours, phone, website); a chevron when it has an action. |
| `Button` | `label`, `icon`, `variant` (`primary` default, or `secondary`), `action` | A full-width 50px button. Primary uses `accent`, secondary uses `chip`. |
| `Divider` | — | A 1px line in `border` colour. |
| `Stack` (`v1`) | `children`, `alignment` (the nine values of `Box`, default `top_start`) | Its children on top of each other, the first at the back. Its size is that of its biggest child that has no `position`; the first child's `position` is ignored. A child with a `position` is laid over the others (a label or badge on an image). |
| `Wrap` (`v1`) | `children`, `gap` (number), `runGap` (number, default `gap`), `align` (`start`·`center`·`end`, default `start`) | Children left to right, flowing onto the next line when the row is full (chips, tags). |
| `Progress` (`v1`) | `value` (0 to 1), `color` (default `accent`), `track` (colour, default `chip`), `height` (2 to 40, default 6) | A rounded bar filled from 0 to `value`. Full width where its parent bounds the width; with no `width` and no `flex` in a parent that does not (a `Row`), 120 px. |
| `Avatar` (`v1`) | `src`, `text`, `size` (16 to 160, default 40), `color` (default `chip`) | A round image. With no image (or when it fails to load) it shows the first two letters of `text`, upper-cased. |
| `TextField`, `Checkbox`, `Switch`, `Select`, `DateField` (`v1`) | Section 7.2 | Form fields. |

### 7.1 Looking like the app's own widgets

The blocks above are small on purpose. These properties let a template match what an app's
designers drew, in px unless said otherwise. All are optional and added to what is there: a
template that doesn't use them draws exactly as before, and an SDK that predates them ignores
the properties (it skips an `Icon` block, as it skips any block it doesn't know).

| Property | On | Meaning |
|---|---|---|
| `padding` | every block | Space inside the block's size: a number for every side, or `{"x": 16, "y": 8, "top": 4, "right": 0, "bottom": 0, "left": 12}` (a side beats `x` / `y`; 0 to 200). A `Box` pads inside its background; a sideways `Row` pads its content, so the padding scrolls with it; any other block gets the space around it. |
| `shadow` | `Box` | One soft shadow: `{"x": 0, "y": 4, "blur": 10, "spread": 0, "color": "#08000000"}` (`color`: a token or `#hex`). |
| `alignment` | `Box` | Where its child sits inside it: `center`, `top`, `bottom`, `start`, `end`, `top_start`, `top_end`, `bottom_start`, `bottom_end`. |
| `justify` | `Row`, `Column` | How the children share the main axis: `start`, `center`, `end`, `space_between`, `space_around`, `space_evenly`. A `Column` needs a `height` for it to matter. |
| `size`, `weight`, `lineHeight`, `letterSpacing`, `font`, `textAlign` | `Text` | Over its `style`, for this text only. `size` 6 to 96 px; `weight` 100 to 900 in hundreds; `lineHeight` a multiple of the size (0.8 to 3); `letterSpacing` in em (`-0.01` is 1% tighter; -0.2 to 0.5); `font` a family the app ships, or `system` for the platform's own; `textAlign` `start`, `center` or `end`. |
| `spans` | `Text` | Instead of `text`: parts of one line, each `{"text": value, "color": colour, "weight": 100–900}`, so a word can have its own colour. Or a language map of such lists when the order differs by language (`{"uz": [...], "ru": [...], "en": [...]}`). |
| `fit` | `Image` | `cover` (default, crops), `fill` (stretches) or `contain` (shows it all). |
| `name`, `size`, `color` | `Icon` | An icon (the list above, or the app's own) at a size (8 to 96, default 24) and colour (default `muted`). A name nobody knows keeps its room and draws nothing. |

A `Divider` takes `padding` too, to give it room: `{"component": "Divider", "padding": {"y": 15.5}}`.
A text style in the theme may also carry `letterSpacing` (em), so every text of that style gets it (§9).

**The app's own icons.** An app hands the SDK its own icons by name, and templates use them like
the built-in ones (`icon` on a `Chip`, `Header`, `InfoRow` or `Button`, or an `Icon` block):

```dart
ZehnIntelligence.registerIcon('cinema', (context, size, color) =>
    SvgPicture.asset('assets/cinema.svg', width: size, height: size, colorFilter: ColorFilter.mode(color, BlendMode.srcIn)));
```

A name is `lower_snake_case` (2 to 32 characters). A registered name beats a built-in of the same
name, so an app can give `forward` its own chevron. The console accepts any such name, so a typo
(`schedul`) is not caught there: it draws nothing.

**Example: a store card in an app's own look** (a white card with a hairline border and a faint
shadow, a 64 px logo tile, the name and a floor chip, the app's chevron):

```json
{ "id": "root", "component": "Box", "color": "#FFFFFFFF", "radius": 20, "padding": 8, "border": "border",
  "shadow": { "y": 4, "blur": 10, "color": "#08000000" }, "child": "row",
  "action": { "name": "open_route", "args": { "route": { "path": "/route" } } } },
{ "id": "row", "component": "Row", "children": ["logo", "mid", "chev"] },
{ "id": "logo", "component": "Box", "width": 64, "height": 64, "color": "#0819212F", "radius": 16, "alignment": "center", "child": "mark" },
{ "id": "mark", "component": "Text", "text": { "path": "/mark" }, "font": "system", "size": 24, "weight": 900, "lineHeight": 1 },
{ "id": "mid", "component": "Column", "flex": 1, "padding": { "left": 12 }, "gap": 4, "children": ["name", "floor"] },
{ "id": "name", "component": "Text", "style": "title", "text": { "path": "/name" } },
{ "id": "floor", "component": "Box", "color": "chip", "radius": 100, "padding": { "x": 8, "y": 2 }, "child": "floor_t" },
{ "id": "floor_t", "component": "Text", "style": "caption", "weight": 500, "color": "muted", "text": { "path": "/floor" } },
{ "id": "chev", "component": "Icon", "name": "forward", "size": 24, "color": "muted", "padding": { "right": 4 } }
```

**Icons** (`icon`) are a fixed list: `theaters`, `layers`, `schedule`, `phone`, `language`,
`movie`, `ticket`, `map`, `parking`, `star`, `info`, and since 0.5.0 `car`, `store`, `calendar`,
`wallet`, `person`, `restaurant`, `bus`, `gift`, and `forward` (a chevron). With an unknown name, `Header` and `InfoRow`
show a neutral default icon, and `Chip` and `Button` show none. A new built-in icon needs an SDK release; an app can also register its own (section 7.1).

**The catalog file.** `catalog/zehn.basic.json` in the SDK repo lists every block (with its
properties and a line on when to use it), icon, action, text style, colour and radius token,
and format this SDK draws, with its `sdk_version`. The analyzer reads it at the commit an app's
`pubspec.lock` names. A test fails when the file and the renderer disagree. A type in
`props` is a name (`value`, `number`, `color`, …), a list of the allowed words, or a number with
its range (`{"type": "number", "min": 6, "max": 96}`). Each block also has its `group`
(`layout`, `content` or `field`) and `needs`, the properties it cannot draw without; the file
lists the checks, what `v1` added (`since`) and the words of section 7.2 too.

**Colours** (`color`, `border`) are a theme token name (`"surface"`, `"muted"`, …, section 9) or a
literal `"#RRGGBB"` / `"#AARRGGBB"`. Prefer tokens, so a theme change restyles every card.

**Radii** (`radius`) are a theme token (`"card"`, `"image"`, …) or a number.

**Text styles** (`style`) are a theme token: `display`, `title`, `body`, `caption`. Default
`body`.

### 7.2 Fields

Fields take input, and exist only in a **form card** (section 4), at most 12 of them, never inside a
repeated block. Typed values are stored with the conversation, shown in the console's conversation
view and read by the model, exactly like typed chat text: there are no password or secret fields.

Every field block has, besides the properties of section 7:

| Property | Type | Meaning |
|---|---|---|
| `field` | string | Required. The key its value is stored and sent under (section 6.5): `lower_snake_case`, 1 to 40 characters, unique in the card. It need not be one of the tool's arguments. |
| `label` | value | Required. Always visible above the field (beside a checkbox or switch). |
| `hint` | value | Help under the field. An error takes its place. |
| `value` | literal | What it starts with when the assistant fills nothing in. |
| `checks` | list | What a value must pass (below). |

The five blocks:

| Block | Own properties | Draws |
|---|---|---|
| `TextField` | `input` (`text` default, `multiline`, `number`, `email`, `phone`), `placeholder` (a format example, never the label), `maxLength` (1 to 4000, default 500) | A box to type into. `input` sets the keyboard and an automatic check. `value` is a string, or a number for `number`. |
| `Checkbox` | — | A box to tick. `value` is `true` or `false`. |
| `Switch` | — | An on and off switch. `value` is `true` or `false`. |
| `Select` | `options` (1 to 50 of `{"value": string of 1 to 64 characters, "label": value}`, values unique), `multiple` (bool), `look` (`dropdown` default, `list`, `chips`), `placeholder` | One option, or several when `multiple`. `dropdown` opens the options in a bottom sheet; `list` is radio rows (checkbox rows when `multiple`); `chips` is chips. `value` is one option's `value`, or a list of them when `multiple`. |
| `DateField` | `min`, `max` (`YYYY-MM-DD` or `"today"`) | A date picked from a calendar. `value` is `YYYY-MM-DD` or `"today"`. |

A field is drawn with a `chip` fill, corners of `radius.button`, its text in `body` and `on_surface`,
its label and hint in `caption` and `muted`, an `accent` outline when focused, and its error in the
`error` colour (section 9). It is at least 48 px tall. A multiple `Select` keeps its options' order
whatever order they were picked in, and tapping a picked option clears it. Strings in `label`,
`hint`, `placeholder`, an option's `label` and a check's `message` are at most 500 characters.

Once a form is answered or locked (and in a card that is not a form), each field is its label, then
its value as text: text as typed; a number as written; `✓` for true and `—` for false; the picked
options' labels joined by `", "`; a date in the `date` format; `—` when empty.

**Checks.** `checks` is a list of rules, at most one of each rule per field:

```json
"checks": [ { "rule": "required" },
            { "rule": "length", "min": 2, "max": 60, "message": { "uz": "…", "ru": "…", "en": "2 to 60 letters" } } ]
```

| `rule` | On | Passes when |
|---|---|---|
| `required` | every field | It has a value. A checkbox or switch must be on. |
| `length` (`min`, `max`) | `TextField` except `number` | The text's length is in range. |
| `range` (`min`, `max`) | `TextField` with `input: number` | The number is in range. |
| `items` (`min`, `max`) | `Select` with `multiple` | That many options are picked. |

`min` ≤ `max`, and `length`, `range` and `items` need at least one of them. `message` is optional
(a value, section 6.2). There are no regular expressions.

**How a value is checked.** The same way on the phone before sending, in the backend when the
answers arrive, and in the console's preview:

1. A hidden field is skipped (section 6.5).
2. A `TextField`'s text is trimmed (no other value is changed). An empty string, an empty list and
   `null` are no value, and the key is left out; `false` is a value. An empty optional field is sent
   as nothing, and only `required` looks at it.
3. For a field with a value, the first failure is reported, in this order: the automatic checks, then
   `required`, then `length`, `range` or `items`.

| Automatic check | Fails when |
|---|---|
| `number` | `input: number` and the text is not `-?digits` with an optional `.` or `,` fraction, or its value is not finite (several hundred digits). Sent as a JSON number (an integer when it has no fraction), a `,` read as `.`. |
| `email` | `input: email` and the text is not like `name@host.tld` (no spaces, one `@`, a dot after it). |
| `phone` | `input: phone` and, with every whitespace, `+`, `-`, `(` and `)` removed, it is not 7 to 15 digits. The value is sent as typed. |
| `date` | Not a real date, or outside `min` and `max` (inclusive). `"today"` is the phone's local date. |
| `option` | A value that is not one of the `Select`'s options. |

`length` also fails when the text is over `maxLength` (default 500, always checked). Lengths count
UTF-16 code units, as Dart and JavaScript do.

**The words.** An error shows the failing check's own `message` when it has one; otherwise the SDK's
words, in the user's language (`{min}` and `{max}` are filled in). For `length`, `range` and `items`
the `_min` words are used when only `min` is set, and the `_max` words when only `max`; the
automatic checks always use the SDK's words. The last five are the form's own status lines and
buttons.

| Key | uz | ru | en |
|---|---|---|---|
| `required` | Bu maydonni to‘ldiring | Заполните это поле | Fill this in |
| `length` | {min} tadan {max} tagacha belgi kiriting | От {min} до {max} символов | Use {min} to {max} characters |
| `length_min` | Kamida {min} ta belgi kiriting | Не меньше {min} символов | Use at least {min} characters |
| `length_max` | Ko‘pi bilan {max} ta belgi kiriting | Не больше {max} символов | Use at most {max} characters |
| `range` | {min} dan {max} gacha son kiriting | Введите число от {min} до {max} | Enter a number from {min} to {max} |
| `range_min` | {min} yoki undan katta son kiriting | Введите {min} или больше | Enter {min} or more |
| `range_max` | {max} yoki undan kichik son kiriting | Введите {max} или меньше | Enter {max} or less |
| `items` | {min} tadan {max} tagacha tanlang | Выберите от {min} до {max} | Choose {min} to {max} |
| `items_min` | Kamida {min} tasini tanlang | Выберите не меньше {min} | Choose at least {min} |
| `items_max` | Ko‘pi bilan {max} tasini tanlang | Выберите не больше {max} | Choose at most {max} |
| `number` | Son kiriting | Введите число | Enter a number |
| `email` | Elektron pochta manzilini kiriting | Введите адрес почты | Enter an email address |
| `phone` | Telefon raqamini kiriting | Введите номер телефона | Enter a phone number |
| `date` | Boshqa sanani tanlang | Выберите другую дату | Choose another date |
| `option` | Variantlardan birini tanlang | Выберите один из вариантов | Choose one of the options |
| `sent` | Yuborildi | Отправлено | Sent |
| `not_answered` | Javob berilmadi | Без ответа | Not answered |
| `not_sent` | Yuborilmadi. Qayta urinib ko‘ring. | Не отправлено. Попробуйте ещё раз. | Not sent. Try again. |
| `update_app` | Javob berish uchun ilovani yangilang. | Обновите приложение, чтобы ответить. | Update the app to answer this. |
| `choose` | Tanlang | Выбрать | Choose |

`catalog/zehn.basic.json` carries this table as `words`, so the console can draw the same text.

---

## 8. Actions

```json
"action": { "name": "open_route", "args": { "route": "/venues/{/public_id}" } }
```

Only four actions exist. Anything else is ignored by the SDK (and logged in debug builds).

| `name` | `args` | What happens |
|---|---|---|
| `open_route` | `route`: a path starting with `/` | Closes the chat and asks the app's router to open it. |
| `ask` | `text` | Sends `text` as the user's next question, as if typed. |
| `open_url` | `url`: `https:`, `tel:` or `mailto:` only | Opens the browser, the dialer or the mail app. |
| `submit` | none | Checks the form's fields and sends the answers (section 4). Only on a `Button`, and only in a form card, which has exactly one. (`v1`) |

Each argument is a value (section 6.2), so it can use data:
`{"url": {"path": "/website"}}`, `{"url": "tel:{/phone}"}`, `{"text": {"uz": "Bugun qanday filmlar bor?", "en": "What's on today?"}}`.

The other three stay allowed in a form card; `ask` sends its text, which locks the form like any
typed message.

Careful with URLs: if the data already contains `https://`, use the path directly. Don't build
`"https://{/website}"` or you get `https://https://…`.

---

## 9. Theme

One per app, sent in `GET /v1/config` → `theme` (section 5), always with every token. Cards and
the chat itself both read it.

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
    "on_accent":  "#FFFFFFFF",
    "error":      "#FFD64545"
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
| `colors.error` | Optional. A field's error text and outline. Missing: `#FFD64545`, the chat's own red. |
| `text.*` | `size` (px), `weight` (100–900), `height` (line height as a multiple), and optionally `letterSpacing` (em, e.g. `-0.01`). |
| `radius.*` | Corner radii in px. `chip` and `button` are used by those blocks. |

Send **all** colour tokens (`error` is the only optional one). The SDK's built-in fallbacks are meant for dark cards, so a missing
token can produce, for example, white text on a white card.

---

## 10. Welcome copy (optional)

`copy.welcome_title` and `copy.welcome_subtitle` in `GET /v1/config` (section 5), for the chat's
first screen (the "How can I help you?" card). Each is one string or a language map; from a map
the SDK picks the user's language, else the app's default, else `en`, else the first. Missing:
the SDK's own neutral text.

---

## 11. Validation the backend should do on publish

The SDK never crashes on a bad template; it just draws less. Catch problems in the console instead:

1. `createSurface.components` is a list; every item has a unique string `id` and a `component`.
2. `component` is one of the blocks in section 7.
3. `root` exists; every `child` / `children` id exists; no cycles; depth ≤ 32.
4. `icon` values are from the icon list; `style` is a text token; colours are tokens or `#hex`.
5. `action.name` is `open_route` / `ask` / `open_url`, with the matching argument, or `submit`
   (no arguments, on a `Button` of a form card).
6. Literal `src` values are `https://` URLs; literal `open_url` values use `https:`, `tel:` or `mailto:`.
7. Every data path the template uses exists in a sample of the linked tool's (trimmed) result:
   catches typos like `/workng_hours`.
8. `route` components: the route starts with `/`, and every `{name}` placeholder is a key the
   props will have.
9. The total template size stays small (aim under 16 KB).
10. A form card (section 7.2): `inline`, 1 to 12 fields with unique keys, exactly one `submit`
    button, no field inside a repeated block, and every field's value, options and checks as
    section 7.2 says. Fields and `submit` appear in no other card.

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
| Write without a confirmed `action_id` | Not made; the model reads `not_confirmed`. |
| A block the phone does not know, in a form card | None of the form is drawn: the card says "Update the app to answer this." A form that silently lost a field must not be sendable. |
| A field in a card that is not a form (a result or confirm card, or `ZiSurfaceView` drawn alone) | The field is read-only: its label and its value as text. A `submit` button draws nothing. |

Nothing in a template can crash the app or run code. A tap can only open an app route, ask a
question, or open an `https:`, `tel:` or `mailto:` link; images load only over `http(s)`.

---

## 14. Testing without the real backend

The SDK repository has a mock console that plays the backend for an app description file:

```bash
dart run zehn_intelligence:mock_server --app path/to/app.json
```

- Put the app's `api`, `tools`, `components`, `theme` and `copy` in the file (TCM's
  is at `tcm_mobile-new-backend/zehn_test/bootstrap.json`). The mock serves `GET /v1/config`,
  sends each card's `surface` in `mount_component`, each tool's built request in
  `client_api_request.request`, fills routes, and asks before writes with a `confirm` card, as
  the backend does.
- The mock answers "cinema"/"kino"/"кино" questions with `cinemas.list` and mounts
  `cinema_details`, "loyalty" with the `loyalty_page` route, and "reserve"/"parking" with a
  confirm card for `parking.reserve` (built-in app only).
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

**How do I add a new block or icon?** That's an SDK change (a new catalog version, such as
`zehn.basic.v1`). A card that uses a new block is served only to SDKs that have it; an older app
never gets it, and its assistant answers in text instead.

**Do I need to localize data on the server?** No. Send the `{uz, ru, en}` objects as they come from
the customer's API; the SDK picks the user's language.

---

## Appendix: JSON Schema for a surface (checks 1–6)

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "$id": "https://zehnmind.ai/schemas/zehn.basic.v1/surface.json",
  "type": "object",
  "required": ["createSurface"],
  "properties": {
    "createSurface": {
      "type": "object",
      "required": ["components"],
      "properties": {
        "surfaceId": { "type": "string" },
        "catalogId": { "enum": ["zehn.basic.v0", "zehn.basic.v1"] },
        "root": { "type": "string", "default": "root" },
        "components": { "type": "array", "minItems": 1, "items": { "$ref": "#/$defs/block" } }
      }
    }
  },
  "$defs": {
    "value": {
      "oneOf": [
        { "type": ["string", "number", "boolean", "null"] },
        { "type": "object", "required": ["path"],
          "properties": { "path": { "type": "string" }, "format": { "type": "string" },
                          "equals": { "type": ["string", "number", "boolean"] } },
          "additionalProperties": false },
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
    "icon": { "type": "string", "pattern": "^[a-z][a-z0-9_]{1,31}$" },
    "place": { "enum": ["center", "top", "bottom", "start", "end", "top_start", "top_end", "bottom_start", "bottom_end"] },
    "date": { "type": "string", "pattern": "^(today|\\d{4}-\\d{2}-\\d{2})$" },
    "options": {
      "type": "array", "minItems": 1, "maxItems": 50,
      "items": { "type": "object", "required": ["value", "label"],
                 "properties": { "value": { "type": "string", "minLength": 1, "maxLength": 64 },
                                 "label": { "$ref": "#/$defs/value" } } }
    },
    "checks": {
      "type": "array", "maxItems": 4,
      "items": { "type": "object", "required": ["rule"],
                 "properties": { "rule": { "enum": ["required", "length", "range", "items"] },
                                 "min": { "type": "number" }, "max": { "type": "number" },
                                 "message": { "$ref": "#/$defs/value" } } }
    },
    "children": {
      "oneOf": [
        { "type": "array", "items": { "type": "string" } },
        {
          "type": "object",
          "required": ["componentId", "path"],
          "properties": { "componentId": { "type": "string" }, "path": { "type": "string" }, "separator": { "type": "string" } }
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
                          "args": { "type": "object", "required": ["url"], "properties": { "url": { "$ref": "#/$defs/value" } } } } },
        { "type": "object", "required": ["name"], "properties": { "name": { "const": "submit" } } }
      ]
    },
    "block": {
      "type": "object",
      "required": ["id", "component"],
      "properties": {
        "id": { "type": "string", "minLength": 1 },
        "component": { "enum": ["Box", "Column", "Row", "Image", "Text", "Icon", "Chip", "Header", "InfoRow", "Button", "Divider",
                                "Stack", "Wrap", "Progress", "Avatar", "TextField", "Checkbox", "Switch", "Select", "DateField"] },
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
        "padding": {
          "oneOf": [
            { "type": "number", "minimum": 0, "maximum": 200 },
            { "type": "object", "additionalProperties": false,
              "properties": { "x": { "type": "number" }, "y": { "type": "number" }, "top": { "type": "number" },
                              "right": { "type": "number" }, "bottom": { "type": "number" }, "left": { "type": "number" } } }
          ]
        },
        "shadow": { "type": "object", "additionalProperties": false,
                    "properties": { "x": { "type": "number" }, "y": { "type": "number" }, "blur": { "type": "number", "minimum": 0 },
                                    "spread": { "type": "number" }, "color": { "$ref": "#/$defs/color" } } },
        "alignment": { "enum": ["center", "top", "bottom", "start", "end", "top_start", "top_end", "bottom_start", "bottom_end"] },
        "justify": { "enum": ["start", "center", "end", "space_between", "space_around", "space_evenly"] },
        "fit": { "enum": ["cover", "fill", "contain"] },
        "spans": { "type": ["array", "object"] },
        "size": { "type": "number", "minimum": 6, "maximum": 160 },
        "weight": { "type": "integer", "minimum": 100, "maximum": 900, "multipleOf": 100 },
        "lineHeight": { "type": "number", "minimum": 0.8, "maximum": 3 },
        "letterSpacing": { "type": "number", "minimum": -0.2, "maximum": 0.5 },
        "font": { "type": "string", "pattern": "^[A-Za-z0-9 _-]{1,64}$" },
        "textAlign": { "enum": ["start", "center", "end"] },
        "name": { "$ref": "#/$defs/icon" },
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
        "variant": { "enum": ["primary", "secondary"] },
        "position": { "$ref": "#/$defs/place" },
        "runGap": { "type": "number", "minimum": 0 },
        "track": { "$ref": "#/$defs/color" },
        "field": { "type": "string", "pattern": "^[a-z][a-z0-9_]{0,39}$" },
        "hint": { "$ref": "#/$defs/value" },
        "value": { "oneOf": [{ "$ref": "#/$defs/value" }, { "type": "array", "items": { "type": "string" } }] },
        "checks": { "$ref": "#/$defs/checks" },
        "input": { "enum": ["text", "multiline", "number", "email", "phone"] },
        "placeholder": { "$ref": "#/$defs/value" },
        "maxLength": { "type": "integer", "minimum": 1, "maximum": 4000 },
        "options": { "$ref": "#/$defs/options" },
        "multiple": { "type": "boolean" },
        "look": { "enum": ["dropdown", "list", "chips"] },
        "min": { "$ref": "#/$defs/date" },
        "max": { "$ref": "#/$defs/date" }
      }
    }
  }
}
```

The schema doesn't check that ids referenced by `root`, `child` and `children` exist, or that
there are no cycles. Do those two checks in code.

It is also looser than the catalog on purpose: a property is typed the same on every block (`size`
allows 6 to 160, though `Text` and `Icon` stop at 96), and it does not know which block takes
which property, nor the rules of a form card (section 7.2). The backend's `spec.schema.json` is the
authority; `catalog/zehn.basic.json` lists each block's properties and ranges.
