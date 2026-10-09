import Base
import ./main.bend as M
import ../Tessra/geometry.bend as G
import ../Kairo/types.bend as K
import ../Kairo/edit.bend as KE
import ../Kairo/dirty.bend as D
import ../Kairo/nodes.bend as N
import ../Syllo/main.bend as S
import ../Syllo/caret.bend as SC
import ../Runika/font.bend as F

# A single-line editable text field.
#
# The application keeps one `Field` per field node and passes it Kairo's
# actions with `feed`. Editing rules come from Kairo's edit.bend; the field
# lays out every candidate text with Syllo before it commits it, so a text
# the font or the layout cannot show is refused whole (nothing is
# substituted or inserted in part) and the field keeps a message that names
# the character. Pointer x maps to a caret stop with Syllo's stops, and the
# text scrolls horizontally to keep the caret visible.
#
# `view` emits only Fill, Stroke and TextRun, in this order:
#   1. Fill   the box (bounds)
#   2. Stroke the 1-unit border, in the error colour while an edit is refused
#   3. Fill   the selection band, clipped to the text area (focused only)
#   4. TextRun the text, or the placeholder when empty, clipped to the text
#      area (bounds inset 12 left and right, 2 top and bottom)
#   5. Fill   the 2-unit caret (focused only)
#   6. Stroke the 2-unit focus ring inset by 2 (focused only)
# Kairo's pointer capture marks the field "pressed"; the field draws no
# pressed state and exports pressed = False.

type FieldTheme is Data:
  FieldTheme{box: U32, border: U32, focus: U32, text: U32, placeholder: U32, selection: U32, caret: U32, error: U32}

# `line` holds the measurements of the laid-out text: its width, the line
# height and the ascent. `scroll` is how far the text is shifted left.
type Field is Data:
  Field{edit: KE.Edit, stops: List<&2, SC.Stop>, line: M.Metrics, scroll: F32, refused: Maybe<&2, String>}

# `dirty`: the field's bounds need a redraw. `request`: what the host must
# do for the user (copy a text to the clipboard, or ask for a paste).
type Fed is Data:
  Fed{field: Field, dirty: Bool, request: KE.Request}

# What an accessibility bridge needs about the field: the text, the caret
# and anchor (scalar indices), and where stop x values sit on screen
# (origin_x + stop.x; origin_x already includes the scroll).
type EditState is Data:
  EditState{id: U32, text: String, caret: U32, anchor: U32, placeholder: String,
    origin_x: F32, origin_y: F32, line_height: F32, stops: List<&2, SC.Stop>}

type FieldView is Data:
  FieldView{view: M.View, edit: EditState}

type Laid is Data:
  Laid{stops: List<&2, SC.Stop>, line: M.Metrics}

def field_theme() -> FieldTheme:
  # RGBA: 1C2433 box, 4A5568 border, A4C8FF focus, EDF2FA text, 7D8796
  # placeholder, 2F5DB3 selection, FFFFFF caret, F05252 error; alpha FF.
  FieldTheme{472134655, 1247111423, 2764636159, 3992124159, 2106038015, 794670079, 4294967295, 4031927039}

def field_node(id: U32, bounds: G.Rect, name: String) -> K.Node:
  K.Node{id, bounds, name, K.EditRole{}, True{}, True{}}

# Width as given; height: the line plus 20 units, at least 44.
def field_size(+line_height: F32, +width: F32) -> G.Size:
  G.Size{width, F32.max(44.0, (line_height + 20.0 : F32))}

def padding() -> F32:
  12.0

# The text area inside the bounds: its left edge, the text top (the line is
# centred vertically) and its width.
def text_top(r: G.Rect, +line_height: F32) -> F32:
  G.Rect{x, +y, w, +h} = r
  (y + F32.max(0.0, (h - line_height : F32)) / 2.0 : F32)

def text_left(r: G.Rect) -> F32:
  G.Rect{+x, y, w, h} = r
  (x + padding() : F32)

def area_width(r: G.Rect) -> F32:
  G.Rect{x, y, +w, h} = r
  F32.max(0.0, (w - 2.0 * padding() : F32))

# Messages. They are plain ASCII, so the host can always lay them out.

def hex.digit(+d: U32) -> Char:
  Chr{Bool.pick(U32, U32.is_lt(d, 10), (d + 48 : U32), (d + 55 : U32))}

def hex.go(digits: Nat, +n: U32, acc: String) -> String:
  match digits:
    case 0n:
      acc
    case 1n+rest:
      +q = U32.div(n, 16)
      hex.go(rest, q, SCon{hex.digit((n - q * 16 : U32)), acc})

