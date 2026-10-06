import Base
import ../main.bend as M
import ../../Kairo/main.bend as K
import ../../Kairo/types.bend as T
import ../../Tessra/geometry.bend as G

# Prints the draw primitives and semantics Mokko produces for one button,
# before and after Kairo moves keyboard focus to it. No window or font needed:
# the label metrics are given directly here (a real host measures them).
def node() -> T.Node:
  M.button_node(1, G.Rect{10.0, 20.0, 120.0, 44.0}, "Count", True{})

def rect(r: G.Rect) -> String:
  G.Rect{x, y, w, h} = r
  "[" ++ F32.show(x) ++ ", " ++ F32.show(y) ++ ", " ++ F32.show(w) ++ "x" ++ F32.show(h) ++ "]"

def primitive(p: M.Primitive) -> String:
  match p:
    case M.Fill{r, rgba}:
      "Fill " ++ rect(r) ++ " rgba=" ++ U32.show(rgba)
    case M.Stroke{r, width, rgba}:
      "Stroke " ++ rect(r) ++ " width=" ++ F32.show(width) ++ " rgba=" ++ U32.show(rgba)
    case M.TextRun{x, top, baseline, label, size, clip, rgba}:
      "TextRun \"" ++ label ++ "\" at " ++ F32.show(x) ++ "," ++ F32.show(top) ++ " baseline=" ++ F32.show(baseline) ++ " clip=" ++ rect(clip)

def print_all(ps: +List<M.Primitive>) -> IO(Unit):
  match ps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{p, rest}:
      do IO<Unit>:
        IO.print("  " ++ primitive(p))
        print_all(rest)

def flag(name: String, on: Bool) -> String:
  match on:
    case True{}: " " ++ name
    case False{}: ""

def semantic(s: M.Semantic) -> String:
  M.Semantic{id, role, label, bounds, enabled, focused, pressed, actions} = s
  "  semantic: id=" ++ U32.show(id) ++ " label=\"" ++ label ++ "\"" ++ flag("enabled", enabled) ++ flag("focused", focused) ++ flag("pressed", pressed)

def show(title: String, view: Result<&2, &2, String, M.View>) -> IO(Unit):
  match view:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{M.View{ps, sem}}:
      do IO<Unit>:
        IO.print(title)
        print_all(ps)
        IO.print(semantic(sem))

def render(state: T.State) -> Result<&2, &2, String, M.View>:
  M.button(node(), state, M.Metrics{50.0, 20.0, 15.0}, 18.0, M.theme())

def both(+state: T.State) -> IO(Unit):
  do IO<Unit>:
    show("Idle:", render(state))
    show("After Tab:", render(K.next(K.dispatch(state, T.KeyDown{T.TabKey{}, False{}, False{}}))))

def start(result: Result<&2, &2, T.Error, T.State>) -> IO(Unit):
  match result:
    case Fail{e}:
      IO.die(Unit, 1, "Kairo rejected the button")
    case Done{state}:
      both(state)

def main() -> IO(Unit):
  start(K.init([node()], 320.0, 120.0))
