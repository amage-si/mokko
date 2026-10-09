import Base
import ../Tessra/geometry.bend as G
import ../Kairo/types.bend as K
import ../Kairo/dirty.bend as D
import ../Kairo/nodes.bend as N

type Metrics is Data:
  Metrics{width: F32, height: F32, ascent: F32}

type Primitive is Data:
  Fill{rect: G.Rect, rgba: U32}
  Stroke{rect: G.Rect, width: F32, rgba: U32}
  TextRun{x: F32, top: F32, baseline: F32, label: String, size: F32, clip: G.Rect, rgba: U32}

type SemanticAction is Data:
  Activate{}

type Semantic is Data:
  Semantic{id: U32, role: K.Role, label: String, bounds: G.Rect, enabled: Bool, focused: Bool, pressed: Bool, actions: +List<SemanticAction>}

type View is Data:
  View{primitives: +List<Primitive>, semantic: Semantic}

type Theme is Data:
  Theme{normal: U32, hover: U32, pressed: U32, disabled: U32, text: U32, muted: U32, focus: U32}

def theme() -> Theme:
  # RGBA: 245CCE, 3170E6, 183F96, 364152, FFFFFF, AAB3C2, A4C8FF; alpha FF.
  Theme{610062079, 829482751, 406820607, 910250751, 4294967295, 2863907583, 2764636159}

def button_node(id: U32, bounds: G.Rect, label: String, enabled: Bool) -> K.Node:
  K.Node{id, bounds, label, K.ButtonRole{}, enabled, True{}}

def text_node(id: U32, bounds: G.Rect, label: String) -> K.Node:
  K.Node{id, bounds, label, K.TextRole{}, True{}, False{}}

def valid_metrics(m: Metrics) -> Bool:
  Metrics{w, +h, +a} = m
  G.valid_length(w) && G.valid_length(h) && G.valid_length(a) && (a <= h : F32)

def text_size(m: Metrics) -> G.Size:
  Metrics{w, h, a} = m
  G.Size{w, h}

def button_size(m: Metrics) -> G.Size:
  Metrics{w, h, a} = m
  G.Size{(w + 32.0 : F32), F32.max(44.0, (h + 20.0 : F32))}

def semantic(node: K.Node, +state: K.State) -> Semantic:
  K.Node{+id, rect, label, +role, +enabled, focusable} = node
  actions = Bool.pick(+List<SemanticAction>, N.is_button(role) && enabled, [Activate{}], Nil{})
  Semantic{id, role, label, rect, enabled, D.focused(state, id), D.pressed(state, id), actions}

# A button's resolved look: the background and label colours, how far the
# background fill is inset from the bounds (the press "sink"), and the
# 2-unit focus ring, drawn when `ring` is True, inset by `ring_inset` in
# `ring_rgba`. The static button is `ButtonLook{bg, fg, 0.0, focused, 2.0,
# focus}`; anim.bend animates every field.
type ButtonLook is Data:
  ButtonLook{bg: U32, fg: U32, sink: F32, ring: Bool, ring_inset: F32, ring_rgba: U32}

def even(+d: F32) -> G.Insets:
  G.Insets{d, d, d, d}

# Fill, the focus ring when shown, then the centred label.
def button_drawn(+rect: G.Rect, label: String, look: ButtonLook, mw: F32, mh: F32, ascent: F32, size: F32) -> +List<Primitive>:
  G.Rect{x, y, +w, +h} = rect
  ButtonLook{bg, fg, sink, ring, ring_inset, ring_rgba} = look
  +tx = (x + F32.max(0.0, (w - mw : F32)) / 2.0 : F32)
  +ty = (y + F32.max(0.0, (h - mh : F32)) / 2.0 : F32)
  clip = G.inset(rect, G.Insets{8.0, 4.0, 8.0, 4.0})
  run = {TextRun{tx, ty, (ty + ascent : F32), label, size, clip, fg} : Primitive}
  +tail = {Con{run, Nil{}} : +List<Primitive>}
  stroke = {Stroke{G.inset(rect, even(ring_inset)), 2.0, ring_rgba} : Primitive}
  Con{Fill{G.inset(rect, even(sink)), bg}, Bool.pick(+List<Primitive>, ring, Con{stroke, tail}, tail)}

