import Base
import ./main.bend as M
import ./field.bend as FL
import ../Kinera/main.bend as KN
import ../Chromi/mix.bend as CM
import ../Kairo/types.bend as K
import ../Kairo/dirty.bend as D
import ../Kairo/edit.bend as KE

# Animated transitions for Mokko's button and text field.
#
# The host keeps one small animation state per control (`ButtonAnim`,
# `FieldAnim`), next to the field's `Field`, and per frame, at the frame's
# clock `now` (U32 ms, IO.now()'s clock):
#   1. `button_step` / `field_step` with Kairo's state: each property heads
#      for the value the state asks for (a Kinera retarget, so a reversal
#      mid-flight starts from the current value and velocity, with no jump);
#   2. `button` / `field_view` draw with the animated values, the same
#      primitive kinds in the same order as the static `M.button` and
#      `FL.view`;
#   3. `button_deadline` / `field_deadline` (combine with `sooner`) answer
#      when to draw again; None means nothing moves: no more frames.
# Settled, every animated look equals the static one, except the press sink.
#
# What moves:
#   - button background: normal -> hover -> pressed colours, mixed in OKLab
#     (Chromi's mix_oklab) by a hover and a press factor;
#   - press "sink": the background inset by up to 1 unit, quick in, spring
#     back on release;
#   - focus ring (button and field): opacity 0 -> 1 while its inset goes
#     from 6 to 2 units, 150 ms ease-out;
#   - field border: border -> error colour while an edit is refused;
#   - caret: solid for 500 ms after any edit or caret move, then blinks
#     with 150 ms fades in a 1 s cycle, 10 times, then stays solid (as GTK's
#     10 s blink timeout), so a focused, untouched field returns to idle.
# `Prefs{reduce, blink}`: reduce makes every transition instant and the
# caret solid; blink False keeps the caret solid.

type Prefs is Data:
  Prefs{reduce: Bool, blink: Bool}

def prefs() -> Prefs:
  Prefs{False{}, True{}}

# Curves
# ------
#
# The rest thresholds are visual: 0.004 of a 0..1 mix factor moves a colour
# channel by at most one byte (255 * 0.004 = 1.02 for a full-range channel,
# under 0.4 for the theme's pairs), and 0.004 unit of a 1-unit sink is
# invisible. Kinera's default (0.001) would add ~40 frames of no visible
# change. A rest speed of 1/s leaves the position test in charge.

# Hover: a critically damped spring, 200 ms response (90% at ~125 ms,
# settled at ~240 ms); it keeps its velocity when reversed.
def hover_curve() -> KN.Curve:
  KN.spring(KN.with_rest(KN.responsive(200.0, 1.0), 0.004, 1.0))

# Focus ring and error border: 150 ms ease-out.
def focus_curve() -> KN.Curve:
  KN.tween(150.0, KN.ease_out())

# Press: 70 ms ease-out in, a snappy spring (250 ms response, ratio 0.8)
# back out.
def press_curve() -> KN.Curve:
  KN.tween(70.0, KN.ease_out())

def release_curve() -> KN.Curve:
  KN.spring(KN.with_rest(KN.responsive(250.0, 0.8), 0.004, 1.0))

def sink_depth() -> F32:
  1.0

def flag(b: Bool) -> F32:
  match b:
    case True{}:
      1.0
    case False{}:
      0.0

# Retargeting
# -----------

# `m` already retargeted, under curve `c` from its start on.
def recurve(m: KN.Motion, c: KN.Curve) -> KN.Motion:
  KN.Motion{old, t, s, f, v} = m
  KN.Motion{c, t, s, f, v}

def move.go(same: Bool, m: KN.Motion, c: KN.Curve, +now: U32, +to: F32) -> KN.Motion:
  match same:
    case True{}:
      m
    case False{}:
      recurve(KN.retarget(m, now, to), c)

