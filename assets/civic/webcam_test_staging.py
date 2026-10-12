"""Webcam tester for the STAGED Lupang Hinirang model (via the local staging server).

    1. D:\\venv_lupang_export\\Scripts\\python.exe inference-service\\local_staging_server.py
    2. python webcam_test_staging.py [--camera 0] [--target 0]

The client does exactly what the mobile app does: MediaPipe Holistic (the
training settings, lupang_common.HOLISTIC_KWARGS) on the UNFLIPPED camera
frame, one frame dict per camera frame {t, pose 33x[x,y,visibility],
left_hand / right_hand 21x[x,y,z] or null}, then POST
/v1/predict_raw/lupang_hinirang. All cleaning, normalisation, resampling,
the ONNX model and every rejection gate run in the server, i.e. the code that
would serve this model in production. The display is mirrored; MediaPipe is not.

Before the first capture the client checks GET /local/staging_info: the
server must have loaded the staged checkpoint (--expect-checkpoint) and an
ONNX file that is NOT byte-identical to production. Every response's
model_version is checked again.

Keys
    SPACE        start recording / stop and predict (auto-stop after 12 s)
    A / D        previous / next target line   (or LEFT / RIGHT arrows)
    0            no target (free testing)
    R            reset the tally
    Q / ESC      quit
Every attempt is appended to reports/lupang_retrain/webcam_sessions/session_<time>.csv and its
landmark frames + target + full server response are saved to
reports/lupang_retrain/webcam_sessions/session_<time>/attempt_NNN.json (inspect them with
inspect_lupang_captures.py). The overlay shows live hand-detection rates while recording:
the reference videos have both hands detected in ~73 % of frames; far below that, the
capture itself (lighting / motion blur) is the problem, not the sign.

    python webcam_test_staging.py --video specialists\\civic_observances\\raw\\lupang_hinirang\\03_Alab_ng_puso\\SRC1_LUPANGHINIRANG_Alab_ng_puso_001.mp4
classifies a recorded clip through the same client -> server path (no window).
"""
import argparse
import csv
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import cv2
import numpy as np

import lupang_common as lc
from live_lupang_engine import open_camera

HERE = Path(__file__).resolve().parent
WINDOW = "Lupang Hinirang - STAGED model test"
FONT = cv2.FONT_HERSHEY_SIMPLEX
GREEN, RED, AMBER, CYAN = (0, 200, 0), (0, 0, 255), (0, 165, 255), (255, 255, 0)
WHITE, GREY, DIM = (255, 255, 255), (190, 190, 190), (120, 120, 120)
DURATION_CHECKS = ("Raw frames", "Duration", "Phrase duration")
KEY_LEFT, KEY_RIGHT = (2424832, 65361), (2555904, 65363)


