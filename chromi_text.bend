import Base
import ../Chromi/main.bend as C
import ../Runika/font.bend as F
import ../Syllo/main.bend as S
import ../Dithra/main.bend as D
import ../Dithra/raster.bend as R
import ./main.bend as M

# Host-side text adapter for Mokko's window demo: Syllo lays out, Dithra
# rasterizes, and Chromi blends the coverage masks.
# Cached results from the public text pipeline; no substitute bitmap font.
type Run is Data:
  Run{metrics: M.Metrics, masks: List<&2, D.PositionedMask>}

def measure(layout: S.Layout) -> M.Metrics:
  S.Layout{ps, w, h, asc, desc, lh, lines} = layout
  M.Metrics{w, h, asc}

def prepare(font: F.Font, label: String, size: F32, width: F32,
  device_scale: F32) -> Result<&2, &2, String, Run>:
  +shared_font = font
  +shared_size = size
  do Result<&2, &2, String, Run>:
    +layout : S.Layout <- S.layout(shared_font, label, shared_size, width)
    masks : List<&2, D.PositionedMask> <- D.render(shared_font, layout, shared_size, device_scale)
    return Run{measure(layout), masks}

def metrics(run: Run) -> M.Metrics:
  Run{m, masks} = run
  m

def paint_mask(mask: D.PositionedMask, canvas: C.Canvas, x: F32, top: F32,
  +device_scale: F32, color: U32) -> C.Canvas:
  D.PositionedMask{dx, dy, start, end, R.Mask{w, h, left, offset_top, advance, data}} = mask
  C.blit_mask(canvas, (x + dx / device_scale : F32),
    (top + dy / device_scale : F32), w, h, data, color)

def paint_masks(masks: List<&2, D.PositionedMask>, canvas: C.Canvas, +x: F32,
  +top: F32, +device_scale: F32, +color: U32) -> C.Canvas:
  match masks:
    case Nil{}:
      canvas
    case mask <> rest:
      paint_masks(rest, paint_mask(mask, canvas, x, top, device_scale, color),
        x, top, device_scale, color)

def paint(run: Run, canvas: C.Canvas, x: F32, top: F32, device_scale: F32,
  color: U32) -> C.Canvas:
  Run{m, masks} = run
  paint_masks(masks, canvas, x, top, device_scale, color)
