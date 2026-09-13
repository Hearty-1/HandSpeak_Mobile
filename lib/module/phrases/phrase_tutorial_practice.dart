import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'phrase_recognizer.dart';

class PhraseTutorialPractice extends StatefulWidget {
  final String targetPhrase;

  const PhraseTutorialPractice({super.key, required this.targetPhrase});

  @override
  _PhraseTutorialPracticeState createState() => _PhraseTutorialPracticeState();
}

class _PhraseTutorialPracticeState extends State<PhraseTutorialPractice> {
  CameraController? _controller;
  HandLandmarkerPlugin? _landmarkerPlugin;
  StreamSubscription<List<Hand>>? _landmarkSubscription;
  final PhraseRecognizer _phraseRecognizer = PhraseRecognizer();

  bool _isInitialized = false;
  bool _isSuccessAchieved = false;

  // Recording state
  bool _isRecordingMotion = false;
  bool _showMotionResult = false;
  DateTime? _startRecordingTime;
  final List<Float32List> _recordingFrames = [];

  static const Duration _dropoutGracePeriod = Duration(milliseconds: 400);
  DateTime? _lastHandsSeenTime;

  static const double _maxRecordingSeconds = 12.0;

  String _debugStatus = "0/4 Fetching training config...";

  double _currentScore = 0.0;
  double _holdProgress = 0.0;

  // Dynamic parameters from Firestore gesture_training_data
  double successThreshold = 70.0;
  int targetSequenceLength = 30;
  final int xpReward = 25;

  @override
  void initState() {
    super.initState();
    _fetchConfigAndInitialize();
  }

  /// Normalizes a gesture name into the same "key" shape the web dashboard
  /// uses for its Firestore doc ids (see normalizeGestureKey() in
  /// lib/content-service.ts on the web side — keep both in sync).
  ///
  /// THIS IS THE ROOT-CAUSE FIX: the web only lowercased the teacher-typed
  /// symbol when building the doc id (e.g. "Good Afternoon" ->
  /// "phrases_good afternoon", space kept), while this screen stripped
  /// spaces from its own hardcoded PascalCase title ("GoodAfternoon" ->
  /// "phrases_goodafternoon"). Those two ids never matched, so the doc-id
  /// read below always missed the real, approved document — the trained
  /// accuracyThreshold on it never reached this screen, which is why
  /// successThreshold stayed stuck at its 0.0/default fallback no matter
  /// what was trained on the web.
  String _normalizeGestureKey(String key) {
    final camelSplit = key.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (m) => '${m[1]}_${m[2]}',
    );
    return camelSplit
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Fetches gesture configuration directly from `gesture_training_data` collection in Firestore.
  Future<void> _fetchConfigAndInitialize() async {
    try {
      if (mounted) {
        setState(() => _debugStatus = "0/4 Querying Firestore 'gesture_training_data'...");
      }

      final normalizedKey = _normalizeGestureKey(widget.targetPhrase);
      final formattedDocId = "phrases_$normalizedKey";

      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('gesture_training_data')
          .doc(formattedDocId)
          .get();

      if (!doc.exists) {
        // Fallback 1: match on the normalized key field the web now stamps
        // on every approved doc (gestureKeyNormalized) — catches docs whose
        // id wasn't migrated yet (see scripts/migrate-gesture-doc-ids.js).
        final normalizedQuery = await FirebaseFirestore.instance
            .collection('gesture_training_data')
            .where('gestureKeyNormalized', isEqualTo: normalizedKey)
            .limit(1)
            .get();

        if (normalizedQuery.docs.isNotEmpty) {
          doc = normalizedQuery.docs.first;
        } else {
          // Fallback 2 (legacy): exact, case-sensitive match on the raw
          // gestureKey field, for docs written before gestureKeyNormalized
          // existed at all.
          final legacyQuery = await FirebaseFirestore.instance
              .collection('gesture_training_data')
              .where('gestureKey', isEqualTo: widget.targetPhrase)
              .limit(1)
              .get();

          if (legacyQuery.docs.isNotEmpty) {
            doc = legacyQuery.docs.first;
          }
        }
      }

      if (doc.exists && doc.data() != null) {
        final data = doc.data() as Map<String, dynamic>;

        // Fetch sequenceLength if available
        if (data['sequenceLength'] != null) {
          targetSequenceLength = (data['sequenceLength'] as num).toInt();
        }

        // Fetch threshold directly or map from toleranceBounds. Guard
        // against 0/negative values — a trained threshold should never be
        // <= 0, so treat that as "not actually configured" and keep the
        // class default (70.0) rather than let every attempt trivially
        // pass (or display a nonsensical 0% requirement).
        final num? rawThreshold = data['accuracyThreshold'] as num?;
        final num? rawDistance = data['toleranceBounds'] != null
            ? data['toleranceBounds']['distance'] as num?
            : null;

        if (rawThreshold != null && rawThreshold > 0) {
          successThreshold = rawThreshold.toDouble();
        } else if (rawDistance != null && rawDistance > 0) {
          successThreshold = rawDistance.toDouble();
        } else {
          debugPrint(
            "Doc ${doc.id} found but accuracyThreshold/toleranceBounds.distance "
            "was missing or <= 0 — keeping default successThreshold=$successThreshold%.",
          );
        }

        debugPrint(
          "Firestore gesture data loaded: docId=${doc.id}, sequenceLength=$targetSequenceLength, threshold=$successThreshold%",
        );
      } else {
        debugPrint(
          "No Firestore doc found for '${widget.targetPhrase}' (tried id='$formattedDocId', "
          "gestureKeyNormalized='$normalizedKey'). Using defaults.",
        );
      }
    } catch (e) {
      debugPrint("Error fetching gesture data from Firestore: $e");
    }

    await _initializePipeline();
  }

