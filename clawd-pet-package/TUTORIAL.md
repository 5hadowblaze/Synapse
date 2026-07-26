# Clawd Pet — Animation Tutorial & Guide

This package contains everything needed to animate **Clawd**, a blocky coral pixel-art
crab mascot, from a single sprite atlas. It is written so that **any AI or engine** can
read it and reproduce the animation without further context.

If you are an AI reading this: everything you need is in this file plus
[`animation-spec.json`](animation-spec.json). Follow the "Quick contract for an AI"
section below and you are done.

---

## 1. What's in this package

```
clawd-pet-package/
├── pet.json                     # Pet identity + which spritesheet to load
├── animation-spec.json          # Machine-readable animation contract (READ THIS FIRST)
├── TUTORIAL.md                  # This file
├── player.html                  # Self-contained reference player (open in a browser)
└── assets/
    ├── spritesheet.webp         # The sprite atlas (RGBA, transparent) — primary
    ├── spritesheet.png          # Same atlas as PNG, for tools that can't read webp
    ├── contact-sheet.png        # Labeled overview of every row/frame (human reference)
    └── previews/                # One animated GIF per state (visual ground truth)
        ├── idle.gif
        ├── running-right.gif
        ├── running-left.gif
        ├── waving.gif
        ├── jumping.gif
        ├── failed.gif
        ├── waiting.gif
        ├── running.gif
        └── review.gif
```

---

## 2. The sprite atlas at a glance

| Property            | Value                                            |
|---------------------|--------------------------------------------------|
| File                | `assets/spritesheet.webp` (or `.png`)            |
| Total size          | **1536 × 1872** pixels                            |
| Grid                | **8 columns × 9 rows**                            |
| Cell (frame) size   | **192 × 208** pixels                             |
| Color / background  | **RGBA, fully transparent** background           |
| Layout              | Row-major. **Each row is one animation state.**  |

The background is **already transparent** (the alpha channel is the mask). Do **not**
apply any color-keying/chroma removal — that step is already done.

### Frame extraction math

A frame at grid position `(row, col)` occupies this pixel rectangle in the atlas:

```
x = col * 192
y = row * 208
w = 192
h = 208
```

Rows are counted from the **top** (row 0 is the first row). Columns from the **left**
(col 0 is the first column). Read only the first *N* columns of a row, where *N* is that
state's frame count (below). **Cells beyond a state's frame count are empty/transparent —
ignore them.**

---

## 3. The 9 animation states

Each row of the atlas is a complete looping (or one-shot) animation. Use these exact
frame counts — reading extra columns will show blank frames.

| Row | State           | Frames | Suggested FPS | Loop  | Meaning / when to show it                                   |
|-----|-----------------|:------:|:-------------:|:-----:|-------------------------------------------------------------|
| 0   | `idle`          | 6      | 6             | yes   | Calm resting — breathing + blinking. **Default state.**     |
| 1   | `running-right` | 8      | 12            | yes   | Moving/being dragged to the **right**; faces right.         |
| 2   | `running-left`  | 8      | 12            | yes   | Moving/being dragged to the **left**; faces left.           |
| 3   | `waving`        | 4      | 8             | yes   | Greeting / getting attention.                               |
| 4   | `jumping`       | 5      | 10            | no    | Hover or playful jump. Play once, then return to `idle`.    |
| 5   | `failed`        | 8      | 10            | no    | Blocked / failed / cancelled reaction. Play once.           |
| 6   | `waiting`       | 6      | 6             | yes   | Waiting for approval, help, or user input (expectant pose). |
| 7   | `running`       | 6      | 8             | yes   | Actively working/processing (thinking — NOT foot-running).  |
| 8   | `review`        | 6      | 8             | yes   | Reviewing finished/ready output (focused lean).             |

> Note on naming: `running` (row 7) means **doing work / processing**, not literal
> locomotion. Left/right travel is `running-right` / `running-left`.

---

## 4. Quick contract for an AI (read this if nothing else)

To animate Clawd:

1. Load `assets/spritesheet.webp` (fall back to `assets/spritesheet.png`).
2. It is a 1536×1872 RGBA image; each frame is 192×208; grid is 8 cols × 9 rows.
3. Pick a state from [`animation-spec.json`](animation-spec.json) → gives you `row`,
   `frames`, `fps`, and `loop`.
4. For frame index `i` (0-based, `0 ≤ i < frames`), blit the sub-rectangle
   `x = i*192, y = row*208, w = 192, h = 208` to the screen.
5. Advance `i` every `1000/fps` milliseconds. If `loop` is true, wrap with `i = (i+1) % frames`;
   otherwise stop on the last frame.
6. The background is transparent — composite over whatever you like.

That is the whole animation. Everything below is reference detail and sample code.

---

## 5. Reference implementations

### 5a. Browser — the included player

Open [`player.html`](player.html) directly in any modern browser. It loads the atlas,
lets you switch between all 9 states, and animates them at the suggested FPS. Use it to
confirm the animation looks right, and read its source as a canonical JS implementation.

### 5b. HTML5 Canvas (minimal)

```html
<canvas id="c" width="192" height="208"></canvas>
<script>
const FW = 192, FH = 208;
// state -> [row, frameCount, fps, loop]
const STATES = {
  idle:[0,6,6,true], "running-right":[1,8,12,true], "running-left":[2,8,12,true],
  waving:[3,4,8,true], jumping:[4,5,10,false], failed:[5,8,10,false],
  waiting:[6,6,6,true], running:[7,6,8,true], review:[8,6,8,true],
};
const ctx = document.getElementById("c").getContext("2d");
const sheet = new Image();
sheet.src = "assets/spritesheet.png";        // or spritesheet.webp
let state = "idle", i = 0, last = 0;
sheet.onload = () => requestAnimationFrame(loop);
function loop(t){
  const [row, frames, fps, doLoop] = STATES[state];
  if (t - last >= 1000/fps){
    last = t;
    i = doLoop ? (i+1) % frames : Math.min(i+1, frames-1);
  }
  ctx.clearRect(0,0,FW,FH);
  ctx.drawImage(sheet, i*FW, row*FH, FW, FH, 0, 0, FW, FH);
  requestAnimationFrame(loop);
}
// To change state: state = "waving"; i = 0;
</script>
```

