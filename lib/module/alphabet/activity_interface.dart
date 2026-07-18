import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/progress_service.dart';
import 'easyAct_mc.dart'; 

class ActivityInterface extends StatelessWidget {
  const ActivityInterface({super.key});

  Widget _buildSectionDivider(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(child: Divider(color: Colors.grey.shade400, thickness: 2)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              title,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w900,
                fontSize: 18,
                letterSpacing: 1.2,
              ),
            ),
          ),
          Expanded(child: Divider(color: Colors.grey.shade400, thickness: 2)),
        ],
      ),
    );
  }

  Widget _buildVerticalPathLine() {
    return Center(
      child: Container(
        width: 8,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.grey.shade400,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true, 
      backgroundColor: const Color(0xFFFFF9E5), // Protects against the black screen fallback
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF322144)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Alphabet Activity',
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      // --- STACK BODY FOR VISUAL ERROR DIAGNOSTICS ---
      body: Stack(
        children: [
          // 1. Background Image layer with built-in asset path checking
          Positioned.fill(
            child: Image.asset(
              'assets/pictures/background1.jpg', 
              fit: BoxFit.cover,
              // Applies the pastel filter natively onto the asset
              color: Colors.white.withOpacity(0.45),
              colorBlendMode: BlendMode.lighten,
              // IF THIS FAILS, IT RUNS THIS CODE INSTEAD OF SHOWING BLACK:
              errorBuilder: (context, error, stackTrace) {
                return Container(
                  color: const Color(0xFFFFF9E5), // Falls back safely to your cream color
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 48),
                        const SizedBox(height: 16),
                        const Text(
                          "⚠️ ASSET LAUNCH ERROR",
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Flutter is trying to find your image at:\n'assets/pictures/background.jpg'\n\n"
                          "But nothing is there! Check your folder spelling or pubspec.yaml configuration.",
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade800, fontSize: 14, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // 2. Interactive UI Content Layer
          SafeArea(
            child: StreamBuilder<DocumentSnapshot>(
              stream: ProgressService().getUserProgressStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800)));
                }

                int categoryStars = 0; 
                Map<String, dynamic> progressMap = {};

                if (snapshot.hasData && snapshot.data!.exists) {
                  final data = snapshot.data!.data() as Map<String, dynamic>?;
                  if (data != null) {
                    progressMap = data['progress'] != null 
                        ? Map<String, dynamic>.from(data['progress']) 
                        : {};
                    
                    progressMap.forEach((key, value) {
                      if (key.startsWith('alphabet_')) {
                        categoryStars += (value as num).toInt();
                      }
                    });
                  }
                }

                final List<Map<String, dynamic>> pathNodes = [
                  {
                    'id': 'alphabet_easy_1',
                    'title': 'Level 1: Sign => Text',
                    'isUnlocked': true, 
                    'unlockMessage': '',
                    'alignment': Alignment.center,
                    'destination': const EasyActMc(levelId: 'alphabet_easy_1', questionType: 'sign_to_text'), 
                  },
                  {
                    'id': 'alphabet_easy_2',
                    'title': 'Level 2: Text => Sign',
                    'isUnlocked': (progressMap['alphabet_easy_1'] ?? 0) >= 2, 
                    'unlockMessage': 'Earn 2 ⭐ in Level 1 to unlock!',
                    'alignment': Alignment.centerRight,
                    'destination': const EasyActMc(levelId: 'alphabet_easy_2', questionType: 'text_to_sign'), 
                  },
                  {
                    'id': 'alphabet_easy_3',
                    'title': 'Level 3: Text vv Sign', 
                    'isUnlocked': (progressMap['alphabet_easy_2'] ?? 0) >= 2, 
                    'unlockMessage': 'Earn 2 ⭐ in Level 2 to unlock!',
                    'alignment': Alignment.centerRight, 
                    'destination': const EasyActMc(levelId: 'alphabet_easy_3', questionType: 'mixed'), 
                  },
                  {
                    'id': 'alphabet_medium_1',
                    'title': 'Level 4: Right/Wrong',
                    'isUnlocked': (progressMap['alphabet_easy_3'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 3 to unlock!',
                    'alignment': Alignment.center,
                    'destination': const EasyActMc(levelId: 'alphabet_medium_1', questionType: 'true_false'),
                  },
                  {
                    'id': 'alphabet_medium_2',
                    'title': 'Level 5: Fill Me!',
                    'isUnlocked': (progressMap['alphabet_medium_1'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 4 to unlock!',
                    'alignment': Alignment.centerLeft,
                    'destination': const EasyActMc(levelId: 'alphabet_medium_2', questionType: 'fill_in'), 
                  },
                  {
                    'id': 'alphabet_medium_3',
                    'title': 'Level 6: Spell', 
                    'isUnlocked': (progressMap['alphabet_medium_2'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 5 to unlock!',
                    'alignment': Alignment.centerLeft,
                    'destination': const EasyActMc(levelId: 'alphabet_medium_3', questionType: 'spell'), 
                  },
                  {
                    'id': 'alphabet_hard_1',
                    'title': 'Level 7: Sign Me!',
                    'isUnlocked': (progressMap['alphabet_medium_3'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 6 to unlock!',
                    'alignment': Alignment.center,
                    'destination': const Placeholder(), 
                  },
                  {
                    'id': 'alphabet_hard_2',
                    'title': 'Level 8: Finger Spell',
                    'isUnlocked': (progressMap['alphabet_hard_1'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 7 to unlock!',
                    'alignment': Alignment.centerRight,
                    'destination': const Placeholder(),
                  },
                  {
                    'id': 'alphabet_hard_3',
                    'title': 'Level 9: The Ultimate Test', 
                    'isUnlocked': (progressMap['alphabet_hard_2'] ?? 0) >= 2,
                    'unlockMessage': 'Earn 2 ⭐ in Level 8 to unlock!',
                    'alignment': Alignment.center, 
                    'destination': const Placeholder(),
                  },
                ];

                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9), 
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFFFB800), width: 2),
                            boxShadow: const [BoxShadow(color: Color(0x05132C4A), blurRadius: 10, offset: Offset(0, 4))],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, color: Color(0xFFFFB800), size: 24),
                              const SizedBox(width: 6),
                              Text(
                                "$categoryStars Stars",
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF222222)),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 30),

                      _buildSectionDivider("EASY"),
                      const SizedBox(height: 10),

                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: pathNodes.length,
                        separatorBuilder: (context, index) {
                          if (index == 2) { 
                            return Column(
                              children: [
                                _buildVerticalPathLine(),
                                _buildSectionDivider("MEDIUM"),
                                _buildVerticalPathLine(),
                              ],
                            );
                          } else if (index == 5) { 
                            return Column(
                              children: [
                                _buildVerticalPathLine(),
                                _buildSectionDivider("HARD"),
                                _buildVerticalPathLine(),
                              ],
                            );
                          }
                          return _buildVerticalPathLine();
                        },
                        itemBuilder: (context, index) {
                          final node = pathNodes[index];
                          final String nodeId = node['id'];
                          final int earnedStars = progressMap[nodeId] ?? 0;
                          final bool isUnlocked = node['isUnlocked'];

                          return Align(
                            alignment: node['alignment'],
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isUnlocked)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: List.generate(3, (starIdx) {
                                      return Icon(
                                        starIdx < earnedStars ? Icons.star_rounded : Icons.star_border_rounded,
                                        color: const Color(0xFFFFB800),
                                        size: 20,
                                      );
                                    }),
                                  )
                                else
                                  Text(
                                    "🔒 Locked",
                                    style: TextStyle(color: Colors.grey.shade700, fontSize: 12, fontWeight: FontWeight.bold),
                                  ),
                                const SizedBox(height: 8),

                                GestureDetector(
                                  onTap: isUnlocked
                                      ? () => Navigator.push(context, MaterialPageRoute(builder: (context) => node['destination']))
                                      : () {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text(node['unlockMessage']),
                                              backgroundColor: Colors.redAccent,
                                            ),
                                          );
                                        },
                                  child: Container(
                                    width: 90,
                                    height: 90,
                                    decoration: BoxDecoration(
                                      color: isUnlocked ? const Color(0xFFFFB800) : Colors.grey.shade300,
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: (isUnlocked ? const Color(0xFFFFB800) : Colors.grey).withOpacity(0.4),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        )
                                      ],
                                      border: Border.all(color: Colors.white, width: 5),
                                    ),
                                    child: Icon(
                                      isUnlocked ? Icons.play_arrow_rounded : Icons.lock_rounded,
                                      color: Colors.white,
                                      size: 46,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),

                                Text(
                                  node['title'],
                                  style: TextStyle(
                                    color: isUnlocked ? const Color(0xFF322144) : Colors.grey.shade700,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                )
                              ],
                            ),
                          );
                        },
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