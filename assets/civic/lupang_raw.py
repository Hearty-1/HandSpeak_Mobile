"""Raw-landmark specialists (Lupang Hinirang v4, Calendar v1) with open-set rejection.

The phone sends per-frame MediaPipe landmarks + timestamps; this module runs
the SAME landmark -> feature pipeline and decision gates as the local live
engines (app/lupang_common.py, a verbatim copy of the training repo's file)
and the specialist's ONNX export. Everything specialist-specific (classes,
INVALID index, still-edge trim, thresholds, duration floors) comes from the
specialist's JSON written by export_lupang_onnx.py.
"""
from __future__ import annotations

import json
import logging
import os
import time
from pathlib import Path
from typing import Any

import numpy as np
import onnxruntime as ort

from . import lupang_common as lc

log = logging.getLogger("handspeak.lupang_raw")

MODELS_DIR = Path(os.getenv("MODELS_DIR", Path(__file__).resolve().parent.parent / "models"))
META_FILE = "lupang_hinirang_v4.json"
# model_id -> metadata file; each entry becomes POST /v1/predict_raw/{model_id}.
RAW_SPECIALISTS = {
    "lupang_hinirang": "lupang_hinirang_v4.json",
    "calendar": "calendar_v1.json",
}


def _softmax(x: np.ndarray) -> np.ndarray:
    e = np.exp(x - x.max(axis=-1, keepdims=True))
    return e / e.sum(axis=-1, keepdims=True)


class RawSpecialistModel:
    def __init__(self, meta_file: str = META_FILE, models_dir: Path = MODELS_DIR) -> None:
        meta = json.loads((models_dir / meta_file).read_text(encoding="utf-8"))
        if meta["feature_version"] != lc.FEATURE_VERSION or meta["feature_names"] != lc.FEATURE_NAMES:
            raise RuntimeError(
                f"{meta_file} was exported for feature set {meta['feature_version']!r} but app/lupang_common.py "
                f"is {lc.FEATURE_VERSION!r}; re-run export_lupang_onnx.py")
        self.meta = meta
        self.model_id: str = meta.get("model_id", "lupang_hinirang")
        self.class_names: list[str] = meta["class_names"]
        self.labels: list[str] = meta.get("display_labels") or self.class_names
        if len(self.labels) != len(self.class_names):
            raise RuntimeError(f"{meta_file}: {len(self.labels)} display labels for {len(self.class_names)} classes")
        self.gate: dict[str, Any] = meta["gate"]
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = int(os.getenv("ORT_THREADS", "1"))
        opts.inter_op_num_threads = 1
        self.session = ort.InferenceSession(str(models_dir / meta["onnx_file"]), sess_options=opts,
                                            providers=["CPUExecutionProvider"])
        probs = self._batch_probs(np.zeros((2, lc.T, lc.FEATURE_DIM), dtype=np.float32))
        if probs.shape != (2, len(self.class_names)) or not np.allclose(probs.sum(1), 1.0, atol=1e-3):
            raise RuntimeError(f"{self.model_id} self-check failed: output {probs.shape}")
        inv = int(self.gate.get("invalid_index", lc.INVALID_IDX))
        if self.class_names[inv] != "INVALID_GESTURE":
            raise RuntimeError(f"{self.model_id}: class {inv} is not INVALID_GESTURE")

    def _batch_probs(self, batch: np.ndarray) -> np.ndarray:
        logits = self.session.run(["logits"], {"features": np.ascontiguousarray(batch, dtype=np.float32)})[0]
        return _softmax(logits.astype(np.float64))

    @staticmethod
    def to_raw(frames: list[dict[str, Any]], image_width: int, image_height: int) -> tuple[np.ndarray, np.ndarray]:
        aspect = image_width / float(image_height)
        raw = np.stack([lc.raw_from_arrays(f.get("pose"), f.get("left_hand"), f.get("right_hand"), aspect)
                        for f in frames])
        ts = np.array([f["t"] for f in frames], dtype=np.float64)
        return raw, ts - ts[0]

    def predict(self, frames: list[dict[str, Any]], image_width: int, image_height: int,
                top_k: int = 3) -> dict[str, Any]:
        t0 = time.perf_counter()
        raw, ts = self.to_raw(frames, image_width, image_height)
        out = lc.evaluate_capture(raw, ts, self._batch_probs, self.gate)
        probs = out["probs"]
        info = out["info"] or {}
        first = out["failed"][0] if out["failed"] else None

        def entry(i: int) -> dict[str, Any]:
            e = {"index": int(i), "label": self.labels[i], "confidence": round(float(probs[i]), 6)}
            if self.labels[i] != self.class_names[i]:
                e["label_en"] = self.class_names[i]
            return e

        top = [entry(i) for i in np.argsort(-probs)[:top_k]] if probs is not None else []
        repairs = info.get("repairs") or {}
        return {
            "model": self.model_id,
            "model_version": f"{lc.FEATURE_VERSION}/{self.meta['source_checkpoint']}",
            "accepted": bool(out["accepted"]),
            "prediction": top[0] if out["accepted"] else None,
            "rejection": None if out["accepted"] else {
                "code": first, "message": lc.REJECT_TEXT.get(first, first)},
            "failed_checks": out["failed"],
            "checks": [{"code": c.code, "label": c.label, "value": round(float(c.value), 4),
                        "threshold": None if c.thr is None else round(float(c.thr), 4),
                        "passed": c.passed, "text": c.text} for c in out["checks"]],
            "top_k": top,
            "capture": {
                "frames": len(frames),
                "active_frames": int(info.get("active_frames", 0)),
                "active_duration_s": round(float(info.get("duration_s", 0.0)), 3),
                "fps": round(float(info.get("fps", 0.0)), 1),
                "resting_hand": repairs.get("resting_hand"),
            },
            "inference_ms": round((time.perf_counter() - t0) * 1000.0, 2),
        }

    def describe(self) -> dict[str, Any]:
        return {
            "id": self.model_id,
            "endpoint": f"/v1/predict_raw/{self.model_id}",
            "classes": self.labels,
            "input": "raw MediaPipe landmarks per frame (see app/main.py RawPredictRequest)",
            "feature_version": lc.FEATURE_VERSION,
            "num_classes": len(self.class_names),
            "invalid_index": self.meta["invalid_index"],
            "mediapipe_settings": self.meta["holistic_settings"],
        }


class LupangRawModel(RawSpecialistModel):
    """Backwards-compatible name for the Lupang Hinirang raw model."""

    def __init__(self, models_dir: Path = MODELS_DIR) -> None:
        super().__init__(RAW_SPECIALISTS["lupang_hinirang"], models_dir)


def load_raw_specialists(models_dir: Path = MODELS_DIR) -> dict[str, RawSpecialistModel]:
    return {mid: RawSpecialistModel(meta, models_dir) for mid, meta in RAW_SPECIALISTS.items()}
