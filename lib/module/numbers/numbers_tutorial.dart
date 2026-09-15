import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'numbers_tutorial_detail.dart';

class NumbersTutorialInterface extends StatefulWidget {
  const NumbersTutorialInterface({super.key});

  @override
  State<NumbersTutorialInterface> createState() => _NumbersTutorialInterfaceState();
}

class _NumbersTutorialInterfaceState extends State<NumbersTutorialInterface> {
  String _searchQuery = "";

  final List<Map<String, dynamic>> _defaultLessons = [
    {'title': '1', 'gestureKey': '1', 'imageUrl': 'assets/pictures/1.png'},
    {'title': '2', 'gestureKey': '2', 'imageUrl': 'assets/pictures/2.png'},
    {'title': '3', 'gestureKey': '3', 'imageUrl': 'assets/pictures/3.png'},
    {'title': '4', 'gestureKey': '4', 'imageUrl': 'assets/pictures/4.png'},
    {'title': '5', 'gestureKey': '5', 'imageUrl': 'assets/pictures/5.png'},
    {'title': '6', 'gestureKey': '6', 'imageUrl': 'assets/pictures/6.png'},
    {'title': '7', 'gestureKey': '7', 'imageUrl': 'assets/pictures/7.png'},
    {'title': '8', 'gestureKey': '8', 'imageUrl': 'assets/pictures/8.png'},
    {'title': '9', 'gestureKey': '9', 'imageUrl': 'assets/pictures/9.png'},
    {'title': '10', 'gestureKey': '10', 'imageUrl': 'assets/pictures/10.png'},
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
        backgroundColor: theme.cardColor.withOpacity(0.4),
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: theme.colorScheme.onSurface),
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
            child: Container(color: Colors.transparent),
          ),
        ),
        title: Text(
          'Number List',
          style: TextStyle(
            color: theme.colorScheme.onSurface,
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
            top: -50,
            left: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.primaryColor.withOpacity(0.25),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -80,
            child: Container(
              width: 280,
              height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.secondary.withOpacity(0.15),
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20.0, 15.0, 20.0, 10.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          color: theme.cardColor.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: theme.colorScheme.surface.withOpacity(0.7), width: 1.5),
                        ),
                        child: TextField(
                          onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()),
                          style: TextStyle(color: theme.colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Search number...',
                            hintStyle: TextStyle(color: theme.colorScheme.onSurface.withOpacity(0.5), fontWeight: FontWeight.w500),
                            prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurface.withOpacity(0.5)),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('tutorial_lessons')
                        .where('category', isEqualTo: 'numbers')
                        .snapshots(),
                    builder: (context, cmsSnapshot) {
                      List<Map<String, dynamic>> mergedLessons = List.from(_defaultLessons);

                      if (cmsSnapshot.hasData && cmsSnapshot.data!.docs.isNotEmpty) {
                        final firestoreLessons = cmsSnapshot.data!.docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return {
                            'id': doc.id,
                            'title': data['displayTitle']?.toString() ?? data['gestureKey']?.toString() ?? '',
                            'gestureKey': data['gestureKey']?.toString() ?? '',
                            'imageUrl': data['imageUrl']?.toString() ?? data['imagePath']?.toString() ?? '',
                          };
                        }).toList();

                        for (var fsLesson in firestoreLessons) {
                          int existingIndex = mergedLessons.indexWhere((loc) =>
                              loc['gestureKey'].toString() == fsLesson['gestureKey'].toString());

                          if (existingIndex != -1) {
                            mergedLessons[existingIndex] = fsLesson;
                          } else {
                            mergedLessons.add(fsLesson);
                          }
                        }
                      }

                      mergedLessons.sort((a, b) {
                        int numA = int.tryParse(a['gestureKey'].toString()) ?? 0;
                        int numB = int.tryParse(b['gestureKey'].toString()) ?? 0;
                        return numA.compareTo(numB);
                      });

                      final List<Map<String, dynamic>> finalDisplayList = [];
                      for (int i = 0; i < mergedLessons.length; i++) {
                        final lesson = mergedLessons[i];
                        if (lesson['title']!.toLowerCase().contains(_searchQuery)) {
                          finalDisplayList.add({
                            ...lesson,
                            'originalIndex': i,
                          });
                        }
                      }

                      if (finalDisplayList.isEmpty) {
                        return Center(
                          child: Text(
                            "No numbers found.",
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        itemCount: finalDisplayList.length,
                        itemBuilder: (context, index) {
                          final lesson = finalDisplayList[index];

                          return LessonCard(
                            title: lesson['title']!,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => NumbersTutorialDetail(
                                    initialIndex: lesson['originalIndex'],
                                    dynamicLessons: mergedLessons,
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class LessonCard extends StatelessWidget {
  final String title;
  final VoidCallback onTap;

  const LessonCard({
    super.key,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
              decoration: BoxDecoration(
                color: theme.cardColor.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.primaryColor.withOpacity(0.5),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      fontFamily: 'Inter',
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withOpacity(0.3),
                          blurRadius: 8,
                          spreadRadius: 1,
                        )
                      ],
                    ),
                    child: Icon(Icons.play_arrow_rounded, color: theme.primaryColor, size: 22),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}