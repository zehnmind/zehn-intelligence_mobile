# Form fields in cards, more blocks, and a card builder in the console — design

Date: 2026-11-12. Scope: the Flutter SDK (`zehn_intelligence`, next release 0.7.0), the
backend and the console. Status: proposed, not built.

## Why

- **Cards can only show things.** The catalog has 11 blocks and none of them takes input. A
  tap can open a route, ask a question or open a link. When the assistant needs a name, a
  phone number, a date and a comment, it has to ask for them one message at a time.
- **Some layouts can't be drawn.** Nothing can sit on top of something else (a label over a
  poster), chips can't flow onto a second line, and there is no progress bar or round avatar.
- **The card editor is a JSON text box.** A developer has to know the format by heart. The
  only help is an "add a block" menu that appends a block attached to nothing.

What was asked (2026-11-12): improve the renderer, add elements, support text fields; in the
console a developer draws components and form fields. Sending cards to users from the console,
a badge on the bubble and a view of what was sent were also asked, and dropped the same day.

## Decisions

| # | Decision | Source |
|---|---|---|
| 1 | The renderer gets more elements and text fields. In the console a developer draws components and form fields. | User |
| 2 | The console cannot send anything to users. No badge on the bubble, no view of sent data. | User ("for now skip it") |
| 3 | Cards appear where they do today: in the chat, when the assistant shows one. No new delivery path. | User agreed to our reading |
| 4 | The JSON text box becomes a builder: blocks to add, the card's structure, a phone preview, and the selected block's properties. Raw JSON stays on its own tab. | User agreed to our mockup |
| 5 | Tapping the form's button checks the fields and hands the values to the assistant as the person's answer in that chat. The card then locks and shows what was entered. | User agreed |
| 6 | An app on an older SDK never gets a card that uses the new blocks. | User agreed |
| 7 | New blocks: text field (one line, several lines, number, phone, email), checkbox, switch, select, Stack, Wrap, Progress, Avatar. | User agreed to our list |

Our calls (the user can revisit them):

- **A form belongs to a tool.** A form card is a third card role, `form`, next to `result` and
  `confirm`. Its `tool` is the tool the answers are for. This keeps today's rule that a card
  has a tool, and tells the model exactly what to do with the answers.
- **Writes still ask first.** The form's answers go to the model, the model calls the tool,
  and a writing tool shows its confirm card as today. So a booking is two taps: Send, then
  Confirm. Nothing in the write path changes.
- **Forms are inline only**, with at most 12 fields. Forms in a sheet or on a full page need
  a chat row that reopens them and a summary after sending; that is later work.
- **Fields live only in form cards**, never inside a repeated block. Result and confirm cards
  stay display-only.
- **A date field is added** to the user's list. Bookings need it and nearly every card format
  has one.
- **A fixed list of checks, no regular expressions.** A developer-written pattern would run
  on our shared server against user input, and Python's and Dart's engines can both be made
  to hang. It waits for a safe engine.
- **No password or secret fields.** Typed values are stored with the conversation, shown in
  the console's conversation view and read by the model, exactly like typed chat text. The
  builder says so on every form card.
- **A form is answered once.** It stays open until the conversation moves on. There is no
  time limit. It counts as answered only when the turn its answers started finishes; if
  that turn fails, the form opens again with everything still typed in.
- **The model writes the tool's arguments** from the answers, and nothing forces them to
  match what was typed. The SDK and the server pass values on untouched; for a writing tool
  the confirm card shows the final arguments.
- **New catalog id `zehn.basic.v1`.** The server decides which catalog a card needs and
  compares it with the caller's SDK version.
- **The builder is our own code** on a small tree library, with unit tests for the block
  operations. Editor frameworks (Puck, Craft.js, GrapesJS) each bring their own document
  shape and their own preview, and we must keep both of ours.
