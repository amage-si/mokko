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
#      mid-flight starts from the current value and velocity, with no jump).
#      Step at the time of the frame on screen (one frame before `now`):
#      a motion retargeted at `now` itself draws its start value there, a
#      first frame that changes no pixel;
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

# Visible rest
# ------------
#
# A spring is settled once what is left of it can no longer change a byte
# of what is drawn. Kinera's settle test (`with_rest`) bounds every later
# value: once omega^2 x^2 + v^2 <= omega^2 rest^2 the factor stays within
# `rest` of its target for good (a rest speed of 1e6/s leaves that energy
# bound alone in charge). So `rest` is the largest factor change that moves
# no colour byte by half a step, and no edge by a quarter pixel:
#   - colour: 0.5 / s, with s the steepest byte change per unit of factor
#     at either end of the pair's OKLab mix (the end the motion settles
#     at); the theme's normal/hover pair has s ~ 24, so rest ~ 0.021;
#     hover/pressed s ~ 83, rest ~ 0.006;
#   - geometry: 0.25 unit (Mokko draws units as pixels) over the sink's
#     depth per unit of factor.
# Measured in a window, the old fixed 0.004 left 11 of 32 hover frames and
# 18 of 39 release frames with no changed pixel.
#
# Every factor is drawn clamped to 0..1 (OKLab mixes stop at their ends,
# the sink at 0, the ring's inset and opacity are clamped), so a spring
# that has passed its target at an end shows that end. It is settled there
# as soon as its way back across, at most its energy bound times the decay
# over a half cycle (e^(-pi zeta / sqrt(1 - zeta^2)); 0 for critical and
# overdamped springs, which cross once), is below `rest`. That is what ends
# the release: its 1.5% overshoot below 0 is invisible and returns by
# 1.5% of that.

# Byte-scaled sRGB channels (and alpha) of an OKLab colour.
def encoded(v: CM.Rgb) -> CM.Rgb:
  CM.Rgb{+r, +g, +b} = v
  CM.Rgb{(CM.to_srgb(r) * 255.0 : F32), (CM.to_srgb(g) * 255.0 : F32), (CM.to_srgb(b) * 255.0 : F32)}

def bytes_of(v: CM.Lab) -> CM.Rgb:
  encoded(CM.oklab_to_linear(v))

def spread(p: CM.Rgb, q: CM.Rgb) -> F32:
  CM.Rgb{+pr, +pg, +pb} = p
  CM.Rgb{+qr, +qg, +qb} = q
  F32.max(F32.abs((pr - qr : F32)), F32.max(F32.abs((pg - qg : F32)), F32.abs((pb - qb : F32))))

# The mix's step used to measure a slope.
def probe() -> F32:
  0.01

# Bytes per unit of factor as the mix from `a` arrives at `b`.
def end_slope(+a: CM.Lab, +b: CM.Lab) -> F32:
  (spread(bytes_of(b), bytes_of(CM.mix_lab(a, b, (1.0 - probe() : F32)))) / probe() : F32)

# The steepest byte change per unit of factor at either end of the OKLab
# mix of `a` and `b` (alpha mixes linearly).
def colour_slope(+a: U32, +b: U32) -> F32:
  +la = CM.of_rgba(a)
  +lb = CM.of_rgba(b)
  +alpha = F32.abs((U32.to_f32((a .&. 255 : U32)) - U32.to_f32((b .&. 255 : U32)) : F32))
  F32.max(alpha, F32.max(end_slope(la, lb), end_slope(lb, la)))

# The factor change that moves no byte of the a..b mix by half a step;
# 1 (settled at once) when the pair is one colour.
def colour_rest(+a: U32, +b: U32) -> F32:
  KN.clamp((0.5 / colour_slope(a, b) : F32), 0.0001, 1.0)

def sink_depth() -> F32:
  1.0

# The press factor mixes the hover or normal colour with the pressed one
# and sinks the fill.
def press_rest(+normal: U32, +hover: U32, +down: U32) -> F32:
  F32.min(F32.min(colour_rest(normal, down), colour_rest(hover, down)), (0.25 / sink_depth() : F32))