def button_rect(+rect: G.Rect, label: String, +enabled: Bool, hovered: Bool, pressed: Bool, focused: Bool, mw: F32, mh: F32, ascent: F32, size: F32, colors: Theme) -> +List<Primitive>:
  Theme{normal, hover, down, disabled, text, muted, focus} = colors
  bg = Bool.pick(U32, enabled, Bool.pick(U32, pressed, down, Bool.pick(U32, hovered, hover, normal)), disabled)
  fg = Bool.pick(U32, enabled, text, muted)
  button_drawn(rect, label, ButtonLook{bg, fg, 0.0, focused, 2.0, focus}, mw, mh, ascent, size)

def button_primitives(node: K.Node, +state: K.State, metrics: Metrics, size: F32, colors: Theme) -> +List<Primitive>:
  K.Node{+id, +rect, label, role, +enabled, focusable} = node
  Metrics{mw, mh, ascent} = metrics
  Theme{normal, hover, pressed, disabled, text, muted, focus} = colors
  button_rect(rect, label, enabled, D.hovered(state, id), D.pressed(state, id), D.focused(state, id), mw, mh, ascent, size, Theme{normal, hover, pressed, disabled, text, muted, focus})

def button_checked(valid: Bool, +node: K.Node, +state: K.State, metrics: Metrics, size: F32, colors: Theme) -> Result<&2, &2, String, View>:
  match valid:
    case False{}:
      Fail{"Mokko: invalid button, metrics or font size"}
    case True{}:
      Done{View{button_primitives(node, state, metrics, size, colors), semantic(node, state)}}

def button(+node: K.Node, state: K.State, +metrics: Metrics, +size: F32, colors: Theme) -> Result<&2, &2, String, View>:
  K.Node{id, rect, label, role, e, f} = node
  button_checked(N.valid(node) && N.is_button(role) && valid_metrics(metrics) && (size > 0.0 : F32) && (size <= 256.0 : F32), node, state, metrics, size, colors)

def text_rect(rect: G.Rect, label: String, metrics: Metrics, size: F32, rgba: U32) -> Primitive:
  G.Rect{+x, +y, +w, +h} = rect
  Metrics{mw, mh, ascent} = metrics
  TextRun{x, y, (y + ascent : F32), label, size, G.Rect{x, y, w, h}, rgba}

def text_checked(valid: Bool, +node: K.Node, state: K.State, metrics: Metrics, size: F32, rgba: U32) -> Result<&2, &2, String, View>:
  match valid:
    case False{}:
      Fail{"Mokko: invalid text, metrics or font size"}
    case True{}:
      K.Node{id, r, label, role, e, f} = node
      Done{View{[text_rect(r, label, metrics, size, rgba)], semantic(node, state)}}

def text(+node: K.Node, state: K.State, +metrics: Metrics, +size: F32, rgba: U32) -> Result<&2, &2, String, View>:
  K.Node{id, rect, label, role, e, f} = node
  text_checked(N.valid(node) && Bool.not(N.is_button(role)) && valid_metrics(metrics) && (size > 0.0 : F32) && (size <= 256.0 : F32), node, state, metrics, size, rgba)

def button_styled.checked(valid: Bool, +node: K.Node, +state: K.State, metrics: Metrics, size: F32, look: ButtonLook) -> Result<&2, &2, String, View>:
  match valid:
    case False{}:
      Fail{"Mokko: invalid button, metrics or font size"}
    case True{}:
      K.Node{id, rect, label, role, enabled, focusable} = node
      Metrics{mw, mh, ascent} = metrics
      Done{View{button_drawn(rect, label, look, mw, mh, ascent, size), semantic(node, state)}}

# The button with a look the caller resolved (anim.bend's animated button);
# the same checks, primitive order and semantic as `button`.
def button_styled(+node: K.Node, state: K.State, +metrics: Metrics, +size: F32, look: ButtonLook) -> Result<&2, &2, String, View>:
  K.Node{id, rect, label, role, e, f} = node
  button_styled.checked(N.valid(node) && N.is_button(role) && valid_metrics(metrics) && (size > 0.0 : F32) && (size <= 256.0 : F32), node, state, metrics, size, look)
