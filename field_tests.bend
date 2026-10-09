import Base
import ./main.bend as M
import ./field.bend as FL
import ../Kairo/main.bend as KM
import ../Kairo/types.bend as K
import ../Kairo/edit.bend as KE
import ../Tessra/geometry.bend as G
import ../Runika/font.bend as F
import ../Runika/check.bend as C

# Text-field checks with Liberation Sans at 20 px, driven through Kairo the
# way a host does: dispatch an input, feed every action to the field.
#
# The field's bounds are (20, 20, 200 x 44), so the text area starts at
# x = 32 and is 176 units wide. "A" advances 13.33984375 units at 20 px;
# every x below is exact in F32.

def bounds() -> G.Rect:
  G.Rect{20.0, 20.0, 200.0, 44.0}

def node() -> K.Node:
  FL.field_node(1, bounds(), "Name")

def button() -> K.Node:
  M.button_node(2, G.Rect{20.0, 80.0, 120.0, 44.0}, "Go", True{})

def started(r: Result<&2, &2, K.Error, K.State>) -> Result<&2, &2, String, K.State>:
  match r:
    case Fail{e}:
      Fail{"Kairo rejected the nodes"}
    case Done{s}:
      Done{s}

type Session is Data:
  Session{state: K.State, fed: FL.Fed, activations: U32}

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

def stepped(c: K.Change, +font: F.Font, fed: FL.Fed, +n: U32) -> Session:
  K.Change{st, +actions, d, l} = c
  Session{st, fold(actions, font, fed), (n + KM.activation_count(actions) : U32)}

def step(i: K.Input, +font: F.Font, s: Session) -> Session:
  Session{st, fed, n} = s
  stepped(KM.dispatch(st, i), font, fed, n)

def run(inputs: +List<K.Input>, +font: F.Font, s: Session) -> Session:
  match inputs:
    case Nil{}:
      s
    case Con{i, rest}:
      run(rest, font, step(i, font, s))

def begin(st: K.State, f: FL.Field) -> Session:
  Session{st, FL.Fed{f, False{}, KE.NoRequest{}}, 0}

# The same session with its dirty flag, request and count cleared.
def rebase(s: Session) -> Session:
  Session{st, FL.Fed{f, d, r}, n} = s
  Session{st, FL.Fed{f, False{}, KE.NoRequest{}}, 0}

def field_of(s: Session) -> FL.Field:
  Session{st, FL.Fed{f, d, r}, n} = s
  f

def text(s: Session) -> String:
  FL.text_of(field_of(s))

def has_text(s: Session, +t: String) -> Bool:
  String.eq(text(s), t)

def edit_is(e: KE.Edit, +caret: U32, +anchor: U32) -> Bool:
  KE.Edit{t, n, c, a} = e
  U32.is_eq(c, caret) && U32.is_eq(a, anchor)

def caret_is(s: Session, +caret: U32, +anchor: U32) -> Bool:
  edit_is(FL.edit_of(field_of(s)), caret, anchor)

def is_dirty(s: Session) -> Bool:
  Session{st, FL.Fed{f, d, r}, n} = s
  d

def activations(s: Session) -> U32:
  Session{st, fed, n} = s
  n

def says(m: Maybe<&2, String>, +expected: String) -> Bool:
  match m:
    case Some{t}:
      String.eq(t, expected)
    case None{}:
      False{}

