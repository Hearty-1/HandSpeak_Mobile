# HandSpeak: Sign Recognition and Reward System

How the app checks a student's signs, and how it rewards learning. Every
number below is the value used in the app's code (file names in brackets).

---

## Part 1. Sign recognition

### 1.1 The big picture

Every camera check follows the same four steps:

1. **See the hand.** The front camera sends frames to Google MediaPipe Hand
   Landmarker, which finds **21 points (landmarks)** on each hand: the wrist,
   and 4 joints on each finger. Each point has `x`, `y` (position in the
   picture, 0 to 1) and `z` (depth).
2. **Make the hand comparable.** The points are rotated upright, mirrored
   like a selfie, and measured relative to the student's own hand size, so
   distance from the camera and hand size do not matter.
3. **Compare with the correct sign.** Still signs are compared with a stored
   example of the sign (a *template*). Moving signs are recorded and sent to
   a trained model.
4. **Decide and give feedback.** Pass or fail, plus a hint ("That looked like
   B", "Move a little more", ...).

Signs are split into two kinds:

| Kind | Signs | How the student answers |
|---|---|---|
| **Static** (still handshape) | Letters A-Y (except J and Z), numbers 1-10 | Hold the sign, tap **CAPTURE & CHECK** |
| **Dynamic** (with movement) | Letters J and Z, numbers 11-100, Greetings, Civic (Lupang Hinirang), categories added on the web | Tap **RECORD SIGN**, sign during the recording, the clip is checked |

---

### 1.2 Static signs (A-Y without J/Z, numbers 1-10)

A static sign passes only if it clears **three checks in a row**:
template match, then look-alike rules, then the server model.

#### Step 1: Template match score (0-100)

`[challenge_camera_sign.dart, easyAct_mc.dart, easyNumAct_mc.dart]`

The template is the 21 points of a correct sign, stored in Firebase Storage
(`models/alphabet/<letter>.json`, `models/numbers/<n>.json`).

**1. Hand size (scale).** Distance from the wrist (point 0) to the middle
finger's knuckle (point 9):

```
d = √[(x₉ − x₀)² + (y₉ − y₀)² + (z₉ − z₀)²]
```

**2. Normalise every point** relative to the wrist and hand size:

```
dxᵢ = (xᵢ − x₀) / d      dyᵢ = (yᵢ − y₀) / d      dzᵢ = (zᵢ − z₀) / d
```

**3. Try 8 orientations.** The hand may be turned or mirrored, so the points
are compared in 8 versions (4 rotations of 90°, each with and without a
mirror), using a 2×2 rotation matrix [a b; c e] and a mirror sign m = ±1:

```
rxᵢ = (dxᵢ · m) · a + dyᵢ · b
ryᵢ = (dxᵢ · m) · c + dyᵢ · e
```

**4. Average distance to the template** (tx, ty, tz) over the 21 points:

```
D = (1/21) · Σᵢ √[(rxᵢ − txᵢ)² + (ryᵢ − tyᵢ)² + (dzᵢ − tzᵢ)²]
```

**5. Score:**

```
Score = clamp( 100 − 80 · D , 0, 100 )        best of the 8 orientations
```

**Tricky letters G, H, K, P, Q** (pointing sideways or down) use a gentler
2D version:
- Hand size is the larger of *(wrist to middle knuckle)* and *0.55 × (wrist to
  index tip)*, at least 0.05.
- The thumb tip, index tip and middle tip (points 4, 8, 12) count **1.5×**.
- The score is `clamp(100 − 45 · D_weighted, 0, 100)`.

**6. Live score.** The best score over the last **1.5 seconds** is shown
("Match 82%"). This lets the student lower the hand to tap the button without
losing the score.

#### Step 2: Look-alike rules  `[dynamic_sign_judge.dart → StaticLetterChecker]`

Some letters share almost the same template (B/C, E/F, M/N, S/A, T/X, U/V/R,
K/peace sign). Extra rules check finger states and positions:

- **Finger states.** Each finger must be straight, bent or curved as the
  letter requires (e.g. B: four straight fingers; C: four curved).
- **Measurements.** These include:
  - the angle between index and middle (U ≈ 0-8°, V > 20°);
  - whether index and middle cross (R);
  - fingertip reach (flat B ≈ 1.9 vs curved C ≈ 1.5 palm lengths);
  - how high the index middle joint rises (X ≥ 0.4, T ≈ 0.1).
- **Rival templates.** For M, N, S, T the hand must match its own template
  better than its look-alikes', by a margin of at least 0.5 points (larger
  for hard pairs such as T vs X).
