# Performance

All numbers were measured on one machine and are only as general as that: **Fedora 43, KDE Plasma 6 on Wayland,
kitty 0.49.1, RTX 2070 Max-Q laptop (NVIDIA 580), 1920×1080 at 144 Hz, display scale 1.25**. The desktop was in normal
use during every run, so treat a couple of watts as noise.

**Method.** GPU power is `nvidia-smi --query-gpu=power.draw`, one sample per second for 30 s, reported as the median of
the run. It is taken 20 s after the window opens; a first attempt that waited only 9 s read still mode at +6 W, which
was the GPU still winding down after the shader build, so give it time. kitty CPU is the change in `utime + stime`
from `/proc/<pid>/stat` over the same 30 s. The window shows a static screen (`tools/patterns/ui.py`, cursor hidden).

## While it runs

| mode | kitty CPU | GPU power, median of run |
|------|-----------|--------------------------|
| no kitty-crt window | | 14.4 W, then 19.7 W in a second run (what else the desktop was doing moved the baseline) |
| `retro-crt` (still) | 0 % | 14.5 W and 19.6 W: within 0.1 W of no window in both runs |
| `retro-crt crt-live` (60 fps) | 7-11 % of one core | 35.0 W and 23.6 W in those two runs; 34.8 W and 36.6 W in two earlier runs against 18.8 W and 20.2 W |

Across the four paired runs live mode raised the median GPU power by **+4 to +21 W (median +16 W)**, and it usually
sits around 35 W. It varies because the GPU moves between power states depending on what else is drawing.

The frame interval makes **no difference**: 16, 33 and 50 ms all measured the same. So the cost is a power-state change
(continuous rendering keeps the GPU out of its low-power state), not a per-frame cost, and slowing the clock does not
help. On battery, use the still monitor (`CRT_SHADERS=retro-crt kitty-crt`, or ctrl+shift+f12).

## Switching

| action | cost |
|--------|------|
| pick a monitor with `ctrl+alt+1..5` | one frame: kitty's own `set_colors` action, no process involved |
| `crt next`, `crt green`, picker keypress | about 85 ms (median of 25, 77-119): 27 ms starting Python plus about 22 ms for each of the two `kitten @` calls |
| live ↔ still (`crt-switch`) | about 7-8 s to build in the background, then about 0.3 s to apply; the window never freezes |
| the same switch without `crt-switch` (`load-config` straight away) | the window froze for about 6 s |
| start with a cold shader cache | 5-10 s (kitty builds 11 modules with `slangc`, one after another) |
| start with a warm cache | building the pipeline again takes about 0.5 s |

`install.sh` builds the default pipeline once, so the first start is the warm one. kitty keeps one pipeline in its
cache: after a live ↔ still switch the next fresh start rebuilds its own default.

## Picture quality

* 16-bit offscreen textures where the driver supports them, so trails and bloom do not band.
* Curvature resamples the picture bilinearly; `flat` reads pixels 1:1.
* With curvature 0.06, clicks and selections are off by up to about 29 px at the extreme corners of a 1080p window
  (`curvature × half the picture height`) and exact along the axes, because kitty maps the mouse to the picture
  *before* the shader bends it. `flat` removes the difference.
