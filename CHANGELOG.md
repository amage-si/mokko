# Changelog

All notable changes to Mokko are recorded here. Mokko follows
[semantic versioning](https://semver.org) in its 0.x form: while the API is
experimental, a minor version (0.2.0) may change it in breaking ways and a
patch version (0.1.1) only fixes. Mokko is built from source together with its
sibling AMAGE libraries; the set of versions tested together is listed in
[eco-build's releases](https://github.com/amage-si/eco-build/tree/main/releases).

## [Unreleased]

### Added

- `anim.bend`: animated transitions on Kinera motions, kept by the host per
  control (`ButtonAnim`, `FieldAnim`) and stepped with Kairo's state at a
  frame clock. Button fill fades between normal, hover and pressed in OKLab
  (Chromi's `mix_oklab`), with mid-flight reversals that keep value and
  velocity; a 1-unit press sink with a spring release; focus rings (button
  and field) that fade and grow in; the field border fading to the error
  colour; a caret blink with fades, solid while typing, stopping after ten
  cycles, optional, and off in an unfocused window. `Prefs{reduce, blink}`:
  reduce motion makes everything instant. `button_deadline`,
  `field_deadline` and `sooner` tell the host when to draw next, `None` once
  nothing moves.
- `button_styled` with `ButtonLook`, and `view_styled` with `FieldStyle` and
  `look_style`: the static views drawn with a resolved look. `button` and
  `view` now go through them, with unchanged output.
- `anim_tests.bend` (22 checks), `examples/anim_render.bend` (the filmstrip
  in `docs/anim-filmstrip.png`) and `examples/anim_bench.bend` (~1.3 µs per
  frame for the demo's button and field).

## [0.1.0] - 2026-10-09

First tagged release, tested with Bend 2.0.35 on Linux (X11/XWayland) as part
of AMAGE Eco 0.1.0.

### Included

- `text` and `button` components with states, focus ring, Kairo nodes and
  Tessra sizes.
- `field`: a single-line editable text field fed by Kairo actions, laid out
  with Syllo, with selection, scrolling, clipboard requests and whole-edit
  refusal of text the font cannot show.
- `Semantic` records for accessibility, published by Auvia.
- The counter model (`demo.bend`) and its window host (`visual.bend`).
- 14 native, 5 demo and 26 field checks.

[0.1.0]: https://github.com/amage-si/mokko/releases/tag/v0.1.0
