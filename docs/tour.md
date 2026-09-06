# The tour

The game drives the wizard through every course in cup order, in real time, so a person can
watch and talk back without touching the wheel.

```bash
cd godot && Godot -- --type=gp --tour
```

Options: `--tour_start=N` begins at the Nth course (1 = Joppa); `--tour_seconds=N` caps each
course (120 by default; a circuit ends after the wizard's first lap, a section race when it
finishes, whichever comes first); `--noattacks` keeps the field from shooting while you look.
A strip under the HUD says which course this is, its cup and the seconds left.

## Talking back

- **SPACE** (or P) pauses and opens the note box. The screenshot is taken the instant of the
  pause, before the box covers the view. The box shows the course, the lap or section, the
  spot on the loop and the race time.
- **Enter** saves the note and resumes; **Esc** resumes without saving; Shift+Enter starts a
  new line.
- **N** and **B** jump to the next and previous course; **T** takes the wheel (WASD, shift
  to drift); **A** hands it back to the auto-driver.

Notes append to `reports/tour-feedback.md` in the repo, newest last, each with the course
and key, the lap or section, the loop fraction and waypoint, the race time, the note and its
screenshot under `reports/tour/`. Commit the file and the images with the rest; the notes
are the record of what a real eye saw on each course, which the probes cannot give.

```markdown
## Joppa Waterwheel Run (joppa) — lap 1, 0.31 of the loop, wp 190, race time 0:24

the village huts sit too far from the curb; the pond reads well

![joppa](tour/joppa-2026-09-06T21-14-03.png)
```

## The probe

`--tour_test` pauses at three seconds of racing, files a note and moves on to the next
course, then quits: the headless check that the pause, the note, the file and the advance
all work. `--tour_hold` with it stays paused with the box up, for a screenshot.