# "U+20AC": at least four upper-case hex digits.
def hex(+n: U32) -> String:
  "U+" ++ hex.go(Bool.pick(Nat, U32.is_gt(n, 1048575), 6n, Bool.pick(Nat, U32.is_gt(n, 65535), 5n, 4n)), n, "")

def refusal_message(r: KE.Refusal) -> String:
  match r:
    case KE.ControlChar{c}:
      "Control character " ++ hex(c) ++ " is not allowed"
    case KE.LineBreak{}:
      "Line breaks are not allowed in this field"
    case KE.TooLong{n}:
      "The text is limited to " ++ U32.show(n) ++ " characters"

def unsupported_message(m: Maybe<&2, SC.Unsupported>, error: String) -> String:
  match m:
    case Some{SC.Unsupported{i, c}}:
      "Character " ++ hex(c) ++ " cannot be displayed"
    case None{}:
      "The text cannot be laid out: " ++ error

# Layout: one line, wide enough never to wrap.

def laid.stops(r: Result<&2, &2, String, List<&2, SC.Stop>>, line: M.Metrics) -> Result<&2, &2, String, Laid>:
  match r:
    case Fail{e}:
      Fail{"The text does not fit on one line"}
    case Done{stops}:
      Done{Laid{stops, line}}

def laid.of(+l: S.Layout) -> Result<&2, &2, String, Laid>:
  S.Layout{ps, w, h, asc, desc, lh, lines} = l
  laid.stops(SC.stops(l), M.Metrics{w, lh, asc})

def laid(r: Result<&2, &2, String, S.Layout>, +font: F.Font, text: String) -> Result<&2, &2, String, Laid>:
  match r:
    case Fail{e}:
      Fail{unsupported_message(SC.unsupported(font, text), e)}
    case Done{l}:
      laid.of(l)

def lay_out(+font: F.Font, +size: F32, +text: String) -> Result<&2, &2, String, Laid>:
  laid(S.layout(font, text, size, 1000000.0), font, text)

# Building a field.

def built(r: Result<&2, &2, String, Laid>, e: KE.Edit) -> Result<&2, &2, String, Field>:
  match r:
    case Fail{m}:
      Fail{m}
    case Done{Laid{stops, line}}:
      Done{Field{e, stops, line, 0.0, None{}}}

def made(r: Result<&2, &2, KE.Refusal, KE.Edit>, +font: F.Font, +size: F32) -> Result<&2, &2, String, Field>:
  match r:
    case Fail{x}:
      Fail{refusal_message(x)}
    case Done{+e}:
      KE.Edit{+text, n, c, a} = e
      built(lay_out(font, size, text), e)

# A field holding `text` (at most 256 scalars), caret at the end. Fails with
# the same message a refused edit would show.
def field(+font: F.Font, +size: F32, +text: String) -> Result<&2, &2, String, Field>:
  made(KE.of(text, KE.default_limit()), font, size)

def text_of(f: Field) -> String:
  Field{KE.Edit{text, n, c, a}, stops, line, scroll, r} = f
  text

def edit_of(f: Field) -> KE.Edit:
  Field{e, stops, line, scroll, r} = f
  e

# The message of the last refused edit, until the next accepted one.
def message(f: Field) -> Maybe<&2, String>:
  Field{e, stops, line, scroll, r} = f
  r

# Scrolling. The scroll stays within [0, text width - area width] and moves
# just enough to keep the caret (pen x `cx`) inside the area.
def visible(+scroll: F32, +cx: F32, +tw: F32, +aw: F32) -> F32:
  +s = F32.min(F32.max(0.0, scroll), F32.max(0.0, (tw - aw : F32)))
  F32.min(F32.max(s, (cx - aw : F32)), cx)

# The scroll the field is shown with in an area `aw` wide.
def scroll_of(f: Field, +aw: F32) -> F32:
  Field{KE.Edit{t, n, +caret, a}, +stops, M.Metrics{+tw, lh, asc}, +scroll, r} = f
  visible(scroll, SC.caret_x(stops, caret), tw, aw)

# Feeding actions.

def unchanged(f: Field) -> Fed:
  Fed{f, False{}, KE.NoRequest{}}

def refuse(f: Field, message: String) -> Fed:
  Field{e, stops, line, scroll, r} = f
  Fed{Field{e, stops, line, scroll, Some{message}}, True{}, KE.NoRequest{}}

