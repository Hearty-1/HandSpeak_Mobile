import cv2
import torch
import torch.nn as nn
import numpy as np
from scipy.interpolate import interp1d
import mediapipe as mp

GREETINGS_MAP = {
    0: "GOOD MORNING",
    1: "GOOD AFTERNOON",
    2: "GOOD EVENING",
    3: "HELLO",
    4: "HOW ARE YOU",
    5: "IM FINE",
    6: "NICE TO MEET YOU",
    7: "THANK YOU",
    8: "[DISABLED] YOURE WELCOME",
    9: "SEE YOU TOMORROW",
    10: "INVALID_GESTURE"
}

class FullSequenceConvBiLSTM(nn.Module):
    def __init__(self, in_features=96, num_classes=11):
        super().__init__()
        self.conv = nn.Sequential(
            nn.Conv1d(in_channels=in_features, out_channels=128, kernel_size=3, padding=1),
            nn.BatchNorm1d(128),
            nn.ReLU(),
            nn.Dropout(0.25)
        )
        self.lstm = nn.LSTM(
            input_size=128, 
            hidden_size=128, 
            num_layers=2, 
            batch_first=True, 
            bidirectional=True, 
            dropout=0.3
        )
        self.classifier = nn.Sequential(
            nn.Linear(128 * 4, 128),
            nn.BatchNorm1d(128),
            nn.ReLU(),
            nn.Dropout(0.35),
            nn.Linear(128, num_classes)
        )

    def forward(self, x):
        x = x.permute(0, 2, 1)
        x = self.conv(x)
        x = x.permute(0, 2, 1)
        out, _ = self.lstm(x)
        mean_pool = torch.mean(out, dim=1)
        max_pool, _ = torch.max(out, dim=1)
        feat = torch.cat((mean_pool, max_pool), dim=1)
        return self.classifier(feat), feat

DEVICE = torch.device('cuda' if torch.cuda.is_available() else 'cpu')
model = FullSequenceConvBiLSTM(in_features=96, num_classes=11).to(DEVICE)
model.load_state_dict(torch.load("palm_robust_11class.pt", map_location=DEVICE))
model.eval()

mp_holistic = mp.solutions.holistic
mp_drawing = mp.solutions.drawing_utils
mp_drawing_styles = mp.solutions.drawing_styles
holistic = mp_holistic.Holistic(
    min_detection_confidence=0.5, 
    min_tracking_confidence=0.5
)

def extract_palm_relative(results):
    pose_pts = []
    if results.pose_landmarks:
        lm = results.pose_landmarks.landmark
        mid_sh = np.array([(lm[11].x + lm[12].x)/2.0, (lm[11].y + lm[12].y)/2.0], dtype=np.float32)
        sh_dist = float(np.linalg.norm(np.array([lm[11].x, lm[11].y]) - np.array([lm[12].x, lm[12].y]))) + 1e-6
        for idx in [11, 12, 13, 14, 15, 16]:
            pt = np.array([lm[idx].x, lm[idx].y], dtype=np.float32)
            norm = (pt - mid_sh) / sh_dist
            pose_pts.extend([float(norm[0]), float(norm[1])])
    else:
        pose_pts = [0.0] * 12

    lh_pts = []
    if results.left_hand_landmarks:
        lm = results.left_hand_landmarks.landmark
        wrist = np.array([lm[0].x, lm[0].y], dtype=np.float32)
        mid_mcp = np.array([lm[9].x, lm[9].y], dtype=np.float32)
        palm_size = float(np.linalg.norm(wrist - mid_mcp)) + 1e-6
        for p in lm:
            pt = np.array([p.x, p.y], dtype=np.float32)
            norm = (pt - wrist) / palm_size
            lh_pts.extend([float(norm[0]), float(norm[1])])
    else:
        lh_pts = [0.0] * 42

    rh_pts = []
    if results.right_hand_landmarks:
        lm = results.right_hand_landmarks.landmark
        wrist = np.array([lm[0].x, lm[0].y], dtype=np.float32)
        mid_mcp = np.array([lm[9].x, lm[9].y], dtype=np.float32)
        palm_size = float(np.linalg.norm(wrist - mid_mcp)) + 1e-6
        for p in lm:
            pt = np.array([p.x, p.y], dtype=np.float32)
            norm = (pt - wrist) / palm_size
            rh_pts.extend([float(norm[0]), float(norm[1])])
    else:
        rh_pts = [0.0] * 42

    vec = np.array(pose_pts + lh_pts + rh_pts, dtype=np.float32)
    return vec if vec.shape == (96,) else np.zeros(96, dtype=np.float32)

cap = cv2.VideoCapture(0, cv2.CAP_DSHOW)
recording = False
buffer = []

main_text = "IDLE: Pindutin ang SPACEBAR bago sumenyas"
sub_metric = ""
display_color = (200, 200, 200)
attempt = 1

