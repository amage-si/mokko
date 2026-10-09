import Base
import ./main.bend as M
import ./field.bend as FL
import ./anim.bend as A
import ../Kinera/main.bend as KN
import ../Chromi/mix.bend as CM
import ../Kairo/main.bend as KM
import ../Kairo/types.bend as K
import ../Tessra/geometry.bend as G
import ../Runika/font.bend as F
import ../Runika/check.bend as C

# Animated transitions, driven like a host: Kairo states from replayed
# inputs, a step per state change at a frame clock, views at frame times.
# The field (id 1) is at (20, 20, 200 x 44), the button (id 2) at
# (20, 80, 120 x 44). Text uses Liberation Sans at 20 px.

def field_bounds() -> G.Rect:
  G.Rect{20.0, 20.0, 200.0, 44.0}

def field_node() -> K.Node:
  FL.field_node(1, field_bounds(), "Name")

def button_node() -> K.Node:
  M.button_node(2, G.Rect{20.0, 80.0, 120.0, 44.0}, "Go", True{})

def started(r: Result<&2, &2, K.Error, K.State>) -> Result<&2, &2, String, K.State>:
  match r:
    case Fail{e}:
      Fail{"Kairo rejected the nodes"}
    case Done{s}:
      Done{s}

def on() -> A.Prefs:
  A.prefs()

def reduce() -> A.Prefs:
  A.Prefs{True{}, True{}}

def steady() -> A.Prefs:
  A.Prefs{False{}, False{}}

# Button helpers.

def button_at(+st: K.State, a: A.ButtonAnim, +now: U32) -> Result<&2, &2, String, M.View>:
  A.button(button_node(), st, M.Metrics{20.0, 20.0, 16.0}, 18.0, M.theme(), a, now)

def static_button(st: K.State) -> Result<&2, &2, String, M.View>:
  M.button(button_node(), st, M.Metrics{20.0, 20.0, 16.0}, 18.0, M.theme())

def bg(v: Result<&2, &2, String, M.View>) -> U32:
  match v:
    case Done{M.View{Con{M.Fill{r, c}, rest}, s}}:
      c
    case _:
      0

def fill_x(v: Result<&2, &2, String, M.View>) -> F32:
  match v:
    case Done{M.View{Con{M.Fill{G.Rect{x, y, w, h}, c}, rest}, s}}:
      x
    case _:
      F32.div(0.0, 0.0)

def hover_of(a: A.ButtonAnim) -> KN.Motion:
  A.ButtonAnim{h, p, f} = a
  h

def kind(p: M.Primitive) -> Char:
  match p:
    case M.Fill{r, c}:
      'F'
    case M.Stroke{r, w, c}:
      'S'
    case M.TextRun{x, t, b, l, s, clip, c}:
      'T'

