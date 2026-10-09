# Mokko API

Mokko's components depend on `Base`, Tessra's `geometry.bend`, and Kairo's
`types.bend`, `dirty.bend`, and `nodes.bend`. Import paths are relative to the
calling file. An application next to the `Mokko`, `Kairo`, and `Tessra`
directories uses:

```bend
import Base
import ./Mokko/main.bend as M
import ./Kairo/main.bend as K
import ./Kairo/types.bend as T
import ./Tessra/geometry.bend as G
```

## Components (`main.bend`)

```bend
Metrics{width: F32, height: F32, ascent: F32}

Primitive:
  Fill{rect: G.Rect, rgba: U32}
  Stroke{rect: G.Rect, width: F32, rgba: U32}
  TextRun{x: F32, top: F32, baseline: F32, label: String, size: F32, clip: G.Rect, rgba: U32}

SemanticAction: Activate{}
Semantic{id: U32, role: T.Role, label: String, bounds: G.Rect, enabled: Bool,
  focused: Bool, pressed: Bool, actions: +List<SemanticAction>}
View{primitives: +List<Primitive>, semantic: Semantic}
Theme{normal, hover, pressed, disabled, text, muted, focus: U32}
```

| Function | Contract |
| --- | --- |
| `button_node(id, bounds, label, enabled)` | A focusable Kairo button node. |
| `text_node(id, bounds, label)` | A non-focusable Kairo text node. |
| `button_size(metrics)` | `(width + 32, max(44, height + 20))`. |
| `text_size(metrics)` | `(width, height)`. |
| `theme()` | Default colors: `#245CCE`, `#3170E6` hover, `#183F96` pressed, `#364152` disabled, white text, `#AAB3C2` muted, `#A4C8FF` focus; alpha `FF`. |
| `button(node, state, metrics, size, theme)` | `Result<&2, &2, String, View>`. |
| `button_styled(node, state, metrics, size, look)` | The same checks, order and semantic, drawn with a resolved `ButtonLook` (used by `anim.bend`). |
| `text(node, state, metrics, size, rgba)` | `Result<&2, &2, String, View>`. |

### Button output

1. `Fill` of the bounds: disabled color if disabled; otherwise pressed, hover,
   or normal, from Kairo's `pressed`/`hovered` projections.
   (`button_styled`: the bounds inset by `look.sink`, in `look.bg`.)
2. When focused, a 2-unit `Stroke` inset by 2 units, so it stays inside the
   bounds and inside Kairo's dirty region for that control.
   (`button_styled`: when `look.ring`, inset by `look.ring_inset`, in
   `look.ring_rgba`.)
3. `TextRun` centered from the metrics, clipped to the bounds inset by
   8 x 4 units; text color, or muted when disabled.

`ButtonLook{bg, fg, sink: F32, ring: Bool, ring_inset: F32, ring_rgba}` is
the resolved look; `button` uses `ButtonLook{state colour, text or muted,
0.0, focused, 2.0, theme.focus}`.

### Text output

One `TextRun` at the bounds' top-left with `baseline = top + ascent`, clipped
to the bounds.

### Validation

`button` and `text` fail with a message when the node is invalid for Kairo, the
role is wrong (a button node for `text`, a text node for `button`), metrics are
negative or non-finite, the ascent exceeds the height, or the font size is
outside `(0, 256]`. The metrics must be measurements of that label at that
size; Mokko cannot check that they match the text.

### Units and colors

Positions are logical units, origin top left. The host converts to physical
pixels. `TextRun.baseline` is absolute; a text layout from Syllo/Dithra starts
at `(x, top)`. Colors are RGBA8 `0xRRGGBBAA`, straight alpha, sRGB.

## Text field (`field.bend`)

The field needs Syllo and Runika (and Splina) beside Mokko, plus Kairo's
`edit.bend`. It imports them as `../Kairo/edit.bend as KE` and
`../Syllo/caret.bend as SC`.

```bend
FieldTheme{box, border, focus, text, placeholder, selection, caret, error: U32}
Field{edit: KE.Edit, stops: List<&2, SC.Stop>, line: Metrics, scroll: F32,
  refused: Maybe<&2, String>}
Fed{field: Field, dirty: Bool, request: KE.Request}
EditState{id: U32, text: String, caret: U32, anchor: U32, placeholder: String,
  origin_x: F32, origin_y: F32, line_height: F32, stops: List<&2, SC.Stop>}
FieldView{view: View, edit: EditState}
```

