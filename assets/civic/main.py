"""HandSpeak FSL inference API (Cloud Run).

POST /v1/predict/{model_id}   model_id: greetings | lupang_hinirang   (legacy: client-built feature vector)
POST /v1/predict_raw/{model_id}   model_id: lupang_hinirang | calendar
                                 raw MediaPipe landmarks per frame -> specialist model + rejection gates
POST /v1/predict_raw/letter_j    dynamic letters: one hand's stroke (21 landmarks per frame + image size)
POST /v1/predict_raw/letter_z    or the 24 jz-v2 features -> P(letter), accepted if >= 0.25
GET  /v1/models               list models + expected feature length
GET  /health                  liveness/readiness (no auth, no data). NOT /healthz: Cloud Run reserves it
"""
import json
import logging
import math
import sys
import time
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field, field_validator, model_validator

from .auth import init_firebase, require_user
from .letters_jz import load_letter_models
from .letters_jz_common import FEATURE_DIM as LETTER_FEATURE_DIM
from .lupang_raw import load_raw_specialists
from .registry import InputValidationError, ModelRegistry

logging.basicConfig(level=logging.INFO, stream=sys.stdout, format="%(message)s")
log = logging.getLogger("handspeak.api")

MAX_BODY_BYTES = 128 * 1024  # a 818-float vector is ~10 KB; anything bigger is abuse
# Raw landmark captures: up to MAX_RAW_FRAMES x (33*3 + 2*21*3) numbers as JSON.
RAW_PATH_PREFIX = "/v1/predict_raw/"
MAX_RAW_BODY_BYTES = 2 * 1024 * 1024
MAX_RAW_FRAMES = 600         # 20 s at 30 fps; the live engine auto-stops at 12 s
MAX_RAW_DURATION_S = 30.0


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_firebase()
    app.state.registry = ModelRegistry()  # fail fast at boot if a model/label file is wrong
    app.state.raw_models = load_raw_specialists()
    for mid, m in app.state.raw_models.items():
        log.info("loaded raw model %s (%s, %d classes)", mid, m.meta["source_checkpoint"], len(m.class_names))
    app.state.letter_models = load_letter_models()
    for mid, m in app.state.letter_models.items():
        log.info("loaded letter model %s (%s, threshold %.2f)", mid, m.meta["model_filename"], m.threshold)
    yield


# Interactive docs/openapi disabled: this is a private API for the mobile app.
app = FastAPI(title="HandSpeak FSL Inference", lifespan=lifespan, docs_url=None, redoc_url=None, openapi_url=None)


@app.middleware("http")
async def limit_body(request: Request, call_next):
    cl = request.headers.get("content-length")
    limit = MAX_RAW_BODY_BYTES if request.url.path.startswith(RAW_PATH_PREFIX) else MAX_BODY_BYTES
    if cl and cl.isdigit() and int(cl) > limit:
        return JSONResponse({"detail": "Request body too large."}, status_code=413)
    return await call_next(request)


class PredictRequest(BaseModel):
    # Flat feature vector built by the SAME pipeline used at training time.
    features: list[float] = Field(..., min_length=1, max_length=4096)
    top_k: int = Field(3, ge=1, le=10)


def _check_points(points, n: int, name: str):
    if points is None:
        return None
    if len(points) != n or any(len(p) < 3 for p in points):
        raise ValueError(f"{name} must be {n} landmarks of [x, y, z|visibility]")
    if not all(math.isfinite(v) for p in points for v in p[:3]):
        raise ValueError(f"{name} contains NaN or Infinity")
    return [list(p[:3]) for p in points]


class RawFrame(BaseModel):
    """One camera frame. Coordinates are MediaPipe-normalised (0..1) in the
    UNMIRRORED image (not the selfie preview). left_hand / right_hand are the
    SIGNER'S left / right hand (MediaPipe Holistic convention). null = not detected."""
    t: float = Field(..., description="capture time in seconds")
    pose: list[list[float]] | None = Field(None, description="33 x [x, y, visibility]")
    left_hand: list[list[float]] | None = Field(None, description="21 x [x, y, z]")
    right_hand: list[list[float]] | None = Field(None, description="21 x [x, y, z]")

    @field_validator("pose")
    @classmethod
    def _pose(cls, v):
        return _check_points(v, 33, "pose")

    @field_validator("left_hand", "right_hand")
    @classmethod
    def _hand(cls, v, info):
        return _check_points(v, 21, info.field_name)


class RawPredictRequest(BaseModel):
    image_width: int = Field(..., gt=0, le=10000)
    image_height: int = Field(..., gt=0, le=10000)
    frames: list[RawFrame] = Field(..., min_length=2, max_length=MAX_RAW_FRAMES)
    top_k: int = Field(3, ge=1, le=10)

    @model_validator(mode="after")
    def _timeline(self):
        ts = [f.t for f in self.frames]
        if not all(math.isfinite(t) for t in ts) or any(b < a for a, b in zip(ts, ts[1:])):
            raise ValueError("frame times must be finite and non-decreasing")
        if ts[-1] - ts[0] > MAX_RAW_DURATION_S:
            raise ValueError(f"capture longer than {MAX_RAW_DURATION_S:.0f} s")
        return self