def kinds_of(ps: +List<M.Primitive>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{p, rest}:
      SCon{kind(p), kinds_of(rest)}

def kinds(v: Result<&2, &2, String, M.View>) -> String:
  match v:
    case Fail{e}:
      "!"
    case Done{M.View{ps, s}}:
      kinds_of(ps)

def due(m: Maybe<&2, U32>, +at: U32) -> Bool:
  match m:
    case Some{x}:
      U32.is_eq(x, at)
    case None{}:
      False{}

def idle(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{x}:
      False{}
    case None{}:
      True{}

def between(+x: F32, +lo: F32, +hi: F32) -> Bool:
  F32.is_gt(x, lo) && F32.is_lt(x, hi)

def close(+a: F32, +b: F32, +eps: F32) -> Bool:
  F32.is_le(F32.abs((a - b : F32)), eps)

# Field helpers.

def fed_field(fed: FL.Fed) -> FL.Field:
  FL.Fed{f, d, r} = fed
  f

def fold(actions: +List<K.Action>, +font: F.Font, f: FL.Field) -> FL.Field:
  match actions:
    case Nil{}:
      f
    case Con{a, rest}:
      fold(rest, font, fed_field(FL.feed(font, 20.0, field_bounds(), 1, f, a)))

type Scene is Data:
  Scene{state: K.State, field: FL.Field}

def stepped(c: K.Change, +font: F.Font, f: FL.Field) -> Scene:
  K.Change{st, +actions, d, l} = c
  Scene{st, fold(actions, font, f)}

def play(inputs: +List<K.Input>, +font: F.Font, s: Scene) -> Scene:
  match inputs:
    case Nil{}:
      s
    case Con{i, rest}:
      Scene{st, f} = s
      play(rest, font, stepped(KM.dispatch(st, i), font, f))

def state_of(s: Scene) -> K.State:
  Scene{st, f} = s
  st

def field_of(s: Scene) -> FL.Field:
  Scene{st, f} = s
  f

def field_step(a: A.FieldAnim, p: A.Prefs, +s: Scene, +now: U32) -> A.FieldAnim:
  A.field_step(a, p, state_of(s), 1, field_of(s), now)

def field_at(+s: Scene, a: A.FieldAnim, p: A.Prefs, +now: U32) -> Result<&2, &2, String, FL.FieldView>:
  A.field_view(field_node(), state_of(s), field_of(s), 20.0, FL.field_theme(), "Type here", a, p, now)

def static_field(+s: Scene) -> Result<&2, &2, String, FL.FieldView>:
  FL.view(field_node(), state_of(s), field_of(s), 20.0, FL.field_theme(), "Type here")

def prims(v: Result<&2, &2, String, FL.FieldView>) -> +List<M.Primitive>:
  match v:
    case Fail{e}:
      Nil{}
    case Done{FL.FieldView{M.View{ps, sem}, e}}:
      ps

def field_kinds(v: Result<&2, &2, String, FL.FieldView>) -> String:
  kinds_of(prims(v))

# Box, border, text, caret, ring: the focused, empty field.
def caret_alpha(ps: +List<M.Primitive>) -> U32:
  match ps:
    case Con{box, Con{line, Con{run, Con{M.Fill{r, c}, rest}}}}:
      (c .&. 255 : U32)
    case _:
      999

def border(ps: +List<M.Primitive>) -> U32:
  match ps:
    case Con{box, Con{M.Stroke{r, w, c}, rest}}:
      c
    case _:
      0

def last(ps: +List<M.Primitive>) -> Maybe<&2, M.Primitive>:
  match ps:
    case Nil{}:
      None{}
    case Con{p, Nil{}}:
      Some{p}
    case Con{p, rest}:
      last(rest)

# The ring's inset from the field bounds and its alpha.
def ring_inset(p: Maybe<&2, M.Primitive>) -> F32:
  match p:
    case Some{M.Stroke{G.Rect{x, y, w, h}, width, c}}:
      (x - 20.0 : F32)
    case _:
      F32.div(0.0, 0.0)

def ring_alpha(p: Maybe<&2, M.Primitive>) -> U32:
  match p:
    case Some{M.Stroke{r, width, c}}:
      (c .&. 255 : U32)
    case _:
      999

def error_of(a: A.FieldAnim) -> KN.Motion:
  A.FieldAnim{f, e, b} = a
  e

def field_deadline(a: A.FieldAnim, p: A.Prefs, +now: U32) -> Maybe<&2, U32>:
  A.field_deadline(a, p, now, 8)

def main() -> IO(Unit):
  do IO<Unit>:
    fr : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- C.unwrap(F.Font, fr)
    +s0 : K.State <- C.unwrap(K.State, started(KM.init([field_node(), button_node()], 400.0, 200.0)))
    +empty : FL.Field <- C.unwrap(FL.Field, FL.field(font, 20.0, ""))
    +hov : K.State = KM.replay([K.PointerMove{60.0, 100.0}], s0)
    +out : K.State = KM.replay([K.PointerMove{300.0, 190.0}], hov)
    +b1 : A.ButtonAnim = A.button_step(A.button_anim(), on(), M.theme(), hov, 2, 1000)
    +v60 : F32 = KN.value(hover_of(b1), 1060)
    C.expect(between(v60, 0.3, 0.97) && U32.is_eq(bg(button_at(hov, b1, 1060)), CM.mix_oklab(610062079, 829482751, v60)),
      "60 ms into a hover the fill is mix_oklab(normal, hover) at Kinera's value")
    C.expect(U32.is_eq(bg(button_at(hov, b1, 1000)), 610062079) && U32.is_eq(bg(button_at(hov, b1, 2000)), 829482751),
      "the hover fade starts at the normal colour and lands exactly on the hover colour")
    C.expect(due(A.button_deadline(b1, 1060, 8), 1068) && idle(A.button_deadline(b1, 1300, 8)) && Bool.not(A.button_animating(b1, 1300)),
      "a frame is due while the hover moves; none once it settled (240 ms)")
    C.expect(Bool.not(idle(A.button_deadline(b1, 1180, 8))) && U32.is_eq(bg(button_at(hov, b1, 1190)), 829482751) && idle(A.button_deadline(b1, 1200, 8)),
      "the hover rests once no colour byte can change: ~195 ms, the frame before already shows the hover colour")
    +b2 : A.ButtonAnim = A.button_step(b1, on(), M.theme(), out, 2, 1060)
    C.expect(close(KN.value(hover_of(b2), 1060), v60, 0.000001) && close(KN.velocity(hover_of(b2), 1060), KN.velocity(hover_of(b1), 1060), 0.001)
      && U32.is_eq(bg(button_at(out, b2, 1060)), bg(button_at(hov, b1, 1060))),
      "hover-out mid-fade keeps the value, the velocity and the colour")
    C.expect(close(KN.value(hover_of(b2), 1068), KN.value(hover_of(b2), 1060), 0.05) && F32.is_lt(KN.value(hover_of(b2), 1150), v60)
      && U32.is_eq(bg(button_at(out, b2, 1400)), 610062079) && idle(A.button_deadline(b2, 1400, 8)),
      "the reversal moves on without a jump and returns to the normal colour, then idles")
    C.expect(U32.is_eq(bg(button_at(hov, A.button_step(b1, on(), M.theme(), hov, 2, 1060), 1060)), bg(button_at(hov, b1, 1060))),
      "stepping again with the same state changes nothing")
    +br : A.ButtonAnim = A.button_step(A.button_anim(), reduce(), M.theme(), hov, 2, 1000)
    C.expect(U32.is_eq(bg(button_at(hov, br, 1000)), 829482751) && idle(A.button_deadline(br, 1000, 8)),
      "reduce motion: the hover colour at once, no frames")
    +settled : A.ButtonAnim = A.button_step(b1, on(), M.theme(), hov, 2, 3000)
    +down : K.State = KM.replay([K.PointerDown{60.0, 100.0, 0}], hov)
    +bp : A.ButtonAnim = A.button_step(settled, on(), M.theme(), down, 2, 3000)
    C.expect(between(fill_x(button_at(down, bp, 3030)), 20.0, 21.0) && F32.is_eq(fill_x(button_at(down, bp, 3070)), 21.0)
      && U32.is_eq(bg(button_at(down, bp, 3070)), 406820607),
      "a press sinks the fill by 1 unit in 70 ms and darkens it to the pressed colour")
    +up : K.State = KM.replay([K.PointerUp{60.0, 100.0, 0}], down)
    +bu : A.ButtonAnim = A.button_step(bp, on(), M.theme(), up, 2, 3100)
    C.expect(between(fill_x(button_at(up, bu, 3150)), 20.0, 21.0) && F32.is_eq(fill_x(button_at(up, bu, 4000)), 20.0)
      && U32.is_eq(bg(button_at(up, bu, 4000)), 829482751) && idle(A.button_deadline(bu, 4000, 8)),
      "release springs back to the hover look, then idles")
    C.expect(Bool.not(idle(A.button_deadline(bu, 3160, 8))) && idle(A.button_deadline(bu, 3270, 8)) && F32.is_eq(fill_x(button_at(up, bu, 3270)), 20.0)
      && U32.is_eq(bg(button_at(up, bu, 3270)), 829482751),
      "release idles as it passes 0 (~166 ms): its overshoot below 0 is clamped away and comes back by 0.05%")
    +tabbed : K.State = KM.replay([K.KeyDown{K.TabKey{}, False{}, False{}}, K.KeyDown{K.TabKey{}, False{}, False{}}], s0)
    +bf : A.ButtonAnim = A.button_step(A.button_anim(), on(), M.theme(), tabbed, 2, 1000)
    C.expect(String.eq(kinds(button_at(tabbed, bf, 1075)), "FST") && String.eq(kinds(button_at(tabbed, bf, 1200)), kinds(static_button(tabbed)))
      && String.eq(kinds(button_at(s0, A.button_anim(), 1000)), kinds(static_button(s0))),
      "button primitive order: fill, focus ring, label, as the static button")
    # The field.
    +fs0 : Scene = Scene{s0, empty}
    +focused : Scene = play([K.PointerDown{100.0, 40.0, 0}, K.PointerUp{100.0, 40.0, 0}], font, fs0)
    +fa : A.FieldAnim = field_step(A.field_anim(), on(), focused, 1000)
    +mid : +List<M.Primitive> = prims(field_at(focused, fa, on(), 1075))
    C.expect(between(ring_inset(last(mid)), 2.0, 6.0) && U32.is_gt(ring_alpha(last(mid)), 0) && U32.is_lt(ring_alpha(last(mid)), 255),
      "the field's focus ring fades and grows in: inset and alpha between")
    +full : +List<M.Primitive> = prims(field_at(focused, fa, on(), 1150))
    C.expect(F32.is_eq(ring_inset(last(full)), 2.0) && U32.is_eq(ring_alpha(last(full)), 255) && U32.is_eq(border(full), border(prims(static_field(focused)))),
      "at 150 ms the ring rests at inset 2, opaque, as the static field")
    C.expect(String.eq(field_kinds(field_at(focused, fa, on(), 1075)), "FSTFS") && String.eq(field_kinds(field_at(focused, fa, on(), 1200)), field_kinds(static_field(focused)))
      && String.eq(field_kinds(field_at(fs0, A.field_anim(), on(), 1000)), field_kinds(static_field(fs0))),
      "field primitive order: box, border, text, caret, focus ring, as the static field")
    C.expect(U32.is_eq(caret_alpha(prims(field_at(focused, fa, on(), 1200))), 255) && due(field_deadline(fa, on(), 1200), 1500),
      "the caret holds solid 500 ms after focus; a timer, not frames, until the first fade")
    C.expect(between(U32.to_f32(caret_alpha(prims(field_at(focused, fa, on(), 1575)))), 0.0, 255.0) && due(field_deadline(fa, on(), 1575), 1583),
      "mid-fade the caret is translucent and frames are due")
    C.expect(U32.is_eq(caret_alpha(prims(field_at(focused, fa, on(), 1800))), 0) && due(field_deadline(fa, on(), 1800), 2000)
      && U32.is_eq(caret_alpha(prims(field_at(focused, fa, on(), 2300))), 255) && due(field_deadline(fa, on(), 2300), 2500),
      "hidden then shown plateaus wait for the next fade without frames")
    C.expect(U32.is_eq(caret_alpha(prims(field_at(focused, fa, on(), 11200))), 255) && idle(field_deadline(fa, on(), 11200))
      && idle(field_deadline(fa, on(), 20000)),
      "after ten cycles the caret stays solid and the field idles")
    +typed : Scene = play([K.TextInput{"a"}], font, focused)
    +ft : A.FieldAnim = field_step(fa, on(), typed, 1800)
    C.expect(U32.is_eq(caret_alpha(prims(field_at(typed, ft, on(), 1800))), 255) && due(field_deadline(ft, on(), 1800), 2300),
      "typing keeps the caret solid and restarts the hold")
    C.expect(U32.is_eq(caret_alpha(prims(field_at(focused, fa, steady(), 1800))), 255) && idle(field_deadline(fa, steady(), 1200)),
      "blink off: a solid caret and no frames")
    +away : Scene = play([K.WindowFocus{False{}}], font, focused)
    +fw : A.FieldAnim = field_step(fa, on(), away, 2000)
    C.expect(String.eq(field_kinds(field_at(away, fw, on(), 2075)), "FSTS") && idle(field_deadline(fw, on(), 2150))
      && String.eq(field_kinds(field_at(away, fw, on(), 2150)), "FST"),
      "an unfocused window stops the blink; the ring fades out, then the field idles")
    +fr2 : A.FieldAnim = field_step(A.field_anim(), reduce(), focused, 1000)
    C.expect(U32.is_eq(ring_alpha(last(prims(field_at(focused, fr2, reduce(), 1000)))), 255) && idle(field_deadline(fr2, reduce(), 1000))
      && U32.is_eq(caret_alpha(prims(field_at(focused, fr2, reduce(), 1800))), 255),
      "reduce motion: the ring at once, a solid caret, no frames")
    +refused : Scene = play([K.TextInput{"☕"}], font, focused)
    +fe : A.FieldAnim = field_step(fa, on(), refused, 3000)
    +ev : F32 = KN.value(error_of(fe), 3060)
    C.expect(between(ev, 0.0, 1.0) && U32.is_eq(border(prims(field_at(refused, fe, on(), 3060))), CM.mix_oklab(1247111423, 4031927039, ev))
      && U32.is_eq(border(prims(field_at(refused, fe, on(), 3150))), 4031927039),
      "a refused edit fades the border to the error colour in OKLab in 150 ms")
    IO.print("Mokko anim: 24 tests passed")
