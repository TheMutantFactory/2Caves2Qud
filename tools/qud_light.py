"""The overland light model (docs/overland.md, G8) — the Python reference.

Qud's per-cell light is the daylight its Daylight widget adds by the time of day, plus
each lit LightSource's radius. Neither depends on anything but the clock and the static
sources, so the racer can BAKE it: per chunk, per cell, light = max(daylight(clock),
point lights). Race mode bakes at the start and again only at keyframes where the daylight
has moved by more than a step; free drive rebakes on a slow cadence. Both use this.

The clock: a Qud day is DAY_SEGMENTS (Calendar: TurnsPerDay x 10 = 12000, 500 an hour);
StartOfDay 3250 (6:30) and StartOfNight 10000 (20:00) are Qud's own constants (confirmed
in raves-of-qud docs/rendering.md). The dawn / dusk ramps are ours (Qud's Daylight radius
grows in steps over roughly the same hours); refine against the bridge's `time` when it
matters.
"""
import math

DAY_SEGMENTS = 12000
START_OF_DAY = 3250
START_OF_NIGHT = 10000
DAWN = 1000        # segments over which the day comes up after START_OF_DAY (two hours)
DUSK = 1000        # segments over which it goes before START_OF_NIGHT


def daylight(seg):
    """0..1 daylight at a day segment (wraps)."""
    s = seg % DAY_SEGMENTS
    if s < START_OF_DAY or s >= START_OF_NIGHT:
        return 0.0
    if s < START_OF_DAY + DAWN:
        return (s - START_OF_DAY) / float(DAWN)
    if s >= START_OF_NIGHT - DUSK:
        return (START_OF_NIGHT - s) / float(DUSK)
    return 1.0


def point_light(dist_cells, radius):
    """A source's light at a distance in cells: full at the source, gone at the radius."""
    if radius <= 0:
        return 0.0
    return max(0.0, min(1.0, 1.0 - dist_cells / float(radius)))


def light_grid(w, h, lights, seg):
    """Per-cell light for a w x h chunk: max of daylight and every (x, y, radius) source."""
    base = daylight(seg)
    grid = [base] * (w * h)
    for (lx, ly, r) in lights:
        if r <= 0:
            continue
        for y in range(max(0, ly - r), min(h, ly + r + 1)):
            for x in range(max(0, lx - r), min(w, lx + r + 1)):
                v = point_light(math.hypot(x - lx, y - ly), r)
                i = y * w + x
                if v > grid[i]:
                    grid[i] = v
    return grid


def clock_segment(seconds, start_seg, seg_per_s):
    """The day segment at `seconds` into a race that started at `start_seg`."""
    return int(round(start_seg + seconds * seg_per_s)) % DAY_SEGMENTS


def bake_keyframes(start_seg, seconds, seg_per_s, max_delta=0.1, step=1.0):
    """Race times (seconds) at which to re-bake so the daylight never drifts more than
    `max_delta` from the last bake. Always starts with 0.0; a race in steady light is one."""
    keys = [0.0]
    last = daylight(clock_segment(0.0, start_seg, seg_per_s))
    t = step
    while t <= seconds:
        d = daylight(clock_segment(t, start_seg, seg_per_s))
        if abs(d - last) > max_delta:
            keys.append(t - step if t - step > keys[-1] else t)
            last = daylight(clock_segment(keys[-1], start_seg, seg_per_s))
        t += step
    return keys