- The rule passes when **most of the last 5 frames** are right, so one noisy
  frame does not fail a good sign.

If a rule fails, the score is capped at **65%** (threshold − 5) and the hint
says what to fix.

#### Step 3: Server confirmation  `[StaticServerCheck]`

When the student taps CAPTURE & CHECK with a score of **70% or more**, the
last **10 frames** are sent to the server's static model
(`/v1/predict_raw/static_letters` or `static_numbers`). The server answers
with its best label and confidence.

```
PASS when:   top label = target
         or  the target is in the server's top answers
             and the server is NOT confident (≥ 0.7) about a different sign
         or  the pair is one the phone's rules already separate
             (e.g. K read as U, R/U, U/V, T/X)
FAIL when:   the server is confident (≥ 0.7) it is a different sign
             ("This looks like Letter B")
```

The server acts as a **veto**: the phone's checks already passed, and the
server stops confident mistakes.

#### Static decision summary

```
PASS  ⇔  live score ≥ 70
       ∧ look-alike rules pass
       ∧ server does not confidently see another sign
```

---

### 1.3 Dynamic signs

#### Recording (all moving signs)  `[sign_recording.dart]`

1. **RECORD SIGN.** A **3-2-1** countdown in activities and practice. There
   is **no countdown in challenges**, because the clock is running.
2. The camera records for about **3 seconds** (letters and numbers), or until
   the hands are lowered (other categories, at most 6 s).
3. Only the frames of the recording are judged, so nothing before the tap
   counts.

#### Letters J and Z  `[dynamic_sign_judge.dart → judgeLetter]`

| Step | What happens |
|---|---|
| 1 | At least **8 frames** with a hand are needed, otherwise "Do the whole movement" |
| 2 | **On the phone:** the stroke (the path of the fingertip) is checked by `fsl_letter_j.onnx` / `fsl_letter_z.onnx`. J: pinky up, down, then curve. Z: right, diagonally down, right |
| 3 | **On the server:** `/v1/predict_raw/letter_j` or `letter_z` decides (`accepted`) |

```
Score = clamp(100 × confidence, 75, 99)   if accepted
Score = 60 × confidence                    if not accepted
PASS  ⇔  phone stroke check passes ∧ server accepts
```

