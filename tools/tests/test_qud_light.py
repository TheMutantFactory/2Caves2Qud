"""The overland light model (docs/overland.md G8): daylight from the clock plus the baked
light sources, per cell. The Python reference the engine's darkness bake mirrors."""
import qud_light as ql


def test_daylight_is_full_at_noon_and_none_at_midnight():
    assert ql.daylight(6000) == 1.0          # noon
    assert ql.daylight(0) == 0.0             # midnight
    assert ql.daylight(ql.START_OF_NIGHT + 500) == 0.0
    assert ql.daylight(ql.START_OF_DAY - 1) == 0.0


def test_dawn_and_dusk_ramp_monotonically():
    dawn = [ql.daylight(s) for s in range(ql.START_OF_DAY, ql.START_OF_DAY + ql.DAWN + 1, 50)]
    assert dawn[0] == 0.0 and dawn[-1] == 1.0 and all(b >= a for a, b in zip(dawn, dawn[1:]))
    dusk = [ql.daylight(s) for s in range(ql.START_OF_NIGHT - ql.DUSK, ql.START_OF_NIGHT + 1, 50)]
    assert dusk[0] == 1.0 and dusk[-1] == 0.0 and all(b <= a for a, b in zip(dusk, dusk[1:]))
    assert ql.daylight(ql.DAY_SEGMENTS + 6000) == 1.0, "the clock wraps"


def test_point_light_falls_off_to_the_radius():
    assert ql.point_light(0.0, 6) == 1.0
    assert 0.0 < ql.point_light(3.0, 6) < 1.0
    assert ql.point_light(6.0, 6) == 0.0
    assert ql.point_light(9.0, 6) == 0.0
    assert ql.point_light(0.0, 0) == 0.0


def test_light_grid_is_the_max_of_daylight_and_sources():
    lights = [(10, 5, 4)]
    night = ql.light_grid(20, 10, lights, 0)
    assert len(night) == 200
    assert night[5 * 20 + 10] == 1.0
    assert night[5 * 20 + 12] == ql.point_light(2.0, 4)
    assert night[0] == 0.0
    noon = ql.light_grid(20, 10, lights, 6000)
    assert all(v == 1.0 for v in noon), "daylight floods everything at noon"
    dusk = ql.light_grid(20, 10, lights, ql.START_OF_NIGHT - ql.DUSK // 2)
    assert dusk[0] == ql.daylight(ql.START_OF_NIGHT - ql.DUSK // 2)
    assert dusk[5 * 20 + 10] == 1.0, "a torch beats a half-lit dusk"


def test_race_clock_maps_seconds_to_segments():
    # a race that starts at 18:00 (segment 9000) and runs an hour of Qud time per real minute
    assert ql.clock_segment(0.0, 9000, 500.0 / 60.0) == 9000
    assert ql.clock_segment(60.0, 9000, 500.0 / 60.0) == 9500
    assert ql.clock_segment(6 * 60.0, 9000, 500.0 / 60.0) == 0, "wraps past midnight"


def test_keyframes_cover_a_race_at_a_bounded_change():
    # the bake schedule: segments at which the light changes enough to re-bake, over a race
    ks = ql.bake_keyframes(start_seg=9000, seconds=200.0, seg_per_s=500.0 / 60.0, max_delta=0.1)
    assert ks[0] == 0.0
    assert all(b > a for a, b in zip(ks, ks[1:]))
    for a, b in zip(ks, ks[1:]):
        da = ql.daylight(ql.clock_segment(a, 9000, 500.0 / 60.0))
        db = ql.daylight(ql.clock_segment(b, 9000, 500.0 / 60.0))
        assert abs(da - db) <= 0.1 + 1e-9
    assert ql.bake_keyframes(6000, 200.0, 500.0 / 60.0, 0.1) == [0.0], "noon to 13:40: one bake"
