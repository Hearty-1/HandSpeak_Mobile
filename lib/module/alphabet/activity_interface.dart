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
  final int targetXpPerLevel;

  const ActivityInterface({
    super.key,
    this.targetXpPerLevel = 1000, 
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5), 
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: ProgressService().getUserProgressStream(),
          builder: (context, snapshot) {
            
            int easyXp = 0;
            int mediumXp = 0;
            int hardXp = 0;
            
            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              if (data != null) {
                // --- UPDATED: Now safely reading from alpEasyXp, alpMediumXp, alpHardXp ---
                easyXp = (data['alpEasyXp'] ?? 0).clamp(0, targetXpPerLevel);
                mediumXp = (data['alpMediumXp'] ?? 0).clamp(0, targetXpPerLevel);
                hardXp = (data['alpHardXp'] ?? 0).clamp(0, targetXpPerLevel);
              }
            }

            // Lock next levels based on the previous level's completion
            bool isMediumLocked = easyXp < targetXpPerLevel;
            bool isHardLocked = mediumXp < targetXpPerLevel;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // --- HEADER ---
                Padding(
                  padding: const EdgeInsets.only(left: 20, top: 20, right: 20, bottom: 10),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Icon(Icons.arrow_back_ios, color: Color(0xFF322144), size: 24),
                      ),
                      const SizedBox(width: 16),
                      const Text(
                        'Activities',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 32,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1.92,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // --- LIST OF ACTIVITY CARDS ---
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Column(
                      children: [
                        _buildThemeCard(
                          context: context,
                          title: 'Easy Level',
                          subtitle: 'Basic Signs',
                          currentXp: easyXp,
                          targetXp: targetXpPerLevel,
                          isLocked: false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const EasyActMc()),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        
                        _buildThemeCard(
                          context: context,
                          title: 'Medium Level',
                          subtitle: 'Phrases',
                          currentXp: mediumXp,
                          targetXp: targetXpPerLevel,
                          isLocked: isMediumLocked,
                          onTap: isMediumLocked ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Complete Easy Level (1000 XP) to unlock!"), 
                                backgroundColor: Colors.redAccent
                              ),
                            );
                          } : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Medium challenges are coming soon!")),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        
                        _buildThemeCard(
                          context: context,
                          title: 'Hard Level',
                          subtitle: 'Sentences',
                          currentXp: hardXp,
                          targetXp: targetXpPerLevel,
                          isLocked: isHardLocked,
                          onTap: isHardLocked ? () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Complete Medium Level (1000 XP) to unlock!"), 
                                backgroundColor: Colors.redAccent
                              ),
                            );
                          } : () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Hard challenges are coming soon!")),
                            );
                          },
                        ),
                        const SizedBox(height: 30),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // --- RESTORED ORIGINAL FIGMA THEME CARD ---
  Widget _buildThemeCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required int currentXp,
    required int targetXp,
    required bool isLocked,
    required VoidCallback? onTap,
  }) {
    final double progressRatio = (currentXp / targetXp).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: isLocked ? 0.6 : 1.0,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: ShapeDecoration(
            color: Colors.white, 
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: isLocked 
                  ? const BorderSide(color: Color(0xFFE0E0E0), width: 1)
                  : const BorderSide(color: Color(0xFFFFB800), width: 2), 
            ),
            shadows: const [
              BoxShadow(
                color: Color(0x05132C4A), 
                blurRadius: 16,
                offset: Offset(0, 6),
              )
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF322144), 
                          fontSize: 24,
                          fontFamily: 'Google Sans Flex',
                          fontWeight: FontWeight.w600,
                          letterSpacing: -1.20,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFF888888), 
                          fontSize: 14,
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    isLocked ? Icons.lock_rounded : Icons.play_circle_fill_rounded,
                    color: isLocked ? Colors.grey : const Color(0xFFFFB800),
                    size: 40,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              Row(
                children: [
                  Image.asset(
                    "assets/pictures/star.png",
                    width: 24,
                    height: 24,
                    errorBuilder: (c, o, s) => const Icon(Icons.star, color: Color(0xFFFFB800), size: 24),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$currentXp XP',
                    style: const TextStyle(
                      color: Color(0xFFBA8E23), 
                      fontSize: 20,
                      fontFamily: 'Holtwood One SC', 
                      fontWeight: FontWeight.w400,
                      letterSpacing: -1.20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: 8,
                    decoration: ShapeDecoration(
                      color: const Color(0xFFF1F1FA),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25),
                      ),
                    ),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      return Container(
                        width: constraints.maxWidth * progressRatio,
                        height: 8,
                        decoration: ShapeDecoration(
                          color: const Color(0xFF7DC579), 
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  currentXp >= targetXp ? 'Level Completed! 🎉' : '${targetXp - currentXp} to next',
                  style: TextStyle(
                    color: currentXp >= targetXp ? Colors.green : const Color(0xFF888888),
                    fontSize: 12,
                    fontFamily: 'Google Sans Flex',
                    fontWeight: currentXp >= targetXp ? FontWeight.bold : FontWeight.w400,
                    letterSpacing: -0.60,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}