import Base
import ./demo.bend as D
import ./main.bend as M
import ../Kairo/main.bend as K
import ../Kairo/types.bend as T
import ../Tessra/geometry.bend as G
import ../Tessra/test_support.bend as A
import ../Runika/font.bend as F

type Report is Data:
  Report{clicks: Nat, clean: Bool, frame: D.Frame, narrow: D.Frame, button: G.Rect}

def model(u: D.Update) -> D.Model:
  D.Update{m, d, l, a} = u
  m

def replay(events: +List<T.Input>, m: D.Model, +font: F.Font) -> Result<&2, &2, String, D.Model>:
  match events:
    case Nil{}:
      Done{m}
    case Con{event, rest}:
      do Result<&2, &2, String, D.Model>:
        update : D.Update <- D.update(m, event, font)
        replay(rest, model(update), font)

def button_bounds(rs: +List<G.Rect>) -> Result<&2, &2, String, G.Rect>:
  match rs:
    case Con{r, Nil{}}:
      Done{r}
    case _:
      Fail{"demo button is absent"}

def runtime_bounds(s: T.State) -> Result<&2, &2, String, G.Rect>:
  T.State{nodes, h, f, cap, k, t, d, live, active, w, hh} = s
  button_bounds(K.bounds(nodes, 2))

def bounds(m: D.Model) -> Result<&2, &2, String, G.Rect>:
  D.Model{s, c, o} = m
  runtime_bounds(s)

def sequence(r: G.Rect) -> +List<T.Input>:
  G.Rect{x, y, w, h} = r
  +cx = (x + w / 2.0 : F32)
  +cy = (y + h / 2.0 : F32)
  [T.PointerMove{cx, cy}, T.PointerDown{cx, cy, 0}, T.PointerUp{1.0, 1.0, 0}, T.PointerDown{cx, cy, 0}, T.PointerUp{cx, cy, 0}, T.PointerUp{cx, cy, 0}, T.KeyDown{T.SpaceKey{}, False{}, False{}}, T.KeyDown{T.SpaceKey{}, True{}, False{}}, T.KeyUp{T.SpaceKey{}}, T.KeyUp{T.SpaceKey{}}]

def is_clean(u: D.Update) -> Bool:
  match u:
    case D.Update{m, Nil{}, False{}, Nil{}}:
      True{}
    case _:
      False{}

def click_count(m: D.Model) -> Nat:
  D.Model{s, c, o} = m
  c

def exercise(+font: F.Font) -> Result<&2, &2, String, Report>:
  do Result<&2, &2, String, Report>:
    +initial : D.Model <- D.init(font, 480.0, 320.0)
    +r : G.Rect <- bounds(initial)
    +updated : D.Model <- replay(sequence(r), initial, font)
    frame : D.Frame <- D.view(updated, font)
    idle : D.Update <- D.update(updated, T.KeyUp{T.SpaceKey{}}, font)
    small : D.Update <- D.update(updated, T.Resize{180.0, 320.0}, font)
    narrow : D.Frame <- D.view(model(small), font)
    return Report{click_count(updated), is_clean(idle), frame, narrow, r}

def has_count(ps: +List<M.Primitive>) -> Bool:
  match ps:
    case Nil{}:
      False{}
    case Con{M.TextRun{x, y, b, label, s, clip, c}, rest}:
      String.eq(label, "Cliques: 2") || has_count(rest)
    case Con{p, rest}:
      has_count(rest)

def frame_count(frame: D.Frame) -> Bool:
  D.Frame{ps, ss, overflow} = frame
  has_count(ps)

def has_semantic(ss: +List<M.Semantic>) -> Bool:
  match ss:
    case Nil{}:
      False{}
    case Con{M.Semantic{2, T.ButtonRole{}, label, r, True{}, True{}, False{}, Con{M.Activate{}, Nil{}}}, rest}:
      String.eq(label, "Clique aqui")
    case Con{other, rest}:
      has_semantic(rest)

def semantic(frame: D.Frame) -> Bool:
  D.Frame{ps, ss, overflow} = frame
  has_semantic(ss)

def in_view(ss: +List<M.Semantic>) -> Bool:
  match ss:
    case Nil{}:
      True{}
    case Con{M.Semantic{id, role, label, G.Rect{+x, y, w, h}, e, f, p, a}, rest}:
      (x >= 0.0 : F32) && (x + w <= 180.0 : F32) && in_view(rest)

def narrow_fits(frame: D.Frame) -> Bool:
  D.Frame{p, s, overflow} = frame
  in_view(s) && Bool.not(overflow)

def checked(result: Result<&2, &2, String, Report>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, error)
    case Done{Report{clicks, clean, +frame, narrow, G.Rect{x, y, w, h}}}:
      do IO<Unit>:
        A.expect(Nat.is_eq(clicks, 2n), "real-font demo counts one pointer and one keyboard activation")
        A.expect(clean, "demo duplicate release has no damage")
        A.expect(frame_count(frame), "draw list contains updated click count")
        A.expect(semantic(frame), "demo exports focused actionable button semantics")
        A.expect(narrow_fits(narrow), "Tessra relayout fits 180 logical pixels with real text metrics")
        IO.print("Button bounds: " ++ F32.show(x) ++ ", " ++ F32.show(y) ++ ", " ++ F32.show(w) ++ ", " ++ F32.show(h))
        IO.print("Mokko demo: 5 tests passed with LiberationSans-Regular.ttf")

def loaded(result: Result<&2, &2, String, F.Font>) -> IO(Unit):
  match result:
    case Fail{error}:
      IO.die(Unit, 1, error)
    case Done{font}:
      checked(exercise(font))

def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    loaded(result)
