import Base
import ../main.bend as M
import ../field.bend as FL
import ../../Kairo/main.bend as KM
import ../../Kairo/types.bend as K
import ../../Kairo/edit.bend as KE
import ../../Tessra/geometry.bend as G
import ../../Runika/font.bend as F

# One text field driven by a scripted session, without a window. Each input
# goes to Kairo; every action Kairo emits is fed to the field, as a host
# does. After each step the script prints the text, caret, anchor, scroll
# origin, refusal and request, then the final primitives. Needs Liberation
# Sans (the field lays its text out with Syllo).

def bounds() -> G.Rect:
  G.Rect{20.0, 20.0, 200.0, 44.0}

def node() -> K.Node:
  FL.field_node(1, bounds(), "Name")

type Step is Data:
  Step{title: String, input: K.Input}

def script() -> +List<Step>:
  [Step{"click into the field", K.PointerDown{100.0, 40.0, 0}},
    Step{"release", K.PointerUp{100.0, 40.0, 0}},
    Step{"type \"Olá, ação\"", K.TextInput{"Olá, ação"}},
    Step{"type \"☕\" (refused)", K.TextInput{"☕"}},
    Step{"paste \"a☕b\" (refused whole)", K.TextInput{"a☕b"}},
    Step{"Space (never activates)", K.KeyDown{K.SpaceKey{}, False{}, False{}}},
    Step{"type \" mundo inteiro, feliz\"", K.TextInput{" mundo inteiro, feliz"}},
    Step{"Home", K.Editing{K.MoveLeft{K.ToEdge{}, False{}}}},
    Step{"Shift+Ctrl+Right", K.Editing{K.MoveRight{K.ByWord{}, True{}}}},
    Step{"Ctrl+C", K.Editing{K.Copy{}}},
    Step{"drag from x 32 to x 70", K.PointerDown{32.0, 40.0, 0}},
    Step{"  move", K.PointerMove{70.0, 40.0}},
    Step{"  release", K.PointerUp{70.0, 40.0, 0}},
    Step{"Ctrl+X", K.Editing{K.Cut{}}},
    Step{"Ctrl+V", K.Editing{K.Paste{}}}]

def kept(+next: KE.Request, before: KE.Request) -> KE.Request:
  match next:
    case KE.NoRequest{}:
      before
    case _:
      next

def merged(next: FL.Fed, before: FL.Fed) -> FL.Fed:
  FL.Fed{f, +d, r} = next
  FL.Fed{bf, +bd, br} = before
  FL.Fed{f, d || bd, kept(r, br)}

def fed_field(fed: FL.Fed) -> FL.Field:
  FL.Fed{f, d, r} = fed
  f

def fold(actions: +List<K.Action>, +font: F.Font, +fed: FL.Fed) -> FL.Fed:
  match actions:
    case Nil{}:
      fed
    case Con{a, rest}:
      fold(rest, font, merged(FL.feed(font, 20.0, bounds(), 1, fed_field(fed), a), fed))

def quoted(t: String) -> String:
  "\"" ++ t ++ "\""

def request(r: KE.Request) -> String:
  match r:
    case KE.NoRequest{}:
      ""
    case KE.CopyText{t}:
      " request=copy " ++ quoted(t)
    case KE.PasteText{}:
      " request=paste"

def refusal(m: Maybe<&2, String>) -> String:
  match m:
    case None{}:
      ""
    case Some{t}:
      " refused=" ++ quoted(t)

def flag(on: Bool, name: String) -> String:
  match on:
    case True{}:
      " " ++ name
    case False{}:
      ""

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
      "TextRun " ++ quoted(label) ++ " at " ++ F32.show(x) ++ "," ++ F32.show(top) ++ " baseline=" ++ F32.show(baseline) ++ " clip=" ++ rect(clip)

def print_all(ps: +List<M.Primitive>) -> IO(Unit):
  match ps:
    case Nil{}:
      IO.pure(Unit, Unit{})
    case Con{p, rest}:
      do IO<Unit>:
        IO.print("  " ++ primitive(p))
        print_all(rest)

def state_line(v: FL.FieldView, +dirty: Bool, +activated: U32, req: KE.Request, refused: Maybe<&2, String>) -> String:
  FL.FieldView{M.View{ps, sem}, FL.EditState{id, text, caret, anchor, p, ox, oy, lh, stops}} = v
  "  " ++ quoted(text) ++ " caret=" ++ U32.show(caret) ++ " anchor=" ++ U32.show(anchor) ++ " origin_x=" ++ F32.show(ox) ++
    flag(dirty, "dirty") ++ flag(U32.is_gt(activated, 0), "ACTIVATED") ++ refusal(refused) ++ request(req)

def viewed(v: Result<&2, &2, String, FL.FieldView>, +dirty: Bool, +activated: U32, req: KE.Request, refused: Maybe<&2, String>) -> IO(Unit):
  match v:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{fv}:
      IO.print(state_line(fv, dirty, activated, req, refused))

def show(+st: K.State, fed: FL.Fed, +activated: U32) -> IO(Unit):
  FL.Fed{+f, dirty, req} = fed
  viewed(FL.view(node(), st, f, 20.0, FL.field_theme(), "Your name"), dirty, activated, req, FL.message(f))

def finish(v: Result<&2, &2, String, FL.FieldView>) -> IO(Unit):
  match v:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{FL.FieldView{M.View{ps, sem}, e}}:
      do IO<Unit>:
        IO.print("Final primitives (box, border, selection, text, caret, focus ring):")
        print_all(ps)

type Session is Data:
  Session{state: K.State, field: FL.Field}

def stepped(c: K.Change, +font: F.Font, f: FL.Field) -> IO(Session):
  K.Change{+st, +actions, d, l} = c
  +fed = fold(actions, font, FL.Fed{f, False{}, KE.NoRequest{}})
  do IO<Session>:
    show(st, fed, KM.activation_count(actions))
    return Session{st, fed_field(fed)}

def play(steps: +List<Step>, +font: F.Font, s: Session) -> IO(Unit):
  match steps:
    case Nil{}:
      Session{st, f} = s
      finish(FL.view(node(), st, f, 20.0, FL.field_theme(), "Your name"))
    case Con{Step{title, input}, rest}:
      Session{st, f} = s
      do IO<Unit>:
        IO.print(title)
        next : Session <- stepped(KM.dispatch(st, input), font, f)
        play(rest, font, next)

def started(r: Result<&2, &2, K.Error, K.State>, +font: F.Font, +f: FL.Field) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, "Kairo rejected the field")
    case Done{+st}:
      do IO<Unit>:
        IO.print("Empty field, unfocused:")
        show(st, FL.Fed{f, False{}, KE.NoRequest{}}, 0)
        play(script(), font, Session{st, f})

def ready(r: Result<&2, &2, String, FL.Field>, +font: F.Font) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{f}:
      started(KM.init([node()], 400.0, 120.0), font, f)

def loaded(r: Result<&2, &2, String, F.Font>) -> IO(Unit):
  match r:
    case Fail{e}:
      IO.die(Unit, 1, e)
    case Done{+font}:
      ready(FL.field(font, 20.0, ""), font)

def main() -> IO(Unit):
  do IO<Unit>:
    r : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    loaded(r)
