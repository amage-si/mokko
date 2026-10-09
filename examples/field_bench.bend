import Base
import ../field.bend as FL
import ../../Kairo/types.bend as K
import ../../Kairo/edit.bend as KE
import ../../Kairo/main.bend as KM
import ../../Tessra/geometry.bend as G
import ../../Runika/font.bend as F

# Times `feed` per keystroke on a 256-scalar Portuguese line at 20 px
# (IO.now has millisecond resolution, so each loop runs many times).
# Typing and Backspace alternate at the end of the text, so every feed lays
# out 255 or 256 scalars with Syllo and rebuilds the caret stops. A caret
# move reuses the stops; a view builds the primitives. Each loop folds its
# result into a checksum printed before the next clock read.

def text() -> String:
  "Texto real em Bend: ação, coração, café e pão. " ++ "Olá! Edição de um campo só, com acentos: é, ê, ã, õ, ç. " ++
    "Texto real em Bend: ação, coração, café e pão. " ++ "Olá! Edição de um campo só, com acentos: é, ê, ã, õ, ç. " ++
    "Mais dezoito letras de teste, para fechar a linha."

def bounds() -> G.Rect:
  G.Rect{20.0, 20.0, 400.0, 44.0}

def node() -> K.Node:
  FL.field_node(1, bounds(), "Bench")

def field_of(fed: FL.Fed) -> FL.Field:
  FL.Fed{f, d, r} = fed
  f

def scalars(e: KE.Edit) -> U32:
  KE.Edit{t, n, c, a} = e
  n

def count(f: FL.Field) -> U32:
  scalars(FL.edit_of(f))

def action(+odd: Bool) -> K.Action:
  Bool.pick(K.Action, odd, K.TextDelivered{1, "a"}, K.EditRequested{1, K.DeleteBack{K.ByChar{}}})

# Backspace first (256 -> 255 scalars), then "a" (255 -> 256), alternating.
def typing(n: Nat, +font: F.Font, f: FL.Field, +odd: Bool, acc: U32) -> U32:
  match n:
    case 0n:
      (acc + count(f) : U32)
    case 1n+p:
      +next = field_of(FL.feed(font, 20.0, bounds(), 1, f, action(odd)))
      typing(p, font, next, Bool.not(odd), (acc + count(next) : U32))

def moving(n: Nat, +font: F.Font, f: FL.Field, +odd: Bool, acc: U32) -> U32:
  match n:
    case 0n:
      acc
    case 1n+p:
      +cmd = Bool.pick(K.EditCommand, odd, K.MoveRight{K.ByChar{}, False{}}, K.MoveLeft{K.ByChar{}, False{}})
      +next = field_of(FL.feed(font, 20.0, bounds(), 1, f, K.EditRequested{1, cmd}))
      moving(p, font, next, Bool.not(odd), (acc + count(next) : U32))

def primitives(v: Result<&2, &2, String, FL.FieldView>) -> U32:
  match v:
    case Fail{e}: 0
    case Done{fv}: 1

def viewing(n: Nat, +st: K.State, +f: FL.Field, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p: viewing(p, st, f, (acc + primitives(FL.view(node(), st, f, 20.0, FL.field_theme(), "")) : U32))

def report(+name: String, +runs: U32, +t0: Nat, +t1: Nat, +check: U32) -> IO(Unit):
  IO.print(name ++ ": " ++ Nat.show(Nat.sub(t1, t0)) ++ " ms for " ++ U32.show(runs) ++ " runs  (check " ++ U32.show(check) ++ ")")

def unwrap(-A: Data, r: Result<&2, &2, String, A>) -> IO(A):
  match r:
    case Fail{e}: IO.die(A, 1, e)
    case Done{v}: IO.pure(A, v)

def started(r: Result<&2, &2, K.Error, K.State>) -> Result<&2, &2, String, K.State>:
  match r:
    case Fail{e}: Fail{"Kairo rejected the field"}
    case Done{s}: Done{s}

def main() -> IO(Unit):
  do IO<Unit>:
    fr : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- unwrap(F.Font, fr)
    +f : FL.Field <- unwrap(FL.Field, FL.field(font, 20.0, text()))
    +st0 : K.State <- unwrap(K.State, started(KM.init([node()], 800.0, 200.0)))
    +st : K.State = KM.replay([K.KeyDown{K.TabKey{}, False{}, False{}}], st0)
    IO.print("scalars " ++ U32.show(count(f)))
    +a0 : Nat <- IO.now()
    +a : U32 = typing(2000n, font, f, False{}, 0)
    IO.print("typing checksum " ++ U32.show(a))
    +a1 : Nat <- IO.now()
    +b : U32 = moving(20000n, font, f, False{}, 0)
    IO.print("moving checksum " ++ U32.show(b))
    +b1 : Nat <- IO.now()
    +c : U32 = viewing(20000n, st, f, 0)
    IO.print("view checksum " ++ U32.show(c))
    +c1 : Nat <- IO.now()
    report("feed, typing or Backspace (lays out 255-256 scalars)", 2000, a0, a1, a)
    report("feed, caret move (no layout)", 20000, a1, b1, b)
    report("view, focused", 20000, b1, c1, c)
