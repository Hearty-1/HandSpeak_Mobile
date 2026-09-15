import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/sound_provider.dart';
import '../../services/progress_service.dart';

// ==========================================
// KIDDIE PROCEDURAL BACKGROUND WIDGET
// ==========================================
class ThemedBackground extends StatelessWidget {
  final Color bgColor;

  const ThemedBackground({super.key, required this.bgColor});

  Widget _buildGlowingOrb(double size, Color color, double top, double left) {
    return Positioned(
      top: top,
      left: left,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withOpacity(0.6), color.withOpacity(0.0)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [bgColor, bgColor.withRed((bgColor.red + 20).clamp(0, 255))],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          _buildGlowingOrb(300, Colors.white.withOpacity(0.15), -50, -100),
          _buildGlowingOrb(400, Colors.white.withOpacity(0.1), 400, 200),
        ],
      ),
    );
  }
}

// ==========================================
// PHRASE ACTIVITY QUESTION INTERFACE
// ==========================================
class PhraseActivityInterface extends StatefulWidget {
  final String levelId;
  final String title;

  const PhraseActivityInterface({
    super.key,
    required this.levelId,
    required this.title,
  });

  @override
  State<PhraseActivityInterface> createState() => _PhraseActivityInterfaceState();
}

class _PhraseActivityInterfaceState extends State<PhraseActivityInterface> {
  SoundProvider? _soundProvider;
  int _currentIndex = 0;
  int _score = 0;
  String? _selectedOption;
  bool _isAnswered = false;

  @override
  void initState() {
    super.initState();
    // Track that the user opened this module
    ProgressService().trackRecentModule(widget.levelId);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _soundProvider = Provider.of<SoundProvider>(context, listen: false);
    } catch (_) {}
  }

  @override
  void dispose() {
    _soundProvider?.stopBgm();
    super.dispose();
  }

  void _handleOptionSelect(String option, String correctAnswer, int totalQuestions) {
    if (_isAnswered) return;

    final isCorrect = option.trim().toLowerCase() == correctAnswer.trim().toLowerCase();

    setState(() {
      _selectedOption = option;
      _isAnswered = true;
      if (isCorrect) _score++;
    });
  }

  void _nextQuestion(int totalQuestions) {
    if (_currentIndex < totalQuestions - 1) {
      setState(() {
        _currentIndex++;
        _selectedOption = null;
        _isAnswered = false;
      });
    } else {
      _finishActivity(totalQuestions);
    }
  }

  Future<void> _finishActivity(int totalQuestions) async {
    final double percentage = _score / totalQuestions;
    int stars = 1;
    if (percentage >= 0.8) {
      stars = 3;
    } else if (percentage >= 0.5) {
      stars = 2;
    }

    // Updated to match your ProgressService method
    await ProgressService().updateLevelXP(widget.levelId, stars);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          "Level Completed! 🎉",
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(3, (i) => Icon(
                i < stars ? Icons.star_rounded : Icons.star_border_rounded,
                color: const Color(0xFFFFB300),
                size: 40,
              )),
            ),
            const SizedBox(height: 16),
            Text(
              "You scored $_score / $totalQuestions",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Return to level selection
            },
            child: const Text("Continue", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scaffoldBgColor = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scaffoldBgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(child: ThemedBackground(bgColor: scaffoldBgColor)),
          SafeArea(
            child: FutureBuilder<QuerySnapshot>(
              future: FirebaseFirestore.instance
                  .collection('activity_questions')
                  .where('level', isEqualTo: widget.levelId)
                  .get(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                }

                final docs = snapshot.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Text(
                      "No questions available for this level.",
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  );
                }

                final currentDoc = docs[_currentIndex].data() as Map<String, dynamic>;
                final questionText = currentDoc['question'] ?? currentDoc['phrase'] ?? '';
                final correctAnswer = currentDoc['correctAnswer'] ?? currentDoc['answer'] ?? '';
                final List<String> options = List<String>.from(currentDoc['options'] ?? []);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Column(
                    children: [
                      // Progress Bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: LinearProgressIndicator(
                          value: (_currentIndex + 1) / docs.length,
                          backgroundColor: Colors.white24,
                          color: const Color(0xFFFFB300),
                          minHeight: 10,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "Question ${_currentIndex + 1} of ${docs.length}",
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 24),

                      // Question Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: const [
                            BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4)),
                          ],
                        ),
                        child: Text(
                          questionText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF332050),
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // Options List
                      Expanded(
                        child: ListView.builder(
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options[index];
                            final isSelected = _selectedOption == option;
                            final isCorrect = option.trim().toLowerCase() == correctAnswer.trim().toLowerCase();

                            Color btnColor = Colors.white;
                            if (_isAnswered) {
                              if (isCorrect) {
                                btnColor = Colors.greenAccent.shade400;
                              } else if (isSelected) {
                                btnColor = Colors.redAccent.shade200;
                              }
                            }

                            return Container(
                              margin: const EdgeInsets.only(bottom: 14),
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: btnColor,
                                  foregroundColor: Colors.black87,
                                  padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                  elevation: 4,
                                ),
                                onPressed: () => _handleOptionSelect(option, correctAnswer, docs.length),
                                child: Text(
                                  option,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Next Button
                      if (_isAnswered)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFB300),
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                            onPressed: () => _nextQuestion(docs.length),
                            child: Text(
                              _currentIndex < docs.length - 1 ? "Next Question" : "Finish Level",
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}