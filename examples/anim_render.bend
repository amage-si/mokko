import Base
import ../main.bend as M
import ../field.bend as FL
import ../anim.bend as A
import ../chromi_text.bend as Text
import ../../Kairo/main.bend as KM
import ../../Kairo/types.bend as K
import ../../Tessra/geometry.bend as G
import ../../Chromi/main.bend as C
import ../../Chromi/geometry.bend as CG
import ../../Chromi/tree.bend as Tree
import ../../Runika/font.bend as F

# A filmstrip of Mokko's animated transitions, painted with Chromi without
# a window, written as build/anim-render.ppm (900x400, run from the Mokko
# directory). Six frames per row, at the times printed under each:
#   1. hover-in: the fill fades normal -> hover (OKLab);
#   2. hover-out at 60 ms, mid-fade: the fade reverses without a jump;
#   3. press at 0, release at 70 ms: the fill sinks and darkens, then
#      springs back;
#   4. a field gains focus: the ring fades and grows in (6 -> 2 units).
# Each control is driven through Kairo and stepped like a host does; the
# primitives are drawn at cell 0 and shifted into their column.

def cell() -> F32:
  150.0

def row_top(+r: U32) -> F32:
  (U32.to_f32(r) * 100.0 : F32)

def button_node(+r: U32) -> K.Node:
  M.button_node(2, G.Rect{15.0, (row_top(r) + 14.0 : F32), 120.0, 44.0}, "Go", True{})

def field_node(+r: U32) -> K.Node:
  FL.field_node(1, G.Rect{5.0, (row_top(r) + 14.0 : F32), 140.0, 44.0}, "Name")

def started(r: Result<&2, &2, K.Error, K.State>) -> K.State:
  match r:
    case Fail{e}:
      K.State{Nil{}, 0, 0, 0, 0, 0, False{}, False{}, False{}, 0.0, 0.0}
    case Done{s}:
      s

def base(+r: U32) -> K.State:
  started(KM.init([button_node(r)], 900.0, 400.0))

def middle(+r: U32) -> F32:
  (row_top(r) + 36.0 : F32)

# Milliseconds after the first step, per row and column.
def time(+r: U32, k: U32) -> U32:
  match k:
    case 0:
      Bool.pick(U32, U32.is_eq(r, 1), 40, 0)
    case 1:
      Bool.pick(U32, U32.is_eq(r, 1), 60, Bool.pick(U32, U32.is_eq(r, 2), 35, 25))
    case 2:
      Bool.pick(U32, U32.is_eq(r, 1), 80, Bool.pick(U32, U32.is_eq(r, 2), 70, 50))
    case 3:
      Bool.pick(U32, U32.is_eq(r, 1), 110, Bool.pick(U32, U32.is_eq(r, 2), 100, 75))
    case 4:
      Bool.pick(U32, U32.is_eq(r, 1), 160, Bool.pick(U32, U32.is_eq(r, 2), 150, 100))
    case _:
      Bool.pick(U32, U32.is_eq(r, 1), 400, Bool.pick(U32, U32.is_eq(r, 2), 400, 150))

def ps_of(v: Result<&2, &2, String, M.View>) -> +List<M.Primitive>:
  match v:
    case Fail{e}:
      Nil{}
    case Done{M.View{ps, s}}:
      ps

def field_ps(v: Result<&2, &2, String, FL.FieldView>) -> +List<M.Primitive>:
  match v:
    case Fail{e}:
      Nil{}
    case Done{FL.FieldView{M.View{ps, s}, e}}:
      ps

# Row 0: hover-in from rest at 1000.
def hover_in(+m: M.Metrics, +t: U32) -> +List<M.Primitive>:
  +hov = KM.replay([K.PointerMove{60.0, middle(0)}], base(0))
  ps_of(A.button(button_node(0), hov, m, 18.0, M.theme(), A.button_step(A.button_anim(), A.prefs(), hov, 2, 1000), (1000 + t : U32)))