- **Google's A2UI renderer is still not adopted.** The 2026-11-10 spike said to look again
  if cards needed forms. Its reasons still hold (wrong uz/ru formats, about 2 MB per app, one
  bad property fails the whole card). Our fields follow A2UI's model, values at a path and
  checks with messages, so a later translation stays mechanical.

## What a person sees

1. They ask for something that needs details ("book a table for Friday").
2. The assistant shows the form card for that tool, with what it already knows filled in
   (the date), and a short line of text.
3. They fill the rest and tap the button. A field that fails a check shows its message under
   it; the first one is scrolled into view and focused.
4. The button shows progress. Once the server accepts the answers, the fields turn into plain
   label-and-value lines and the button becomes the word **Sent**.
5. The assistant carries on: for a writing tool, the confirm card; for a reading tool, the
   result.

If they type or speak instead of filling the form, the form locks as **Not answered** and
the message is handled as usual. To change an answer after sending they just say so, and the
assistant shows a new form filled with the earlier values.

## Blocks: catalog `zehn.basic.v1`

Everything in `zehn.basic.v0` stays as it is. Added:

### Layout and display (allowed in every card)

| Block | Properties | Draws |
|---|---|---|
| `Stack` | `children`, `alignment` (the nine `Box` values, default `top_start`) | Its children on top of each other, first at the back. It is as big as its biggest child. |
| `Wrap` | `children`, `gap`, `runGap`, `align` (`start` · `center` · `end`) | Children left to right, flowing onto the next line. |
| `Progress` | `value` (0 to 1), `color` (default `accent`), `track` (colour, default `chip`), `height` (default 6) | A rounded bar. |
| `Avatar` | `src`, `text` (shown when there is no image, its first two letters), `size` (default 40), `color` | A round image. |

A new common property, `position` (the nine alignment values), places a block inside the
`Stack` that holds it. Other parents ignore it. `padding` keeps it off the edge.

### Fields (form cards only)

Every field has:

| Property | Type | Meaning |
|---|---|---|
| `field` | string | Required. The key its value is stored and sent under: `lower_snake_case`, 1 to 40 characters, unique in the card. |
| `label` | value | Required. Always visible above the field (beside a checkbox or switch). |
| `hint` | value | Help under the field. An error takes its place. |
| `value` | literal | What it starts with when the assistant fills nothing in. |
| `checks` | list | See "Checks". |

| Block | Own properties | Value sent |
|---|---|---|
| `TextField` | `input`: `text` (default) · `multiline` · `number` · `email` · `phone`; `placeholder` (a format example, never the label); `maxLength` (1 to 4000, default 500) | A trimmed string; a JSON number for `number`. |
| `Checkbox` | — | `true` / `false` |
| `Switch` | — | `true` / `false` |
| `Select` | `options`: 1 to 50 of `{"value": string, "label": value}`; `multiple` (bool); `look`: `dropdown` (default; opens a list in a bottom sheet) · `list` (radio rows, or checkbox rows when `multiple`) · `chips`; `placeholder` | The option's `value`; a list of them when `multiple`. Never a joined string. |
| `DateField` | `min`, `max`: `YYYY-MM-DD` or `"today"` | `YYYY-MM-DD` |

`input` sets the keyboard and an automatic check: `number` must be a number (a comma or a
point as the decimal mark), `email` must look like an address, `phone` must have 7 to 15
digits once spaces, `+`, dashes and brackets are removed. Phone masks are not in this change.

### Where values live

A field's value is at `/form/<field>` in the card's data. Other blocks read it with the paths
cards already have: `{"path": "/form/name"}`, or `"Hello, {/form/name}"` in a string. They
redraw as the person types.

A value may now also be a comparison, for showing a block only for one answer:

```json
{ "id": "other", "component": "TextField", "field": "other_reason", "label": "Tell us more",
  "visible": { "path": "/form/reason", "equals": "other" } }
```

It gives `true` or `false`. There are no other operators. A field that is hidden, or inside a
hidden block, is not checked and not sent.

### Checks

