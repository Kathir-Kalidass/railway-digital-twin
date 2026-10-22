import os
os.environ["ML_STUB"] = "1"
import pytest
from detector import WildlifeDetector


def test_stub_returns_one_animal_detection():
    detector = WildlifeDetector(stub=True)
    result = detector.detect(b"not-a-real-jpeg")
    assert result["model"] == "stub"
    assert len(result["detections"]) == 1
    det = result["detections"][0]
    assert det["label"] in {
        "bird", "cat", "dog", "horse", "sheep", "cow",
        "elephant", "bear", "zebra", "giraffe",
    }
    assert 0.0 <= det["confidence"] <= 1.0
    assert len(det["box"]) == 4


def test_stub_is_deterministic():
    detector = WildlifeDetector(stub=True)
    assert detector.detect(b"x") == detector.detect(b"x")


def test_invalid_image_is_rejected_before_model_load():
    detector = WildlifeDetector(stub=False)

    def fail_load():
        raise AssertionError("model must not load for an invalid image")

    detector._load = fail_load
    with pytest.raises(ValueError, match="invalid image"):
        detector.detect(b"not-an-image")
