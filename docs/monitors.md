# Monitors: the parameters, and adding your own

A monitor is a `Look`: 32 numbers describing the tube. They live in `shaders/retro-crt.slang`: `amber_look()` is the
starting point and `monitor_look()` is a `switch` that changes only what differs.

| parameter | meaning |
|-----------|---------|
| `phosphor` | linear RGB of the phosphor at full brightness |
| `tint` | 0 keeps the terminal's colours, 1 makes the picture monochrome in the phosphor colour |
| `saturation` | colour saturation when `tint` < 1 |
| `mono_value` | with `tint`: how much saturated colours keep their brightness (0 = plain luma, so pure blue goes dark) |
| `persistence` | afterglow decay time constant per channel, seconds (only moves in live mode) |
| `bloom_glow`, `bloom_halo`, `bloom_threshold` | tight glow, wide halation, and the level below which nothing blooms |
| `softness` | horizontal beam softness, pixels |
| `chroma`, `chroma_base` | RGB convergence error: growing towards the edges, and a constant red/blue offset, pixels |
| `scanlines`, `scanline_pitch` | gap darkness (0..1) and spacing in physical pixels |
| `scanline_gap_power`, `scanline_beam_bloom` | how thin the gaps are, and how much bright pixels fill them |
| `mask`, `mask_pitch` | aperture grille strength and RGB triad width, pixels (0 for monochrome tubes) |
| `curvature` | barrel distortion as a fraction of half the window height at the corners |
| `corner_radius`, `bezel_px` | rounded glass corners and the frame width, pixels (the frame hides that much of the window edge) |
| `bezel_color`, `bezel_spill` | plastic colour and how much screen light it catches |
| `flicker`, `hum` | global brightness shimmer and a slow rolling brightness bar |
| `noise`, `noise_size` | snow amplitude and grain size, pixels |
| `hsync`, `jitter` | per-line horizontal wobble and whole-picture shake, pixels |
| `gain`, `ambient`, `vignette`, `glass_shine` | brightness compensation, the glass never being fully black, corner darkening, reflection of the room |

`flat` is not a monitor but a modifier applied on top of any of them: it zeroes `curvature`, `bezel_px`,
`corner_radius`, `hsync` and `jitter` and lowers the vignette, so the picture is 1:1 with what kitty drew and mouse
selection lines up exactly.

## Add a monitor

1. In `shaders/retro-crt.slang`: raise `NUM_MONITORS`, extend the comment beside it with the new name, and add a
   `case N:` to `monitor_look()` that overrides what differs from amber.
2. In `bin/crt`: append the name to `MONITORS` and a line to `DESCRIPTIONS`.
3. In `config/crt.conf.in`: add `map ctrl+alt+N set_colors --all --configured background=#0000NN` (NN is the two-digit
   hex of N-1). Monitor numbers go up to 15 (the code must stay a few levels off black).
4. `python3 -m unittest discover -s tests` tells you if any of the three disagree with the others.
5. `./install.sh --dev` if you are running from the repo, then `crt <name>`. A running window needs its shader rebuilt
   once (restart it, or ctrl+shift+f12 twice).

## Tuning tips

* Text too soft: lower `softness`, `bloom_glow` and `scanlines`, or use `flat` (no resampling at all).
* Too dark: raise `gain`. It compensates for what scanlines and the mask take away.
* A rounder screen: raise `curvature`. Mouse selection is off by up to roughly `curvature × half-height` pixels at the extreme
  corners (0.06 gives about one cell at 1080p) and exact along the axes.
* A longer trail: raise `persistence`. Green is 0.16 s, amber 0.07 s.
* Quick look at what a pass produces: set `DEBUG_VIEW` in the shader to 1 (the phosphor image), 2 (glow) or 3 (halo).