| Function | Contract |
| --- | --- |
| `field_node(id, bounds, name)` | A focusable, enabled Kairo node with `EditRole`; `name` is the accessible name, not the text. |
| `field_size(line_height, width)` | `(width, max(44, line_height + 20))`. |
| `field_theme()` | Box `#1C2433`, border `#4A5568`, focus `#A4C8FF`, text `#EDF2FA`, placeholder `#7D8796`, selection `#2F5DB3`, caret `#FFFFFF`, error `#F05252`; alpha `FF`. |
| `field(font, size, text)` | `Result<&2, &2, String, Field>` with the caret at the end. Fails with the message an edit would show (control, line break, more than 256 scalars, or a character Syllo cannot lay out). |
| `feed(font, size, bounds, id, field, action)` | `Fed` after one Kairo action. Only `TextDelivered`, `EditRequested`, and `EditPointer` for `id` change the field; anything else returns it unchanged with `dirty` False. |
| `view(node, state, field, size, theme, placeholder)` | `Result<&2, &2, String, FieldView>`. Fails when the node is invalid or not `EditRole`, or the size is outside `(0, 256]`. |
| `view_styled(node, state, field, size, theme, placeholder, style)` | The same, drawn with a resolved `FieldStyle` (used by `anim.bend`). |
| `look_style(FieldLook{focused, refused}, theme)` | The static style `view` uses. |
| `text_of(field)`, `edit_of(field)`, `message(field)` | The text, the `KE.Edit`, and the refusal message (`None` after an accepted edit). |
| `hex(scalar)` | `"U+20AC"`: at least four upper-case hex digits. |

`font` and `size` must be the same in `field`, `feed`, and `view`, and
`bounds` must be the node's bounds (after a relayout, the new ones).

### Feeding

1. `TextDelivered{id, text}` inserts with `KE.insert` (it replaces the
   selection), `EditRequested{id, command}` applies `KE.apply`.
2. When the text changed, the candidate is laid out with Syllo on one line
   (`S.layout` with width 1,000,000, then `SC.stops`). The field commits the
   new edit and its stops only if both succeed.
3. A refusal keeps the previous text, caret, and selection, sets `refused` to
   a message, drops the request, and reports `dirty`. Messages are ASCII:
   `Character U+2615 cannot be displayed` (from `SC.unsupported`),
   `Control character U+0009 is not allowed`, `Line breaks are not allowed in
   this field`, `The text is limited to 256 characters`. The next accepted
   action clears it.
4. `EditPointer{id, x, y, drag}` maps `x` to a stop with
   `SC.hit(stops, x - (bounds.x + 12) + scroll)` and calls `KE.place` with
   `extend = drag`. A drag outside the bounds keeps extending and scrolls.
5. The scroll is clamped to `[0, text width - area width]`, then moved just
   enough to keep the caret inside the text area (bounds inset 12 left and
   right).

`dirty` is True when the text, caret, anchor, scroll, or refusal changed.
Focus, hover, and capture changes come from Kairo's own dirty regions.
`request` is `KE.NoRequest`, `KE.CopyText{text}` (Copy, Cut), or
`KE.PasteText` (Paste). The host answers a paste by sending the clipboard text
as Kairo `TextInput`, which reaches the field as `TextDelivered` and is checked
like typing.

Cost on this machine (`examples/field_bench.bend`, 256-scalar Portuguese line
at 20 px, one thread): a keystroke that changes the text takes about 66 µs
(Syllo layout and stops dominate), a caret move about 2 µs, and a focused
`view` about 8 µs.

### Field output

The text area is the bounds inset by 12 units left and right; the line is
centred vertically. Primitives, in order:

1. `Fill` of the bounds (box).
2. `Stroke` of the bounds, 1 unit: border colour, or the error colour while
   `refused` is set.
3. `Fill` of the selection band, cut to the text area (focused only, non-empty
   selection only).
4. `TextRun` of the text at `x = text area left - scroll`, or the placeholder
   in its colour when the text is empty, clipped to the bounds inset 12 x 2.