```json
"checks": [ { "rule": "required" },
            { "rule": "length", "min": 2, "max": 60, "message": { "uz": "…", "ru": "…", "en": "2 to 60 letters" } } ]
```

| `rule` | On | Passes when |
|---|---|---|
| `required` | every field | It has a value. A checkbox or switch must be on. |
| `length` (`min`, `max`) | `TextField` except `number` | The text's length is in range. |
| `range` (`min`, `max`) | `TextField` `number` | The number is in range. |
| `items` (`min`, `max`) | `Select` with `multiple` | That many options are picked. |

`message` is optional. The SDK has its own words for every rule and for the automatic
`number`, `email`, `phone` and date-range checks, in uz, ru and en. An empty optional field
is sent as nothing and only `required` looks at it.

### The submit action

`{"name": "submit"}`, no arguments, only on a `Button`. A form card has exactly one. The
other three actions stay allowed in a form card; `ask` sends its text, which closes the form
like any typed message.

### Theme

One new optional colour token, `error` (default `#FFD64545`, the chat's own red). Fields use
existing tokens: fill `chip`, corner `radius.button`, text `body`, label and hint `caption`
in `muted`, focus outline `accent`. A field is at least 48 px tall.

## A form card on the server

Stored card: `{"tool": "...", "role": "form", "layout": "single", "surface": {...}}`. The
component's kind must be `inline`. Not allowed on a form: `items`, `id`, `max_items`,
`confirm_label`. One form per tool.

New refusals on save and publish (same shape as today's card errors):

| Code | When |
|---|---|
| `form_needs_inline` | The component's kind is not `inline`. |
| `card_form_taken` | The tool already has a form. |
| `form_needs_field` / `form_too_many_fields` | No field, or more than 12. |
| `form_needs_submit` | Not exactly one `Button` with `submit`. |
| `input_needs_form` | A field or `submit` in a result or confirm card. |
| `input_in_repeat` | A field inside a repeated block. |
| `field_taken` | Two fields with the same `field`. |

A field's key is **not** required to be one of the tool's arguments (a form may collect a
date and a time that the model joins into one argument). The builder offers the tool's
arguments as suggestions and notes a key that isn't one.

### Which catalog a card needs

On save the server sets `surface.catalogId` itself: `zehn.basic.v1` when the card uses a new
block, `position`, `submit` or `equals`; otherwise `zehn.basic.v0`. What the client sent is
overwritten. Cards already stored stay `v0`.

At run time `zehn.basic.v1` needs SDK 0.7.0. A caller below it (a missing or malformed
version counts as new, as `frame.py` already does) is treated like this:

- `v1` result cards are left out of `ui__show_card`, so the model answers in text.
- No forms are offered.
- A `v1` confirm card falls back to the default confirm template.
- Reading history skips `v1` cards the same way.

The cached tool and system text gains this level in its cache key.

Also fixed here: the schema refuses `{"path": "...", "format": "..."}` although the SDK has
drawn it since 0.5.0. It is accepted from now on, in both catalogs.

## A form in a turn

### Showing it

When the caller can draw forms and the spec has at least one, the model gets a second tool
beside `ui__show_card`. Apps without forms keep byte-identical tool and system text.

```json
{ "name": "ui__show_form",
  "input_schema": { "type": "object", "additionalProperties": false, "required": ["form"],
    "properties": { "form": { "enum": ["book_table"] }, "values": { "type": "object" } } } }
```

Its description lists each form as `- {name}: before {tool}. {description} Fields: …` with
each field's key and kind. The system prompt gains a short paragraph: show a tool's form when
several of its arguments are missing instead of asking one by one, fill in what is already
known, never ask again for what the person gave.

`values` is the prefill, by field key. A key the form doesn't have, or a value of the wrong
type, is dropped without refusing the call. The model reads back a fixed line saying the form
is shown and not answered yet, writes its sentence, and the turn ends `done`. Nothing pauses.

The phone gets a new event (older SDKs ignore event types they don't know):

```
event: form
data: {"call_id":"…","form_id":"<uuid>","component":"book_table","tool":"bookings.create",
       "surface":{…},"props":{"form":{"date":"2026-11-14"}}}
```

The server stores a row first, as it does for a confirm card: `form_id` (made from the turn
and call ids), conversation, turn, `call_id`, component, tool, prefill, `status`
(`pending` · `submitted` · `dismissed`), `values`, the turn that decided it, and when.

### Sending the answers

`POST /v1/turns` with a third input shape. It needs a `conversation_id` and counts as a turn
for the rate limits, like a tap on a confirm card.

```json
{ "conversation_id": "…", "language": "uz",
  "input": { "type": "form", "form_id": "<uuid>", "values": { "name": "Ali", "guests": 2 } } }
```

The server, in order:

1. Finds the form: `404 form_not_found`; `409 form_used` (with `params.status`) unless it is
   `pending`.
2. Checks `values` against the template in the conversation's spec version: no unknown keys,
   right types, the automatic checks, the listed checks, skipping fields that are hidden for
   these values. `values` is at most 32 KB. A failure is `422 form_invalid` with
   `params.errors: [{"field": "phone", "rule": "phone"}]`, and the form stays `pending`.
3. Marks it `submitted` for this turn and stores the values. A second submit while that turn
   runs gets `409 form_used`.
4. Starts the turn. The user message holds only the note, which now ends with: the person
   filled in form `{component}` for `{tool}`, their answers as JSON, use them as that tool's
   arguments and ask only for what is still missing.

**A form is answered only when that turn ends `done`.** If the turn can't start, or starts
and fails for any reason (the phone dropped the stream, the model was down, an internal
error), the form is `pending` again and can be sent again. This is unlike a confirm tap,
which is burnt on failure so a write is never sent twice: sending a form writes nothing, and
a writing tool still asks through its confirm card. How the server gets there (undoing the
claim when the turn fails, or looking at the deciding turn's outcome when the next submit
arrives) is the builder's choice; one form must never feed two turns that both finish.

**Any** new turn in a conversation (typed, spoken, a confirm tap, another form) marks its
other `pending` forms `dismissed`. So does the failure of the turn that showed a form: that
turn is not remembered, so its form would be missing from history, and trying the message
again brings a fresh one.

**The server does not compare the tool's arguments with the form's values.** The SDK, the
server and the note pass every value on exactly as typed (text trimmed, nothing else). From
there the model writes the tool's arguments, and may reshape them: a date and a time joined
into one argument, spaces taken out of a phone number. For a writing tool the confirm card
shows the final arguments before anything is sent.

### History and the console's conversation view

`GET /v1/conversations/{id}` returns a `type: "form"` item with `call_id`, `form_id`,
`component`, `surface`, `status` and `props` (`{"form": …}` holding the sent values when
submitted, else the prefill). A `pending` form in a reopened conversation can still be
answered. The submit's own user message draws no bubble, as with confirm taps.

The console's conversation view gets the same item and draws it read-only with its status.
Follow-up suggestions must not be given the raw note as "the question" for a form turn.

## SDK

- **Where typed values are kept.** In the chat's cubit, per `form_id`, not in the widgets.
  They survive a card scrolling out of the list, the switch to voice or history and back,
  and closing and reopening the chat. They do not survive the app being killed.
- **No lost focus.** Today every keystroke in the chat's own input rebuilds the sheet and
  re-parses every card. A template is parsed once per chat item, a field's widget is keyed
  by form and block id, and typing in a field redraws only its card. Typing in a field must
  not trigger the chat's jump to the bottom.
- **Keyboard.** The keyboard matches `input`. The action key is Next on every text field but
  the last, Done on the last; `multiline` keeps its new-line key. The focused field scrolls
  clear of the keyboard.
- **Errors.** A field shows its error once it has lost focus or Send was tapped, then
  updates as the person types. Send stays enabled; a failed Send scrolls to and focuses the
  first failing field. Errors sit under the field, in `error`, and are announced.
- **Send.** Disabled while the chat is busy, like Confirm. On tap: check, then `sending`
  (fields off, progress on the button), then the turn. `turn.started` draws it as sent.
  - Refused before that: `form_invalid` puts the errors on their fields; `form_used` takes
    the status the server names.
  - Any other failure, before or after `turn.started` (no network, a timeout, the turn
    ending in an error): back to `pending` with every value kept and a "Not sent. Try
    again." line. The chat's own Retry sends the same form input again.
  - The conversation can't go on (`conversation_full`, `conversation_spec_changed`,
    `conversation_not_found`): a form can't be carried into a new conversation, so it locks
    as **Not answered**, still showing what was typed.
  - The turn that showed the form ends in an error: the form locks as **Not answered**.
- **Read-only drawing** (submitted, dismissed, and history): each field is its label and
  value as text, "—" when empty; the submit button is replaced by **Sent** or
  **Not answered**. The same template is used; there is no second template to write.
- **A block it doesn't know** in a form card: the SDK draws none of the form and shows
  "Update the app to answer this." A form that silently lost a field must not be sendable.
- **Accessibility.** Fields carry their label and error for screen readers, and `Button`
  blocks are announced as buttons. The renderer has no semantics at all today.
- `ZiSurfaceView` stays public; drawn without a form it shows fields read-only.
- `catalog/zehn.basic.json` keeps its path (the analyzer downloads it by that path) and
  becomes `zehn.basic.v1`. It also gains what the console needs to build a property panel:
  each property's type, allowed values and range, each block's required property and its
  group (layout, content, field). `catalog_test.dart` keeps proving the file matches the
  renderer.
- The mock server gets a form conversation.

## Console

The builder replaces the template text box in the card editor. The fields above it (tool,
role, layout and so on) stay, with `form` as a third role and a form starter template.

**Three panes, with the JSON on a tab.** This is the layout of the mockup the user agreed to
(shown in conversation on 2026-11-12, kept nowhere else; it fixed nothing beyond this):

```
┌ Blocks ───────────┐ ┌ Preview ─────────────┐ ┌ Properties ──────┐
│ Layout   Column … │ │      ┌ phone ─────┐  │ │ Text field       │
│ Content  Text …   │ │      │ the card   │  │ │ Saved as  [    ] │
│ Fields   Text f.… │ │      │ as the SDK │  │ │ Placeholder [  ] │
├ Structure ────────┤ │      │ draws it   │  │ │ Input     [ v ]  │
│ Column            │ │      └────────────┘  │ │ Longest answer   │
│  ├ Header         │ │  Select | Try        │ │ [x] Must be      │
│  ├ Text field ●   │ │  language, sample    │ │     filled in    │
│  └ Button         │ │                      │ │                  │
└───────────────────┘ └──────────────────────┘ └──────────────────┘
```

How this folds on narrower screens, next to the tool, role and layout fields, is the
builder's choice.

- **Blocks** (left, top): every block as a chip, grouped as layout, content and fields
  (fields only in a form card), with a filter box. Clicking one adds it inside the selected
  container, or after the selected block. There is no dragging onto the phone.
- **Structure** (left, below): the card as a tree. Drag a row to reorder or nest it; a line means
  "between", a highlighted row means "inside". Each row has duplicate, delete, move up, move
  down, move in and move out, so nothing needs a mouse. Blocks that nothing points at (legal
  in hand-written JSON) are listed under "Not attached".
- **Preview** (middle): the existing phone preview, drawn by `CardView`. In *Select* mode
  hovering outlines a block and a click selects it, in step with the tree; a repeated block
  selects its template. In *Try* mode fields work, checks run, and Send shows the JSON that
  would be sent. Language and sample data controls stay.
- **Properties** (right): built from the catalog file for the selected block, grouped as
  content, layout, look, action, field and visibility. A text value has three modes: one
  text, per language, or from data (picked from the sample data's paths). Colours and radii
  are token swatches with a custom value. Options and checks are small row editors. For a
  field, the key is picked from the tool's arguments or typed.
- **JSON** tab: the same card as text. It is applied when it parses, as one undo step. It is
  never reformatted while being typed, and keys the builder doesn't know (`_note`) survive
  every edit.

**Rules the block operations enforce** (their own module, unit-tested first): a `Box` holds
one child; a block can't move into itself; depth 32; 100 blocks; 16 KB counted in UTF-8
bytes; duplicating re-ids the whole subtree; renaming an id rewrites every reference to it;
deleting a block deletes what only it held.

**Undo and redo:** whole-card snapshots, typing merged into one step per property.
Ctrl/Cmd+Z works outside text inputs and leaves a text input's own undo alone.

**Problems:** the client's checks and the server's (`/cards/check` and the save refusal) are
merged into one list tied to blocks: a dot on the tree row and the message under the
property. Today the server's list replaces the client's and the preview's is separate.

**Also in the console:**

- `CardView` draws the new blocks and the read-only form, applies value formats (it ignores
  them today) and `equals`.
- The vendored catalog file replaces the hand-kept `BLOCK_KEYS`, `CHOICES` and `RANGES`,
  whose allowed values are keyed by property name across all blocks.
- The theme editor gets the `error` colour.
- Mock mode learns the new blocks, and `Icon`, which it is missing today.
- Every new string exists in uz, ru and en.
- New packages: `@headless-tree/core` and `@headless-tree/react` 1.8.0 (MIT, any React),
  and `vitest` for the first unit tests, run in CI beside lint and build.

## Backend, beyond the above

- `spec.schema.json` and `cards/surface.py` learn the new blocks, properties, `submit`,
  `equals` and the `error` token. A copy of the SDK's catalog file sits in the tests, and a
  test proves the server's lists match it.
- New value-bearing properties (`hint`, `placeholder`, option labels, check messages) are
  added to the data-path walk.
- The analyzer may use the four layout and display blocks (it already keeps only what the
  app's SDK build has). It does not draft forms.
- The graph version is raised, since a turn can now start from a form.
- `docs/sdk.md`, `docs/turns.md`, both copies of `DYNAMIC_CARDS.md` and
  `MOBILE_INTEGRATION.md` describe the new blocks, event and input.

## Not in this change

- Sending cards from the console, a badge on the bubble, a view of sent data.
- Forms in a sheet or on a full page; forms with several steps.
- Regular-expression checks, phone masks, secret fields, values that bypass the model,
  slider, time, file upload, options loaded from data or from the customer's API.
- Fields in result or confirm cards (for example editing a confirm card's arguments).
- A server check that the tool's arguments match what was typed.
- The analyzer drafting forms.
- Dragging onto the phone preview; free placement on a canvas.
- A backend checker generated from the catalog file; its checks stay hand-written.
- A stable user identity. Builds that pin a spec version are still offered no cards.

## What would make this a failure

- A person fills a form and loses it: to the keyboard, to scrolling, to closing the chat.
- The SDK, the server or the note changes a typed value on its way to the model, or a hidden
  field's value is sent.
- An older app shows half a form.
- The builder rewrites or drops parts of a card it doesn't understand.
- The console preview and the phone draw the same card differently.

## Done means

- SDK 0.7.0 draws all nine new blocks; a form can be filled, checked, sent, reopened from
  history, and answered once only; widget tests cover each block and each state.
- The server accepts and checks form cards, offers them only to 0.7.0 and newer, takes the
  `form` input, re-checks the values and stores them; protocol fixtures cover showing,
  sending, a refused send and a dismissed form.
- In the console a developer builds a form card without touching JSON, sees it as the phone
  draws it, tries it, and saves it; the block operations have unit tests; lint and build
  pass.
- A card saved before this change opens in the builder and saves back byte for byte when
  nothing was edited.
