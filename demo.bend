import Base
import ./main.bend as M
import ../Tessra/main.bend as L
import ../Tessra/geometry.bend as G
import ../Kairo/types.bend as T
import ../Kairo/main.bend as K
import ../Syllo/main.bend as S
import ../Runika/font.bend as F

# Pure application model. Chromi/Ankra own rendering and the window/event loop.
type Model is Data:
  Model{runtime: T.State, clicks: Nat, overflow: Bool}

type Update is Data:
  Update{model: Model, dirty: +List<G.Rect>, layout: Bool, actions: +List<T.Action>}

type Frame is Data:
  Frame{primitives: +List<M.Primitive>, semantics: +List<M.Semantic>, overflow: Bool}

type Measurements is Data:
  Measurements{title: M.Metrics, button: M.Metrics, status: M.Metrics}

type Arranged is Data:
  Arranged{nodes: +List<T.Node>, overflow: Bool}

def title() -> String:
  "AMAGE Eco"

def label() -> String:
  "Clique aqui"

def status(clicks: Nat) -> String:
  "Cliques: " ++ Nat.show(clicks)

def metrics(layout: S.Layout) -> M.Metrics:
  S.Layout{p, w, h, asc, desc, lh, lines} = layout
  M.Metrics{w, h, asc}

def measure(+font: F.Font, clicks: Nat, +width: F32) -> Result<&2, &2, String, Measurements>:
  do Result<&2, &2, String, Measurements>:
    t : S.Layout <- S.layout(font, title(), 28.0, F32.max(1.0, (width - 64.0 : F32)))
    b : S.Layout <- S.layout(font, label(), 18.0, 1000000.0)
    s : S.Layout <- S.layout(font, status(clicks), 16.0, 1000000.0)
    return Measurements{metrics(t), metrics(b), metrics(s)}

def child(id: U32, preferred: G.Size, +available: F32) -> L.Child:
  L.Child{id, preferred, L.Constraints{G.Size{0.0, 0.0}, G.Size{available, 1000000.0}}}

def configured(m: Measurements, +w: F32, h: F32) -> Result<&2, &2, L.Error, L.Layout>:
  Measurements{t, b, M.Metrics{sw, sh, sa}} = m
  +available = F32.max(0.0, (w - 64.0 : F32))
  L.layout(G.Rect{0.0, 0.0, w, h}, L.Config{L.Column{}, G.Insets{32.0, 32.0, 32.0, 32.0}, 20.0, L.Leading{}, L.Center{}},
    [child(1, M.text_size(t), available), child(2, M.button_size(b), available), child(3, G.Size{available, sh}, available)])

def nodes_from(ps: +List<L.Placement>, clicks: Nat) -> Result<&2, &2, String, +List<T.Node>>:
  match ps:
    case Con{L.Placement{1, title_rect}, Con{L.Placement{2, button_rect}, Con{L.Placement{3, status_rect}, Nil{}}}}:
      Done{[M.text_node(1, title_rect, title()), M.button_node(2, button_rect, label(), True{}), M.text_node(3, status_rect, status(clicks))]}
    case _:
      Fail{"Mokko demo: unexpected Tessra placement sequence"}

def arranged(result: Result<&2, &2, L.Error, L.Layout>, clicks: Nat) -> Result<&2, &2, String, Arranged>:
  match result:
    case Fail{e}:
      Fail{"Mokko demo: invalid layout geometry or constraints"}
    case Done{L.Layout{c, ps, overflow}}:
      do Result<&2, &2, String, Arranged>:
        nodes : +List<T.Node> <- nodes_from(ps, clicks)
        return Arranged{nodes, overflow}

def arrange(font: F.Font, +clicks: Nat, +w: F32, +h: F32) -> Result<&2, &2, String, Arranged>:
  do Result<&2, &2, String, Arranged>:
    measures : Measurements <- measure(font, clicks, w)
    arranged(configured(measures, w, h), clicks)

def initialized(result: Result<&2, &2, T.Error, T.State>, overflow: Bool) -> Result<&2, &2, String, Model>:
  match result:
    case Fail{e}:
      Fail{"Mokko demo: Kairo rejected initial nodes or viewport"}
    case Done{s}:
      Done{Model{s, 0n, overflow}}