### 5c. CSS-only sprite (single state, e.g. idle)

```css
.clawd {
  width: 192px; height: 208px;
  background: url("assets/spritesheet.png") 0 0 / auto no-repeat;
  animation: clawd-idle 1s steps(6) infinite;   /* 6 frames -> 6 fps at 1s */
}
/* Move across 6 frames of row 0. End x = -(6 * 192) = -1152px, y stays 0 (row 0). */
@keyframes clawd-idle { from { background-position: 0 0; } to { background-position: -1152px 0; } }
```

For a different row, offset `background-position-y` by `-row * 208px` and set the step
count and total X shift to that state's frame count.

### 5d. Python (Pillow) — extract every frame to PNGs

```python
from PIL import Image

FW, FH = 192, 208
STATES = {
    "idle": (0, 6), "running-right": (1, 8), "running-left": (2, 8),
    "waving": (3, 4), "jumping": (4, 5), "failed": (5, 8),
    "waiting": (6, 6), "running": (7, 6), "review": (8, 6),
}
sheet = Image.open("assets/spritesheet.webp").convert("RGBA")
for name, (row, frames) in STATES.items():
    for i in range(frames):
        frame = sheet.crop((i*FW, row*FH, i*FW+FW, row*FH+FH))
        frame.save(f"{name}_{i}.png")
```

### 5e. Python (Pillow) — rebuild an animated GIF for one state

```python
from PIL import Image

FW, FH = 192, 208
row, frames, fps = 0, 6, 6          # idle
sheet = Image.open("assets/spritesheet.webp").convert("RGBA")
imgs = [sheet.crop((i*FW, row*FH, i*FW+FW, row*FH+FH)) for i in range(frames)]
imgs[0].save("idle.gif", save_all=True, append_images=imgs[1:],
             duration=int(1000/fps), loop=0, disposal=2, transparency=0)
```

### 5f. Game engines (general notes)

- **Unity:** Import `spritesheet.png`, set Sprite Mode = Multiple, use the Sprite Editor
  with a grid slice of cell size 192×208. Each row becomes one animation clip; set the
  clip's sample rate to the suggested FPS.
- **Godot:** Use an `AnimatedSprite2D` with a `SpriteFrames` resource, or a `Sprite2D`
  with `hframes = 8`, `vframes = 9`, and drive `frame` = `row*8 + col`.
- **Phaser / PixiJS:** Load as a spritesheet with frame size 192×208 and define
  animations by frame index ranges (row*8 .. row*8 + frames-1).
- **Any engine:** the universal rule is the rectangle in §2. If your tool asks for
  columns/rows, use 8×9; if it asks for frame size, use 192×208.

---

## 6. Suggested behavior / state machine

A simple way to make Clawd feel alive (mirrors how these mascots are typically driven):

- Default to `idle`.
- On greeting / first appearance → `waving`, then back to `idle`.
- While dragged or moving right → `running-right`; moving left → `running-left`.
- While doing work / thinking → `running`.
- While waiting for the user to approve or answer → `waiting`.
- When presenting a finished result → `review`.
- On success celebration → `jumping` (one-shot) → `idle`.
- On error / blocked / cancelled → `failed` (one-shot) → `idle`.

One-shot states (`jumping`, `failed`) should play their frames once and then fall back
to `idle`. Looping states repeat until the driving condition changes.

---

## 7. Ready-to-paste prompt for an AI

If you want to hand this whole package to an AI and have it build the animation, paste
something like this along with the files:

```
You are given a sprite atlas for a mascot named "Clawd" plus an animation spec.

Files:
- assets/spritesheet.webp (or assets/spritesheet.png): a 1536x1872 RGBA image,
  transparent background, laid out as an 8-column by 9-row grid of 192x208 cells.
- animation-spec.json: the machine-readable contract (row, frame count, fps, loop per state).

Each row is one animation state. Frame (row, col) is the pixel rectangle
x=col*192, y=row*208, w=192, h=208. Read only the first N columns of a row where N is
that state's frame count from the spec; ignore any empty trailing cells. The background
is already transparent — do not color-key.

Build a [web page / component / game object] that displays Clawd and can play any of the
9 states (idle, running-right, running-left, waving, jumping, failed, waiting, running,
review) at the spec's suggested FPS, looping the looping states and playing one-shot
states once before returning to idle. Start in the idle state.
```

---

## 8. Troubleshooting

- **Blank/empty frames appear:** you're reading more columns than the state has frames.
  Clamp to the frame count in §3 / the spec.
- **Animation looks like it "jumps back":** you're wrapping a one-shot state. Set
  `jumping` and `failed` to non-looping.
- **Colored halo around the crab:** your loader is ignoring the alpha channel. Load as
  RGBA and composite with alpha blending. Do not re-key the background.
- **`.webp` won't load in your tool:** use `assets/spritesheet.png` instead — it is the
  identical atlas.
- **Frames look offset/misaligned:** confirm cell size is 192×208 (not square) and grid
  is 8×9. The cells are taller than they are wide.
- **Wrong direction:** `running-right` faces right, `running-left` faces left. If your
  movement direction and the sprite disagree, you've swapped rows 1 and 2.
