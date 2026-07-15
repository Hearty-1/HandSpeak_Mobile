import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '/services/progress_service.dart';
import 'easyNumAct_mc.dart'; // Routes to the numbers quiz

class NumbersActivityInterface extends StatelessWidget {
  final int targetXp;

  const NumbersActivityInterface({
    super.key,
    this.targetXp = 1000,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5), 
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: ProgressService().getUserProgressStream(),
          builder: (context, snapshot) {
            
            // 1. Fetch segregated level-specific XP for Numbers from Firestore
            int numEasyXp = 0;
            int numMediumXp = 0;
            int numHardXp = 0;

            if (snapshot.hasData && snapshot.data!.exists) {
              final data = snapshot.data!.data() as Map<String, dynamic>?;
              if (data != null) {
                // Read progress fields, falling back to 0
                numEasyXp = (data['numEasyXp'] ?? 0).clamp(0, targetXp);
                numMediumXp = (data['numMediumXp'] ?? 0).clamp(0, targetXp);
                numHardXp = (data['numHardXp'] ?? 0).clamp(0, targetXp);
              }
            }

            // 2. Lock next levels based on the previous level's completion
            bool isMediumLocked = numEasyXp < targetXp;
            bool isHardLocked = numMediumXp < targetXp;

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
                        'Numbers',
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
                          subtitle: 'Basic Numbers',
                          currentXp: numEasyXp,
                          targetXp: targetXp,
                          isLocked: false,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (context) => const NumbersQuizScreen()),
                            );
                          },
                        ),
                        const SizedBox(height: 20),
                        
                        _buildThemeCard(
                          context: context,
                          title: 'Medium Level',
                          subtitle: 'Double Digits',
                          currentXp: numMediumXp,
                          targetXp: targetXp,
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
                          subtitle: 'Math Signs',
                          currentXp: numHardXp,
                          targetXp: targetXp,
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
                  // --- RESTORED STAR ICON ---
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