Without an internet connection the sign cannot pass ("Could not reach the
server").

#### Numbers 11-100  `[judgeNumber]`

| Step | What happens |
|---|---|
| 1 | At least **12 frames**, otherwise "Too fast. Hold the first shape, move, then hold the last shape" |
| 2 | The recording is resampled to **24 frames** and sent to `/v1/predict_raw/numbers`, which uses the model for that number's group (11-20, 20-30, …, 91-100) |
| 3 | If the server says it is correct, the app still checks the **start and end handshapes** (BaseShapeVerifier). A wrong first shape fails with a score of 45 |

```
PASS  ⇔  server isCorrect ∧ start / end handshape correct
Score = server accuracyScore
```

The server also returns the number it saw, for hints like "That looked like
Number 34", and a still hand is told "Do the movement".

#### Greetings, Civic and categories added on the web

These use **full-body tracking** (pose + both hands) and models trained on
the web:
- Greetings: `/v1/predict/greetings`
- Civic: `/v1/predict_raw/lupang_hinirang`
- Web categories: `/v1/predict_raw/<modelId>` from `published_gesture_models`

`[custom_category_screen.dart → CloudModelPractice._assess]`

**1. Clip check.** The recording is cut to the same shape as the training
clips (sign length plus 400 ms margin). It must pass the training limits:
- signing time ≥ 0.75 s;
- body seen in ≥ 80% of frames;
- hands seen in ≥ 30% of frames;
- hand cut off in ≤ 50% of frames.

**2. Model answer.** The model gives a probability for each sign, plus "Not
recognised" (the *invalid* class).

**3. Pass rule.** The values come from the web settings (per model or per
sign):

```
invalid       = probability of "Not recognised"
share(sign)   = P(sign) / (1 − invalid)        the sign's share among real signs
lead          = share(best) − share(second best)

PASS ⇔ best sign = target sign  AND  (
         ( server accepted the clip  ∧  P(best) ≥ minConfidence )
      OR ( invalid ≤ maxInvalid  ∧  share(best) ≥ minSignShare  ∧  lead ≥ minSignLead ) )
```

Default values: minConfidence 0.70, minSignShare 0.20, minSignLead 0.10,
maxInvalid 0.75. Faculty tune them per sign on the web; for example, Colors
uses minConfidence 0.65, maxInvalid 0.40 and minSignShare 1.01, which turns
the share rule off.

**4. Feedback:**
- best = target but not enough → "Almost! Make it clearer";
- another sign leads → "That looked like Red";
- the clip was rejected → "Move a little more" / "Show your hands".

---

### 1.4 What is saved from every attempt (analytics)

| Where | What |
|---|---|
| `gesture_attempts` (Hard activities) | Per attempt: sign, predicted sign, score, pass mark, correct / wrong, mistake type, hands seen, model, time |
| `practice_sessions` (continuous practice) | One document per run, described below |
| `activity_sessions` | One document per activity play, with every answer |
| `solo_challenges`, `group_challenges` | One document per game, with every answer |

**Mistake types** (used in every report):

| Type | When |
|---|---|
| `noHands` | No hand was seen |
| `wrongSign` | The model recognised a different sign |
| `nearMiss` | Score ≥ pass mark − 20 (e.g. 50-69) |
| `lowScore` | Anything else |

**Practice session numbers**  `[tutorial_session_recorder.dart]`:

```
accuracyPercent = correct / attempts × 100
averageScore    = Σ scores / attempts
scoreBuckets    : low < 50 · borderline 50-69 · good 70-84 · strong ≥ 85
needsAttention  = attempts > 0 ∧ ( accuracy < 70  ∨  any sign's accuracy < 70 )
expireAt        = endedAt + 90 days   (deleted automatically by Firestore TTL)
```

---

## Part 2. Reward system

### 2.1 Overview

| Reward | What it measures | Where it shows |
|---|---|---|
| **XP** (experience points) | Effort and progress: every new thing learned | Home, Profile, leaderboards, module cards |
| **Stars** (★) | Quality of an activity level (0-3) | Level map, module cards, Profile |
| **Hearts** (♥) | Mistakes allowed in one activity play | During activities |
| **Streak** (🔥) | Days in a row with learning | Home, Profile |
| **Daily quests** | Personal goals for today | Daily Challenges |
| **Badges** | Long-term achievements | Profile → Achievements |

**Design basis.** These follow common practice in learning apps such as
Duolingo:
- **Fixed XP per action.** The same in every category, so adding content never
  changes the value of a lesson.
- **Full XP only the first time.** Students cannot farm XP by repeating easy
  items.
- **Small capped XP for repeats.** Reviewing is still worth something.
- **Stars and hearts reward accuracy,** not just finishing.
- **Personal quests and streaks** build a daily habit.

---

### 2.2 XP rules  `[xp_rewards.dart, progress_service.dart]`

| Action | XP | Rule |
|---|---|---|
| Tutorial sign, **first time mastered** | **20** | Once per sign |
| Practice sign, **first time correct** | **10** | Once per sign (practice is separate from the tutorial) |
| Activity level, **each NEW star** | **10** | Max 30 per level (3 stars) |
| **Repeat** (mastered sign again, or replaying a level without beating the best stars) | **3** | Max **50 XP per category per day** |
| Daily quest completed | **20-120** | The quest's reward (see 2.6) |
| Solo / group challenge | **= game score** | See 2.5 |

Every XP award is added to four totals at once:

```
module XP (e.g. alphabetXp) += xp     total XP (xp)                  += xp
daily XP  (dailyXp)         += xp     this week's XP (weekXp.2026-W46) += xp
```

The **Weekly League** ranks students by this week's XP (Monday-Sunday, ISO
weeks). Each week has its own field, so everyone starts the week at 0
automatically. The **Global Rank** uses total XP.

