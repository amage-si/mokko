# Contributing to Mokko

Use Bend 2.0.35 for the current baseline. Read `bend guide` before editing Bend
and keep project text in English. Library implementation belongs in Bend; the
official runtime and operating system remain external dependencies.

## Validation

Clone the sibling repositories beside this directory with capitalized names
(see the README table): Tessra and Kairo for the components; Syllo, Runika, and
Splina for the model tests; Chromi, Dithra, and Ankra for the window demo. The
model tests and the demo read Liberation Sans from
`/usr/share/fonts/liberation/LiberationSans-Regular.ttf`.

From the Mokko repository root:

```sh
export BEND_NO_TELEMETRY=1
mkdir -p build
bend main.bend --check-only
bend tests.bend -o build/tests
./build/tests --threads 2 --gpu off
bend examples/button.bend -o build/button
./build/button --threads 2 --gpu off
bend demo_tests.bend -o build/demo_tests
./build/demo_tests --threads 2 --gpu off
bend visual.bend -o build/visual
bend field_tests.bend -o build/field_tests
./build/field_tests --threads 2 --gpu off
bend examples/field.bend -o build/field
./build/field --threads 2 --gpu off
```

When a change affects visible behavior, run `./build/visual --threads 2 --gpu off`
in an X11/XWayland session. Check hover, press, release outside, click, Tab,
Space with key repeat, Enter, and normal window closure. A successful build
alone does not validate the user experience. The other checks need no display.

Build one target at a time. The window demo is the largest graph here; the
native Bend runtime reserves substantial virtual address space, and a
virtual-memory limit is not a resident-memory limit. Preserve crash evidence
and investigate before repeating a failed compiler invocation.

## Changes

Keep the API small and the output declarative. Add a focused regression check
when behavior changes, update [docs/api.md](docs/api.md), and report what was
actually validated. Distinguish a skipped redraw from no presentation: the
official runtime keeps presenting and polling.

Use English commit messages that explain the result. Do not commit `build/`,
generated C, logs, crash dumps, captures with other windows, credentials, or
machine-specific paths. Do not publish BendHub packages or create releases as
a side effect of validation.

Compatibility work follows concrete Linux progress. New components need
explicit implementations, semantics, and their own validation before being
advertised as supported.
