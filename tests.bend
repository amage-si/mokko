import Base
import ./main.bend as M
import ../Kairo/main.bend as K
import ../Kairo/types.bend as T
import ../Tessra/geometry.bend as G
import ../Tessra/test_support.bend as A

def node() -> T.Node:
  M.button_node(1, G.Rect{10.0, 20.0, 120.0, 44.0}, "Contar", True{})

def fixture() -> T.State:
  T.State{[node()], 0, 0, 0, 0, 0, False{}, True{}, True{}, 400.0, 200.0}

def view(s: T.State) -> Result<&2, &2, String, M.View>:
  M.button(node(), s, M.Metrics{60.0, 20.0, 14.0}, 18.0, M.theme())

def color(v: Result<&2, &2, String, M.View>) -> U32:
  match v:
    case Done{M.View{Con{M.Fill{r, rgba}, rest}, sem}}:
      rgba
    case _:
      0

def primitive_count(v: Result<&2, &2, String, M.View>) -> U32:
  match v:
    case Fail{e}:
      0
    case Done{M.View{ps, sem}}:
      U32.from_nat(List.length(&2, M.Primitive, ps))

def semantic_valid(v: Result<&2, &2, String, M.View>) -> Bool:
  match v:
    case Done{M.View{ps, M.Semantic{1, T.ButtonRole{}, label, r, True{}, True{}, False{}, Con{M.Activate{}, Nil{}}}}}:
      String.eq(label, "Contar")
    case _:
      False{}

def invalid(v: Result<&2, &2, String, M.View>) -> Bool:
  Result.is_fail(&2, &2, String, M.View, v)

def label_position(v: Result<&2, &2, String, M.View>) -> Bool:
  match v:
    case Done{M.View{Con{M.Fill{r, c}, Con{M.TextRun{x, top, baseline, l, s, clip, color}, Nil{}}}, sem}}:
      F32.is_eq(x, 40.0) && F32.is_eq(top, 32.0) && F32.is_eq(baseline, 46.0) && G.equal(clip, G.Rect{18.0, 24.0, 104.0, 36.0})
    case _:
      False{}

def text_semantics(v: Result<&2, &2, String, M.View>) -> Bool:
  match v:
    case Done{M.View{Con{M.TextRun{x, top, baseline, label, size, clip, color}, Nil{}}, M.Semantic{2, T.TextRole{}, sl, r, True{}, False{}, False{}, Nil{}}}}:
      F32.is_eq(baseline, 24.0) && String.eq(label, "Texto") && String.eq(sl, "Texto")
    case _:
      False{}

def minimum(s: G.Size) -> Bool:
  G.Size{w, h} = s
  F32.is_eq(w, 92.0) && F32.is_eq(h, 44.0)

def main() -> IO(Unit):
  do IO<Unit>:
    A.expect(U32.is_eq(color(view(fixture())), 610062079), "normal button fill")
    A.expect(U32.is_eq(color(view(K.replay([T.PointerMove{20.0, 30.0}], fixture()))), 829482751), "hover changes button fill")
    A.expect(U32.is_eq(color(view(K.replay([T.PointerDown{20.0, 30.0, 0}], fixture()))), 406820607), "press changes button fill")
    A.expect(U32.is_eq(color(view(K.replay([T.PointerDown{20.0, 30.0, 0}, T.PointerUp{20.0, 30.0, 0}], fixture()))), 829482751), "release returns hover fill")
    A.expect(U32.is_eq(primitive_count(view(fixture())), 2), "unfocused button emits fill and text")
    A.expect(U32.is_eq(primitive_count(view(K.replay([T.KeyDown{T.TabKey{}, False{}, False{}}], fixture()))), 3), "focus emits visible inner ring")
    A.expect(semantic_valid(view(K.replay([T.KeyDown{T.TabKey{}, False{}, False{}}], fixture()))), "semantic role label action and focus exported")
    A.expect(label_position(view(fixture())), "label centered using supplied metrics and clipped")
    A.expect(minimum(M.button_size(M.Metrics{60.0, 20.0, 14.0})), "button measurement includes padding and minimum height")
    A.expect(invalid(M.button(node(), fixture(), M.Metrics{1.0, 10.0, 12.0}, 18.0, M.theme())), "invalid ascent rejected")
    A.expect(invalid(M.button(node(), fixture(), M.Metrics{F32.div(0.0, 0.0), 20.0, 14.0}, 18.0, M.theme())), "NaN text width rejected")
    A.expect(invalid(M.button(node(), fixture(), M.Metrics{60.0, 20.0, 14.0}, 0.0, M.theme())), "zero font size rejected")
    A.expect(text_semantics(M.text(M.text_node(2, G.Rect{10.0, 10.0, 100.0, 20.0}, "Texto"), fixture(), M.Metrics{50.0, 20.0, 14.0}, 18.0, 4294967295)), "text draws at baseline and exports text semantics")
    A.expect(U32.is_eq(color(M.button(M.button_node(1, G.Rect{10.0, 20.0, 120.0, 44.0}, "Contar", False{}), fixture(), M.Metrics{60.0, 20.0, 14.0}, 18.0, M.theme())), 910250751), "disabled button palette")
    IO.print("Mokko: 14 tests passed")