  Future<void> _initializePipeline() async {
    try {
      if (mounted) {
        setState(() => _debugStatus = "1/4 Initializing Phrase Recognizer...");
      }
      await _phraseRecognizer.initialize(customSequenceLength: targetSequenceLength);

      if (mounted) {
        setState(() => _debugStatus = "2/4 Initializing MediaPipe Landmarker...");
      }
      _landmarkerPlugin = HandLandmarkerPlugin.create(
        numHands: 2,
        minHandDetectionConfidence: 0.5,
        delegate: HandLandmarkerDelegate.gpu,
      );

      _landmarkSubscription = _landmarkerPlugin!.landmarkStream.listen(
        _onHandsDetected,
        onError: (e) {
          if (mounted) {
            setState(() => _debugStatus = "❌ LANDMARK STREAM ERROR: $e");
          }
        },
      );

      if (mounted) {
        setState(() => _debugStatus = "3/4 Opening Camera Stream...");
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) {
          setState(() => _debugStatus = "❌ Error: Camera Hardware Not Found!");
        }
        return;
      }

      final frontCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        frontCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      await _controller!.initialize();

      await _controller!.startImageStream((CameraImage image) {
        if (!_isInitialized || _landmarkerPlugin == null || _isSuccessAchieved) {
          return;
        }
        try {
          _landmarkerPlugin!.processFrame(
            image,
            _controller!.description.sensorOrientation,
          );
        } catch (e) {
          if (mounted) {
            setState(() => _debugStatus = "❌ FRAME STREAM ERROR: $e");
          }
        }
      });

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _debugStatus = "✅ PIPELINE ACTIVE (Pass Rate: ${successThreshold.toStringAsFixed(0)}%)";
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _debugStatus = "❌ PIPELINE INITIALIZATION CRASH:\n$e");
      }
    }
  }

  void _onHandsDetected(List<Hand> detectedHands) {
    if (_isSuccessAchieved || !mounted || _showMotionResult) return;

    final bool handsPresent = detectedHands.isNotEmpty;
    final now = DateTime.now();

    if (handsPresent) {
      _lastHandsSeenTime = now;

      if (!_isRecordingMotion) {
        _isRecordingMotion = true;
        _startRecordingTime = now;
        _recordingFrames.clear();
        _phraseRecognizer.resetHandSlotTracking();
        setState(() => _debugStatus = "🎥 Recording phrase...");
      }

      _recordingFrames.add(_phraseRecognizer.extractFrameFeatures(detectedHands));

      final double elapsedSeconds =
          now.difference(_startRecordingTime!).inMilliseconds / 1000.0;

      final int requiredFrames = _phraseRecognizer.sequenceLength;
      final bool haveEnoughFrames = _recordingFrames.length >= requiredFrames;
      final bool timedOut = elapsedSeconds >= _maxRecordingSeconds;

      setState(() {
        _holdProgress = (_recordingFrames.length / requiredFrames).clamp(0.0, 1.0);
        _debugStatus =
            "🎥 Recording phrase... (${_recordingFrames.length}/$requiredFrames frames)";
      });

      if (haveEnoughFrames || timedOut) {
        _evaluateRecording();
      }
    } else if (_isRecordingMotion) {
      final lastSeen = _lastHandsSeenTime;
      final bool withinGrace =
          lastSeen != null && now.difference(lastSeen) <= _dropoutGracePeriod;

      if (!withinGrace) {
        setState(() {
          _isRecordingMotion = false;
          _startRecordingTime = null;
          _holdProgress = 0.0;
          _debugStatus = "✋ Place your hand inside camera view...";
        });
        _recordingFrames.clear();
      }
    }
  }

  void _evaluateRecording() {
    _isRecordingMotion = false;
    _showMotionResult = true;

    final scores = _phraseRecognizer.rawScoresForRecording(_recordingFrames);

    final double elapsedForDebug =
        DateTime.now().difference(_startRecordingTime!).inMilliseconds / 1000.0;
    final double effectiveFps =
        elapsedForDebug > 0 ? _recordingFrames.length / elapsedForDebug : 0.0;

    debugPrint(
      "=== ${widget.targetPhrase.toUpperCase()} EVAL === "
      "frames=${_recordingFrames.length} elapsed=${elapsedForDebug.toStringAsFixed(2)}s "
      "fps=${effectiveFps.toStringAsFixed(1)} | scores=$scores",
    );

    _recordingFrames.clear();

    if (scores.isEmpty) {
      setState(() {
        _showMotionResult = false;
        _holdProgress = 0.0;
        _debugStatus = "❌ PREDICTION ERROR: model returned no scores";
      });
      return;
    }

    String topLabel = "";
    double topScore = -1.0;
    scores.forEach((label, score) {
      if (score > topScore) {
        topScore = score;
        topLabel = label;
      }
    });

    String targetClean =
        widget.targetPhrase.replaceAll(" ", "_").replaceAll("-", "_").toLowerCase().trim();
    String predictedClean =
        topLabel.replaceAll(" ", "_").replaceAll("-", "_").toLowerCase().trim();

    double? targetRawScore;
    scores.forEach((label, score) {
      final labelClean = label.replaceAll(" ", "_").replaceAll("-", "_").toLowerCase().trim();
      if (labelClean == targetClean) targetRawScore = score;
    });

    if (targetRawScore == null) {
      setState(() {
        _showMotionResult = false;
        _holdProgress = 0.0;
        _debugStatus = "❌ '${widget.targetPhrase}' not found in label map";
      });
      return;
    }

    final double finalScore = (targetRawScore! * 100.0).clamp(0.0, 100.0);

    setState(() {
      _currentScore = finalScore;
      _holdProgress = 0.0;
      _debugStatus =
          "🤖 Top guess: '$predictedClean' (${(topScore * 100).toStringAsFixed(1)}%)\n"
          "🎯 Target: '$targetClean' — score: ${finalScore.toStringAsFixed(1)}% (Req: ${successThreshold.toStringAsFixed(0)}%)";
    });

    if (_currentScore >= successThreshold) {
      _onSuccess();
    } else {
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted && !_isSuccessAchieved) {
          setState(() {
            _showMotionResult = false;
            _currentScore = 0.0;
            _debugStatus = "✋ Place your hand inside camera view...";
          });
        }
      });
    }
  }

  Future<void> _awardXp() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final docRef = FirebaseFirestore.instance.collection('users').doc(user.uid);

        await docRef.set({
          'phraseXp': FieldValue.increment(xpReward),
          'xp': FieldValue.increment(xpReward),
          'dailyXp': FieldValue.increment(xpReward),
          'weeklyXp': FieldValue.increment(xpReward),
          'completedLessons': FieldValue.increment(1),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint("Firestore XP Update Error: $e");
    }
  }

  void _onSuccess() async {
    _isSuccessAchieved = true;
    _holdProgress = 0.0;

    HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 100));
    HapticFeedback.heavyImpact();

    await _awardXp();

    if (!mounted) return;

    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AlertDialog(
          backgroundColor: theme.cardColor.withOpacity(0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: theme.dividerColor.withOpacity(0.15), width: 1.5),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: theme.cardColor, shape: BoxShape.circle),
                child: Icon(Icons.waving_hand_rounded, color: theme.primaryColor, size: 24),
              ),
              const SizedBox(width: 10),
              Text("Success!", style: TextStyle(fontWeight: FontWeight.w900, color: textColor)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Outstanding job! You have successfully mastered the phrase \"${widget.targetPhrase}\"!",
                style: TextStyle(fontSize: 16, color: textColor, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.green.withOpacity(0.3), width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.bolt, color: Colors.green, size: 20),
                      const SizedBox(width: 4),
                      Text(
                        "+$xpReward XP Earned!",
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.green),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.pop(context);
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  child: Text("Back to Tutorial", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            )
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.stopImageStream();
    _controller?.dispose();
    _landmarkSubscription?.cancel();
    _landmarkerPlugin?.dispose();
    _phraseRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    String phraseDisplay = widget.targetPhrase;
    String formattedPhrase = widget.targetPhrase.replaceAll(" ", "_").toLowerCase();

    bool isPassing = _currentScore >= successThreshold;
    final double screenWidth = MediaQuery.of(context).size.width;

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.6),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: textColor),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.transparent,
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withOpacity(0.1),
                    width: 0.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        title: Text(
          'Practice Mode',
          style: TextStyle(
            color: textColor,
            fontSize: 22,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
            letterSpacing: -0.96,
          ),
        ),
      ),
      body: Stack(
        children: [
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.primaryColor.withOpacity(0.2),
              ),
            ),
          ),
          Positioned(
            bottom: 50,
            left: -50,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF4CAF50).withOpacity(0.15),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      phraseDisplay,
                      style: TextStyle(
                        color: textColor,
                        fontSize: 32,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'Inter',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8.0),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _debugStatus,
                        style: const TextStyle(
                          color: Colors.yellowAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: screenWidth * 0.55,
                      child: AspectRatio(
                        aspectRatio: 1 / 1,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.asset(
                              "assets/pictures/$formattedPhrase.jpg",
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                color: theme.dividerColor.withOpacity(0.1),
                                child: Icon(Icons.broken_image, color: textColor.withOpacity(0.4), size: 50),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: screenWidth * 0.55,
                      child: AspectRatio(
                        aspectRatio: 1 / 1,
                        child: Stack(
                          alignment: Alignment.center,
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: theme.cardColor,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  width: 4.0,
                                  color: isPassing ? Colors.green : theme.dividerColor.withOpacity(0.3),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.06),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: _isInitialized && _controller != null
                                    ? FittedBox(
                                        fit: BoxFit.cover,
                                        child: SizedBox(
                                          width: _controller!.value.previewSize?.height ?? 1,
                                          height: _controller!.value.previewSize?.width ?? 1,
                                          child: CameraPreview(_controller!),
                                        ),
                                      )
                                    : Center(
                                        child: CircularProgressIndicator(color: theme.primaryColor),
                                      ),
                              ),
                            ),
                            if (_isInitialized && !_isSuccessAchieved)
                              Center(
                                child: Container(
                                  width: 100,
                                  height: 100,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isPassing ? Colors.green.withOpacity(0.8) : Colors.white54,
                                      width: 3.0,
                                    ),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: BackdropFilter(
                                        filter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          color: Colors.black45,
                                          child: Text(
                                            "Position Hand",
                                            style: TextStyle(
                                              color: isPassing ? Colors.greenAccent : Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_holdProgress > 0.0) ...[
                      Column(
                        children: [
                          const Text(
                            "Hold steady...",
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.w900, fontSize: 18),
                          ),
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                              child: Container(
                                width: screenWidth * 0.70,
                                height: 16,
                                decoration: BoxDecoration(
                                  color: theme.cardColor.withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: theme.dividerColor.withOpacity(0.2), width: 1),
                                ),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    widthFactor: _holdProgress,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(colors: [Colors.greenAccent, Colors.green]),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    ] else ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: isPassing ? Colors.green.withOpacity(0.2) : theme.cardColor.withOpacity(0.75),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: isPassing ? Colors.green.withOpacity(0.4) : theme.dividerColor.withOpacity(0.2),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              "Score: ${_currentScore.toStringAsFixed(1)}%",
                              style: TextStyle(
                                color: isPassing ? Colors.green.shade700 : textColor.withOpacity(0.7),
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}