def silent(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{t}:
      False{}
    case None{}:
      True{}

def message_is(s: Session, +expected: String) -> Bool:
  says(FL.message(field_of(s)), expected)

def no_message(s: Session) -> Bool:
  silent(FL.message(field_of(s)))

def asks_paste(s: Session) -> Bool:
  Session{st, FL.Fed{f, d, r}, n} = s
  match r:
    case KE.PasteText{}:
      True{}
    case _:
      False{}

def copies(s: Session, +expected: String) -> Bool:
  Session{st, FL.Fed{f, d, r}, n} = s
  match r:
    case KE.CopyText{t}:
      String.eq(t, expected)
    case _:
      False{}

def view(s: Session) -> Result<&2, &2, String, FL.FieldView>:
  Session{st, FL.Fed{f, d, r}, n} = s
  FL.view(node(), st, f, 20.0, FL.field_theme(), "Type here")

def kind(p: M.Primitive) -> Char:
  match p:
    case M.Fill{r, c}:
      'F'
    case M.Stroke{r, w, c}:
      'S'
    case M.TextRun{x, t, b, l, s, clip, c}:
      'T'

def kinds_of(ps: +List<M.Primitive>) -> String:
  match ps:
    case Nil{}:
      ""
    case Con{p, rest}:
      SCon{kind(p), kinds_of(rest)}

def primitives(v: Result<&2, &2, String, FL.FieldView>) -> +List<M.Primitive>:
  match v:
    case Fail{e}:
      Nil{}
    case Done{FL.FieldView{M.View{ps, sem}, e}}:
      ps

def kinds(v: Result<&2, &2, String, FL.FieldView>) -> String:
  kinds_of(primitives(v))

def border(ps: +List<M.Primitive>) -> U32:
  match ps:
    case Con{box, Con{M.Stroke{r, w, c}, rest}}:
      c
    case _:
      0

def band_at(ps: +List<M.Primitive>, +x: F32, +width: F32) -> Bool:
  match ps:
    case Con{box, Con{line, Con{M.Fill{G.Rect{bx, by, bw, bh}, c}, rest}}}:
      F32.is_eq(bx, x) && F32.is_eq(bw, width) && U32.is_eq(c, 794670079)
    case _:
      False{}

def placeholder_run(ps: +List<M.Primitive>) -> Bool:
  match ps:
    case Con{box, Con{line, Con{M.TextRun{x, t, b, label, s, clip, c}, Nil{}}}}:
      String.eq(label, "Type here") && U32.is_eq(c, 2106038015) && F32.is_eq(x, 32.0)
    case _:
      False{}

def semantic_ok(v: Result<&2, &2, String, FL.FieldView>) -> Bool:
  match v:
    case Done{FL.FieldView{M.View{ps, M.Semantic{1, K.EditRole{}, label, r, True{}, True{}, False{}, Nil{}}}, e}}:
      String.eq(label, "Name")
    case _:
      False{}

def origin(v: Result<&2, &2, String, FL.FieldView>) -> F32:
  match v:
    case Done{FL.FieldView{m, FL.EditState{id, t, c, a, p, ox, oy, lh, stops}}}:
      ox
    case Fail{e}:
      F32.div(0.0, 0.0)

def failed_with(r: Result<&2, &2, String, FL.Field>, +expected: String) -> Bool:
  match r:
    case Fail{m}:
      String.eq(m, expected)
    case Done{f}:
      False{}

def repeat(n: Nat, +c: Char, acc: String) -> String:
  match n:
    case 0n:
      acc
    case 1n+p:
      repeat(p, c, SCon{c, acc})

def click(+x: F32) -> +List<K.Input>:
  [K.PointerDown{x, 40.0, 0}, K.PointerUp{x, 40.0, 0}]

def key(+k: K.KeyName) -> +List<K.Input>:
  [K.KeyDown{k, False{}, False{}}, K.KeyUp{k}]

def edit(c: K.EditCommand) -> K.Input:
  K.Editing{c}

def clean(fed: FL.Fed) -> Bool:
  FL.Fed{g, d, r} = fed
  Bool.not(d) && String.eq(FL.text_of(g), "")

def ignored(+font: F.Font, f: FL.Field) -> Bool:
  clean(FL.feed(font, 20.0, bounds(), 1, f, K.TextDelivered{2, "x"}))

def main() -> IO(Unit):
  do IO<Unit>:
    fr : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- C.unwrap(F.Font, fr)
    +st : K.State <- C.unwrap(K.State, started(KM.init([node(), button()], 400.0, 200.0)))
    +empty : FL.Field <- C.unwrap(FL.Field, FL.field(font, 20.0, ""))
    +aa : FL.Field <- C.unwrap(FL.Field, FL.field(font, 20.0, "AA"))
    +full : FL.Field <- C.unwrap(FL.Field, FL.field(font, 20.0, repeat(256n, 'a', "")))
    +idle : Session = begin(st, empty)
    C.expect(String.eq(kinds(view(idle)), "FST") && placeholder_run(primitives(view(idle))),
      "unfocused empty field: box, border, placeholder at the text area's left edge")
    +typed : Session = run(List.append(&2, K.Input, click(100.0), [K.TextInput{"Olá"}]), font, idle)
    C.expect(has_text(typed, "Olá") && caret_is(typed, 3, 3) && is_dirty(typed), "click then typing inserts at the caret")
    C.expect(semantic_ok(view(typed)), "semantic: EditRole, the node name, focused, never pressed, no actions")
    +euro : Session = run([K.TextInput{"€"}], font, rebase(typed))
    C.expect(has_text(euro, "Olá") && message_is(euro, "Character U+20AC cannot be displayed") && is_dirty(euro),
      "typing U+20AC is refused whole, with a message naming the character")
    C.expect(U32.is_eq(border(primitives(view(euro))), 4031927039), "a refused edit draws the error border")
    +pasted : Session = run([K.TextInput{"ab€cd"}], font, rebase(euro))
    C.expect(has_text(pasted, "Olá") && caret_is(pasted, 3, 3) && message_is(pasted, "Character U+20AC cannot be displayed"),
      "a paste with one unsupported character is refused whole")
    +broken : Session = run([K.TextInput{"a\nb"}], font, rebase(pasted))
    C.expect(has_text(broken, "Olá") && message_is(broken, "Line breaks are not allowed in this field"), "a line break is refused")
    +fixed : Session = run([K.TextInput{"!"}, edit(K.Paste{})], font, rebase(broken))
    C.expect(has_text(fixed, "Olá!") && no_message(fixed) && asks_paste(fixed) && U32.is_eq(border(primitives(view(fixed))), 1247111423),
      "an accepted edit clears the refusal; Paste asks the host for the clipboard")
    +copied : Session = run([edit(K.SelectAll{}), edit(K.Copy{})], font, rebase(fixed))
    C.expect(copies(copied, "Olá!") && has_text(copied, "Olá!") && caret_is(copied, 4, 0), "SelectAll then Copy requests the whole text")
    +cut : Session = run([edit(K.Cut{})], font, rebase(copied))
    C.expect(copies(cut, "Olá!") && has_text(cut, "") && caret_is(cut, 0, 0), "Cut requests the text and empties the field")
    +mark : Session = run([K.TextInput{SCon{'e', SCon{Chr{769}, ""}}}, edit(K.DeleteBack{K.ByChar{}})], font, rebase(cut))
    C.expect(has_text(mark, "") && no_message(mark), "a base and its combining mark are laid out and deleted together")
    C.expect(ignored(font, empty), "an action for another id leaves the field clean")
    +keys : Session = run(List.append(&2, K.Input, key(K.SpaceKey{}), key(K.EnterKey{})), font, rebase(typed))
    C.expect(U32.is_eq(activations(keys), 0) && has_text(keys, "Olá"), "Space and Enter on the focused field never activate")
    +tabbed : Session = run(List.append(&2, K.Input, [K.KeyDown{K.TabKey{}, False{}, False{}}], key(K.SpaceKey{})), font, rebase(typed))
    C.expect(U32.is_eq(activations(tabbed), 1), "after Tab to the button, Space activates the button")
    +hit : Session = run(click(46.0), font, begin(st, aa))
    C.expect(caret_is(hit, 1, 1), "a click 14 units into \"AA\" places the caret at stop 1")
    +held : Session = run([K.PointerDown{32.0, 40.0, 0}, K.PointerMove{59.0, 40.0}], font, begin(st, aa))
    C.expect(caret_is(held, 2, 0), "a drag from stop 0 to x 27 selects both letters")
    C.expect(String.eq(kinds(view(held)), "FSFTFS"), "primitive order: box, border, selection, text, caret, focus ring")
    C.expect(band_at(primitives(view(held)), 32.0, 26.6796875), "the selection band spans the two letters")
    C.expect(semantic_ok(view(held)), "a captured pointer does not mark the field pressed")
    +long : Session = run(List.append(&2, K.Input, click(100.0), [K.TextInput{repeat(40n, 'A', "")}]), font, idle)
    C.expect(F32.is_eq(origin(view(long)), F32.neg(325.59375)), "40 letters scroll so the caret sits at the right edge")
    +home : Session = run([edit(K.MoveLeft{K.ToEdge{}, False{}})], font, rebase(long))
    C.expect(F32.is_eq(origin(view(home)), 32.0) && is_dirty(home), "Home scrolls back to the start")
    +far : Session = run([edit(K.MoveRight{K.ToEdge{}, False{}})], font, rebase(home))
    C.expect(F32.is_eq(origin(view(far)), F32.neg(325.59375)), "End scrolls to keep the caret visible")
    +back : Session = run(click(32.0), font, rebase(far))
    C.expect(caret_is(back, 27, 27), "a click on a scrolled field maps through the scroll")
    +cleared : Session = run([edit(K.SelectAll{}), edit(K.DeleteBack{K.ByChar{}})], font, rebase(far))
    C.expect(has_text(cleared, "") && F32.is_eq(origin(view(cleared)), 32.0), "deleting everything resets the scroll")
    +over : Session = run(List.append(&2, K.Input, click(100.0), [K.TextInput{"b"}]), font, begin(st, full))
    C.expect(message_is(over, "The text is limited to 256 characters") && Nat.is_eq(String.length(text(over)), 256n), "the 257th character is refused")
    C.expect(failed_with(FL.field(font, 20.0, "café €"), "Character U+20AC cannot be displayed"), "a field cannot start with unsupported text")
    IO.print("Mokko field: 25 tests passed with LiberationSans-Regular.ttf")
