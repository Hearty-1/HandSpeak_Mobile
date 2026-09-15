import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '/providers/sound_provider.dart';
import '/services/progress_service.dart';

class CivicTutorialPractice extends StatefulWidget {
  final String category;
  final List<Map<String, dynamic>> questions;

  const CivicTutorialPractice({
    super.key,
    this.category = 'Civic Video Lesson',
    this.questions = const [],
  });

  @override
  State<CivicTutorialPractice> createState() => _CivicTutorialPracticeState();
}

class _CivicTutorialPracticeState extends State<CivicTutorialPractice> {
  int _currentStep = 0;
  int _selectedOption = -1;
  bool _answered = false;
  int _score = 0;
  bool _progressSaved = false;

  // In-memory cache for civic template images downloaded from Firebase Storage
  static final Map<String, Uint8List> _templateImageCache = {};
  Uint8List? _templateImageBytes;
  bool _isImageLoading = false;

  @override
  void initState() {
    super.initState();
    _loadTemplateImage();
  }

  /// Normalizes keys for Firebase Storage document/file paths.
  String _normalizeKey(String key) {
    final camelSplit = key.replaceAllMapped(
      RegExp(r'([a-z0-9])([A-Z])'),
      (m) => '${m[1]}_${m[2]}',
    );
    return camelSplit
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// Fetches template image from Firebase Storage with in-memory caching.
  Future<void> _loadTemplateImage() async {
    if (widget.questions.isEmpty || _currentStep >= widget.questions.length) return;

    final questionData = widget.questions[_currentStep];
    final String rawKey = questionData['imageKey'] ??
        questionData['id'] ??
        '${widget.category}_$_currentStep';
    final normalizedKey = _normalizeKey(rawKey);

    // Check in-memory cache first
    if (_templateImageCache.containsKey(normalizedKey)) {
      if (mounted) {
        setState(() {
          _templateImageBytes = _templateImageCache[normalizedKey];
          _isImageLoading = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isImageLoading = true);
    }

    try {
      // Fetch dynamic template image from Firebase Cloud Storage
      final ref = FirebaseStorage.instance
          .ref()
          .child('civic_templates/$normalizedKey.jpg');

      final Uint8List? data = await ref.getData(5 * 1024 * 1024); // 5MB max limit
      if (data != null && data.isNotEmpty) {
        _templateImageCache[normalizedKey] = data; // Cache in memory
        if (mounted) {
          setState(() {
            _templateImageBytes = data;
            _isImageLoading = false;
          });
        }
        return;
      }
    } catch (e) {
      debugPrint(
        "Firebase Storage template download for '$normalizedKey' failed: $e. Falling back to default asset.",
      );
    }

    if (mounted) {
      setState(() {
        _templateImageBytes = null;
        _isImageLoading = false;
      });
    }
  }

  void _playSound(String effect) {
    try {
      final soundProvider = Provider.of<SoundProvider>(context, listen: false) as dynamic;
      soundProvider.playSound(effect);
    } catch (_) {
      try {
        final soundProvider = Provider.of<SoundProvider>(context, listen: false) as dynamic;
        soundProvider.playSoundEffect(effect);
      } catch (_) {
        // Sound provider method not found; fails silently
      }
    }
  }

  Future<void> _saveUserProgress() async {
    if (_progressSaved) return;
    _progressSaved = true;

    try {
      dynamic service = ProgressService();
      final levelKey = 'civic_practice_${_normalizeKey(widget.category)}';
      final stars = _score == widget.questions.length ? 3 : 2;
      final xpEarned = _score * 15;

      try {
        await service.updateUserProgress(
          levelKey: levelKey,
          stars: stars,
          xpEarned: xpEarned,
          xpCategoryKey: 'civicXp',
        );
      } catch (_) {
        await service.updateUserProgress(levelKey, stars, xpEarned);
      }
    } catch (e) {
      debugPrint("Error updating progress service: $e");
    }
  }

  void _handleNextStep() {
    setState(() {
      if (_currentStep < widget.questions.length - 1) {
        _currentStep++;
        _selectedOption = -1;
        _answered = false;
        _loadTemplateImage();
      } else {
        _currentStep++;
        _saveUserProgress();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.6),
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Practice Quiz',
          style: TextStyle(
            color: textColor,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.scaffoldBackgroundColor,
                  theme.primaryColor.withOpacity(0.08),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: widget.questions.isEmpty
                  ? _buildNoQuestionsView(theme)
                  : _buildPracticeUI(theme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoQuestionsView(ThemeData theme) {
    final textColor = theme.colorScheme.onSurface;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.quiz_outlined, size: 70, color: textColor.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text(
            'No practice questions found for this video.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
          ),
          const SizedBox(height: 8),
          Text(
            'Add practice questions inside the Firestore document.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: textColor.withOpacity(0.6)),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Back to Video',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPracticeUI(ThemeData theme) {
    if (_currentStep >= widget.questions.length) {
      return _buildCompletionView(theme);
    }

    final questionData = widget.questions[_currentStep];
    final List<String> options = List<String>.from(questionData['options'] ?? []);
    final int correctIdx = questionData['correctIndex'] ?? 0;
    final textColor = theme.colorScheme.onSurface;
    final formattedCategory = _normalizeKey(widget.category);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Question ${_currentStep + 1}/${widget.questions.length}',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textColor.withOpacity(0.7),
          ),
        ),
        const SizedBox(height: 12),
        // Template Image Preview Box with In-Memory Caching and Cloud Storage Loading
        SizedBox(
          height: 150,
          width: double.infinity,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: theme.cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: _isImageLoading
                  ? Center(child: CircularProgressIndicator(color: theme.primaryColor))
                  : _templateImageBytes != null
                      ? Image.memory(
                          _templateImageBytes!,
                          fit: BoxFit.cover,
                        )
                      : Image.asset(
                          "assets/pictures/$formattedCategory.jpg",
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: theme.dividerColor.withOpacity(0.1),
                            child: Icon(Icons.school_rounded, color: textColor.withOpacity(0.4), size: 48),
                          ),
                        ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          questionData['question'] ?? 'Question',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textColor,
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView.builder(
            itemCount: options.length,
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              Color borderClr = theme.dividerColor.withOpacity(0.2);
              Color fillClr = theme.cardColor;

              if (_answered) {
                if (index == correctIdx) {
                  borderClr = Colors.green;
                  fillClr = Colors.green.withOpacity(0.15);
                } else if (index == _selectedOption) {
                  borderClr = Colors.red;
                  fillClr = Colors.red.withOpacity(0.15);
                }
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: GestureDetector(
                  onTap: _answered
                      ? null
                      : () {
                          setState(() {
                            _selectedOption = index;
                            _answered = true;
                            if (index == correctIdx) {
                              _score++;
                              _playSound('correct');
                            } else {
                              _playSound('wrong');
                            }
                          });
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: fillClr,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: borderClr, width: 2),
                    ),
                    child: Text(
                      options[index],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_answered)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: _handleNextStep,
            child: Text(
              _currentStep < widget.questions.length - 1 ? 'Next Question' : 'Complete Practice',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildCompletionView(ThemeData theme) {
    final textColor = theme.colorScheme.onSurface;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.verified,
            size: 80,
            color: Colors.green,
          ),
          const SizedBox(height: 20),
          Text(
            'Practice Complete!',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'You scored $_score out of ${widget.questions.length}',
            style: TextStyle(
              fontSize: 18,
              color: textColor.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '+${_score * 15} Civic XP Earned',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: theme.primaryColor,
            ),
          ),
          const SizedBox(height: 36),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.primaryColor,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Done',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}