import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/sound_provider.dart';
import '../../services/progress_service.dart';
import 'phraseAct.dart';

class PhrasesActivityInterface extends StatefulWidget {
  final String difficulty;

  const PhrasesActivityInterface({
    super.key,
    required this.difficulty,
  });

  @override
  State<PhrasesActivityInterface> createState() => _PhrasesActivityInterfaceState();
}

class _PhrasesActivityInterfaceState extends State<PhrasesActivityInterface> {
  late dynamic _soundProvider;

  @override
  void initState() {
    super.initState();
    try {
      Provider.of<SoundProvider>(context, listen: false).playBgm();
    } catch (_) {}
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
    try {
      _soundProvider.stopBgm();
    } catch (_) {}
    super.dispose();
  }

  Map<String, dynamic> _getThemeStyles(BuildContext context) {
    final bgColor = Theme.of(context).scaffoldBackgroundColor.value;

    if (bgColor == 0xFF080928) { // Galaxy Explorer
      const nodeColor = Color(0xFFB9A6FF);
      return {
        'primary': const Color(0xFF7C4DFF),
        'text': const Color(0xFFB9A6FF),
        'line': nodeColor.withOpacity(0.6),
        'dividerText': const Color(0xFFB9A6FF).withOpacity(0.7),
        'appBarIcon': const Color(0xFFB9A6FF),
        'cardBg': const Color(0xFF1B1A4B),
        'nodeColor': nodeColor,
        'nodeLightColor': const Color(0xFFC3B1E1),
      };
    }
    if (bgColor == 0xFF1D3D3A) { // Enchanted Forest
      const nodeColor = Color(0xFFB8D4CF);
      return {
        'primary': const Color(0xFFD7B3A1),
        'text': const Color(0xFFF2F5F4),
        'line': nodeColor.withOpacity(0.6),
        'dividerText': const Color(0xFFF2F5F4).withOpacity(0.7),
        'appBarIcon': const Color(0xFFF2F5F4),
        'cardBg': const Color(0xFF4D7C73),
        'nodeColor': nodeColor,
        'nodeLightColor': const Color(0xFFE2F1ED),
      };
    }
    if (bgColor == 0xFF001B3A) { // Deep Ocean
      const nodeColor = Color(0xFF00E5FF);
      return {
        'primary': const Color(0xFF00E5FF),
        'text': Colors.white,
        'line': nodeColor.withOpacity(0.7),
        'dividerText': Colors.white70,
        'appBarIcon': Colors.white,
        'cardBg': Colors.black54,
        'nodeColor': nodeColor,
        'nodeLightColor': const Color(0xFF80F3FF),
      };
    }
    if (bgColor == 0xFFE0EAFC) { // Cloudy Sky
      const nodeColor = Color(0xFF5C7CFA);
      return {
        'primary': const Color(0xFF5C7CFA),
        'text': const Color(0xFF1E1E1E),
        'line': nodeColor.withOpacity(0.6),
        'dividerText': Colors.black54,
        'appBarIcon': const Color(0xFF322144),
        'cardBg': Colors.white.withOpacity(0.9),
        'nodeColor': nodeColor,
        'nodeLightColor': const Color(0xFF91A7FF),
      };
    }

    // Default Theme
    const defaultNodeYellow = Color(0xFFFFB300);
    return {
      'primary': const Color(0xFFFF6B8B),
      'text': const Color(0xFF332050),
      'line': defaultNodeYellow.withOpacity(0.6),
      'dividerText': const Color(0xFF6E5686),
      'appBarIcon': const Color(0xFF332050),
      'cardBg': Colors.white.withOpacity(0.92),
      'nodeColor': defaultNodeYellow,
      'nodeLightColor': const Color(0xFFFFE082),
    };
  }