# Heads `m` for `to` under `c`, from its value and velocity at `now`; the
# same target changes nothing. Reduce: at rest at `to` at once. A finished
# motion collapses to rest (clock-independent).
def move(reduce: Bool, +m: KN.Motion, c: KN.Curve, +now: U32, +to: F32) -> KN.Motion:
  match reduce:
    case True{}:
      KN.rest(c, to)
    case False{}:
      KN.settle(move.go(F32.is_eq(KN.target(m), to), m, c, now, to), now)

# Deadlines
# ---------

# The earlier of two deadlines (wrap-aware, measured from `now`); None
# when neither control needs a frame.
def sooner(+now: U32, a: Maybe<&2, U32>, b: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match a b:
    case None{} None{}:
      None{}
    case None{} Some{y}:
      Some{y}
    case Some{x} None{}:
      Some{x}
    case Some{+x} Some{+y}:
      Some{Bool.pick(U32, U32.is_le((x - now : U32), (y - now : U32)), x, y)}

def is_some(m: Maybe<&2, U32>) -> Bool:
  match m:
    case None{}:
      False{}
    case Some{x}:
      True{}

# Looks
# -----

# `rgba` with its alpha scaled by `o` (clamped to 0..1), rounded.
def fade(+rgba: U32, +o: F32) -> U32:
  +a = U32.to_f32((rgba .&. 255 : U32))
  ((rgba .&. 4294967040 : U32) .|. F32.to_u32(F32.floor((a * KN.clamp(o, 0.0, 1.0) + 0.5 : F32))) : U32)

# The ring grows from 6 units inside the bounds to its resting 2.
def ring_inset(+f: F32) -> F32:
  (2.0 + 4.0 * (1.0 - KN.clamp(f, 0.0, 1.0)) : F32)

# Button
# ------

type ButtonAnim is Data:
  ButtonAnim{hover: KN.Motion, press: KN.Motion, focus: KN.Motion}

# A button at rest: not hovered, not pressed, not focused.
def button_anim() -> ButtonAnim:
  ButtonAnim{KN.rest(hover_curve(), 0.0), KN.rest(release_curve(), 0.0), KN.rest(focus_curve(), 0.0)}

def press_for(down: Bool) -> KN.Curve:
  match down:
    case True{}:
      press_curve()
    case False{}:
      release_curve()

# Retargets the button `id` to Kairo's state at `now`. Call it every frame
# (or after every dispatch); it is idempotent while the state holds.
def button_step(a: ButtonAnim, prefs: Prefs, +state: K.State, +id: U32, +now: U32) -> ButtonAnim:
  ButtonAnim{h, p, f} = a
  Prefs{+reduce, blink} = prefs
  +down = D.pressed(state, id)
  ButtonAnim{move(reduce, h, hover_curve(), now, flag(D.hovered(state, id))), move(reduce, p, press_for(down), now, flag(down)), move(reduce, f, focus_curve(), now, flag(D.focused(state, id)))}

def tint(enabled: Bool, normal: U32, hover: U32, down: U32, disabled: U32, +h: F32, +p: F32) -> U32:
  match enabled:
    case True{}:
      CM.mix_oklab(CM.mix_oklab(normal, hover, h), down, p)
    case False{}:
      disabled

def button_look(+enabled: Bool, colors: M.Theme, a: ButtonAnim, +now: U32) -> M.ButtonLook:
  M.Theme{normal, hover, down, disabled, text, muted, +focus} = colors
  ButtonAnim{hm, pm, fm} = a
  +p = KN.value(pm, now)
  +f = KN.value(fm, now)
  M.ButtonLook{tint(enabled, normal, hover, down, disabled, KN.value(hm, now), p), Bool.pick(U32, enabled, text, muted), (F32.max(0.0, p) * sink_depth() : F32), F32.is_gt(f, 0.0), ring_inset(f), fade(focus, f)}

# The button drawn at `now`: like M.button (same checks, primitive order
# Fill, [focus ring], TextRun, and semantic), with the animated look.
def button(+node: K.Node, state: K.State, +metrics: M.Metrics, +size: F32, colors: M.Theme, a: ButtonAnim, +now: U32) -> Result<&2, &2, String, M.View>:
  K.Node{id, r, l, ro, enabled, fo} = node
  M.button_styled(node, state, metrics, size, button_look(enabled, colors, a, now))

# When the button needs its next frame; None once nothing moves.
def button_deadline(a: ButtonAnim, +now: U32, +frame_ms: U32) -> Maybe<&2, U32>:
  ButtonAnim{h, p, f} = a
  sooner(now, KN.next_deadline(h, now, frame_ms), sooner(now, KN.next_deadline(p, now, frame_ms), KN.next_deadline(f, now, frame_ms)))

def button_animating(a: ButtonAnim, +now: U32) -> Bool:
  is_some(button_deadline(a, now, 1))

# Caret blink
# -----------

# Milliseconds: solid after an edit, one cycle, one fade, and when the
# blinking stops (the hold plus ten cycles, ending solid).
def blink_hold() -> U32:
  500

def blink_period() -> U32:
  1000

def blink_fade() -> U32:
  150

def blink_stop() -> U32:
  10500

# `since`: when the caret last moved, the text changed or focus changed;
# caret, anchor and count as seen then; `focused` as of the last step.
type Blink is Data:
  Blink{since: U32, caret: U32, anchor: U32, count: U32, focused: Bool}

def one_if(b: Bool) -> U32:
  match b:
    case True{}:
      1
    case False{}:
      0

# A cycle: 0 fading out (0-150), 1 hidden (150-500), 2 fading in
# (500-650), 3 shown (650-1000).
def phase(+q: U32) -> U32:
  (one_if(U32.is_ge(q, 150)) + one_if(U32.is_ge(q, 500)) + one_if(U32.is_ge(q, 650)) : U32)

def faded(+p: F32) -> F32:
  KN.ease_at(KN.ease_in_out(), p)

def phase_opacity(k: U32, +q: U32) -> F32:
  match k:
    case 0:
      (1.0 - faded((U32.to_f32(q) / U32.to_f32(blink_fade()) : F32)) : F32)
    case 1:
      0.0
    case 2:
      faded(((U32.to_f32(q) - 500.0) / U32.to_f32(blink_fade()) : F32))
    case _:
      1.0

def phase_deadline(k: U32, +q: U32, +now: U32, +frame_ms: U32) -> U32:
  match k:
    case 0:
      (now + U32.max(frame_ms, 1) : U32)
    case 1:
      (now + 500 - q : U32)
    case 2:
      (now + U32.max(frame_ms, 1) : U32)
    case _:
      (now + blink_period() - q : U32)

def cycle(+d: U32) -> U32:
  ((d - blink_hold() : U32) % blink_period() : U32)

def opacity_at(running: Bool, +d: U32) -> F32:
  match running:
    case False{}:
      1.0
    case True{}:
      +q = cycle(d)
      phase_opacity(phase(q), q)

# The caret's opacity `d` ms after `since`; solid unless blinking.
def caret_opacity(blinking: Bool, +d: U32) -> F32:
  opacity_at(blinking && U32.is_ge(d, blink_hold()) && U32.is_lt(d, blink_stop()), d)

def in_cycle(+d: U32, +next: U32, +now: U32) -> Maybe<&2, U32>:
  Bool.pick(Maybe<&2, U32>, U32.is_ge((next - now + d : U32), blink_stop()), None{}, Some{next})

def blink_due(holding: Bool, stopped: Bool, +d: U32, +now: U32, +frame_ms: U32) -> Maybe<&2, U32>:
  match holding stopped:
    case True{} _:
      Some{(now + blink_hold() - d : U32)}
    case False{} True{}:
      None{}
    case False{} False{}:
      +q = cycle(d)
      in_cycle(d, phase_deadline(phase(q), q, now, frame_ms), now)

# Frames only during the fades; a timer at the start of the next fade
# during the plateaus; None when not blinking or once the blink stopped.
def blink_deadline(blinking: Bool, +d: U32, +now: U32, +frame_ms: U32) -> Maybe<&2, U32>:
  match blinking:
    case False{}:
      None{}
    case True{}:
      blink_due(U32.is_lt(d, blink_hold()), U32.is_ge(d, blink_stop()), d, now, frame_ms)

def blinked(b: Blink, +focused: Bool, +caret: U32, +anchor: U32, +count: U32, +now: U32) -> Blink:
  Blink{since, c, a, n, was} = b
  moved = U32.is_ne(c, caret) || U32.is_ne(a, anchor) || U32.is_ne(n, count) || Bool.xor(was, focused)
  Blink{Bool.pick(U32, moved, now, since), caret, anchor, count, focused}

def edited(b: Blink, +focused: Bool, e: KE.Edit, +now: U32) -> Blink:
  KE.Edit{t, count, caret, anchor} = e
  blinked(b, focused, caret, anchor, count, now)

# Field
# -----

type FieldAnim is Data:
  FieldAnim{focus: KN.Motion, error: KN.Motion, blink: Blink}

# A field at rest: unfocused, no refusal.
def field_anim() -> FieldAnim:
  FieldAnim{KN.rest(focus_curve(), 0.0), KN.rest(focus_curve(), 0.0), Blink{0, 0, 0, 0, False{}}}

# Retargets the field `id` (holding `f`) to Kairo's state at `now`: the
# focus ring, the error border, and the caret's blink clock, restarted by
# any edit, caret move or focus change.
def field_step(a: FieldAnim, prefs: Prefs, state: K.State, +id: U32, +f: FL.Field, +now: U32) -> FieldAnim:
  FieldAnim{fo, er, bl} = a
  Prefs{+reduce, blink} = prefs
  +focused = D.focused(state, id)
  FieldAnim{move(reduce, fo, focus_curve(), now, flag(focused)), move(reduce, er, focus_curve(), now, flag(FL.is_refused(FL.message(f)))), edited(bl, focused, FL.edit_of(f), now)}

def blinking(p: Prefs, b: Blink) -> Bool:
  Prefs{reduce, blink} = p
  Blink{s, c, a, n, focused} = b
  blink && Bool.not(reduce) && focused

def since(b: Blink) -> U32:
  Blink{s, c, a, n, f} = b
  s

def field_style(+focused: Bool, colors: FL.FieldTheme, a: FieldAnim, prefs: Prefs, +now: U32) -> FL.FieldStyle:
  FL.FieldTheme{box, border, +focus, ink, faint, band, caret, error} = colors
  FieldAnim{fm, em, +bl} = a
  +fo = KN.value(fm, now)
  FL.FieldStyle{focused, CM.mix_oklab(border, error, KN.value(em, now)), F32.is_gt(fo, 0.0), ring_inset(fo), fade(focus, fo), fade(caret, caret_opacity(blinking(prefs, bl), (now - since(bl) : U32)))}

# The field drawn at `now`: like FL.view (same checks, primitive order,
# semantic and EditState), with the animated border, ring and caret.
def field_view(+node: K.Node, +state: K.State, f: FL.Field, +size: F32, +colors: FL.FieldTheme, placeholder: String, a: FieldAnim, prefs: Prefs, +now: U32) -> Result<&2, &2, String, FL.FieldView>:
  K.Node{+id, r, l, ro, e, fo} = node
  FL.view_styled(node, state, f, size, colors, placeholder, field_style(D.focused(state, id), colors, a, prefs, now))

# When the field needs its next frame; None once nothing moves.
def field_deadline(a: FieldAnim, prefs: Prefs, +now: U32, +frame_ms: U32) -> Maybe<&2, U32>:
  FieldAnim{fm, em, +bl} = a
  sooner(now, KN.next_deadline(fm, now, frame_ms), sooner(now, KN.next_deadline(em, now, frame_ms), blink_deadline(blinking(prefs, bl), (now - since(bl) : U32), now, frame_ms)))

def field_animating(a: FieldAnim, prefs: Prefs, +now: U32) -> Bool:
  is_some(field_deadline(a, prefs, now, 1))