# ---------------------------------------------------------------------------
# Server
# ---------------------------------------------------------------------------
class StagingClient:
    def __init__(self, url, expect_checkpoint):
        self.url = url.rstrip("/")
        self.expect = expect_checkpoint
        self.info = self._get("/local/staging_info")
        problems = []
        if self.info.get("loaded_source_checkpoint") != expect_checkpoint:
            problems.append(f"server loaded {self.info.get('loaded_source_checkpoint')!r}, expected {expect_checkpoint!r}")
        if self.info.get("is_production_model"):
            problems.append("the served ONNX is byte-identical to the production model")
        if problems:
            raise SystemExit("Not the staged model: " + "; ".join(problems))
        self.classes = self.info["class_names"]
        # Line slots merged into another line (model trained with lupang_common.RETIRED_CLASSES).
        self.retired = [i for i, c in enumerate(self.classes) if "(merged into" in c]

    def _get(self, path):
        try:
            with urllib.request.urlopen(self.url + path, timeout=10) as r:
                return json.loads(r.read())
        except urllib.error.HTTPError as e:
            raise SystemExit(f"{self.url}{path}: HTTP {e.code} - is this the LOCAL staging server "
                             f"(inference-service/local_staging_server.py)?")
        except OSError as e:
            raise SystemExit(f"Cannot reach {self.url} ({e}). Start the staging server first:\n"
                             f"  D:\\venv_lupang_export\\Scripts\\python.exe inference-service\\local_staging_server.py")

    def predict(self, frames, width, height):
        body = json.dumps({"image_width": width, "image_height": height, "frames": frames, "top_k": 3}).encode()
        req = urllib.request.Request(self.url + "/v1/predict_raw/lupang_hinirang", data=body,
                                     headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                res = json.loads(r.read())
        except urllib.error.HTTPError as e:
            return {"error": f"HTTP {e.code}: {e.read().decode(errors='replace')[:200]}"}
        if not res.get("model_version", "").endswith("/" + self.expect):
            raise SystemExit(f"Response came from model {res.get('model_version')!r}, not {self.expect!r}")
        return res


# ---------------------------------------------------------------------------
# Capture (same MediaPipe settings and frame handling as live_lupang_engine.py)
# ---------------------------------------------------------------------------
def frame_dict(results, t):
    """MediaPipe results -> one /v1/predict_raw frame (normalised image coords, unmirrored)."""
    def pts(lms, vis):
        if not lms:
            return None
        return [[round(p.x, 6), round(p.y, 6), round(p.visibility if vis else p.z, 6)] for p in lms.landmark]
    return {"t": round(t, 4), "pose": pts(results.pose_landmarks, True),
            "left_hand": pts(results.left_hand_landmarks, False),
            "right_hand": pts(results.right_hand_landmarks, False)}


def hand_quality(frames):
    """Share of frames with left / right / both / any hand detected (first..last hand frame)."""
    l = np.array([f["left_hand"] is not None for f in frames])
    r = np.array([f["right_hand"] is not None for f in frames])
    hit = np.flatnonzero(l | r)
    if len(hit) == 0:
        return {"left": 0.0, "right": 0.0, "both": 0.0, "any": 0.0}
    a, b = hit[0], hit[-1] + 1
    return {"left": float(l[a:b].mean()), "right": float(r[a:b].mean()),
            "both": float((l & r)[a:b].mean()), "any": float((l | r)[a:b].mean())}


def summarize(res, classes, target):
    """Server response -> what the UI / CSV show."""
    if "error" in res:
        return {"verdict": "ERROR", "text": res["error"], "color": RED, "outcome": "error", "top": [],
                "checks": [], "res": res}
    checks = {c["label"]: c for c in res["checks"]}
    top = res["top_k"]
    if res["accepted"]:
        p = res["prediction"]
        text, color = f"ACCEPTED: [{p['index'] + 1:02d}] {classes[p['index']]}  ({p['confidence']:.0%})", GREEN
        outcome = "accepted" if target is None else ("CORRECT" if p["index"] == target else "WRONG")
    else:
        code = res["rejection"]["code"]
        text, color = f"NO PREDICTION - {res['rejection']['message']} [{code}]", RED
        outcome = "no prediction"
    if outcome == "WRONG":
        color = AMBER
    return {"verdict": outcome, "text": text, "color": color, "outcome": outcome, "top": top,
            "checks": res["checks"], "checks_by_label": checks, "res": res}


# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------
def put(img, text, xy, scale=0.5, color=WHITE, thick=1):
    cv2.putText(img, text, xy, FONT, scale, color, thick, cv2.LINE_AA)


def display_frame(frame, min_width=1280):
    """Mirrored (display only) and enlarged so the text panel fits; capture is untouched."""
    disp = cv2.flip(frame, 1)
    if disp.shape[1] < min_width:
        f = min_width / disp.shape[1]
        disp = cv2.resize(disp, (min_width, int(round(disp.shape[0] * f))), interpolation=cv2.INTER_LINEAR)
    return disp


def draw(disp, st, client):
    h, w = disp.shape[:2]
    g = client.info["gate"]
    cv2.rectangle(disp, (0, 0), (w, 78), (20, 20, 20), -1)
    put(disp, f"STAGED {client.info['loaded_source_checkpoint']}  onnx {client.info['onnx_sha256'][:10]}  "
              f"gate conf>={g['min_conf']:.2f} margin>={g['min_margin']:.2f}", (10, 18), 0.45, CYAN)
    tgt = "free test (no target)" if st["target"] is None else \
        f"target [{st['target'] + 1:02d}] {client.classes[st['target']]}"
    if st["recording"]:
        hq = hand_quality(st["frames"]) if st["frames"] else None
        if hq:
            put(disp, f"hands detected: L {hq['left']:.0%}  R {hq['right']:.0%}  both {hq['both']:.0%} "
                      f"(reference videos: both ~73%)", (10, 96), 0.5,
                GREEN if hq["both"] >= 0.5 else (AMBER if hq["both"] >= 0.25 else RED))
        cv2.circle(disp, (18, 38), 7, RED, -1)
        put(disp, f"REC {len(st['frames'])} frames {time.perf_counter() - st['t0']:.1f}s | {tgt} | SPACE stop",
            (32, 43), 0.5, RED)
    else:
        put(disp, f"{tgt} | SPACE record  A/D target  0 none  R reset  Q quit", (10, 43), 0.5, WHITE)
    tally = st["tally"]
    put(disp, f"tally: correct {tally['CORRECT']}  wrong {tally['WRONG']}  no prediction {tally['no prediction']}"
              f"  (free-test accepted {tally['accepted']})", (10, 70), 0.45, GREY)

    s = st["summary"]
    if s is None:
        return
    rows = s["checks"]
    panel_h = 170 + 16 * len(rows)
    y0 = max(84, h - panel_h)
    over = disp.copy()
    cv2.rectangle(over, (0, y0), (w, h), (15, 15, 15), -1)
    cv2.addWeighted(over, 0.85, disp, 0.15, 0, disp)
    put(disp, s["text"][:80], (10, y0 + 26), 0.62, s["color"], 2)
    if s["outcome"] in ("CORRECT", "WRONG"):
        put(disp, s["outcome"] + ("" if s["outcome"] == "CORRECT" else
                                  f" (expected [{st['last_target'] + 1:02d}] {client.classes[st['last_target']]})"),
            (10, y0 + 50), 0.55, s["color"], 2)
    hq = st.get("last_quality")
    if hq and hq["both"] < 0.4:
        put(disp, f"capture quality: both hands in {hq['both']:.0%} of frames (reference ~73%) - "
                  f"more light / slower movement", (int(w * 0.46), y0 + 50), 0.45, AMBER)
    if s["outcome"] == "no prediction" and st["last_target"] is not None:
        put(disp, f"rejected (target was [{st['last_target'] + 1:02d}] {client.classes[st['last_target']]})",
            (10, y0 + 50), 0.5, GREY)

    # Confidence / margin / duration summary.
    top = s["top"]
    cb = s.get("checks_by_label", {})
    y = y0 + 76
    if len(top) >= 2:
        p1, p2 = top[0]["confidence"], top[1]["confidence"]
        put(disp, f"confidence {p1:.3f} (need >= {g['min_conf']:.2f})", (10, y), 0.48,
            GREEN if p1 >= g["min_conf"] else AMBER)
        put(disp, f"margin top1-top2 {p1 - p2:.3f} (need >= {g['min_margin']:.2f})", (10, y + 18), 0.48,
            GREEN if p1 - p2 >= g["min_margin"] else AMBER)
        y += 18
        hdr = "model scores" + ("" if s["outcome"] in ("accepted", "CORRECT", "WRONG") else
                                " (NOT a prediction - rejected)")
        put(disp, hdr, (10, y + 20), 0.42, DIM)
        for r, e in enumerate(top):
            put(disp, f"{r + 1}. [{e['index'] + 1:02d}] {client.classes[e['index']][:30]:<30} {e['confidence'] * 100:5.1f}%",
                (10, y + 38 + r * 17), 0.45, WHITE)
    else:
        put(disp, "classifier not run (a pre-check failed) - no scores", (10, y), 0.48, DIM)
    dur = [cb[k] for k in DURATION_CHECKS if k in cb]
    dur_ok = all(c["passed"] for c in dur) if dur else None
    cap = s["res"].get("capture", {})
    put(disp, f"duration gate: {'PASS' if dur_ok else ('FAIL' if dur_ok is False else 'n/a')}   active "
              f"{cap.get('active_duration_s', 0):.2f}s / {cap.get('active_frames', 0)} frames @ {cap.get('fps', 0):.0f} fps",
        (10, y + 96), 0.48, GREEN if dur_ok else RED)

    # Every gate check, as the server evaluated it.
    x = int(w * 0.46)
    for r, c in enumerate(rows):
        yy = y0 + 76 + r * 16
        if yy > h - 4:
            break
        put(disp, ("OK  " if c["passed"] else "FAIL") + f" {c['label']}: {c['text']}"[:80], (x, yy), 0.4,
            GREEN if c["passed"] else AMBER)


# ---------------------------------------------------------------------------
# Session log
# ---------------------------------------------------------------------------
class SessionLog:
    FIELDS = ["time", "target_index", "target_line", "outcome", "accepted", "pred_index", "pred_line",
              "top1_index", "top1_conf", "top2_index", "top2_conf", "margin", "rejection_code",
              "failed_checks", "active_duration_s", "active_frames", "fps", "frames_sent", "model_version",
              "hands_left", "hands_right", "hands_both", "hands_any", "capture_file"]

    def __init__(self, classes):
        d = HERE / "reports" / "lupang_retrain" / "webcam_sessions"
        d.mkdir(parents=True, exist_ok=True)
        stamp = time.strftime('%Y%m%d_%H%M%S')
        self.path = d / f"session_{stamp}.csv"
        self.capture_dir = d / f"session_{stamp}"
        self.capture_dir.mkdir(exist_ok=True)
        self.n = 0
        self.classes = classes
        with open(self.path, "w", newline="", encoding="utf-8") as f:
            csv.writer(f).writerow(self.FIELDS)

    def add(self, target, s, frames, width, height):
        res, top = s["res"], s["top"]
        n_frames = len(frames)
        hq = hand_quality(frames)
        self.n += 1
        cap_file = self.capture_dir / f"attempt_{self.n:03d}.json"
        cap_file.write_text(json.dumps({
            "target_index": target, "target_line": None if target is None else self.classes[target],
            "image_width": width, "image_height": height, "frames": frames, "hand_quality": hq,
            "response": res}), encoding="utf-8")
        cap = res.get("capture", {})
        row = [time.strftime("%H:%M:%S"), "" if target is None else target,
               "" if target is None else self.classes[target], s["outcome"], res.get("accepted"),
               res["prediction"]["index"] if res.get("prediction") else "",
               self.classes[res["prediction"]["index"]] if res.get("prediction") else "",
               top[0]["index"] if top else "", top[0]["confidence"] if top else "",
               top[1]["index"] if len(top) > 1 else "", top[1]["confidence"] if len(top) > 1 else "",
               round(top[0]["confidence"] - top[1]["confidence"], 6) if len(top) > 1 else "",
               (res.get("rejection") or {}).get("code", ""), "|".join(res.get("failed_checks", [])),
               cap.get("active_duration_s", ""), cap.get("active_frames", ""), cap.get("fps", ""), n_frames,
               res.get("model_version", ""), round(hq["left"], 3), round(hq["right"], 3), round(hq["both"], 3),
               round(hq["any"], 3), cap_file.name]
        with open(self.path, "a", newline="", encoding="utf-8") as f:
            csv.writer(f).writerow(row)


def print_attempt(i, s, classes, target):
    print(f"\n--- attempt {i} | target: {'none' if target is None else classes[target]} ---")
    print("  " + s["text"] + ("" if s["outcome"] in ("accepted", "no prediction", "error") else f"  -> {s['outcome']}"))
    for e in s["top"]:
        print(f"  [{e['index'] + 1:02d}] {classes[e['index']]:<40} {e['confidence']:.3f}")
    for c in s["checks"]:
        print(f"  [{'OK  ' if c['passed'] else 'FAIL'}] {c['label']:<15} {c['text']}")


# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------
def run_video(client, path, target):
    """A recorded clip through the same client -> server path (decoder timestamps)."""
    import mediapipe as mp
    cap = cv2.VideoCapture(str(path))
    if not cap.isOpened():
        raise SystemExit(f"cannot open {path}")
    w, h = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    frames, t0 = [], None
    with mp.solutions.holistic.Holistic(**lc.HOLISTIC_KWARGS) as holistic:
        while True:
            ok, frame = cap.read()
            if not ok:
                break
            t = cap.get(cv2.CAP_PROP_POS_MSEC) / 1000.0
            t0 = t if t0 is None else t0
            rgb, _ = lc.prepare_frame(frame)
            frames.append(frame_dict(holistic.process(rgb), t - t0))
    cap.release()
    s = summarize(client.predict(frames, w, h), client.classes, target)
    print_attempt(1, s, client.classes, target)
    return s


def run_live(client, args):
    import mediapipe as mp
    mp_h = mp.solutions.holistic
    drawing, styles = mp.solutions.drawing_utils, mp.solutions.drawing_styles
    if args.backend == "msmf":                     # optional: some drivers give dark DSHOW frames
        cap = cv2.VideoCapture(args.camera, cv2.CAP_MSMF)
        if not cap.isOpened():
            raise SystemExit(f"Cannot open camera {args.camera} with MSMF")
    else:
        cap = open_camera(args.camera)            # default, unchanged: DSHOW, then any backend
    holistic = mp_h.Holistic(**lc.HOLISTIC_KWARGS)
    log = SessionLog(client.classes)
    st = {"recording": False, "frames": [], "t0": 0.0, "summary": None, "target": args.target,
          "last_target": None, "tally": {"CORRECT": 0, "WRONG": 0, "no prediction": 0, "accepted": 0, "error": 0}}
    attempt = 0
    print(f"Session log: {log.path}")
    try:
        while True:
            ok, frame = cap.read()
            if not ok:
                print("Camera frame grab failed; exiting.")
                break
            h, w = frame.shape[:2]
            rgb, _ = lc.prepare_frame(frame)              # unflipped, as in training and the app
            results = holistic.process(rgb)
            now = time.perf_counter()
            stop = False
            if st["recording"]:
                st["frames"].append(frame_dict(results, now - st["t0"]))
                stop = now - st["t0"] > args.max_seconds
            for lms, conn in ((results.pose_landmarks, mp_h.POSE_CONNECTIONS),
                              (results.left_hand_landmarks, mp_h.HAND_CONNECTIONS),
                              (results.right_hand_landmarks, mp_h.HAND_CONNECTIONS)):
                if lms:
                    drawing.draw_landmarks(frame, lms, conn)
            disp = display_frame(frame)
            draw(disp, st, client)
            cv2.imshow(WINDOW, disp)
            key = cv2.waitKeyEx(1)
            k8 = key & 0xFF if key != -1 else -1
            if k8 in (ord("q"), ord("Q"), 27) or cv2.getWindowProperty(WINDOW, cv2.WND_PROP_VISIBLE) < 1:
                break
            if not st["recording"]:
                n = len(client.classes) - 1               # 22 line slots (INVALID_GESTURE is not a target)
                retired = set(client.retired)             # merged-away line slots are never a target
                if key in KEY_LEFT or k8 in (ord("a"), ord("A")):
                    st["target"] = n - 1 if st["target"] is None else (st["target"] - 1) % n
                    while st["target"] in retired:
                        st["target"] = (st["target"] - 1) % n
                elif key in KEY_RIGHT or k8 in (ord("d"), ord("D")):
                    st["target"] = 0 if st["target"] is None else (st["target"] + 1) % n
                    while st["target"] in retired:
                        st["target"] = (st["target"] + 1) % n
                elif k8 == ord("0"):
                    st["target"] = None
                elif k8 in (ord("r"), ord("R")):
                    st["tally"] = {k: 0 for k in st["tally"]}
            if k8 == ord(" ") and not st["recording"]:
                st.update(recording=True, frames=[], t0=time.perf_counter(), summary=None)
            elif (k8 == ord(" ") or stop) and st["recording"]:
                st["recording"] = False
                attempt += 1
                if len(st["frames"]) < 2:
                    continue
                put(disp, "classifying...", (10, 100), 0.7, CYAN, 2)
                cv2.imshow(WINDOW, disp)
                cv2.waitKey(1)
                s = summarize(client.predict(st["frames"], w, h), client.classes, st["target"])
                st["summary"], st["last_target"] = s, st["target"]
                st["last_quality"] = hand_quality(st["frames"])
                key_t = s["outcome"] if s["outcome"] in st["tally"] else "error"
                st["tally"][key_t] += 1
                print_attempt(attempt, s, client.classes, st["target"])
                print("  hands detected: " + ", ".join(f"{k} {v:.0%}" for k, v in st["last_quality"].items()))
                if "error" not in s["res"]:
                    log.add(st["target"], s, st["frames"], w, h)
    finally:
        cap.release()
        holistic.close()
        cv2.destroyAllWindows()
        print(f"\nSession log: {log.path}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--server", default="http://127.0.0.1:8765")
    ap.add_argument("--expect-checkpoint", default="palm_lupang_v9_switch",
                    help="source checkpoint the staged model must report")
    ap.add_argument("--camera", type=int, default=0)
    ap.add_argument("--backend", choices=["dshow", "msmf"], default="dshow",
                    help="Windows capture method (default dshow, as before); see check_cameras.py")
    ap.add_argument("--target", type=int, help="initial target line, 1-22 (default: none)")
    ap.add_argument("--max-seconds", type=float, default=12.0)
    ap.add_argument("--video", help="classify a recorded clip instead of the webcam (no window)")
    ap.add_argument("--check", action="store_true", help="only verify the server serves the staged model")
    args = ap.parse_args()
    if args.target is not None:
        if not 1 <= args.target <= 22:
            raise SystemExit("--target must be 1-22")
        args.target -= 1
    client = StagingClient(args.server, args.expect_checkpoint)
    if args.target is not None and args.target in client.retired:
        print(f"--target {args.target + 1} is merged into line {lc.MERGED_LINE + 1} "
              f"({client.classes[lc.MERGED_LINE]}); using that line")
        args.target = lc.MERGED_LINE
    i = client.info
    print(f"Server model: {i['loaded_source_checkpoint']} from {i['onnx_file']}")
    print(f"  onnx sha256 {i['onnx_sha256']} (production {i['production_onnx_sha256']})")
    floors = [d for k, d in enumerate(i['gate']['class_min_duration'][:22]) if k not in client.retired]
    print(f"  gate min_conf {i['loaded_gate_min_conf']}, min_margin {i['loaded_gate_min_margin']}, "
          f"per-line min duration {min(floors):.2f}-{max(floors):.2f}s")
    if args.check:
        return 0
    if args.video:
        run_video(client, args.video, args.target)
        return 0
    run_live(client, args)
    return 0


if __name__ == "__main__":
    sys.exit(main())
