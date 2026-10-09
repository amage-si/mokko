# Changelog

All notable changes to Mokko are recorded here. Mokko follows
[semantic versioning](https://semver.org) in its 0.x form: while the API is
experimental, a minor version (0.2.0) may change it in breaking ways and a
patch version (0.1.1) only fixes. Mokko is built from source together with its
sibling AMAGE libraries; the set of versions tested together is listed in
[eco-build's releases](https://github.com/amage-si/eco-build/tree/main/releases).

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