5. `Fill` of the 2-unit caret centred on the caret x, one line high (focused
   only).
6. `Stroke` of the focus ring, 2 units, inset 2 (focused only).

`FieldStyle{focused, border, ring: Bool, ring_inset: F32, ring_rgba,
caret_rgba}` resolves the look: `focused` shows items 3 and 5, `border`
colours item 2, `ring` shows item 6 at `ring_inset` in `ring_rgba`, and
`caret_rgba` colours the caret. `view` uses `FieldStyle{focused, error or
border, focused, 2.0, theme.focus, theme.caret}`.

Fills and strokes are square: hosts must not round them. Kairo marks a
captured control as pressed; the field draws no pressed or hover state.

The semantic is `Semantic{id, EditRole, name, bounds, enabled, focused,
pressed = False, actions = []}`, the same shape as the other components.
`EditState` carries what an accessibility bridge needs: the text, caret and
anchor (scalar indices), and `origin_x + stop.x` is a stop's screen x
(`origin_x` includes the scroll).

## Animated transitions (`anim.bend`)

`anim.bend` animates the button and the field with
[Kinera](https://github.com/amage-si/kinera) motions and Chromi's OKLab mixing. It imports
`../Kinera/main.bend` and `../Chromi/mix.bend` (which needs only Chromi's
`color.bend`) beside the field's imports. The static `button` and `view`
are unchanged.

```bend
Prefs{reduce: Bool, blink: Bool}                 # prefs() = Prefs{False, True}
ButtonAnim{hover: KN.Motion, press: KN.Motion, focus: KN.Motion}
FieldAnim{focus: KN.Motion, error: KN.Motion, blink: Blink}
Blink{since: U32, caret: U32, anchor: U32, count: U32, focused: Bool}
```

The host keeps one `ButtonAnim` per button id and one `FieldAnim` per field
id (next to its `Field`). Clocks are `U32` milliseconds of one monotonic
clock (`IO.now()`, Ankra's frame time); `frame_ms` is the frame interval the
host draws at (8 at 120 Hz).

| Function | Contract |
| --- | --- |
| `button_anim()`, `field_anim()` | At rest: not hovered, pressed, focused or refused. |
| `button_step(anim, prefs, state, id, now)` | Retargets each property to Kairo's `hovered`, `pressed` and `focused` for `id` at `now`. Idempotent while the state holds: call it every frame, or after every dispatch. |
| `field_step(anim, prefs, state, id, field, now)` | The focus ring to `focused`, the border to `message(field)` being set, and the blink clock restarted when the caret, anchor, scalar count or focus changed. |
| `button(node, state, metrics, size, theme, anim, now)` | `M.button` drawn at `now`: same checks, primitive kinds and order, and semantic. |
| `field_view(node, state, field, size, theme, placeholder, anim, prefs, now)` | `FL.view` drawn at `now`: same checks, primitive kinds and order, semantic and `EditState`. |
| `button_deadline(anim, now, frame_ms)`, `field_deadline(anim, prefs, now, frame_ms)` | `Maybe<&2, U32>`: when to draw next. `None`: nothing moves, no more frames. |
| `sooner(now, a, b)` | The earlier of two deadlines (wrap-aware); `None` when both are. |
| `button_animating(anim, now)`, `field_animating(anim, prefs, now)` | A deadline is due. |

### Per frame

```bend
b2 = A.button_step(b, prefs, kairo, button_id, now)
f2 = A.field_step(fa, prefs, kairo, field_id, field, now)
button_view = A.button(button_node, kairo, metrics, 18.0, M.theme(), b2, now)
field_view  = A.field_view(field_node, kairo, field, 20.0, FL.field_theme(), placeholder, f2, prefs, now)
next = A.sooner(now, A.button_deadline(b2, now, 8), A.field_deadline(f2, prefs, now, 8))
# Some{t}: wake at t (a frame while something moves, a timer while the
# caret waits); None: sleep until the next input.
```

Keep the stepped states (`b2`, `f2`) for the next frame. Step after every
Kairo dispatch too, at the input's time, so a change starts when it
happened. Every animated look stays inside the node's bounds (the sink and
the ring are insets), so while a control's deadline is `Some`, redrawing its
bounds is the whole damage; Kairo needs no extra region.

### What moves

| Property | Curve | Asks for frames |
| --- | --- | --- |
| Button fill, normal to hover | critical spring, 200 ms response (90% at ~125 ms) | ~255 ms |
| Button fill to pressed, and the 1-unit sink | 70 ms ease-out tween | 70 ms |
| Release back | spring, 250 ms response, ratio 0.8 | ~310 ms |
| Focus ring (button and field): opacity 0 to 1, inset 6 to 2 | 150 ms ease-out tween | 150 ms |
| Field border to the error colour | 150 ms ease-out tween | 150 ms |

The fill is `mix_oklab(mix_oklab(normal, hover, h), pressed, p)` (disabled:
the disabled colour); the border is `mix_oklab(border, error, e)`; the ring's
alpha is the theme's scaled by its opacity. Settled, the animated looks equal
the static ones, except that a held press keeps the 1-unit sink.

Each property is a Kinera `Motion`, retargeted from its current value and
velocity, so hover-out during the hover-in turns back with no jump; a
property that changes curve (press in, release out) keeps value and velocity
across the change. Rest thresholds are 0.004 of the 0..1 factor (at most one
colour byte), not Kinera's 0.001, which would add ~40 frames of invisible
change.

### Caret blink

The caret is solid for 500 ms after any edit, caret move or focus change,
then blinks in a 1 s cycle: a 150 ms ease-in-out fade out, hidden to 500 ms,
a 150 ms fade in, shown to 1000 ms. Frames are due only during the fades;
the plateaus ask for a timer at the next fade. After ten cycles (10.5 s
without an edit) the caret stays solid and the field needs no frames, as
GTK's blink timeout. An unfocused window (Kairo's `WindowFocus{False}`)
unfocuses the field: the caret is not drawn and the blink stops. `Prefs.blink`
False keeps the caret solid.

