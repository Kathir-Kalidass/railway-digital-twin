import os
os.environ["ML_STUB"] = "1"
from fastapi.testclient import TestClient
from app import app

client = TestClient(app)


def test_health_reports_stub():
    res = client.get("/health")
    assert res.status_code == 200
    body = res.json()
    assert body["ok"] is True
    assert body["stub"] is True
    assert body["modelLoaded"] is True


def test_detect_rejects_empty_body():
    res = client.post("/detect", content=b"", headers={"content-type": "image/jpeg"})
    assert res.status_code == 400


def test_detect_returns_detections():
    res = client.post("/detect", content=b"jpeg-bytes", headers={"content-type": "image/jpeg"})
    assert res.status_code == 200
    body = res.json()
    assert body["model"] == "stub"
    assert body["detections"]
