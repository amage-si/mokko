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
| `text(node, state, metrics, size, rgba)` | `Result<&2, &2, String, View>`. |

### Button output

1. `Fill` of the bounds: disabled color if disabled; otherwise pressed, hover,
   or normal, from Kairo's `pressed`/`hovered` projections.
2. When focused, a 2-unit `Stroke` inset by 2 units, so it stays inside the
   bounds and inside Kairo's dirty region for that control.
3. `TextRun` centered from the metrics, clipped to the bounds inset by
   8 x 4 units; text color, or muted when disabled.

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