  Widget _buildVerticalPathLine(Map<String, dynamic> themeStyles) {
    final Color nodeColor = themeStyles['nodeColor'];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(4, (index) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4.0),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: nodeColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: nodeColor.withOpacity(0.4), blurRadius: 4, spreadRadius: 1)
              ],
            ),
          ),
        )),
      ),
    );
  }

  String get _appBarTitle {
    if (widget.difficulty.isEmpty) return 'Phrase Activity';
    return '${widget.difficulty[0].toUpperCase()}${widget.difficulty.substring(1)} Phrases';
  }

  @override
  Widget build(BuildContext context) {
    final themeStyles = _getThemeStyles(context);
    final scaffoldBgColor = Theme.of(context).scaffoldBackgroundColor;
    final String currentDifficulty = widget.difficulty.isNotEmpty ? widget.difficulty.toLowerCase() : 'easy';
    final Color nodeColor = themeStyles['nodeColor'];
    final Color nodeLightColor = themeStyles['nodeLightColor'];

    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: scaffoldBgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: themeStyles['appBarIcon']),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _appBarTitle,
          style: TextStyle(
            color: themeStyles['appBarIcon'],
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: ThemedBackground(bgColor: scaffoldBgColor),
          ),
          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: ProgressService().getUserProgressStream(),
              builder: (context, userProgressSnapshot) {
                if (userProgressSnapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: nodeColor));
                }

                int totalCategoryStars = 0;
                int totalEasyStars = 0;
                int totalMediumStars = 0;
                Map<String, dynamic> progressMap = {};

                if (userProgressSnapshot.hasData && userProgressSnapshot.data!.exists) {
                  final data = userProgressSnapshot.data!.data() as Map<String, dynamic>?;
                  if (data != null) {
                    progressMap = Map<String, dynamic>.from(data['progress'] ?? data['activityProgress'] ?? {});

                    final String prefix = 'phrases_${currentDifficulty}_';
                    progressMap.forEach((key, value) {
                      final int stars = (value as num).toInt();
                      final String keyLower = key.toLowerCase();
                      if (keyLower.startsWith(prefix)) totalCategoryStars += stars;
                      if (keyLower.startsWith('phrases_easy_')) totalEasyStars += stars;
                      if (keyLower.startsWith('phrases_medium_')) totalMediumStars += stars;
                    });
                  }
                }

                bool isTierUnlocked = true;
                if (currentDifficulty == 'medium') {
                  isTierUnlocked = totalEasyStars >= 5;
                } else if (currentDifficulty == 'hard') {
                  isTierUnlocked = totalMediumStars >= 5;
                }

                return StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('activity_questions')
                      .where('category', whereIn: ['phrase', 'phrases', 'Phrase', 'Phrases'])
                      .snapshots(),
                  builder: (context, questionsSnapshot) {
                    if (questionsSnapshot.connectionState == ConnectionState.waiting) {
                      return Center(child: CircularProgressIndicator(color: nodeColor));
                    }

                    final docs = questionsSnapshot.data?.docs ?? [];
                    final Map<String, Map<String, dynamic>> levelsMap = {};

                    for (var doc in docs) {
                      final data = doc.data() as Map<String, dynamic>;
                      final String? levelId = data['level'];
                      final String cat = (data['category'] ?? '').toString().trim().toLowerCase();

                      // Strict alphabet leakage filter
                      if (cat.contains('alphabet')) continue;

                      if (levelId != null && levelId.toLowerCase().startsWith('phrases_${currentDifficulty}_')) {
                        if (!levelsMap.containsKey(levelId)) {
                          final levelNum = levelId.split('_').last;
                          levelsMap[levelId] = {
                            'levelId': levelId,
                            'type': data['type'] ?? 'Multiple Choice',
                            'title': 'Level $levelNum',
                          };
                        }
                      }
                    }

                    final levelKeys = levelsMap.keys.toList();
                    levelKeys.sort((a, b) {
                      final int numA = int.tryParse(a.split('_').last) ?? 0;
                      final int numB = int.tryParse(b.split('_').last) ?? 0;
                      return numA.compareTo(numB);
                    });

                    if (levelKeys.isEmpty) {
                      return Center(
                        child: Text(
                          "No questions found for $currentDifficulty mode.",
                          style: TextStyle(color: themeStyles['text'], fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      );
                    }

                    final alignments = [
                      Alignment.center,
                      Alignment.centerRight,
                      Alignment.center,
                      Alignment.centerLeft,
                    ];

                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: themeStyles['cardBg'],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: nodeColor, width: 2),
                                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 4))],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.star_rounded, color: nodeColor, size: 24),
                                  const SizedBox(width: 6),
                                  Text(
                                    "$totalCategoryStars / ${levelKeys.length * 3} Stars",
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: themeStyles['text']),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                            physics: const BouncingScrollPhysics(),
                            itemCount: levelKeys.length,
                            itemBuilder: (context, index) {
                              final levelId = levelKeys[index];
                              final levelData = levelsMap[levelId]!;
                              final String title = levelData['title'];

                              final int earnedStars = progressMap[levelId] ?? 0;
                              final String prevLevelId = index > 0 ? levelKeys[index - 1] : '';
                              final int prevLevelStars = prevLevelId.isNotEmpty ? (progressMap[prevLevelId] ?? 0) : 0;

                              final bool isUnlocked = isTierUnlocked && (index == 0 || prevLevelStars >= 2);

                              final unlockMsg = !isTierUnlocked
                                  ? 'Earn at least 5 ⭐ in the previous difficulty to unlock!'
                                  : 'Earn 2 ⭐ in Level $index to unlock!';

                              return Column(
                                children: [
                                  Align(
                                    alignment: alignments[index % alignments.length],
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (isUnlocked)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: List.generate(3, (starIdx) {
                                              return Icon(
                                                starIdx < earnedStars ? Icons.star_rounded : Icons.star_border_rounded,
                                                color: nodeColor,
                                                size: 20,
                                              );
                                            }),
                                          )
                                        else
                                          Text(
                                            "🔒 Locked",
                                            style: TextStyle(color: themeStyles['dividerText'], fontSize: 12, fontWeight: FontWeight.bold),
                                          ),
                                        const SizedBox(height: 8),

                                        GestureDetector(
                                          onTap: isUnlocked
                                              ? () {
                                                  try {
                                                    _soundProvider.stopBgm();
                                                  } catch (_) {}
                                                  Navigator.push(
                                                    context,
                                                    MaterialPageRoute(
                                                      builder: (context) => PhraseActivityInterface(
                                                        levelId: levelId,
                                                        title: title,
                                                      ),
                                                    ),
                                                  ).then((_) {
                                                    try {
                                                      _soundProvider.playBgm();
                                                    } catch (_) {}
                                                  });
                                                }
                                              : () {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text(unlockMsg),
                                                      backgroundColor: Colors.redAccent,
                                                    ),
                                                  );
                                                },
                                          child: Stack(
                                            alignment: Alignment.center,
                                            children: [
                                              Container(
                                                width: 104,
                                                height: 104,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: isUnlocked ? nodeColor.withOpacity(0.3) : Colors.black12,
                                                ),
                                              ),
                                              Container(
                                                width: 86,
                                                height: 86,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  gradient: LinearGradient(
                                                    colors: isUnlocked
                                                      ? [nodeLightColor, nodeColor]
                                                      : [Colors.grey.shade400, Colors.grey.shade700],
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: (isUnlocked ? nodeColor : Colors.black).withOpacity(0.5),
                                                      blurRadius: 10,
                                                      offset: const Offset(0, 6),
                                                    )
                                                  ],
                                                  border: Border.all(
                                                    color: isUnlocked ? Colors.white : Colors.grey.shade400,
                                                    width: 4,
                                                  ),
                                                ),
                                                child: Center(
                                                  child: Icon(
                                                    isUnlocked ? Icons.play_arrow_rounded : Icons.lock_rounded,
                                                    color: Colors.white,
                                                    size: 46,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 10),

                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: themeStyles['cardBg'],
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            title,
                                            style: TextStyle(
                                              color: isUnlocked ? themeStyles['text'] : themeStyles['dividerText'],
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14,
                                            ),
                                          ),
                                        )
                                      ],
                                    ),
                                  ),

                                  if (index < levelKeys.length - 1)
                                    _buildVerticalPathLine(themeStyles),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}