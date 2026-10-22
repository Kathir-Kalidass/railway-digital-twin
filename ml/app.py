import logging
import os
from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from detector import WildlifeDetector

logging.basicConfig(level=logging.INFO)
app = FastAPI(title="Railway Wildlife Detector")
detector = WildlifeDetector()


@app.get("/health")
def health():
    return {
        "ok": True,
        "stub": detector.stub,
        "modelLoaded": detector.model_loaded,
        "model": "stub" if detector.stub else "ssdlite320_mobilenet_v3_large",
        "device": detector.device,
    }


@app.post("/detect")
async def detect(request: Request):
    body = await request.body()
    if not body:
        return JSONResponse({"error": "empty image"}, status_code=400)
    if len(body) > 1_000_000:
        return JSONResponse({"error": "image too large"}, status_code=413)
    try:
        result = detector.detect(body)
    except ValueError as exc:
        return JSONResponse({"error": str(exc)}, status_code=400)
    except Exception as exc:
        logging.exception("detector failed")
        return JSONResponse({"error": "model unavailable", "detail": str(exc)}, status_code=503)
    logging.info(
        "detect model=%s detections=%d latencyMs=%s",
        result["model"], len(result["detections"]), result.get("latencyMs"),
    )
    return result
