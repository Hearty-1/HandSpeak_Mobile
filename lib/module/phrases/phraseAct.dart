import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'phrase_activity.dart';

class ThemedBackground extends StatelessWidget {
  final Color bgColor;

  const ThemedBackground({super.key, required this.bgColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            bgColor,
            bgColor.withOpacity(0.85),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
    );
  }
}

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
  @override
  Widget build(BuildContext context) {
    final scaffoldBgColor = Theme.of(context).scaffoldBackgroundColor;
    final nodeColor = Theme.of(context).primaryColor;
    final String currentDifficulty = widget.difficulty.toLowerCase();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: Theme.of(context).colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          '${currentDifficulty.toUpperCase()} PHRASES',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurface,
            fontSize: 20,
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
            child: StreamBuilder<QuerySnapshot>(
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

                  // Strict filter against non-phrase categories or alphabet leakage
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

                // Sort levels numerically (e.g. phrases_easy_1, phrases_easy_2, phrases_easy_10)
                levelKeys.sort((a, b) {
                  final int numA = int.tryParse(a.split('_').last) ?? 0;
                  final int numB = int.tryParse(b.split('_').last) ?? 0;
                  return numA.compareTo(numB);
                });

                if (levelKeys.isEmpty) {
                  return Center(
                    child: Text(
                      'No levels found for $currentDifficulty mode.',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  physics: const BouncingScrollPhysics(),
                  itemCount: levelKeys.length,
                  itemBuilder: (context, index) {
                    final levelId = levelKeys[index];
                    final levelData = levelsMap[levelId]!;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        leading: CircleAvatar(
                          radius: 24,
                          backgroundColor: nodeColor,
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        title: Text(
                          levelData['title'] ?? 'Level ${index + 1}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        subtitle: Text('Type: ${levelData['type']}'),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => PhraseActivityInterface(
                                levelId: levelId,
                                title: levelData['title'] ?? 'Level ${index + 1}',
                              ),
                            ),
                          );
                        },
                      ),
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