**Repeat XP with the daily cap:**

```
repeatXP = min( 3 , 50 − repeatXP already earned today in this category )
```

**Maximum XP from one level (first play):** 3 stars × 10 = 30 XP. Replays
give only the 3 XP repeat (capped), unless a new star is earned: going from
1★ to 3★ gives (3 − 1) × 10 = 20 XP.

---

### 2.3 Hearts and stars (activities)  `[easyAct_mc.dart, easyNumAct_mc.dart, phraseAct.dart, civicAct.dart]`

- Every play starts with **5 hearts**.
- A **wrong answer costs 1 heart** (any question type, including camera
  questions).
- At **0 hearts → game over**: the level is not completed, 0 stars.
- A camera question with no model yet is **skipped** (no heart lost).

**Stars at the end of the level:**

```
hearts left = 5        → ★★★  (no mistakes)
hearts left = 3 or 4   → ★★   (1-2 mistakes)
hearts left = 1 or 2   → ★    (3-4 mistakes)
hearts left = 0        → game over, 0 stars
```

Only the **best** stars of each level are kept (`users.progress.<levelId>`);
a worse replay never lowers them.

---

### 2.4 Practice  `[tutorial_session_practice.dart]`

- One sign at a time, checked like the Hard activities (CAPTURE & CHECK or
  RECORD SIGN).
- **First time a sign is correct: +10 XP.** After that, the 3 XP repeat rule
  applies.
- No hearts and no stars: practice is safe to fail. TRY AGAIN as often as
  needed; ◀ ▶ move between signs.
- Every attempt is recorded in `practice_sessions` (see 1.4).

---

### 2.5 Challenges (solo and group)  `[challenge_categories.dart → ChallengeScoring]`

Points per question, the same in solo and group games:

```
points = 0                                         if wrong or time ran out
points = 50                                        base for a correct answer
       + round( 100 × timeLeft / maxTime )         speed bonus (0-100)
       + (streak ≥ 2 ? streak × 15 : 0)            streak bonus
```

`streak` = correct answers in a row, including this one.

*Example:* the 3rd correct answer in a row, answered with 6 of 10 seconds
left: 50 + 60 + 3 × 15 = **155 points**.

**XP from a game:** the total game score is added as XP.

| | Solo | Group |
|---|---|---|
| XP | total XP, daily XP, this week's XP and the category's module XP | same as solo |
| Counters | games played, solo challenges completed, questions answered, correct answers | — |
| Stars | — | ≥ 500 pts → ★★★, ≥ 250 → ★★, else ★ |
| Record | `solo_challenges` | `group_challenges` |

**Accuracy:**

```
accuracy = correct answers / total questions × 100
```

---

### 2.6 Daily quests  `[daily_challenge_service.dart]`

Every day each student gets **3 quests**, chosen for them.

**1. The learner profile** (last 14 days):

```
activeDays       = days with at least one activity play
levelsPerDay     = completed levels / activeDays
completionRate   = completed levels / attempted levels
levelsPerHour    = completed levels / hours studied
                   (gaps between plays under 30 min count as study time)
signAccuracy     = correct / total of the last 100 camera signs   (needs ≥ 5)
```

**2. Pace:**

| Pace | Rule |
|---|---|
| **Starter** | fewer than 3 levels ever completed |
| **Fast** | levelsPerDay ≥ 5, or (levelsPerHour ≥ 6 and completion ≥ 75%), or (levelsPerDay ≥ 3.5 and completion ≥ 85%) |
| **Steady** | levelsPerDay < 2, or completion < 60% |
| **Balanced** | everything else |

**3. Weakest category** (lowest score among categories the student has
tried):

```
categoryScore = (completion + starsAvg/3 + signAccuracy) / 3
                (without signAccuracy when fewer than 5 camera signs:
                 (completion + starsAvg/3) / 2)
```