class LetterStrokeRequest(BaseModel):
    """Dynamic letter J / Z. Send EITHER the stroke (frames + image size) OR
    the 24 jz-v2 features already computed on the phone.
    frames: the recorded stroke of the signing hand, 21 x [x, y, (z)]
    MediaPipe-normalised landmarks per frame; mirrored or unmirrored image."""
    frames: list[list[list[float]]] | None = Field(None, min_length=2, max_length=MAX_RAW_FRAMES)
    image_width: int | None = Field(None, gt=0, le=10000)
    image_height: int | None = Field(None, gt=0, le=10000)
    features: list[float] | None = Field(None, min_length=LETTER_FEATURE_DIM, max_length=LETTER_FEATURE_DIM)

    @model_validator(mode="after")
    def _one_input(self):
        if (self.frames is None) == (self.features is None):
            raise ValueError("send either 'frames' (+ image_width, image_height) or 'features', not both")
        if self.features is not None:
            if not all(math.isfinite(v) for v in self.features):
                raise ValueError("features contain NaN or Infinity")
            return self
        if self.image_width is None or self.image_height is None:
            raise ValueError("'frames' needs image_width and image_height (for the aspect ratio)")
        for i, fr in enumerate(self.frames):
            if len(fr) != 21 or any(len(p) < 2 for p in fr):
                raise ValueError(f"frame {i} must be 21 landmarks of [x, y, (z)]")
            if not all(math.isfinite(v) for p in fr for v in p[:2]):
                raise ValueError(f"frame {i} contains NaN or Infinity")
        return self


@app.get("/health")
def health(request: Request):
    return {"status": "ok", "models": list(request.app.state.registry.models),
            "raw_models": list(request.app.state.raw_models) + list(request.app.state.letter_models)}


@app.get("/v1/models")
def list_models(request: Request, user: dict = Depends(require_user)):
    return {"models": request.app.state.registry.describe(),
            "raw_models": [m.describe() for m in request.app.state.raw_models.values()]
            + [m.describe() for m in request.app.state.letter_models.values()]}


# Registered before /v1/predict_raw/{model_id} so these exact paths take precedence.
@app.post("/v1/predict_raw/letter_j")
def predict_letter_j(body: LetterStrokeRequest, request: Request, user: dict = Depends(require_user)):
    return _predict_letter("letter_j", body, request, user)


@app.post("/v1/predict_raw/letter_z")
def predict_letter_z(body: LetterStrokeRequest, request: Request, user: dict = Depends(require_user)):
    return _predict_letter("letter_z", body, request, user)


def _predict_letter(model_id: str, body: LetterStrokeRequest, request: Request, user: dict):
    model = request.app.state.letter_models[model_id]
    t0 = time.perf_counter()
    try:
        if body.features is not None:
            result = model.predict(features=body.features)
        else:
            result = model.predict(frames=[[p[:3] if len(p) >= 3 else p + [0.0] for p in fr] for fr in body.frames],
                                   aspect=body.image_width / body.image_height)
    except ValueError as e:
        raise HTTPException(422, str(e))
    except Exception:
        log.exception("letter inference failed")
        raise HTTPException(500, "Inference failed.")
    # Never log landmarks or features; decision summary only.
    log.info(json.dumps({
        "event": "predict_letter", "uid": user["uid"], "model": model_id, "accepted": result["accepted"],
        "confidence": result["confidence"], "input": result["input"],
        "total_ms": round((time.perf_counter() - t0) * 1000, 2),
    }))
    return result


@app.post("/v1/predict_raw/{model_id}")
def predict_raw(model_id: str, body: RawPredictRequest, request: Request, user: dict = Depends(require_user)):
    model = request.app.state.raw_models.get(model_id)
    if model is None:
        raise HTTPException(404, f"Unknown raw model '{model_id}'.")
    t0 = time.perf_counter()
    try:
        result = model.predict(
            [f.model_dump() for f in body.frames], body.image_width, body.image_height, top_k=body.top_k)
    except Exception:
        log.exception("raw inference failed")
        raise HTTPException(500, "Inference failed.")
    # Never log landmarks (biometric-ish user data); decision summary only.
    log.info(json.dumps({
        "event": "predict_raw", "uid": user["uid"], "model": model_id,
        "accepted": result["accepted"],
        "label_index": result["prediction"]["index"] if result["prediction"] else None,
        "rejection": result["rejection"]["code"] if result["rejection"] else None,
        "frames": result["capture"]["frames"],
        "total_ms": round((time.perf_counter() - t0) * 1000, 2),
    }))
    return result


@app.post("/v1/predict/{model_id}")
def predict(model_id: str, body: PredictRequest, request: Request, user: dict = Depends(require_user)):
    model = request.app.state.registry.get(model_id)
    if model is None:
        raise HTTPException(404, f"Unknown model '{model_id}'.")

    t0 = time.perf_counter()
    try:
        result = model.predict(body.features, top_k=body.top_k)
    except InputValidationError as e:
        raise HTTPException(422, str(e))
    except Exception:
        log.exception("inference failed")
        raise HTTPException(500, "Inference failed.")

    # Structured log for Cloud Logging. Never log the feature vector (it is biometric-ish user data).
    log.info(json.dumps({
        "event": "predict", "uid": user["uid"], "model": model_id,
        "label_index": result["prediction"]["index"],
        "confidence": result["prediction"]["confidence"],
        "total_ms": round((time.perf_counter() - t0) * 1000, 2),
    }))
    return result