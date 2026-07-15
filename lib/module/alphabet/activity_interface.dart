import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/progress_service.dart';
import 'easyAct_mc.dart'; 

void main() {
  runApp(const FigmaToCodeApp());
}

class FigmaToCodeApp extends StatelessWidget {
  const FigmaToCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFFFFF9E5),
      ),
      home: const ActivityInterface(),
    );
  }
}

class ActivityInterface extends StatelessWidget {
  const ActivityInterface({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF322144)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Alphabet Path',
          style: TextStyle(
            color: Colors.black,
            fontSize: 24,
            fontFamily: 'Inter',
            fontWeight: FontWeight.w800,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: ProgressService().getUserProgressStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Color(0xFFFFB800)));
            }

            int globalStars = 0;
            Map<String, dynamic> progressMap = {};

            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              if (data != null) {
                globalStars = data['stars'] ?? 0;
                progressMap = data['progress'] != null 
                    ? Map<String, dynamic>.from(data['progress']) 
                    : {};
              }
            }

            // --- DEFINE THE 9-LEVEL ROADMAP & STAR GATES ---
            final List<Map<String, dynamic>> pathNodes = [
              // 🟢 EASY LEVELS
              {
                'id': 'alphabet_easy_1',
                'title': 'Easy 1: Sign to Text',
                'isUnlocked': true, 
                'unlockMessage': '',
                'alignment': Alignment.center,
                'destination': const EasyActMc(levelId: 'alphabet_easy_1', questionType: 'sign_to_text'), 
              },
              {
                'id': 'alphabet_easy_2',
                'title': 'Easy 2: Text to Sign',
                'isUnlocked': (progressMap['alphabet_easy_1'] ?? 0) >= 2, 
                'unlockMessage': 'Earn 2 ⭐ in Easy 1 to unlock!',
                'alignment': Alignment.centerRight,
                'destination': const EasyActMc(levelId: 'alphabet_easy_2', questionType: 'text_to_sign'), 
              },
              {
                'id': 'alphabet_easy_3',
                'title': 'Easy 3: Mixed Review', 
                'isUnlocked': (progressMap['alphabet_easy_2'] ?? 0) >= 2, 
                'unlockMessage': 'Earn 2 ⭐ in Easy 2 to unlock!',
                'alignment': Alignment.centerRight, 
                'destination': const EasyActMc(levelId: 'alphabet_easy_3', questionType: 'mixed'), 
              },

              // 🟡 MEDIUM LEVELS
              {
                'id': 'alphabet_medium_1',
                'title': 'Medium 1: Sign to Text',
                'isUnlocked': (progressMap['alphabet_easy_3'] ?? 0) >= 2,
                'unlockMessage': 'Earn 2 ⭐ in Easy 3 to unlock!',
                'alignment': Alignment.center,
                'destination': const Placeholder(), // Replace with Medium screen later
              },
              {
                'id': 'alphabet_medium_2',
                'title': 'Medium 2: Text to Sign',
                'isUnlocked': (progressMap['alphabet_medium_1'] ?? 0) >= 2,
                'unlockMessage': 'Earn 2 ⭐ in Medium 1 to unlock!',
                'alignment': Alignment.centerLeft,
                'destination': const Placeholder(),
              },
              {
                'id': 'alphabet_medium_3',
                'title': 'Medium 3: Mixed Mastery', 
                'isUnlocked': (progressMap['alphabet_medium_2'] ?? 0) >= 2,
                'unlockMessage': 'Earn 2 ⭐ in Medium 2 to unlock!',
                'alignment': Alignment.centerLeft,
                'destination': const Placeholder(),
              },

              // 🔴 HARD LEVELS
              {
                'id': 'alphabet_hard_1',
                'title': 'Hard 1: Sign to Text',
                'isUnlocked': (progressMap['alphabet_medium_3'] ?? 0) >= 2,
                'unlockMessage': 'Earn 2 ⭐ in Medium 3 to unlock!',
                'alignment': Alignment.center,
                'destination': const Placeholder(), // Replace with Hard screen later
              },
              {
                'id': 'alphabet_hard_2',
                'title': 'Hard 2: Text to Sign',
                'isUnlocked': (progressMap['alphabet_hard_1'] ?? 0) >= 2,
                'unlockMessage': 'Earn 2 ⭐ in Hard 1 to unlock!',
                'alignment': Alignment.centerRight,
                'destination': const Placeholder(),
              },
              {
                'id': 'alphabet_hard_3',
                'title': 'Hard 3: The Ultimate Test', 
                'isUnlocked': (progressMap['alphabet_hard_2'] ?? 0) >= 2,
                'unlockMessage': 'Earn 2 ⭐ in Hard 2 to unlock!',
                'alignment': Alignment.center, 
                'destination': const Placeholder(),
              },
            ];

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              physics: const BouncingScrollPhysics(),
              child: Column(
                children: [
                  // --- GLOBAL STAR BADGE ---
                  Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
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
                            "$globalStars Total Stars",
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF222222)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),

                  // --- WINDING PATH BUILDER ---
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pathNodes.length,
                    separatorBuilder: (context, index) {
                      return Center(
                        child: Container(
                          width: 8,
                          height: 40,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
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
                            // Star Rating Row over the Node
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
                                style: TextStyle(color: Colors.grey.shade500, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            const SizedBox(height: 8),

                            // Circular Level Node
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

                            // Node Label
                            Text(
                              node['title'],
                              style: TextStyle(
                                color: isUnlocked ? const Color(0xFF322144) : Colors.grey.shade500,
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
    );
  }
}