# Row 1: hover-in at 1000, out at 1060.
def reversal(+m: M.Metrics, +t: U32) -> +List<M.Primitive>:
  +hov = KM.replay([K.PointerMove{60.0, middle(1)}], base(1))
  +out = KM.replay([K.PointerMove{500.0, middle(1)}], hov)
  +a = A.button_step(A.button_anim(), A.prefs(), hov, 2, 1000)
  +b = A.button_step(a, A.prefs(), out, 2, 1060)
  +early = U32.is_lt(t, 60)
  ps_of(A.button(button_node(1), Bool.pick(K.State, early, hov, out), m, 18.0, M.theme(), Bool.pick(A.ButtonAnim, early, a, b), (1000 + t : U32)))

# Row 2: hovered and settled; press at 1000, release at 1070.
def press(+m: M.Metrics, +t: U32) -> +List<M.Primitive>:
  +hov = KM.replay([K.PointerMove{60.0, middle(2)}], base(2))
  +down = KM.replay([K.PointerDown{60.0, middle(2), 0}], hov)
  +up = KM.replay([K.PointerUp{60.0, middle(2), 0}], down)
  +rested = A.button_step(A.button_anim(), A.prefs(), hov, 2, 0)
  +a = A.button_step(rested, A.prefs(), down, 2, 1000)
  +b = A.button_step(a, A.prefs(), up, 2, 1070)
  +early = U32.is_lt(t, 70)
  ps_of(A.button(button_node(2), Bool.pick(K.State, early, down, up), m, 18.0, M.theme(), Bool.pick(A.ButtonAnim, early, a, b), (1000 + t : U32)))

# Row 3: a click focuses an empty field at 1000.
def focus(+empty: FL.Field, +t: U32) -> +List<M.Primitive>:
  +st = KM.replay([K.PointerDown{60.0, middle(3), 0}, K.PointerUp{60.0, middle(3), 0}], started(KM.init([field_node(3)], 900.0, 400.0)))
  field_ps(A.field_view(field_node(3), st, empty, 18.0, FL.field_theme(), "Name", A.field_step(A.field_anim(), A.prefs(), st, 1, empty, 1000), A.prefs(), (1000 + t : U32)))

def frame(+m: M.Metrics, +empty: FL.Field, r: U32, +t: U32) -> +List<M.Primitive>:
  match r:
    case 0:
      hover_in(m, t)
    case 1:
      reversal(m, t)
    case 2:
      press(m, t)
    case _:
      focus(empty, t)

def moved(r: G.Rect, +dx: F32) -> G.Rect:
  G.Rect{x, y, w, h} = r
  G.Rect{(x + dx : F32), y, w, h}

def shift(ps: +List<M.Primitive>, +dx: F32) -> +List<M.Primitive>:
  match ps:
    case Nil{}:
      Nil{}
    case Con{M.Fill{r, c}, rest}:
      Con{M.Fill{moved(r, dx), c}, shift(rest, dx)}
    case Con{M.Stroke{r, w, c}, rest}:
      Con{M.Stroke{moved(r, dx), w, c}, shift(rest, dx)}
    case Con{M.TextRun{x, top, b, l, s, clip, c}, rest}:
      Con{M.TextRun{(x + dx : F32), top, b, l, s, moved(clip, dx), c}, shift(rest, dx)}

def caption(+r: U32, +t: U32) -> M.Primitive:
  +top = (row_top(r) + 66.0 : F32)
  M.TextRun{15.0, top, (top + 11.0 : F32), U32.show(t) ++ " ms", 13.0, G.Rect{0.0, top, 150.0, 20.0}, 2863907583}

def rect(r: G.Rect) -> CG.Rect:
  G.Rect{x, y, w, h} = r
  CG.Rect{x, y, w, h}

def run_paint(r: Result<&2, &2, String, Text.Run>, canvas: C.Canvas, +x: F32, +top: F32, +clip: G.Rect, +rgba: U32) -> C.Canvas:
  match r:
    case Fail{e}:
      C.reject(canvas, e)
    case Done{run}:
      C.reset_clip(Text.paint(run, C.clip_rect(canvas, rect(clip)), x, top, 1.0, rgba))

