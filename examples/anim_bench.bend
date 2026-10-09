import Base
import ../main.bend as M
import ../field.bend as FL
import ../anim.bend as A
import ../../Kairo/main.bend as KM
import ../../Kairo/types.bend as K
import ../../Tessra/geometry.bend as G
import ../../Runika/font.bend as F

# Cost of the demo's animations per frame (a button and a text field), and
# how long each transition keeps asking for frames. 100000 calls per row,
# at clocks cycling through the first 200 ms of the transitions, so every
# call evaluates moving springs and tweens. Run it alone, with the Eco
# bench lock held, from the Mokko directory.

type Op is Data:
  Idle{}
  ButtonStep{}
  ButtonRetarget{}
  ButtonView{}
  FieldStep{}
  FieldView{}
  Deadlines{}
  Frame{}

type Scene is Data:
  Scene{hov: K.State, out: K.State, button: A.ButtonAnim, focused: K.State, field: FL.Field, fa: A.FieldAnim, metrics: M.Metrics}

def field_node() -> K.Node:
  FL.field_node(1, G.Rect{20.0, 20.0, 200.0, 44.0}, "Name")

def button_node() -> K.Node:
  M.button_node(2, G.Rect{20.0, 80.0, 120.0, 44.0}, "Go", True{})

def started(r: Result<&2, &2, K.Error, K.State>) -> K.State:
  match r:
    case Fail{e}:
      K.State{Nil{}, 0, 0, 0, 0, 0, False{}, False{}, False{}, 0.0, 0.0}
    case Done{s}:
      s

def bg(v: Result<&2, &2, String, M.View>) -> F32:
  match v:
    case Done{M.View{Con{M.Fill{r, c}, rest}, s}}:
      U32.to_f32((c .&. 65535 : U32))
    case _:
      0.0

def border(v: Result<&2, &2, String, FL.FieldView>) -> F32:
  match v:
    case Done{FL.FieldView{M.View{Con{box, Con{M.Stroke{r, w, c}, rest}}, s}, e}}:
      U32.to_f32((c .&. 65535 : U32))
    case _:
      0.0

def due(m: Maybe<&2, U32>) -> F32:
  match m:
    case Some{x}:
      U32.to_f32((x .&. 255 : U32))
    case None{}:
      0.0

def frame(+s: Scene, +now: U32) -> F32:
  Scene{+hov, out, b, +focused, +field, fa, m} = s
  +b2 = A.button_step(b, A.prefs(), hov, 2, now)
  +f2 = A.field_step(fa, A.prefs(), focused, 1, field, now)
  (bg(A.button(button_node(), hov, m, 18.0, M.theme(), b2, now)) + border(A.field_view(field_node(), focused, field, 20.0, FL.field_theme(), "Type here", f2, A.prefs(), now))
    + due(A.sooner(now, A.button_deadline(b2, now, 8), A.field_deadline(f2, A.prefs(), now, 8))) : F32)

def button_step(+s: Scene, +now: U32) -> F32:
  Scene{hov, out, b, focused, field, fa, m} = s
  due(A.button_deadline(A.button_step(b, A.prefs(), hov, 2, now), now, 0))

def button_retarget(+s: Scene, +now: U32) -> F32:
  Scene{hov, out, b, focused, field, fa, m} = s
  due(A.button_deadline(A.button_step(b, A.prefs(), Bool.pick(K.State, U32.is_eq((now .&. 1 : U32), 0), hov, out), 2, now), now, 0))

def button_view(+s: Scene, +now: U32) -> F32:
  Scene{hov, out, b, focused, field, fa, m} = s
  bg(A.button(button_node(), hov, m, 18.0, M.theme(), b, now))

def field_step(+s: Scene, +now: U32) -> F32:
  Scene{hov, out, b, focused, field, fa, m} = s
  due(A.field_deadline(A.field_step(fa, A.prefs(), focused, 1, field, now), A.prefs(), now, 0))

def field_view(+s: Scene, +now: U32) -> F32:
  Scene{hov, out, b, focused, field, fa, m} = s
  border(A.field_view(field_node(), focused, field, 20.0, FL.field_theme(), "Type here", fa, A.prefs(), now))

def deadlines(+s: Scene, +now: U32) -> F32:
  Scene{hov, out, b, focused, field, fa, m} = s
  due(A.sooner(now, A.button_deadline(b, now, 8), A.field_deadline(fa, A.prefs(), now, 8)))

def call(op: Op, +s: Scene, +now: U32) -> F32:
  match op:
    case Idle{}:
      U32.to_f32(now)
    case ButtonStep{}:
      button_step(s, now)
    case ButtonRetarget{}:
      button_retarget(s, now)
    case ButtonView{}:
      button_view(s, now)
    case FieldStep{}:
      field_step(s, now)
    case FieldView{}:
      field_view(s, now)
    case Deadlines{}:
      deadlines(s, now)
    case Frame{}:
      frame(s, now)