print("\n=== SYSTEM ONLINE (ORIGINAL SETUP: CLASS 8 DISABLED) ===")
print("Pindutin ang SPACEBAR para mag-record at tapusin.")
print("Pindutin ang 'Q' para lumabas.\n")

while cap.isOpened():
    ret, frame = cap.read()
    if not ret: 
        break

    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = holistic.process(rgb)
    feat = extract_palm_relative(results)

    # UPPER BODY / POSE SKELETON
    if results.pose_landmarks:
        mp_drawing.draw_landmarks(
            frame, 
            results.pose_landmarks, 
            mp_holistic.POSE_CONNECTIONS,
            landmark_drawing_spec=mp_drawing_styles.get_default_pose_landmarks_style()
        )
    # LEFT HAND
    if results.left_hand_landmarks:
        mp_drawing.draw_landmarks(
            frame, 
            results.left_hand_landmarks, 
            mp_holistic.HAND_CONNECTIONS,
            mp_drawing_styles.get_default_hand_landmarks_style(),
            mp_drawing_styles.get_default_hand_connections_style()
        )
    # RIGHT HAND
    if results.right_hand_landmarks:
        mp_drawing.draw_landmarks(
            frame, 
            results.right_hand_landmarks, 
            mp_holistic.HAND_CONNECTIONS,
            mp_drawing_styles.get_default_hand_landmarks_style(),
            mp_drawing_styles.get_default_hand_connections_style()
        )

    if recording:
        buffer.append(feat)

    disp = cv2.flip(frame, 1)
    h, w, _ = disp.shape

    # UI Banner
    cv2.rectangle(disp, (0, 0), (w, 115), (20, 20, 20), -1)
    status_header = f"NAGTATALA ({len(buffer)} frames)... [SPACEBAR] para tapusin" if recording else "IDLE: Pindutin ang SPACEBAR para magsimula"
    s_col = (0, 0, 255) if recording else (0, 255, 255)
    cv2.putText(disp, status_header, (20, 26), cv2.FONT_HERSHEY_SIMPLEX, 0.52, s_col, 2)
    cv2.putText(disp, main_text, (20, 64), cv2.FONT_HERSHEY_SIMPLEX, 0.75, display_color, 2)
    
    if sub_metric:
        cv2.putText(disp, sub_metric, (20, 95), cv2.FONT_HERSHEY_SIMPLEX, 0.46, (200, 200, 200), 1)

    cv2.imshow("FSL Recognition Engine", disp)
    key = cv2.waitKey(1) & 0xFF

    if key == ord(' '):
        if not recording:
            recording = True
            buffer = []
            main_text = "Sumesenyas..."
            sub_metric = ""
            display_color = (0, 255, 255)
        else:
            recording = False
            raw_seq = np.array(buffer, dtype=np.float32)

            if len(raw_seq) < 14:
                main_text = "No confident prediction"
                sub_metric = "Masyadong mabilis ang kumpas (<14 frames)"
                display_color = (0, 0, 255)
            else:
                f_interp = interp1d(np.linspace(0, 1, len(raw_seq)), raw_seq, axis=0, kind='linear')
                seq32 = f_interp(np.linspace(0, 1, 32)).astype(np.float32)

                t_input = torch.tensor(seq32, dtype=torch.float32).unsqueeze(0).to(DEVICE)
                with torch.no_grad():
                    logits, _ = model(t_input)
                    
                    # HARD MASK CLASS 8 (YOU'RE WELCOME)
                    logits[:, 8] = -1e9
                    
                    probs = torch.softmax(logits, dim=-1).squeeze(0).cpu().numpy()

                ranked = np.argsort(probs)[::-1]
                top1_idx = int(ranked[0])
                top2_idx = int(ranked[1])
                top1_prob = probs[top1_idx] * 100.0
                margin = (probs[top1_idx] - probs[top2_idx]) * 100.0

                print(f"\n--- PAGSUBOK #{attempt} (Frames: {len(raw_seq)}) ---")
                for r in range(4):
                    c = int(ranked[r])
                    print(f"Top {r+1}: {GREETINGS_MAP[c]:<25} ({probs[c]*100:6.2f}%)")

                if top1_idx == 10:
                    main_text = "No confident prediction"
                    sub_metric = f"Tinanggihan: INVALID_GESTURE ({top1_prob:.1f}%)"
                    display_color = (0, 0, 255)
                elif top1_prob < 55.0 or margin < 12.0:
                    main_text = "No confident prediction"
                    sub_metric = f"Alanganin: {GREETINGS_MAP[top1_idx]} ({top1_prob:.1f}%) | Margin: {margin:.1f}%"
                    display_color = (0, 0, 255)
                else:
                    main_text = f"PREDICTION: {GREETINGS_MAP[top1_idx]}"
                    sub_metric = f"Confidence: {top1_prob:.1f}% | Margin: {margin:.1f}%"
                    display_color = (0, 255, 0)

                attempt += 1

    elif key == ord('q'):
        break

cap.release()
cv2.destroyAllWindows()
holistic.close()
