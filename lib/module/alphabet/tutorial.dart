import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tutorial_interface_3.dart'; 

class TutorialInterface extends StatefulWidget {
  const TutorialInterface({super.key});

  @override
  State<TutorialInterface> createState() => _TutorialInterfaceState();
}

class _TutorialInterfaceState extends State<TutorialInterface> {
  String _searchQuery = ""; 

  // 1. Define the default local fallback list
  final List<Map<String, dynamic>> _defaultLessons = [
    {'title': 'Aa', 'gestureKey': 'A', 'imageUrl': 'assets/pictures/A.jpg'},
    {'title': 'Bb', 'gestureKey': 'B', 'imageUrl': 'assets/pictures/B.jpg'},
    {'title': 'Cc', 'gestureKey': 'C', 'imageUrl': 'assets/pictures/C.jpg'},
    {'title': 'Dd', 'gestureKey': 'D', 'imageUrl': 'assets/pictures/D.jpg'},
    {'title': 'Ee', 'gestureKey': 'E', 'imageUrl': 'assets/pictures/E.jpg'},
    {'title': 'Ff', 'gestureKey': 'F', 'imageUrl': 'assets/pictures/F.jpg'},
    {'title': 'Gg', 'gestureKey': 'G', 'imageUrl': 'assets/pictures/G.jpg'},
    {'title': 'Hh', 'gestureKey': 'H', 'imageUrl': 'assets/pictures/H.jpg'},
    {'title': 'Ii', 'gestureKey': 'I', 'imageUrl': 'assets/pictures/I.jpg'},
    {'title': 'Jj', 'gestureKey': 'J', 'imageUrl': 'assets/pictures/J.jpg'},
    {'title': 'Kk', 'gestureKey': 'K', 'imageUrl': 'assets/pictures/K.jpg'},
    {'title': 'Ll', 'gestureKey': 'L', 'imageUrl': 'assets/pictures/L.jpg'},
    {'title': 'Mm', 'gestureKey': 'M', 'imageUrl': 'assets/pictures/M.jpg'},
    {'title': 'Nn', 'gestureKey': 'N', 'imageUrl': 'assets/pictures/N.jpg'},
    {'title': 'Oo', 'gestureKey': 'O', 'imageUrl': 'assets/pictures/O.jpg'},
    {'title': 'Pp', 'gestureKey': 'P', 'imageUrl': 'assets/pictures/P.jpg'},
    {'title': 'Qq', 'gestureKey': 'Q', 'imageUrl': 'assets/pictures/Q.jpg'},
    {'title': 'Rr', 'gestureKey': 'R', 'imageUrl': 'assets/pictures/R.jpg'},
    {'title': 'Ss', 'gestureKey': 'S', 'imageUrl': 'assets/pictures/S.jpg'},
    {'title': 'Tt', 'gestureKey': 'T', 'imageUrl': 'assets/pictures/T.jpg'},
    {'title': 'Uu', 'gestureKey': 'U', 'imageUrl': 'assets/pictures/U.jpg'},
    {'title': 'Vv', 'gestureKey': 'V', 'imageUrl': 'assets/pictures/V.jpg'},
    {'title': 'Ww', 'gestureKey': 'W', 'imageUrl': 'assets/pictures/W.jpg'},
    {'title': 'Xx', 'gestureKey': 'X', 'imageUrl': 'assets/pictures/X.jpg'},
    {'title': 'Yy', 'gestureKey': 'Y', 'imageUrl': 'assets/pictures/Y.jpg'},
    {'title': 'Zz', 'gestureKey': 'Z', 'imageUrl': 'assets/pictures/Z.jpg'},
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
      
      // --- GLASSMORPHISM APP BAR ---
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
          'Tutorial List',
          style: TextStyle(
            color: theme.colorScheme.onSurface, 
            fontSize: 22, 
            fontFamily: 'Inter', 
            fontWeight: FontWeight.w800, 
            letterSpacing: -0.96
          ),
        ),
      ),
      
      body: Stack(
        children: [
          // Ambient Color Blobs
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

          // Main View Content
          SafeArea(
            child: Column(
              children: [
                // Glassmorphism Search Bar Container
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
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03), 
                              blurRadius: 8, 
                              offset: const Offset(0, 3)
                            )
                          ],
                        ),
                        child: TextField(
                          onChanged: (value) => setState(() => _searchQuery = value.toLowerCase()), 
                          style: TextStyle(color: theme.colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'Search letter...',
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
                
                // Hybrid StreamBuilder
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('tutorial_lessons')
                        .where('category', isEqualTo: 'alphabet')
                        .snapshots(),
                    builder: (context, snapshot) {
                      // 2. Start with a clone of the local data
                      List<Map<String, dynamic>> mergedLessons = List.from(_defaultLessons);

                      // 3. If Firestore has data, merge it into our local list
                      if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
                        final firestoreLessons = snapshot.data!.docs.map((doc) {
                          final data = doc.data() as Map<String, dynamic>;
                          return {
                            'id': doc.id,
                            'title': data['displayTitle']?.toString() ?? data['gestureKey']?.toString() ?? '',
                            'gestureKey': data['gestureKey']?.toString() ?? '',
                            'imageUrl': data['imageUrl']?.toString() ?? '',
                          };
                        }).toList();

                        for (var fsLesson in firestoreLessons) {
                          // Check if this letter already exists in our default list
                          int existingIndex = mergedLessons.indexWhere((loc) => 
                              loc['gestureKey'].toString().toUpperCase() == fsLesson['gestureKey'].toString().toUpperCase()
                          );
                          
                          if (existingIndex != -1) {
                            // Replace local version with the cloud version
                            mergedLessons[existingIndex] = fsLesson;
                          } else {
                            // Add completely new letter to the list
                            mergedLessons.add(fsLesson);
                          }
                        }
                      }

                      // Sort the final merged list alphabetically by gestureKey
                      mergedLessons.sort((a, b) => (a['gestureKey'] as String).compareTo(b['gestureKey'] as String));

                      // 4. Apply local search filter to the merged list
                      final filteredLessons = mergedLessons.where((lesson) =>
                          lesson['title']!.toLowerCase().contains(_searchQuery)).toList();

                      if (filteredLessons.isEmpty) {
                         return Center(child: Text("No letters found.", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface.withOpacity(0.7))));
                      }

                      return ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        itemCount: filteredLessons.length, 
                        itemBuilder: (context, index) {
                          final lesson = filteredLessons[index];
                          final bool isLocked = false; 
                          
                          return LessonCard(
                            title: lesson['title']!,
                            isLocked: isLocked,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => TutorialInterface3(
                                    initialIndex: index,
                                    dynamicLessons: filteredLessons, 
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    }
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
  final bool isLocked;
  final VoidCallback onTap;

  const LessonCard({
    super.key,
    required this.title,
    required this.isLocked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Opacity(
            opacity: isLocked ? 0.6 : 1.0,
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                decoration: BoxDecoration(
                  color: isLocked 
                      ? theme.cardColor.withOpacity(0.2) 
                      : theme.cardColor.withOpacity(0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isLocked 
                        ? theme.colorScheme.surface.withOpacity(0.4) 
                        : theme.primaryColor.withOpacity(0.5), 
                    width: 1.5
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04), 
                      blurRadius: 10, 
                      offset: const Offset(0, 4)
                    )
                  ],
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
                        color: isLocked 
                            ? theme.colorScheme.onSurface.withOpacity(0.4) 
                            : theme.colorScheme.onSurface,
                        letterSpacing: -1.0,
                      ),
                    ),
                    isLocked
                        ? Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.lock_outline, color: theme.colorScheme.onSurface.withOpacity(0.5), size: 22),
                          )
                        : Container(
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
                            child: Icon(
                              Icons.play_arrow_rounded, 
                              color: theme.primaryColor,
                              size: 22,
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}