**4. Today's 3 quests:**
1. one from the student's **pace** track;
2. one **targeted**: an untried category (Explorer) or the weakest category
   (Skill Builder);
3. a **bonus**: Starter quests for newer learners, the other pace for balanced
   learners, or Consistency.

Rules:
- A quest already completed is never offered again.
- The choice is fixed for the day (it does not change when the app reopens).

**Rewards (XP):**

| Track | Examples | XP |
|---|---|---|
| Starter | First lesson, first activity, 3 correct signs | 20-40 |
| Steady Pace | 1 level, 2 lessons, retry a level, 50 XP today | 25-45 |
| Fast Track | Hard levels, 3-star levels, 300 XP today, 90% accuracy | 80-120 |
| Skill Builder | 2 levels / 5 signs in the weakest category | 60 |
| Explorer | First level in a new category | 50 |
| Consistency | 3- or 7-day streak, early bird, all 4 categories today | 40-120 |

There are 34 quests in total. Completing every quest of a track unlocks that
track's badge.

---

### 2.7 Streak  `[arena.dart → _checkAndResetDailyStats]`

Checked once per day when the student opens the app:

```
days since last active = 1   → streak + 1
days since last active > 1   → streak = 1   (streak broken)
first time ever              → streak = 1
```

Each new day also resets the daily counters (daily XP, lessons today, and so
on).

---

### 2.8 Badges  `[achievements.dart, badge_catalog.dart]`

```
unlocked ⇔ current value of the badge's metric ≥ target
```

- Once unlocked, a badge stays unlocked, even if the value drops later (for
  example, a broken streak).
- Metrics include: total XP, stars, streak, levels per category, Hard levels,
  3-star levels, solo challenges, followers, daily quests completed, and
  others.
- Faculty can edit or add badges from the web (`badges` collection).

**Progress bar:**

```
badge progress = min( current / target , 1 )
```

---

### 2.9 Completion rates

**Module completion** (each category card)  `[custom_category_screen.dart → ModuleProgress]`

```
completion % = ( signs mastered + stars earned ) / ( tutorial signs + 3 × activity levels ) × 100
```

- **Signs mastered** counts tutorial signs learned (capped at the number of
  lessons).
- **Stars earned** counts the best stars of every level (capped at 3 per
  level).

A module is **completed** at 100%: every sign learned and 3 stars on every
level.

*Example:* Alphabet has 26 signs and 38 levels, so the total is
26 + 114 = 140. With 25 signs and 81 stars: (25 + 81) / 140 = **76%**.

**Parts shown on the Tutorial card and in the breakdown:**

```
signs learned   = mastered / tutorial signs
activity stars  = stars earned / (3 × levels)
```

**Other rates:**

| Rate | Formula | Used in |
|---|---|---|
| Level completion rate | completed plays / attempted plays (14 days) | Daily quest pace |
| Sign accuracy | correct / total camera signs (last 100) | Daily quests, Sharp Shooter quest |
| Practice accuracy | correct / attempts | `practice_sessions` |
| Challenge accuracy | correct / questions × 100 | `solo_challenges`, results screen |
| Activity correct count | correct answers / total questions | `activity_sessions` |

---

## Appendix: key thresholds at a glance

| Value | Number |
|---|---|
| Static sign pass mark | 70 / 100 |
| Look-alike rule fail cap | 65 / 100 |
| Server static confidence (veto) | 0.70 |
| Static hold window | 1.5 s (best score), 10 frames sent to the server |
| J / Z minimum frames | 8 |
| Numbers 11-100 minimum frames / clip | 12 / 24 |
| Web-model defaults | minConfidence 0.70 · minSignShare 0.20 · minSignLead 0.10 · maxInvalid 0.75 |
| Hearts per play | 5 |
| XP: tutorial / practice / star / repeat | 20 / 10 / 10 / 3 (repeat cap 50 per category per day) |
| Challenge points | 50 base + up to 100 speed + 15 × streak |
| Daily quests per day | 3 |
| Practice record kept | 90 days |
| Activity log kept | 365 days |