# Curves
# ------

def resting(s: KN.Spring, +rest: F32) -> KN.Curve:
  KN.spring(KN.with_rest(s, rest, 1000000.0))

# Hover: a critically damped spring, 200 ms response (90% at ~125 ms);
# it keeps its velocity when reversed.
def hover_curve(+rest: F32) -> KN.Curve:
  resting(KN.responsive(200.0, 1.0), rest)

# Focus ring and error border: 150 ms ease-out.
def focus_curve() -> KN.Curve:
  KN.tween(150.0, KN.ease_out())

# Press: 70 ms ease-out in, a snappy spring (250 ms response, ratio 0.8)
# back out.
def press_curve() -> KN.Curve:
  KN.tween(70.0, KN.ease_out())

def release_curve(+rest: F32) -> KN.Curve:
  resting(KN.responsive(250.0, 0.8), rest)

# What a property's curve depends on, built only when it retargets (the
# rests cost a few OKLab conversions).
type Pace is Data:
  HoverPace{normal: U32, hover: U32}
  PressPace{down: Bool, normal: U32, hover: U32, pressed: U32}
  FocusPace{}

def press_for(down: Bool, +normal: U32, +hover: U32, +pressed: U32) -> KN.Curve:
  match down:
    case True{}:
      press_curve()
    case False{}:
      release_curve(press_rest(normal, hover, pressed))

def curve_of(p: Pace) -> KN.Curve:
  match p:
    case HoverPace{+normal, +hover}:
      hover_curve(colour_rest(normal, hover))
    case PressPace{down, +normal, +hover, +pressed}:
      press_for(down, normal, hover, pressed)
    case FocusPace{}:
      focus_curve()

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

def move.go(same: Bool, m: KN.Motion, p: Pace, +now: U32, +to: F32) -> KN.Motion:
  match same:
    case True{}:
      m
    case False{}:
      recurve(KN.retarget(m, now, to), curve_of(p))

# How far back across its end a spring can still come, per unit of its
# energy bound: the decay over a half cycle; underdamped springs only.
def comeback(d: KN.Damping) -> F32:
  match d:
    case KN.Under{+decay, +wd}:
      F32.exp(F32.neg((decay * 3.14159265 / wd : F32)))
    case KN.Critical{}:
      0.0
    case KN.Over{r1, r2}:
      0.0

def spring_back(s: KN.Spring, +x: F32, +v: F32) -> Bool:
  KN.Spring{+omega, d, +rest, rs} = s
  +bound = F32.sqrt((x * x + (v / omega : F32) * (v / omega : F32) : F32))
  F32.is_le((bound * comeback(d) : F32), rest)

def back_within(c: KN.Curve, +x: F32, +v: F32) -> Bool:
  match c:
    case KN.Physics{s}:
      spring_back(s, x, v)
    case KN.Tween{d, e}:
      False{}

def past.go(beyond: Bool, +m: KN.Motion, +x: F32, +now: U32) -> Bool:
  match beyond:
    case False{}:
      False{}
    case True{}:
      back_within(KN.curve(m), x, KN.velocity(m, now))

# Whether `m`, heading for an end of 0..1, is past it at `now` for good (see
# Visible rest): what it still does is clamped away.
def past(+m: KN.Motion, +now: U32) -> Bool:
  +to = KN.target(m)
  +x = (KN.value(m, now) - to : F32)
  past.go((F32.is_eq(to, 0.0) && F32.is_lt(x, 0.0)) || (F32.is_eq(to, 1.0) && F32.is_gt(x, 0.0)), m, x, now)

def landed(done: Bool, +m: KN.Motion) -> KN.Motion:
  match done:
    case False{}:
      m
    case True{}:
      KN.rest(KN.curve(m), KN.target(m))

# A finished motion collapses to rest (clock-independent); so does one past
# its end for good.
def settled(+m: KN.Motion, +now: U32) -> KN.Motion:
  +s = KN.settle(m, now)
  landed(past(s, now), s)

