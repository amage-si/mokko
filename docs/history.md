# Validation history

A short record of how Mokko (with Tessra and Kairo) was validated during its
first development round, October 2026, with Bend 2.0.35 on Linux
(Hyprland/Wayland with XWayland, Ryzen 7 5800H, AMD integrated and NVIDIA RTX
3050 Mobile graphics; the demo used the CPU path only).

## Native suites

Builds ran one at a time with reduced priority. All passed with exit 0:
20 Tessra checks, 41 Kairo checks, 11 Kairo adapter checks, 14 Mokko component
checks, and 5 Mokko model checks with Liberation Sans, 91 in total.

## Window runs

A first session, with an earlier build, showed hover, pressed, the focus ring,
a release outside keeping 0, a click giving 1, Space with four autorepeat
release/press pairs giving only 2, and Enter giving 3. Redraws then took
18–33 ms; a later build reused cached text metrics and brought them to
1–2 ms without a counter change and 7–9 ms with one.

A second scripted run of that later build did **not** pass: the counter was
already at 17 before the script's first event, and the start-state assertion
stopped it. The source of those inputs was not instrumented, and the app did
not crash.

A final single run of the same unchanged binary was then instrumented end to
end. An XRecord observer was armed before launch and persisted only events for
the new window; 31 synthetic events were sent with `XSendEvent` to that window
alone, without global input injection. All 31 arrived and matched in type,
detail, coordinates, and state; the only extra event was the system `FocusIn`
before the script. The run took 5.25 s and covered:

| Step | Result |
| --- | --- |
| Open | 0, button not focused |
| Hover, press | Hover and pressed colors, still 0 |
| Drag out and release | Still 0 |
| Click inside | 1 |
| Click outside, then Tab | Focus ring back, still 1 |
| Space with 4 autorepeat pairs | Pressed, still 1, no redraw on repeats |
| Release Space | Exactly 2 |
| Enter | Exactly 3 |

Duplicate mouse, Space, and Enter releases and three no-change moves produced
no redraw. The window closed on `WM_DELETE_WINDOW` with exit 0 and no window
left behind. Thirteen captures were checked by OCR, sampled colors, and visual
inspection; `docs/preview.png` is the final one. Binary and source hashes were
identical before and after the run. The resident set was about 27 MB while the
runtime reserved about 10 GB of virtual address space, which is not RAM use.

These were synthetic events targeted at the window, not a test with a physical
keyboard. Real window resize, window blur, IME, GPU presentation, and assistive
technology were not part of this validation.

## Compiler aborts in the same round

Four Bend compiler processes aborted (SIGABRT) during the round; their command
lines were Chromi and Splina builds, not Tessra, Kairo, or Mokko. No abort was
observed in this library's builds or runs. Build guidance from that incident:
build one target at a time, do not set virtual-memory limits on the compiler
or runtime, keep crash reports, and investigate before retrying.