def inner(n: Nat, +op: Op, +s: Scene, +i: U32, acc: F32) -> F32:
  match n:
    case 0n:
      acc
    case 1n+k:
      inner(k, op, s, (i + 1 : U32), (acc + call(op, s, (1000 + i % 200 : U32)) : F32))

# `zero` is 0 computed from the clock, so the loop cannot run before it.
def outer(n: Nat, +op: Op, +s: Scene, +zero: U32, acc: F32) -> F32:
  match n:
    case 0n:
      acc
    case 1n+k:
      outer(k, op, s, zero, inner(1000n, op, s, zero, acc))

def measure(+name: String, op: Op, s: Scene) -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    +sum : F32 <- IO.pure(F32, outer(100n, op, s, U32.mul(U32.from_nat(t0), 0), 0.0))
    IO.print("  checksum " ++ F32.show(sum))
    +t1 : Nat <- IO.now()
    IO.print(name ++ ": 100000 calls in " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms")

# Milliseconds from `now` until no frame is due, checked every ms.
def button_settles(n: Nat, moving: Bool, +a: A.ButtonAnim, +now: U32, +t: U32) -> U32:
  match n:
    case 0n:
      t
    case 1n+k:
      match moving:
        case False{}:
          t
        case True{}:
          button_settles(k, A.button_animating(a, (now + t + 1 : U32)), a, now, (t + 1 : U32))

def field_settles(n: Nat, moving: Bool, +p: A.Prefs, +a: A.FieldAnim, +now: U32, +t: U32) -> U32:
  match n:
    case 0n:
      t
    case 1n+k:
      match moving:
        case False{}:
          t
        case True{}:
          field_settles(k, A.field_animating(a, p, (now + t + 1 : U32)), p, a, now, (t + 1 : U32))

def button_for(+a: A.ButtonAnim, +now: U32) -> U32:
  button_settles(5000n, A.button_animating(a, now), a, now, 0)

def field_for(+p: A.Prefs, +a: A.FieldAnim, +now: U32) -> U32:
  field_settles(20000n, A.field_animating(a, p, now), p, a, now, 0)

def run(+s: Scene, +down: K.State, +up: K.State) -> IO(Unit):
  Scene{+hov, +out, +b, +focused, +field, fa, m} = s
  +rested = A.button_step(A.button_anim(), A.prefs(), hov, 2, 0)
  +pressed = A.button_step(rested, A.prefs(), down, 2, 1000)
  do IO<Unit>:
    IO.print("hover-in asks for frames for " ++ U32.show(button_for(b, 1000)) ++ " ms")
    IO.print("hover-out at 60 ms: " ++ U32.show(button_for(A.button_step(b, A.prefs(), out, 2, 1060), 1060)) ++ " ms more")
    IO.print("press asks for frames for " ++ U32.show(button_for(pressed, 1000)) ++ " ms")
    IO.print("release after 100 ms: " ++ U32.show(button_for(A.button_step(pressed, A.prefs(), up, 2, 1100), 1100)) ++ " ms")
    IO.print("focus ring asks for frames for " ++ U32.show(field_for(A.Prefs{False{}, False{}}, A.field_step(A.field_anim(), A.Prefs{False{}, False{}}, focused, 1, field, 1000), 1000)) ++ " ms (blink off)")
    IO.print("focused field with blink idles after " ++ U32.show(field_for(A.prefs(), fa, 1000)) ++ " ms")
    measure("empty loop", Idle{}, s)
    measure("button_step, state unchanged", ButtonStep{}, s)
    measure("button_step, retarget every call", ButtonRetarget{}, s)
    measure("button view (animated)", ButtonView{}, s)
    measure("field_step", FieldStep{}, s)
    measure("field_view (animated)", FieldView{}, s)
    measure("both deadlines", Deadlines{}, s)
    measure("frame: both steps, views, deadlines", Frame{}, s)

def scened(r: Result<&2, &2, String, FL.Field>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{+field}:
      +s0 = started(KM.init([field_node(), button_node()], 400.0, 200.0))
      +hov = KM.replay([K.PointerMove{60.0, 100.0}], s0)
      +out = KM.replay([K.PointerMove{300.0, 190.0}], hov)
      +focused = KM.replay([K.PointerDown{100.0, 40.0, 0}, K.PointerUp{100.0, 40.0, 0}, K.PointerMove{60.0, 100.0}], s0)
      run(Scene{hov, out, A.button_step(A.button_anim(), A.prefs(), hov, 2, 1000), focused, field, A.field_step(A.field_anim(), A.prefs(), focused, 1, field, 1000), M.Metrics{20.0, 20.0, 16.0}},
        KM.replay([K.PointerDown{60.0, 100.0, 0}], hov), KM.replay([K.PointerDown{60.0, 100.0, 0}, K.PointerUp{60.0, 100.0, 0}], hov))

def loaded(r: Result<&2, &2, String, F.Font>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{+font}:
      scened(FL.field(font, 20.0, "Olá"))

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    loaded(r)