# Heads `m` for `to` under the curve `p` asks for, from its value and
# velocity at `now`; the same target changes nothing. Reduce: at rest at
# `to` at once.
def move(reduce: Bool, +m: KN.Motion, p: Pace, +now: U32, +to: F32) -> KN.Motion:
  match reduce:
    case True{}:
      KN.rest(KN.instant(), to)
    case False{}:
      settled(move.go(F32.is_eq(KN.target(m), to), m, p, now, to), now)

# When `m` needs its next frame: none once done or past its end for good.
def deadline.go(gone: Bool, +m: KN.Motion, +now: U32, +frame_ms: U32) -> Maybe<&2, U32>:
  match gone:
    case True{}:
      None{}
    case False{}:
      KN.next_deadline(m, now, frame_ms)

def deadline_of(+m: KN.Motion, +now: U32, +frame_ms: U32) -> Maybe<&2, U32>:
  deadline.go(past(m, now), m, now, frame_ms)

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
# (Each retarget sets its curve, so the resting ones are placeholders.)
def button_anim() -> ButtonAnim:
  ButtonAnim{KN.rest(KN.instant(), 0.0), KN.rest(KN.instant(), 0.0), KN.rest(focus_curve(), 0.0)}

# Retargets the button `id` to Kairo's state at `now`. Call it every frame
# (or after every dispatch); it is idempotent while the state holds.
# `colors` is the theme the button is drawn with: the springs rest once no
# byte of its colours can change (see Visible rest).
def button_step(a: ButtonAnim, prefs: Prefs, colors: M.Theme, +state: K.State, +id: U32, +now: U32) -> ButtonAnim:
  ButtonAnim{h, p, f} = a
  Prefs{+reduce, blink} = prefs
  M.Theme{+normal, +hover, +pressed, disabled, text, muted, focus} = colors
  +down = D.pressed(state, id)
  ButtonAnim{move(reduce, h, HoverPace{normal, hover}, now, flag(D.hovered(state, id))), move(reduce, p, PressPace{down, normal, hover, pressed}, now, flag(down)), move(reduce, f, FocusPace{}, now, flag(D.focused(state, id)))}

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
  M.ButtonLook{tint(enabled, normal, hover, down, disabled, KN.value(hm, now), p), Bool.pick(U32, enabled, text, muted), (KN.clamp(p, 0.0, 1.0) * sink_depth() : F32), F32.is_gt(f, 0.0), ring_inset(f), fade(focus, f)}

# The button drawn at `now`: like M.button (same checks, primitive order
# Fill, [focus ring], TextRun, and semantic), with the animated look.
def button(+node: K.Node, state: K.State, +metrics: M.Metrics, +size: F32, colors: M.Theme, a: ButtonAnim, +now: U32) -> Result<&2, &2, String, M.View>:
  K.Node{id, r, l, ro, enabled, fo} = node
  M.button_styled(node, state, metrics, size, button_look(enabled, colors, a, now))

# When the button needs its next frame; None once nothing moves.
def button_deadline(a: ButtonAnim, +now: U32, +frame_ms: U32) -> Maybe<&2, U32>:
  ButtonAnim{h, p, f} = a
  sooner(now, deadline_of(h, now, frame_ms), sooner(now, deadline_of(p, now, frame_ms), deadline_of(f, now, frame_ms)))

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
  FieldAnim{move(reduce, fo, FocusPace{}, now, flag(focused)), move(reduce, er, FocusPace{}, now, flag(FL.is_refused(FL.message(f)))), edited(bl, focused, FL.edit_of(f), now)}

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
  sooner(now, deadline_of(fm, now, frame_ms), sooner(now, deadline_of(em, now, frame_ms), blink_deadline(blinking(prefs, bl), (now - since(bl) : U32), now, frame_ms)))

def field_animating(a: FieldAnim, prefs: Prefs, +now: U32) -> Bool:
  is_some(field_deadline(a, prefs, now, 1))
