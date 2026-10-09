import Base
import ../main.bend as M
import ../field.bend as FL
import ../chromi_text.bend as Text
import ../../Kairo/main.bend as KM
import ../../Kairo/types.bend as K
import ../../Kairo/edit.bend as KE
import ../../Tessra/geometry.bend as G
import ../../Chromi/main.bend as C
import ../../Chromi/geometry.bend as CG
import ../../Chromi/tree.bend as Tree
import ../../Runika/font.bend as F

# Paints five text-field states with Chromi, without a window, and writes
# them as build/field-render.ppm (340x340, run from the Mokko directory):
#   1. empty and unfocused: the placeholder;
#   2. focused, caret at the end;
#   3. a drag selection;
#   4. "€" refused: the error border;
#   5. a long text scrolled to keep the caret at the right edge.
# Each field is driven through Kairo like a host does. Fill and Stroke are
# painted square (C.fill_rect, C.stroke_rect); a TextRun is laid out by
# Syllo, rasterized by Dithra and clipped (chromi_text.bend).

def bounds(+k: U32) -> G.Rect:
  G.Rect{20.0, (20.0 + U32.to_f32(k) * 64.0 : F32), 300.0, 44.0}

def middle(+k: U32) -> F32:
  (42.0 + U32.to_f32(k) * 64.0 : F32)

def fed_field(fed: FL.Fed) -> FL.Field:
  FL.Fed{f, d, r} = fed
  f

def fold(actions: +List<K.Action>, +font: F.Font, +r: G.Rect, f: FL.Field) -> FL.Field:
  match actions:
    case Nil{}:
      f
    case Con{a, rest}:
      fold(rest, font, r, fed_field(FL.feed(font, 20.0, r, 1, f, a)))

type Scene is Data:
  Scene{state: K.State, field: FL.Field}

def stepped(c: K.Change, +font: F.Font, +r: G.Rect, f: FL.Field) -> Scene:
  K.Change{st, +actions, d, l} = c
  Scene{st, fold(actions, font, r, f)}

def play(inputs: +List<K.Input>, +font: F.Font, +r: G.Rect, s: Scene) -> Scene:
  match inputs:
    case Nil{}:
      s
    case Con{i, rest}:
      Scene{st, f} = s
      play(rest, font, r, stepped(KM.dispatch(st, i), font, r, f))

def scripted(+k: U32) -> +List<K.Input>:
  match k:
    case 0:
      Nil{}
    case 1:
      [K.PointerDown{310.0, middle(1), 0}, K.PointerUp{310.0, middle(1), 0}]
    case 2:
      [K.PointerDown{32.0, middle(2), 0}, K.PointerMove{90.0, middle(2)}, K.PointerUp{90.0, middle(2), 0}]
    case 3:
      [K.PointerDown{310.0, middle(3), 0}, K.PointerUp{310.0, middle(3), 0}, K.TextInput{"€"}]
    case _:
      [K.PointerDown{100.0, middle(4), 0}, K.PointerUp{100.0, middle(4), 0}, K.Editing{K.MoveRight{K.ToEdge{}, False{}}}]

def initial(+k: U32) -> String:
  match k:
    case 0:
      ""
    case 1:
      "Olá, ação"
    case 2:
      "Olá, ação"
    case 3:
      "Olá"
    case _:
      "Texto real em Bend: ação, coração, café e pão."

def started(r: Result<&2, &2, K.Error, K.State>) -> Result<&2, &2, String, K.State>:
  match r:
    case Fail{e}:
      Fail{"Kairo rejected the field"}
    case Done{s}:
      Done{s}

def scene(+font: F.Font, +k: U32) -> Result<&2, &2, String, Scene>:
  do Result<&2, &2, String, Scene>:
    st : K.State <- started(KM.init([FL.field_node(1, bounds(k), "Name")], 340.0, 340.0))
    f : FL.Field <- FL.field(font, 20.0, initial(k))
    return play(scripted(k), font, bounds(k), Scene{st, f})

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

def viewed(v: Result<&2, &2, String, FL.FieldView>, +font: F.Font, canvas: C.Canvas) -> C.Canvas:
  match v:
    case Fail{e}:
      C.reject(canvas, e)
    case Done{FL.FieldView{M.View{ps, sem}, e}}:
      paint(ps, font, canvas)

def drawn(s: Result<&2, &2, String, Scene>, +font: F.Font, +k: U32, canvas: C.Canvas) -> C.Canvas:
  match s:
    case Fail{e}:
      C.reject(canvas, e)
    case Done{Scene{st, f}}:
      viewed(FL.view(FL.field_node(1, bounds(k), "Name"), st, f, 20.0, FL.field_theme(), "Your name"), font, canvas)

def scenes(n: Nat, +font: F.Font, +k: U32, canvas: C.Canvas) -> C.Canvas:
  match n:
    case 0n:
      canvas
    case 1n+p:
      scenes(p, font, (k + 1 : U32), drawn(scene(font, k), font, k, canvas))

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
    IO.print("wrote build/field-render.ppm")

def write.body(r: File & Result<&1, &1, U32 & String, Unit>, pixels: List<&2, U32>) -> IO(Unit):
  (f, ok) = r
  do IO<Unit>:
    r2 : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, pixels)
    write.done(r2)

def write(+w: U32, +h: U32, pixels: List<&2, U32>) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File, File.open("build/field-render.ppm", "w"))
    r1 : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, "P6\n" ++ U32.show(w) ++ " " ++ U32.show(h) ++ "\n255\n")
    write.body(r1, pixels)

def saved(canvas: C.Canvas) -> IO(Unit):
  match canvas:
    case C.Failed{message}:
      IO.die(Unit, 1, message)
    case C.Canvas{+w, +h, scale, d, +side, clip, +pixels}:
      write(w, h, bytes(U32.to_nat((w * h : U32)), pixels, side, w, (w * h : U32), []))

def loaded(r: Result<&2, &2, String, F.Font>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{+font}:
      # RGBA 0D141EFF: the demo's dark background.
      saved(scenes(5n, font, 0, C.new(340, 340, 1.0, 219422463)))

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    loaded(r)
