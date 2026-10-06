import Base
import ./demo.bend as D
import ./main.bend as M
import ../Kairo/types.bend as T
import ../Kairo/base_adapter.bend as B
import ../Tessra/geometry.bend as G
import ../Chromi/main.bend as C
import ../Chromi/geometry.bend as CG
import ./chromi_text.bend as Text
import ../Ankra/main.bend as A
import ../Runika/font.bend as F

# Integration glue only: text caches, renderer and window belong to siblings.
type Cache is Data:
  Cache{title: Text.Run, button: Text.Run, status: Text.Run, clicks: Nat}

type Host is Data:
  Host{model: D.Model, adapter: B.Adapter, font: F.Font, cache: Cache, redraws: U32}

type Pending is Data:
  Pending{model: D.Model, dirty: Bool}

def unwrap(-V: Data, result: Result<&2, &2, String, V>) -> IO(V):
  match result:
    case Fail{message}:
      IO.die(V, 1, message)
    case Done{value}:
      IO.pure(V, value)

def count(model: D.Model) -> Nat:
  D.Model{s, clicks, overflow} = model
  clicks

def cache(+font: F.Font) -> Result<&2, &2, String, Cache>:
  do Result<&2, &2, String, Cache>:
    title : Text.Run <- Text.prepare(font, D.title(), 28.0, 416.0, 1.0)
    button : Text.Run <- Text.prepare(font, D.label(), 18.0, 1000000.0, 1.0)
    status : Text.Run <- Text.prepare(font, D.status(0n), 16.0, 1000000.0, 1.0)
    return Cache{title, button, status, 0n}

def refresh_needed(same: Bool, cache: Cache, font: F.Font, +clicks: Nat) -> Result<&2, &2, String, Cache>:
  match same:
    case True{}:
      Done{cache}
    case False{}:
      Cache{title, button, old, old_count} = cache
      do Result<&2, &2, String, Cache>:
        status : Text.Run <- Text.prepare(font, D.status(clicks), 16.0, 1000000.0, 1.0)
        return Cache{title, button, status, clicks}

def refresh(+cache: Cache, font: F.Font, +clicks: Nat) -> Result<&2, &2, String, Cache>:
  Cache{t, b, s, previous} = cache
  refresh_needed(Nat.is_eq(previous, clicks), cache, font, clicks)

def rect(r: G.Rect) -> CG.Rect:
  G.Rect{x, y, w, h} = r
  CG.Rect{x, y, w, h}

def cached(cache: Cache, +label: String) -> Text.Run:
  Cache{title, button, status, clicks} = cache
  Bool.pick(Text.Run, String.eq(label, D.title()), title, Bool.pick(Text.Run, String.eq(label, D.label()), button, status))

def view_cached(model: D.Model, cache: Cache) -> Result<&2, &2, String, D.Frame>:
  D.Model{runtime, clicks, overflow} = model
  Cache{title, button, status, previous} = cache
  D.view_measured(D.Measurements{Text.metrics(title), Text.metrics(button), Text.metrics(status)}, runtime, overflow)

def paint(ps: +List<M.Primitive>, +cache: Cache, canvas: C.Canvas) -> C.Canvas:
  match ps:
    case Nil{}:
      canvas
    case Con{M.Fill{r, color}, rest}:
      paint(rest, cache, C.fill_rect(canvas, rect(r), color))
    case Con{M.Stroke{r, width, color}, rest}:
      paint(rest, cache, C.stroke_rect(canvas, rect(r), width, color))
    case Con{M.TextRun{x, top, baseline, label, size, clip, color}, rest}:
      c = Text.paint(cached(cache, label), C.clip_rect(canvas, rect(clip)), x, top, 1.0, color)
      paint(rest, cache, C.reset_clip(c))

def draw(frame: D.Frame, cache: Cache) -> Result<&1, &1, U32 & String, Image>:
  D.Frame{ps, semantics, overflow} = frame
  c = C.new(480, 320, 1.0, 219422463)
  c = C.fill_rect(c, CG.Rect{16.0, 16.0, 448.0, 288.0}, 354033919)
  C.finish(paint(ps, cache, c))

def any_dirty(rects: +List<G.Rect>) -> Bool:
  match rects:
    case Nil{}:
      False{}
    case _:
      True{}

def merge(update: D.Update, dirty: Bool) -> Pending:
  D.Update{model, regions, layout, actions} = update
  Pending{model, dirty || layout || any_dirty(regions)}

def event(p: Pending, e: T.Input, font: F.Font) -> Result<&2, &2, String, Pending>:
  Pending{model, dirty} = p
  do Result<&2, &2, String, Pending>:
    update : D.Update <- D.update(model, e, font)
    return merge(update, dirty)

def events(es: +List<T.Input>, p: Pending, +font: F.Font) -> Result<&2, &2, String, Pending>:
  match es:
    case Nil{}:
      Done{p}
    case Con{e, rest}:
      do Result<&2, &2, String, Pending>:
        next : Pending <- event(p, e, font)
        events(rest, next, font)

def redraw(p: Pending, adapter: B.Adapter, +font: F.Font, cache: Cache, +redraws: U32) -> IO(A.Step<Host>):
  match p:
    case Pending{model, False{}}:
      IO.pure(A.Step<Host>, A.Keep{Host{model, adapter, font, cache, redraws}})
    case Pending{+model, True{}}:
      do IO<A.Step<Host>>:
        before : Nat <- IO.now()
        +ready : Cache <- unwrap(Cache, refresh(cache, font, count(model)))
        frame : D.Frame <- unwrap(D.Frame, view_cached(model, ready))
        image : Image <- IO.try(Image, IO.pure(Result<&1, &1, U32 & String, Image>, draw(frame, ready)))
        after : Nat <- IO.now()
        IO.print("Mokko redraw=" ++ U32.show((redraws + 1 : U32)) ++ " clicks=" ++ Nat.show(count(model)) ++ " draw_ms=" ++ Nat.show(Nat.sub(after, before)))
        return A.Redraw{Host{model, adapter, font, ready, (redraws + 1 : U32)}, image}

def normalized(n: B.Normalized, model: D.Model, +font: F.Font, cache: Cache, redraws: U32) -> IO(A.Step<Host>):
  B.Normalized{adapter, inputs} = n
  do IO<A.Step<Host>>:
    pending : Pending <- unwrap(Pending, events(inputs, Pending{model, False{}}, font))
    redraw(pending, adapter, font, cache, redraws)

def tick(batch: A.Batch, host: Host) -> IO(A.Step<Host>):
  A.Batch{closed, n, events} = batch
  Host{model, adapter, +font, cache, redraws} = host
  do IO<A.Step<Host>>:
    mapped : B.Normalized <- unwrap(B.Normalized, B.normalize(events, adapter, 1.0))
    normalized(mapped, model, font, cache, redraws)

def main() -> IO(Unit):
  do IO<Unit>:
    result : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- unwrap(F.Font, result)
    +model : D.Model <- unwrap(D.Model, D.init(font, 480.0, 320.0))
    +assets : Cache <- unwrap(Cache, cache(font))
    frame : D.Frame <- unwrap(D.Frame, view_cached(model, assets))
    image : Image <- IO.try(Image, IO.pure(Result<&1, &1, U32 & String, Image>, draw(frame, assets)))
    IO.print("Mokko visual ready: primary=0; Tab/Shift+Tab; Enter/Space; release outside cancels; max 18000 polls")
    A.run(~Host, ~tick, "AMAGE Eco - Mokko interaction", 480, 320, 18000n, Host{model, B.init(), font, assets, 1}, image)
    IO.print("Mokko visual closed")
