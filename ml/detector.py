import io
import os
import time

ANIMAL_LABELS = {
    "bird", "cat", "dog", "horse", "sheep", "cow",
    "elephant", "bear", "zebra", "giraffe",
}


class WildlifeDetector:
    def __init__(self, stub=None, device=None, min_confidence=None):
        self.stub = os.getenv("ML_STUB", "0") == "1" if stub is None else bool(stub)
        self.device = device or os.getenv("ML_DEVICE", "cpu")
        self.min_confidence = float(
            min_confidence if min_confidence is not None else os.getenv("ML_MIN_CONFIDENCE", "0.5")
        )
        self._model = None
        self._labels = None

    @property
    def model_loaded(self):
        if self.stub:
            return True
        try:
            self._load()
            return True
        except Exception:
            return False

    def _load(self):
        if self._model is not None:
            return
        import torch
        import torchvision
        from torchvision.models.detection import SSDLite320_MobileNet_V3_Large_Weights

        weights = SSDLite320_MobileNet_V3_Large_Weights.DEFAULT
        model = torchvision.models.detection.ssdlite320_mobilenet_v3_large(weights=weights)
        model.eval()
        model.to(self.device)
        self._model = model
        self._labels = weights.meta["categories"]

    def detect(self, image_bytes):
        if not image_bytes:
            raise ValueError("empty image")
        if self.stub:
            return {
                "model": "stub",
                "detections": [{
                    "label": "elephant",
                    "confidence": 0.92,
                    "box": [0.32, 0.34, 0.72, 0.78],
                }],
                "latencyMs": 1,
            }

        import torch
        from PIL import Image
        from torchvision.transforms.functional import pil_to_tensor

        self._load()
        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
        tensor = pil_to_tensor(image).float().div(255.0).unsqueeze(0).to(self.device)
        started = time.time()
        with torch.no_grad():
            output = self._model(tensor)[0]

        detections = []
        for label_id, score, box in zip(
            output["labels"].tolist(), output["scores"].tolist(), output["boxes"].tolist()
        ):
            label = self._labels[label_id]
            if label not in ANIMAL_LABELS or score < self.min_confidence:
                continue
            width, height = image.size
            detections.append({
                "label": label,
                "confidence": round(float(score), 4),
                "box": [box[0] / width, box[1] / height, box[2] / width, box[3] / height],
            })
        detections.sort(key=lambda d: d["confidence"], reverse=True)
        return {
            "model": "ssdlite320_mobilenet_v3_large",
            "detections": detections,
            "latencyMs": int((time.time() - started) * 1000),
        }
