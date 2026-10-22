# Railway wildlife detector

FastAPI service used by the backend camera pipeline. It accepts one JPEG frame
and returns COCO animal detections.

```bash
cd ml
python -m pip install -r requirements.txt
ML_STUB=1 uvicorn app:app --host 127.0.0.1 --port 8001
curl -s http://127.0.0.1:8001/health
```

`ML_STUB=1` returns a deterministic elephant detection without loading torch
or downloading weights. The normal path uses torchvision
`ssdlite320_mobilenet_v3_large`, filters to COCO animal labels, and caches
weights under `ml/.cache/` when configured by torchvision.

`ML_DEVICE` defaults to `cpu`; `ML_MIN_CONFIDENCE` defaults to `0.5`.