### Reduce motion

`Prefs.reduce` True: every step lands at its target at once (no frames) and
the caret is solid.

### Cost

`examples/anim_bench.bend` (Bend 2.0.36, `--threads 2`, this Linux machine,
100,000 calls at clocks inside the transitions, less a ~0.37 µs loop
baseline): `button_step` ~0.1 µs (0.15 µs when it retargets), animated
button view ~0.47 µs, `field_step` ~0.06 µs, animated field view ~0.48 µs
(an "Olá" field), both deadlines ~0.03 µs. A whole frame of the demo's two
controls (both steps, both views, the combined deadline) is about 1.3 µs.

## Counter model (`demo.bend`)

The demo needs Syllo and Runika (and Splina, which Runika imports) beside
Mokko. It is pure: no window, renderer, or IO.

| Function | Contract |
| --- | --- |
| `init(font, width, height)` | `Result<&2, &2, String, Model>`: measures title, button, and status with Syllo, lays them out with Tessra, and builds the Kairo state. |
| `update(model, input, font)` | `Result<&2, &2, String, Update>` for one Kairo input. |
| `view(model, font)` | `Result<&2, &2, String, Frame>`. |

`Model{runtime, clicks: Nat, overflow}` counts with `Nat`, so it never wraps.
`Update{model, dirty, layout, actions}`: each `Activated` increments the count
once, updates the status label in Kairo, and dirties it. Do not call `view`
when `dirty` is empty and `layout` is false, or after close. `Resize`
recomputes the layout. `Frame{primitives, semantics, overflow}` is the
renderer's input. Viewing after close, or after the three known nodes were
removed, is an explicit error.

## Window host (`visual.bend` and `chromi_text.bend`)

`visual.bend` opens a 480x320 window at scale 1.0 with `Ankra.run`, normalizes
events with `Kairo/base_adapter` (also on empty polls), draws `Fill` and
`Stroke` with Chromi, and draws text through `chromi_text.bend`: Syllo layout,
Dithra coverage masks, and `Chromi.blit_mask`. The title and button text and
their metrics are rasterized once and cached; the status text is redone when
the count changes. The window closes on a close request or after 18,000 polls.

## Ownership and scope

Views are plain data built per call. The host owns the window, image, font, and
caches. Mokko has no AT-SPI code; `Semantic` is the contract consumed by Auvia.
The API is not stable yet.