def paint(ps: +List<M.Primitive>, +font: F.Font, canvas: C.Canvas) -> C.Canvas:
  match ps:
    case Nil{}:
      canvas
    case Con{M.Fill{r, rgba}, rest}:
      paint(rest, font, C.fill_rect(canvas, rect(r), rgba))
    case Con{M.Stroke{r, width, rgba}, rest}:
      paint(rest, font, C.stroke_rect(canvas, rect(r), width, rgba))
    case Con{M.TextRun{x, top, baseline, label, size, clip, rgba}, rest}:
      paint(rest, font, run_paint(Text.prepare(font, label, size, 1000000.0, 1.0), canvas, x, top, clip, rgba))

def cells(n: Nat, +m: M.Metrics, +font: F.Font, +empty: FL.Field, +r: U32, +k: U32, canvas: C.Canvas) -> C.Canvas:
  match n:
    case 0n:
      canvas
    case 1n+p:
      +t = time(r, k)
      +dx = (U32.to_f32(k) * cell() : F32)
      cells(p, m, font, empty, r, (k + 1 : U32), paint(shift(Con{caption(r, t), frame(m, empty, r, t)}, dx), font, canvas))

def rows(n: Nat, +m: M.Metrics, +font: F.Font, +empty: FL.Field, +r: U32, canvas: C.Canvas) -> C.Canvas:
  match n:
    case 0n:
      canvas
    case 1n+p:
      rows(p, m, font, empty, (r + 1 : U32), cells(6n, m, font, empty, r, 0, canvas))

# PPM bytes, built backwards from the last pixel.
def bytes(n: Nat, +image: Image, +side: U32, +w: U32, +i: U32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n:
      acc
    case 1n+p:
      +j = (i - 1 : U32)
      +y = U32.div(j, w)
      +x = (j - y * w : U32)
      +c = Tree.sample(image, side, x, y, (x < side / 2 : U32), (y < side / 2 : U32))
      bytes(p, image, side, w, j, (c >> 24n : U32) <> ((c >> 16n) .&. 255 : U32) <> ((c >> 8n) .&. 255 : U32) <> acc)

def write.done(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, ok) = r
  do IO<Unit>:
    File.close(f)
    IO.print("wrote build/anim-render.ppm")

def write.body(r: File & Result<&1, &1, U32 & String, Unit>, pixels: List<&2, U32>) -> IO(Unit):
  (f, ok) = r
  do IO<Unit>:
    r2 : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, pixels)
    write.done(r2)

def write(+w: U32, +h: U32, pixels: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open("build/anim-render.ppm", "w"))
    r1 : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, "P6\n" ++ U32.show(w) ++ " " ++ U32.show(h) ++ "\n255\n")
    write.body(r1, pixels)

def saved(canvas: C.Canvas) -> IO(Unit):
  match canvas:
    case C.Failed{message}:
      IO.die(Unit, 1, message)
    case C.Canvas{+w, +h, scale, d, +side, clip, +pixels}:
      write(w, h, bytes(U32.to_nat((w * h : U32)), pixels, side, w, (w * h : U32), []))

def fielded(r: Result<&2, &2, String, FL.Field>, +m: M.Metrics, +font: F.Font) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{+empty}:
      # RGBA 151E2BFF: the demo's panel colour.
      saved(rows(4n, m, font, empty, 0, C.new(900, 400, 1.0, 354033919)))

# The button label measured by the text pipeline.
def measured(r: Result<&2, &2, String, Text.Run>, +font: F.Font) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{run}:
      fielded(FL.field(font, 18.0, ""), Text.metrics(run), font)

def loaded(r: Result<&2, &2, String, F.Font>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{+font}:
      measured(Text.prepare(font, "Go", 18.0, 1000000.0, 1.0), font)

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    loaded(r)
