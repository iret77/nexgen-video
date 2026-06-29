from nexgen_engine.frames import crop_from_master, pan_pair


def test_frames_modules_import():
    assert pan_pair is not None
    assert crop_from_master is not None


def test_no_musicvideo_references():
    import inspect

    assert "musicvideo" not in inspect.getsource(pan_pair)
    assert "musicvideo" not in inspect.getsource(crop_from_master)


def test_exposes_public_api():
    assert hasattr(pan_pair, "plan_pan_pair")
    assert hasattr(pan_pair, "generate_pan_pair")
    assert hasattr(pan_pair, "PanPairPlan")
    assert hasattr(crop_from_master, "plan_crop")
    assert hasattr(crop_from_master, "generate_crop")
    assert hasattr(crop_from_master, "CropPlan")


def test_plan_pan_pair_horizontal():
    # 32:9 master, 16:9 target → target box is half the master width, both boxes full height.
    plan = pan_pair.plan_pan_pair((3200, 900), "16:9", "right", travel_pct=100.0)
    assert plan.target_size == (1600, 900)
    assert plan.start_box[1] == 0 and plan.start_box[3] == 900
    assert plan.travel_px == 1600
    # 'right' starts at the left edge and ends at the right edge for full travel.
    assert plan.start_box[0] == 0
    assert plan.end_box[0] == 1600


def test_plan_pan_pair_rejects_too_narrow_master():
    import pytest

    with pytest.raises(ValueError):
        pan_pair.plan_pan_pair((1600, 900), "21:9", "right")


def test_plan_crop_center_from_wide_master():
    # 21:9 master, 16:9 target → height stays, width shrinks, centered.
    plan = crop_from_master.plan_crop((2100, 900), "16:9", anchor="center")
    assert plan.target_size == (1600, 900)
    left = plan.box[0]
    assert left == (2100 - 1600) // 2
    assert plan.box == (left, 0, left + 1600, 900)


def test_plan_crop_full_take_on_matching_aspect():
    plan = crop_from_master.plan_crop((1600, 900), "16:9")
    assert plan.box == (0, 0, 1600, 900)
    assert plan.target_size == (1600, 900)