def is_refused(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{x}:
      True{}
    case None{}:
      False{}

# Commits `edit` (laid out as `stops` and `line`), clears the refusal and
# rescrolls. `changed` says the text, caret or anchor moved.
def settle(+f: Field, +bounds: G.Rect, +changed: Bool, request: KE.Request) -> Fed:
  Field{e, stops, line, +scroll, +r} = f
  +next = scroll_of(f, area_width(bounds))
  Fed{Field{e, stops, line, next, None{}}, changed || is_refused(r) || F32.is_ne(next, scroll), request}

def relaid(r: Result<&2, &2, String, Laid>, +bounds: G.Rect, f: Field, edit: KE.Edit, request: KE.Request) -> Fed:
  match r:
    case Fail{m}:
      refuse(f, m)
    case Done{Laid{stops, line}}:
      Field{old, s, l, scroll, refused} = f
      settle(Field{edit, stops, line, scroll, refused}, bounds, True{}, request)

def committed(text_changed: Bool, +font: F.Font, +size: F32, +bounds: G.Rect, f: Field, +edit: KE.Edit, +moved: Bool, request: KE.Request) -> Fed:
  match text_changed:
    case False{}:
      Field{old, stops, line, scroll, refused} = f
      settle(Field{edit, stops, line, scroll, refused}, bounds, moved, request)
    case True{}:
      KE.Edit{+text, n, c, a} = edit
      relaid(lay_out(font, size, text), bounds, f, edit, request)

def accepted(a: KE.Applied, +font: F.Font, +size: F32, +bounds: G.Rect, f: Field) -> Fed:
  KE.Applied{edit, text_changed, moved, request} = a
  committed(text_changed, font, size, bounds, f, edit, moved, request)

def inserted(r: Result<&2, &2, KE.Refusal, KE.Applied>, +font: F.Font, +size: F32, +bounds: G.Rect, f: Field) -> Fed:
  match r:
    case Fail{x}:
      refuse(f, refusal_message(x))
    case Done{a}:
      accepted(a, font, size, bounds, f)

def typed(ok: Bool, +font: F.Font, +size: F32, +bounds: G.Rect, +f: Field, +text: String) -> Fed:
  match ok:
    case False{}:
      unchanged(f)
    case True{}:
      inserted(KE.insert(edit_of(f), text, KE.default_limit()), font, size, bounds, f)

def commanded(ok: Bool, +font: F.Font, +size: F32, +bounds: G.Rect, +f: Field, command: K.EditCommand) -> Fed:
  match ok:
    case False{}:
      unchanged(f)
    case True{}:
      accepted(KE.apply(edit_of(f), command), font, size, bounds, f)

def placed(+f: Field, +bounds: G.Rect, +next: KE.Edit) -> Fed:
  Field{KE.Edit{t, n, +caret, +anchor}, stops, line, scroll, refused} = f
  KE.Edit{nt, nn, +nc, +na} = next
  settle(Field{next, stops, line, scroll, refused}, bounds, U32.is_ne(caret, nc) || U32.is_ne(anchor, na), KE.NoRequest{})

# A press (drag False) places the caret; a drag extends the selection. The
# pointer x is mapped through the scroll the field is shown with.
def pointed(ok: Bool, +bounds: G.Rect, +f: Field, +x: F32, +drag: Bool) -> Fed:
  match ok:
    case False{}:
      unchanged(f)
    case True{}:
      Field{e, +stops, line, s, r} = f
      +shown = scroll_of(f, area_width(bounds))
      placed(f, bounds, KE.place(e, SC.hit(stops, (x - text_left(bounds) + shown : F32)), drag))

# Applies one Kairo action to the field `id` laid out in `bounds`. Actions
# for other ids, and other actions, leave it unchanged and clean.
def feed(+font: F.Font, +size: F32, +bounds: G.Rect, +id: U32, f: Field, a: K.Action) -> Fed:
  match a:
    case K.TextDelivered{+target, text}:
      typed(U32.is_eq(target, id), font, size, bounds, f, text)
    case K.EditRequested{+target, command}:
      commanded(U32.is_eq(target, id), font, size, bounds, f, command)
    case K.EditPointer{+target, x, y, drag}:
      pointed(U32.is_eq(target, id), bounds, f, x, drag)
    case _:
      unchanged(f)

# Drawing.

def clipped.fill(some: Bool, +a: F32, +b: F32, top: F32, height: F32, rgba: U32, tail: +List<M.Primitive>) -> +List<M.Primitive>:
  match some:
    case False{}:
      tail
    case True{}:
      Con{M.Fill{G.Rect{a, top, (b - a : F32), height}, rgba}, tail}

# A fill from x0 to x1, cut to [left, right]; nothing when empty.
def clipped(+x0: F32, +x1: F32, +left: F32, +right: F32, top: F32, height: F32, rgba: U32, tail: +List<M.Primitive>) -> +List<M.Primitive>:
  +a = F32.max(x0, left)
  +b = F32.min(x1, right)
  clipped.fill(F32.is_gt(b, a), a, b, top, height, rgba, tail)

def bands(bs: List<&2, SC.Band>, +origin: F32, +left: F32, +right: F32, +top: F32, +rgba: U32, tail: +List<M.Primitive>) -> +List<M.Primitive>:
  match bs:
    case Nil{}:
      tail
    case Con{SC.Band{+x, bt, +w, +h}, rest}:
      +x0 = (origin + x : F32)
      clipped(x0, (x0 + w : F32), left, right, top, h, rgba, bands(rest, origin, left, right, top, rgba, tail))

def selection(focused: Bool, +stops: List<&2, SC.Stop>, +caret: U32, +anchor: U32, +lh: F32, +origin: F32, +left: F32, +right: F32, +top: F32, +rgba: U32, tail: +List<M.Primitive>) -> +List<M.Primitive>:
  match focused:
    case False{}:
      tail
    case True{}:
      bands(SC.selection(stops, caret, anchor, lh), origin, left, right, top, rgba, tail)

type FieldLook is Data:
  FieldLook{focused: Bool, refused: Bool}

def primitives(+rect: G.Rect, look: FieldLook, +f: Field, +size: F32, colors: FieldTheme, placeholder: String) -> +List<M.Primitive>:
  FieldLook{+focused, refused} = look
  Field{KE.Edit{text, +count, +caret, +anchor}, +stops, M.Metrics{tw, +lh, +asc}, sc, r} = f
  FieldTheme{box, border, focus, ink, faint, band, caret_rgba, error} = colors
  +left = text_left(rect)
  +top = text_top(rect, lh)
  +aw = area_width(rect)
  +origin = (left - scroll_of(f, aw) : F32)
  +empty = U32.is_eq(count, 0)
  +right = (left + aw : F32)
  ring = {M.Stroke{G.inset(rect, G.Insets{2.0, 2.0, 2.0, 2.0}), 2.0, focus} : M.Primitive}
  +rings = Bool.pick(+List<M.Primitive>, focused, [ring], Nil{})
  cursor = {M.Fill{G.Rect{(origin + SC.caret_x(stops, caret) - 1.0 : F32), top, 2.0, lh}, caret_rgba} : M.Primitive}
  +after = Bool.pick(+List<M.Primitive>, focused, Con{cursor, rings}, rings)
  run = {M.TextRun{origin, top, (top + asc : F32), Bool.pick(String, empty, placeholder, text), size, G.inset(rect, G.Insets{padding(), 2.0, padding(), 2.0}), Bool.pick(U32, empty, faint, ink)} : M.Primitive}
  +marked = selection(focused, stops, caret, anchor, lh, origin, left, right, top, band, Con{run, after})
  Con{M.Fill{rect, box}, Con{M.Stroke{rect, 1.0, Bool.pick(U32, refused, error, border)}, marked}}

def edit_state(+id: U32, +rect: G.Rect, +f: Field, placeholder: String) -> EditState:
  Field{KE.Edit{text, n, caret, anchor}, stops, M.Metrics{tw, +lh, asc}, sc, r} = f
  EditState{id, text, caret, anchor, placeholder, (text_left(rect) - scroll_of(f, area_width(rect)) : F32), text_top(rect, lh), lh, stops}

def view_checked(ok: Bool, +node: K.Node, +state: K.State, +f: Field, +size: F32, colors: FieldTheme, +placeholder: String) -> Result<&2, &2, String, FieldView>:
  match ok:
    case False{}:
      Fail{"Mokko: invalid text field node or font size"}
    case True{}:
      K.Node{+id, +rect, label, role, +enabled, focusable} = node
      +focused = D.focused(state, id)
      ps = primitives(rect, FieldLook{focused, is_refused(message(f))}, f, size, colors, placeholder)
      semantic = {M.Semantic{id, K.EditRole{}, label, rect, enabled, focused, False{}, Nil{}} : M.Semantic}
      Done{FieldView{M.View{ps, semantic}, edit_state(id, rect, f, placeholder)}}

# The field's primitives (see the order above), its semantic (EditRole, the
# node label as name, never pressed, no actions) and its EditState.
def view(+node: K.Node, state: K.State, f: Field, +size: F32, colors: FieldTheme, placeholder: String) -> Result<&2, &2, String, FieldView>:
  K.Node{id, rect, label, +role, e, fo} = node
  view_checked(N.valid(node) && N.is_edit(role) && (size > 0.0 : F32) && (size <= 256.0 : F32), node, state, f, size, colors, placeholder)