def init_arranged(a: Arranged, w: F32, h: F32) -> Result<&2, &2, String, Model>:
  Arranged{nodes, overflow} = a
  initialized(K.init(nodes, w, h), overflow)

def init(font: F.Font, +w: F32, +h: F32) -> Result<&2, &2, String, Model>:
  do Result<&2, &2, String, Model>:
    a : Arranged <- arrange(font, 0n, w, h)
    init_arranged(a, w, h)

def merge_label(change: T.Change, clicks: Nat, overflow: Bool, dirty: +List<G.Rect>, layout: Bool, actions: +List<T.Action>) -> Update:
  T.Change{s, label_actions, extra, label_layout} = change
  Update{Model{s, clicks, overflow}, List.append(&2, G.Rect, dirty, extra), layout, actions}

def reflowed(a: Arranged, s: T.State, clicks: Nat, dirty: +List<G.Rect>, actions: +List<T.Action>) -> Update:
  Arranged{nodes, overflow} = a
  T.State{old, hover, focus, c, k, target, down, live, active, w, h} = s
  Update{Model{T.State{nodes, 0, focus, 0, 0, 0, False{}, live, active, w, h}, clicks, overflow}, dirty, True{}, actions}

def finish_update(layout: Bool, font: F.Font, +s: T.State, +clicks: Nat, overflow: Bool, dirty: +List<G.Rect>, actions: +List<T.Action>) -> Result<&2, &2, String, Update>:
  match layout:
    case False{}:
      Done{merge_label(K.set_label(s, 3, status(clicks)), clicks, overflow, dirty, False{}, actions)}
    case True{}:
      T.State{nodes, hh, f, c, k, t, d, l, active, w, h} = s
      do Result<&2, &2, String, Update>:
        a : Arranged <- arrange(font, clicks, w, h)
        return reflowed(a, s, clicks, dirty, actions)

def changed(change: T.Change, font: F.Font, clicks: Nat, overflow: Bool) -> Result<&2, &2, String, Update>:
  T.Change{s, +actions, dirty, layout} = change
  next_clicks = Nat.add(clicks, U32.to_nat(K.activation_count(actions)))
  finish_update(layout, font, s, next_clicks, overflow, dirty, actions)

def update(model: Model, event: T.Input, font: F.Font) -> Result<&2, &2, String, Update>:
  Model{s, clicks, overflow} = model
  changed(K.dispatch(s, event), font, clicks, overflow)

def combine(a: M.View, b: M.View, c: M.View, overflow: Bool) -> Frame:
  M.View{ap, as} = a
  M.View{bp, bs} = b
  M.View{cp, cs} = c
  Frame{List.append(&2, M.Primitive, ap, List.append(&2, M.Primitive, bp, cp)), [as, bs, cs], overflow}

def render_nodes(nodes: +List<T.Node>, +s: T.State, measures: Measurements, overflow: Bool) -> Result<&2, &2, String, Frame>:
  match nodes:
    case Con{title_node, Con{button_node, Con{status_node, Nil{}}}}:
      Measurements{tm, bm, sm} = measures
      do Result<&2, &2, String, Frame>:
        # RGBA EDF2FAFF: pale title on the dark panel.
        a : M.View <- M.text(title_node, s, tm, 28.0, 3992124159)
        b : M.View <- M.button(button_node, s, bm, 18.0, M.theme())
        c : M.View <- M.text(status_node, s, sm, 16.0, 2863907583)
        return combine(a, b, c, overflow)
    case _:
      Fail{"Mokko demo: view is unavailable after close or external node removal"}

def view_measured(m: Measurements, +s: T.State, overflow: Bool) -> Result<&2, &2, String, Frame>:
  T.State{nodes, hover, f, c, k, t, down, live, active, w, h} = s
  render_nodes(nodes, s, m, overflow)

def view_state(+s: T.State, clicks: Nat, overflow: Bool, font: F.Font) -> Result<&2, &2, String, Frame>:
  T.State{nodes, hover, f, c, k, t, down, live, active, w, h} = s
  do Result<&2, &2, String, Frame>:
    m : Measurements <- measure(font, clicks, w)
    view_measured(m, s, overflow)

def view(model: Model, font: F.Font) -> Result<&2, &2, String, Frame>:
  Model{+s, clicks, overflow} = model
  view_state(s, clicks, overflow, font)
