import 'dart:ui'; 
import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; 
import 'package:flutter_application_1/module/alphabet/alphabet_interface.dart'; 
import 'package:flutter_application_1/module/numbers/numbers_interface.dart'; 
import '../services/progress_service.dart'; 
import '../module/module.dart'; 
import '../module/phrases/phrase_interface.dart';
import '../module/civic/civic_interface.dart';
import '../profile/profile.dart'; 
import '../leaderboard/arena.dart'; 
import '../home/settings_screen.dart';
import '../widgets/app_nav_bar.dart';
import '/services/performance_monitor.dart';
import '/auth/login_screen.dart';
import '/auth/role_selection_screen.dart';
import '/services/role_service.dart';
import '/module/alphabet/tutorial_practice.dart' show TutorialPractice;

import '../home/notification_bell.dart'; // Added import for the standardized bell

void main() {
  runApp(const FigmaToCodeApp()); 
}

class FigmaToCodeApp extends StatelessWidget {
  const FigmaToCodeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, 
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFFFF9E5), 
        primaryColor: const Color(0xFFFFB800),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFFFB800),
          secondary: Color(0xFFFF8227),
          onPrimary: Colors.white,
          onSurface: Color(0xFF222222),
        ),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardColor: const Color(0xFF1E1E1E),
        primaryColor: const Color(0xFFFFB800),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFFB800),
          secondary: Color(0xFFFF8227),
          onPrimary: Colors.black,
          onSurface: Colors.white,
        ),
      ),
      home: const SnedInterafce1(userName: "Student"), 
    );
  }
}

Route _fadeRoute(Widget page) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(opacity: animation, child: child);
    },
    transitionDuration: const Duration(milliseconds: 180),
  );
}

class SnedInterafce1 extends StatelessWidget {
  final String userName; 

  const SnedInterafce1({super.key, required this.userName}); 

  Widget _buildAvatarImage(BuildContext context, String? avatarData, double scale, {double size = 48}) {
    final theme = Theme.of(context);
    if (avatarData == null || avatarData.isEmpty) {
      return Icon(Icons.person, color: theme.primaryColor, size: 26 * scale);
    }
    
    if (avatarData.startsWith('data:image')) {
      try {
        final String base64String = avatarData.split(',').last;
        final Uint8List bytes = base64Decode(base64String);
        return Image.memory(bytes, width: size * scale, height: size * scale, fit: BoxFit.cover);
      } catch (e) {
        return Icon(Icons.broken_image_rounded, color: theme.disabledColor, size: 26 * scale);
      }
    } else {
      return Image.network(
        avatarData,
        width: size * scale,
        height: size * scale,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Icon(Icons.person, color: theme.primaryColor, size: 26 * scale),
      );
    }
  }

  static const int _moduleTargetXp = 1000; // XP that completes a module (module.dart)

  static String _moduleOf(String raw) {
    final k = raw.toLowerCase().trim();
    if (k.contains('number')) return 'numbers';
    if (k.contains('phrase') || k.contains('word') || k.contains('common')) return 'common words';
    if (k.contains('civic')) return 'civic';
    if (k.contains('alpha') || k.contains('letter')) return 'alphabet';
    return '';
  }

  /// The two most recently opened modules (latest first), filling [moduleXp]
  /// and [lastOpened] for their cards. Order: `moduleLastOpened` timestamps,
  /// then the legacy `recentModules` list (newest entries last). Locked
  /// modules are skipped; Alphabet / Numbers fill in for new learners.
  static List<String> _latestModules(
    Map<String, dynamic> data,
    Map<String, int> moduleXp,
    Map<String, DateTime> lastOpened,
  ) {
    int xp(String field) => (data[field] as num?)?.toInt() ?? 0;
    final mapped = <String, int>{};
    final progress = data['progress'];
    if (progress is Map) {
      progress.forEach((key, value) {
        final m = _moduleOf('$key');
        if (m.isNotEmpty && value is num) mapped[m] = (mapped[m] ?? 0) + value.toInt();
      });
    }
    final fields = {
      'alphabet': xp('alphabetXp'),
      'numbers': xp('numbersXp'),
      'common words': math.max(xp('phraseXp'), xp('wordsXp')),
      'civic': math.max(xp('civicXp'), xp('civicsXp')),
    };
    for (final m in fields.keys) {
      moduleXp[m] = math.max(fields[m]!, mapped[m] ?? 0);
    }

    final opened = data['moduleLastOpened'];
    if (opened is Map) {
      opened.forEach((key, value) {
        final m = _moduleOf('$key');
        if (m.isNotEmpty && value is Timestamp) lastOpened[m] = value.toDate();
      });
    }

    final wordsLocked = moduleXp['alphabet']! < _moduleTargetXp;
    final civicLocked = wordsLocked || moduleXp['common words']! < _moduleTargetXp;
    bool unlocked(String m) => !(m == 'common words' && wordsLocked) && !(m == 'civic' && civicLocked);

    final byTime = lastOpened.keys.toList()..sort((a, b) => lastOpened[b]!.compareTo(lastOpened[a]!));
    final legacy = [
      for (final e in ((data['recentModules'] as List?) ?? const []).reversed) _moduleOf('$e'),
    ];
    final ordered = <String>[];
    for (final m in [...byTime, ...legacy, 'alphabet', 'numbers']) {
      if (m.isNotEmpty && unlocked(m) && !ordered.contains(m)) ordered.add(m);
    }
    return ordered.take(2).toList();
  }

  static String _timeAgo(DateTime? t) {
    if (t == null) return 'Start learning';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return '${d.inDays} days ago';
    return '${t.month}/${t.day}/${t.year}';
  }

  /// "Continue Learning" shortcut: module art, name, last opened and the
  /// module's XP progress; tapping resumes the module.
  Widget _buildContinueCard(BuildContext context, String moduleKey, int xp, DateTime? opened, double scale) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final (String title, String imagePath, Widget Function(int) screen) = switch (moduleKey) {
      'numbers' => ('Numbers', 'assets/pictures/numbers.png', (int x) => NumbersInterface(currentXp: x, targetXp: _moduleTargetXp)),
      'common words' => ('Words/Phrases', 'assets/pictures/words.png', (int x) => PhraseInterface(currentXp: x, targetXp: _moduleTargetXp)),
      'civic' => ('Civic Observances', 'assets/pictures/civic.png', (int x) => CivicInterface(currentXp: x, targetXp: _moduleTargetXp)),
      _ => ('Alphabet', 'assets/pictures/abc.png', (int x) => AlphabetInterface(currentXp: x, targetXp: _moduleTargetXp)),
    };
    final shownXp = math.min(xp, _moduleTargetXp);
    final progress = shownXp / _moduleTargetXp;
    final complete = xp >= _moduleTargetXp;
    final accent = complete ? Colors.green : theme.primaryColor;

    return GestureDetector(
      onTap: () {
        ProgressService().trackRecentModule(moduleKey);
        Navigator.push(context, _fadeRoute(screen(shownXp)));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24 * scale),
        clipBehavior: Clip.antiAlias,
        child: SmartBlur(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: EdgeInsets.all(16 * scale),
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(24 * scale),
              border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 58 * scale,
                      width: 58 * scale,
                      padding: EdgeInsets.all(10 * scale),
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor.withOpacity(0.8),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))],
                      ),
                      child: Image.asset(imagePath, fit: BoxFit.contain),
                    ),
                    const Spacer(),
                    Container(
                      padding: EdgeInsets.all(7 * scale),
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 18 * scale),
                    ),
                  ],
                ),
                SizedBox(height: 14 * scale),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.w800, letterSpacing: -0.3, height: 1.15),
                ),
                SizedBox(height: 4 * scale),
                Row(
                  children: [
                    Icon(Icons.history_rounded, size: 13 * scale, color: textColor.withOpacity(0.5)),
                    SizedBox(width: 4 * scale),
                    Flexible(
                      child: Text(
                        _timeAgo(opened),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textColor.withOpacity(0.55), fontSize: 12 * scale, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                if (context.roles.can(AppFeature.progress)) ...[
                  const Spacer(),
                  SizedBox(height: 12 * scale),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6 * scale),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 7 * scale,
                      backgroundColor: theme.dividerColor.withOpacity(0.15),
                      color: accent,
                    ),
                  ),
                  SizedBox(height: 6 * scale),
                  Text(
                    complete ? 'Completed' : '$shownXp / $_moduleTargetXp XP',
                    style: TextStyle(color: complete ? Colors.green : textColor.withOpacity(0.6), fontSize: 11.5 * scale, fontWeight: FontWeight.w700),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Guest home (Faculty / Parent): no XP, no recent progress. Instead: a sign
  // of the day to practise, every module's tutorials, and a role tip.
  // ---------------------------------------------------------------------------

  static const _guestModules = <({String key, String title, String blurb, String image, IconData icon})>[
    (key: 'alphabet', title: 'Alphabet', blurb: 'A–Z hand signs', image: 'assets/pictures/abc.png', icon: Icons.abc_rounded),
    (key: 'numbers', title: 'Numbers', blurb: 'Counting signs', image: 'assets/pictures/numbers.png', icon: Icons.pin_rounded),
    (key: 'common words', title: 'Words/Phrases', blurb: 'Everyday greetings', image: 'assets/pictures/words.png', icon: Icons.forum_rounded),
    (key: 'civic', title: 'Civic Observances', blurb: 'Lupang Hinirang', image: 'assets/pictures/civic.png', icon: Icons.flag_rounded),
  ];

  static Widget _moduleScreen(String key) => switch (key) {
        'numbers' => const NumbersInterface(currentXp: 0, targetXp: _moduleTargetXp),
        'common words' => const PhraseInterface(currentXp: 0, targetXp: _moduleTargetXp),
        'civic' => const CivicInterface(currentXp: 0, targetXp: _moduleTargetXp),
        _ => const AlphabetInterface(currentXp: 0, targetXp: _moduleTargetXp),
      };

  /// Same letter for everyone on a given day (A-Z, rotating daily).
  static String _signOfTheDay() {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day).difference(DateTime(2024)).inDays;
    return String.fromCharCode('A'.codeUnitAt(0) + day % 26);
  }

  Widget _sectionTitle(BuildContext context, String title, double scale, {String? subtitle}) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(color: textColor, fontSize: 20 * scale, fontWeight: FontWeight.bold, letterSpacing: -0.5)),
        if (subtitle != null) ...[
          SizedBox(height: 2 * scale),
          Text(subtitle, style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 13 * scale, fontWeight: FontWeight.w500)),
        ],
        SizedBox(height: 14 * scale),
      ],
    );
  }

  Widget _buildSignOfTheDay(BuildContext context, double scale) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final letter = _signOfTheDay();
    return GestureDetector(
      onTap: () => Navigator.push(context, _fadeRoute(TutorialPractice(targetLetter: letter))),
      child: _buildGlassContainer(
        context: context,
        scale: scale,
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18 * scale),
              child: Container(
                width: 92 * scale,
                height: 92 * scale,
                color: theme.scaffoldBackgroundColor.withOpacity(0.8),
                child: Image.asset(
                  'assets/pictures/$letter.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(letter, style: TextStyle(fontSize: 44 * scale, fontWeight: FontWeight.w900, color: theme.primaryColor)),
                  ),
                ),
              ),
            ),
            SizedBox(width: 16 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Letter $letter',
                    style: TextStyle(color: textColor, fontSize: 24 * scale, fontWeight: FontWeight.w900, letterSpacing: -0.6),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    'Copy the handshape, then try it on camera.',
                    style: TextStyle(color: textColor.withOpacity(0.65), fontSize: 13 * scale, fontWeight: FontWeight.w500, height: 1.3),
                  ),
                  SizedBox(height: 10 * scale),
                  Row(
                    children: [
                      Icon(Icons.videocam_rounded, size: 16 * scale, color: theme.primaryColor),
                      SizedBox(width: 6 * scale),
                      Text('Practice this sign',
                          style: TextStyle(color: theme.primaryColor, fontSize: 13.5 * scale, fontWeight: FontWeight.w800)),
                      SizedBox(width: 2 * scale),
                      Icon(Icons.chevron_right_rounded, size: 18 * scale, color: theme.primaryColor),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestModuleTile(
      BuildContext context, ({String key, String title, String blurb, String image, IconData icon}) m, double scale) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    return GestureDetector(
      onTap: () => Navigator.push(context, _fadeRoute(_moduleScreen(m.key))),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22 * scale),
        clipBehavior: Clip.antiAlias,
        child: SmartBlur(
          filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
          child: Container(
            padding: EdgeInsets.all(14 * scale),
            decoration: BoxDecoration(
              color: theme.cardColor.withOpacity(0.6),
              borderRadius: BorderRadius.circular(22 * scale),
              border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 16, offset: const Offset(0, 8))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      height: 50 * scale,
                      width: 50 * scale,
                      padding: EdgeInsets.all(9 * scale),
                      decoration: BoxDecoration(
                        color: theme.scaffoldBackgroundColor.withOpacity(0.8),
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(m.image, fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Icon(m.icon, color: theme.primaryColor)),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_forward_rounded, size: 18 * scale, color: textColor.withOpacity(0.4)),
                  ],
                ),
                SizedBox(height: 12 * scale),
                Text(
                  m.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor, fontSize: 15.5 * scale, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
                SizedBox(height: 2 * scale),
                Text(
                  m.blurb,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 12 * scale, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuestTip(BuildContext context, UserRole role, double scale) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final (IconData icon, String title, String body) = role == UserRole.parent
        ? (
            Icons.family_restroom_rounded,
            'Learn together',
            'Pick one sign a day and practise it with your child. Let them teach it back to you. It is the fastest way to remember.',
          )
        : (
            Icons.co_present_rounded,
            'Teaching tip',
            'Use the tutorial videos to introduce a sign in class. Students log in with their own accounts to play activities and earn XP.',
          );
    return _buildGlassContainer(
      context: context,
      scale: scale,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(10 * scale),
            decoration: BoxDecoration(color: theme.colorScheme.secondary.withOpacity(0.18), shape: BoxShape.circle),
            child: Icon(icon, color: theme.colorScheme.secondary, size: 26 * scale),
          ),
          SizedBox(width: 14 * scale),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.w800)),
                SizedBox(height: 4 * scale),
                Text(body,
                    style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 13 * scale, fontWeight: FontWeight.w500, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGuestSections(BuildContext context, UserRole role, double scale) => [
        _sectionTitle(context, 'Sign of the Day', scale),
        _buildSignOfTheDay(context, scale),
        SizedBox(height: 28 * scale),
        _sectionTitle(context, 'Explore the Modules', scale, subtitle: 'Watch the tutorials and practise each sign on camera.'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          mainAxisSpacing: 14 * scale,
          crossAxisSpacing: 14 * scale,
          childAspectRatio: 1.1,
          children: [for (final m in _guestModules) _buildGuestModuleTile(context, m, scale)],
        ),
        SizedBox(height: 28 * scale),
        _buildGuestTip(context, role, scale),
      ];

  Widget _buildDailyTreasureCard(BuildContext context, double scale, String subtitle) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          _fadeRoute(const LeaderboardScreen(initialTab: 'challenges')),
        );
      },
      child: _buildGlassContainer(
        context: context,
        scale: scale,
        color: const Color(0xFFFF8227).withOpacity(0.85), 
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10 * scale),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.25),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.redeem_rounded, color: Colors.white, size: 36 * scale),
            ),
            SizedBox(width: 16 * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily Challenges!', 
                    style: TextStyle(
                      color: Colors.white, 
                      fontSize: 18 * scale, 
                      fontWeight: FontWeight.w900, 
                      letterSpacing: -0.5,
                    ), 
                  ),
                  SizedBox(height: 4 * scale),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9), 
                      fontSize: 13 * scale, 
                      fontWeight: FontWeight.w600,
                    ), 
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withOpacity(0.8), size: 20 * scale),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final isDark = theme.brightness == Brightness.dark;

    // Role-based access (Student = everything; Faculty / Parent = tutorials + practice).
    final roles = context.roles;
    final bool isGuest = roles.isGuest;
    final bool canProgress = roles.can(AppFeature.progress);
    final bool canChallenges = roles.can(AppFeature.challenges);
    final bool canProfile = roles.can(AppFeature.profile);
    final bool canNotifications = roles.can(AppFeature.notifications);

    final double screenWidth = MediaQuery.of(context).size.width; 
    final double scale = screenWidth / 393 > 1.2 ? 1.2 : screenWidth / 393; 

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      ),
    );

    return StreamBuilder<DocumentSnapshot>(
      stream: ProgressService().getUserProgressStream(), 
      builder: (context, userSnapshot) {
        String studentName = isGuest ? roles.roleLabel : userName; 
        int streak = 0; 
        int totalXp = 0; 
        int stars = 0; 
        String? avatarUrl; 
        List<String> recentModules = [];
        String questSubtitle = 'Your personalised quests are ready!';

        // Continue Learning: per-module XP + when each module was last opened.
        final moduleXp = <String, int>{for (final m in ProgressService.modules) m: 0};
        final lastOpened = <String, DateTime>{};

        if (userSnapshot.hasData && userSnapshot.data!.exists) { 
          final userData = userSnapshot.data!.data() as Map<String, dynamic>?; 
          if (userData != null) {
            final quests = userData['dailyChallenges'];
            if (quests is List && quests.isNotEmpty) {
              final done = Set<String>.from(userData['completedDailyChallenges'] ?? const []);
              final claimedToday = quests.where((q) => q is Map && done.contains(q['id'])).length;
              final lp = userData['learnerProfile'];
              final pace = lp is Map
                  ? const {'starter': 'Getting Started', 'steady': 'Steady Pace', 'balanced': 'Balanced', 'fast': 'Fast Track'}[lp['pace']]
                  : null;
              questSubtitle = claimedToday >= quests.length
                  ? 'All ${quests.length} quests done today. Great work!'
                  : '$claimedToday of ${quests.length} quests done${pace != null ? ' · $pace' : ''}';
            }
            studentName = userData['name'] ?? userData['displayName'] ?? studentName; 
            streak = userData['streak'] ?? 0; 
            totalXp = userData['xp'] ?? 0; 
            stars = userData['stars'] ?? (totalXp ~/ 1000);  
            avatarUrl = userData['avatar'] ?? userData['photoURL']; 

            recentModules = _latestModules(userData, moduleXp, lastOpened);
          }
        }

        if (recentModules.isEmpty) {
          recentModules = ['alphabet', 'numbers'];
        }

        int targetXp = 1000; 
        int currentLevel = (totalXp ~/ targetXp) + 1; 
        int xpInLevel = totalXp % targetXp; 
        double progressRatio = xpInLevel / targetXp; 

        return Scaffold(
          extendBodyBehindAppBar: true, 
          extendBody: true, 
          backgroundColor: theme.scaffoldBackgroundColor, 
          
          drawer: Drawer(
            backgroundColor: theme.cardColor.withOpacity(0.95), 
            elevation: 0,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 60, bottom: 20, left: 20, right: 20), 
                  decoration: BoxDecoration(
                    color: theme.primaryColor, 
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset("assets/pictures/logo.png", width: 60), 
                          const SizedBox(width: 10),
                          Image.asset("assets/pictures/image 66.png", width: 60), 
                        ],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Menu', 
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isGuest) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${roles.roleLabel} access',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary.withOpacity(0.85),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 10), 
                    children: [
                      ListTile(
                        leading: Icon(Icons.settings, color: theme.primaryColor), 
                        title: Text('Settings', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)), 
                        onTap: () {
                          Navigator.pop(context); 
                          Navigator.push(context, _fadeRoute(const SettingsScreen()));
                        }, 
                      ),
                      ListTile(
                        leading: Icon(Icons.help_outline, color: theme.primaryColor), 
                        title: Text('Help & Support', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)), 
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, _fadeRoute(const InfoDetailScreen(
                            title: 'Help & Support',
                            sections: [
                              InfoSection(
                                title: 'The Learning Loop',
                                body: 'Your Filipino Sign Language learning path is divided into four stages: Tutorials, Practice, Activities, and Challenges. Achieve 1000 XP points to unlock the next module.',
                                icon: Icons.loop_rounded,
                              ),
                              InfoSection(
                                title: 'Camera Combat',
                                body: 'Ensure you are in a well-lit area and use the Mirror-Mode Camera. A green checkmark means you scored a hit, while a red "X" means you need to adjust your form.',
                                icon: Icons.camera_alt_rounded,
                              ),
                              InfoSection(
                                title: 'Leveling Up & Streaks',
                                body: 'Keep practicing to earn Experience Points (XP) and fill your Level Progress Bar. Enable Streak Reminders to keep your momentum going.',
                                icon: Icons.local_fire_department_rounded,
                              ),
                              InfoSection(
                                title: 'Multiplayer Challenges',
                                body: 'Challenge your classmates by tapping "Join a Room" and entering a Room Code, or act as the host by selecting "Create a Room".',
                                icon: Icons.group_rounded,
                              ),
                              InfoSection(
                                title: 'Customizing Experience',
                                body: 'Visit the Settings screen to change your game Theme (like Galaxy Explorer or Deep Ocean), and toggle your Background Music on or off.',
                                icon: Icons.palette_rounded,
                              ),
                              InfoSection(
                                title: 'Reporting Bugs',
                                body: 'Teachers can submit a bug report directly to the admin using the "Feedback & Support" tool. Students should report issues to their teachers.',
                                icon: Icons.bug_report_rounded,
                              ),
                            ],
                          )));
                        }, 
                      ),
                      ListTile(
                        leading: Icon(Icons.info_outline, color: theme.primaryColor), 
                        title: Text('About Us', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)), 
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, _fadeRoute(const AboutUsScreen()));
                        }, 
                      ),
                      ListTile(
                        leading: Icon(Icons.gavel_rounded, color: theme.primaryColor), 
                        title: Text('Terms & Privacy Policy', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)), 
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, _fadeRoute(const InfoDetailScreen(
                            title: 'Terms of Service & Privacy Policy',
                            sections: [
                              InfoSection(
                                title: '1. Acceptance of Terms',
                                body: 'By downloading, installing, accessing, or using the HandSpeak application, you acknowledge that you have read, understood, and agree to be bound by these Terms of Service. If you do not agree to these terms, you must discontinue use immediately.',
                                icon: Icons.handshake_rounded,
                              ),
                              InfoSection(
                                title: '2. Eligibility & Access',
                                body: 'Access to the HandSpeak platform is expressly restricted to authorized personnel, faculty, and enrolled students of Sto. Tomas North Central School (STNCS). All new registrations are subject to administrative review and remain in a "Pending" status until formally verified.',
                                icon: Icons.admin_panel_settings_rounded,
                              ),
                              InfoSection(
                                title: '3. Account Security',
                                body: 'Users are solely responsible for maintaining the confidentiality of their account credentials. HandSpeak assumes no liability for any loss, damage, or unauthorized access arising from a user\'s failure to secure their account information.',
                                icon: Icons.lock_person_rounded,
                              ),
                              InfoSection(
                                title: '4. Device Permissions',
                                body: 'The application requires access to your device\'s camera to facilitate real-time gesture recognition. By using the app, you grant explicit consent for this hardware access required for core functionality.',
                                icon: Icons.perm_camera_mic_rounded,
                              ),
                              InfoSection(
                                title: '5. Content & Moderation',
                                body: 'All user-generated content, instructional materials, and dataset modifications submitted by faculty members are subject to administrative review. We reserve the right to modify, restrict, or remove any content at our sole discretion to maintain educational integrity.',
                                icon: Icons.rule_rounded,
                              ),
                              InfoSection(
                                title: '6. Limitation of Liability',
                                body: 'HandSpeak is provided on an "AS IS" and "AS AVAILABLE" basis. The developers disclaim all warranties, express or implied, including accuracy of gesture recognition. In no event shall the developers be liable for direct, indirect, incidental, or consequential damages resulting from app usage.',
                                icon: Icons.warning_amber_rounded,
                              ),
                              InfoSection(
                                title: '7. Data Collection (Player Profiles)',
                                body: 'We collect essential details to build your player profile—such as your Full Name, Email, Student ID, Grade Level, and Section. This information is required for account generation and system security.',
                                icon: Icons.person_rounded,
                              ),
                              InfoSection(
                                title: '8. Privacy & Stats Tracking',
                                body: 'We track your gameplay stats—including module completion rates, experience points (XP), earned badges, and gesture accuracy scores. This ensures your progress is accurately recorded and saved.',
                                icon: Icons.analytics_rounded,
                              ),
                              InfoSection(
                                title: '9. Teacher Analytics',
                                body: 'Your performance data is securely beamed to a cloud database so your teachers can view descriptive and predictive analytics. This aids educators in tailoring your learning interventions while maintaining strict role-based access control (RBAC).',
                                icon: Icons.school_rounded,
                              )
                            ],
                          )));
                        }, 
                      ),
                      ListTile(
  leading: Icon(isGuest ? Icons.swap_horiz_rounded : Icons.logout_rounded, color: const Color(0xFFF34B1B)), 
  title: Text(isGuest ? 'Change Role' : 'Sign Out', style: const TextStyle(color: Color(0xFFF34B1B), fontWeight: FontWeight.w600)), 
  onTap: () async {
    if (isGuest) {
      // Faculty / Parent have no account: just leave guest mode and ask for a role again.
      await context.read<RoleProvider>().clear();
      if (!context.mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const RoleSelectionScreen()),
        (route) => false,
      );
      return;
    }
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (context) => const SnedStudentLogin()), 
      (route) => false
    );
  }, 
),
                    ],
                  ),
                ),
              ],
            ),
          ),

          appBar: AppBar(
            toolbarHeight: 65,
            backgroundColor: theme.cardColor.withOpacity(0.4),
            elevation: 0,
            centerTitle: true,
            iconTheme: theme.iconTheme.copyWith(color: textColor),
            flexibleSpace: ClipRRect(
              clipBehavior: Clip.antiAlias,
              child: SmartBlur(
                filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                child: Container(color: Colors.transparent),
              ),
            ),
            title: Text(
              "Home", 
              style: TextStyle(color: textColor, fontWeight: FontWeight.w700, letterSpacing: -0.5),
            ),
            actions: [
              if (canNotifications) const NotificationBell(),
              Padding(
                padding: const EdgeInsets.only(right: 16.0, left: 8.0),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
                  ),
                  child: ClipOval(
                    child: Image.asset(
                      "assets/pictures/image 66.png", 
                      width: 40, 
                      height: 40, 
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.account_circle, 
                        size: 40, 
                        color: Theme.of(context).disabledColor
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          bottomNavigationBar: AppNavBar(
            currentIndex: 0,
            onTap: (i) {
              switch (i) {
                case 1:
                  Navigator.pushReplacement(context, _fadeRoute(const SnedInterface2()));
                case 2:
                  Navigator.pushReplacement(context, _fadeRoute(const LeaderboardScreen()));
                case 3:
                  Navigator.pushReplacement(context, _fadeRoute(const ProfileScreen()));
              }
            },
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
                top: 300,
                right: -100,
                child: Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.secondary.withOpacity(0.15),
                  ),
                ),
              ),

              SingleChildScrollView(
                physics: const BouncingScrollPhysics(), 
                padding: EdgeInsets.only(
                  left: 24 * scale, 
                  right: 24 * scale, 
                  top: 110 * scale, 
                  bottom: 120 * scale, 
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, 
                  children: [
                    if (isGuest)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: _buildGlassStatBadge(context, roles.role!.icon, '${roles.roleLabel} · Guest', theme.primaryColor, scale),
                      )
                    else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                      children: [
                        GestureDetector(
                          onTap: canProfile ? () => Navigator.push(context, _fadeRoute(const ProfileScreen())) : null, 
                          child: Container(
                            width: 48 * scale,
                            height: 48 * scale,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.cardColor.withOpacity(0.6),
                              border: Border.all(color: theme.primaryColor.withOpacity(0.5), width: 1.5),
                            ),
                            child: ClipOval(
                              child: _buildAvatarImage(context, avatarUrl, scale),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _buildGlassStatBadge(context, Icons.local_fire_department_rounded, '$streak', theme.colorScheme.secondary, scale), 
                            SizedBox(width: 8 * scale), 
                            _buildGlassStatBadge(context, Icons.bolt_rounded, '$totalXp', const Color(0xFF2196F3), scale), 
                            SizedBox(width: 8 * scale), 
                            _buildGlassStatBadge(context, Icons.star_rounded, '$stars', theme.primaryColor, scale), 
                          ],
                        ),
                      ],
                    ),
                    SizedBox(height: 25 * scale), 

                    _buildGlassContainer(
                      context: context,
                      scale: scale,
                      color: theme.primaryColor.withOpacity(0.85), 
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                        crossAxisAlignment: CrossAxisAlignment.center, 
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, 
                              children: [
                                Text(
                                  'Mabuhay,', 
                                  style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 18 * scale, fontWeight: FontWeight.w800, letterSpacing: -0.5), 
                                ),
                                Text(
                                  '$studentName!', 
                                  style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 32 * scale, fontWeight: FontWeight.w900, height: 1.0, letterSpacing: -1.0), 
                                ),
                                if (!canProgress) ...[
                                  SizedBox(height: 10 * scale),
                                  Text(
                                    roles.role == UserRole.parent
                                        ? 'Learn Filipino Sign Language with your child, one sign at a time.'
                                        : 'Explore the lessons your students learn, sign by sign.',
                                    style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.9), fontSize: 14 * scale, fontWeight: FontWeight.w600, height: 1.3),
                                  ),
                                  SizedBox(height: 12 * scale),
                                  Wrap(
                                    spacing: 8 * scale,
                                    runSpacing: 6 * scale,
                                    children: [
                                      for (final (icon, label) in [
                                        (Icons.play_circle_rounded, 'Tutorials'),
                                        (Icons.videocam_rounded, 'Camera practice'),
                                      ])
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.onPrimary.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(14 * scale),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(icon, size: 14 * scale, color: theme.colorScheme.onPrimary),
                                              SizedBox(width: 5 * scale),
                                              Text(label,
                                                  style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 12 * scale, fontWeight: FontWeight.w800)),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                                ] else ...[
                                SizedBox(height: 12 * scale), 
                                Text(
                                  'Level $currentLevel', 
                                  style: TextStyle(color: theme.colorScheme.onPrimary.withOpacity(0.9), fontSize: 16 * scale, fontWeight: FontWeight.w700), 
                                ),
                                SizedBox(height: 6 * scale), 
                                
                                Container(
                                  height: 26 * scale, 
                                  width: double.infinity, 
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onPrimary.withOpacity(0.3), 
                                    borderRadius: BorderRadius.circular(13 * scale), 
                                  ),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: (MediaQuery.of(context).size.width - 150) * progressRatio.clamp(0.0, 1.0),  
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.onPrimary, 
                                          borderRadius: BorderRadius.circular(13 * scale), 
                                          boxShadow: [BoxShadow(color: theme.colorScheme.onPrimary.withOpacity(0.5), blurRadius: 8)],
                                        ),
                                      ),
                                      Align(
                                        alignment: Alignment.centerLeft, 
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 12 * scale), 
                                          child: Text(
                                            '$xpInLevel XP', 
                                            style: TextStyle(
                                              color: theme.primaryColor,  
                                              fontWeight: FontWeight.w900,  
                                              fontSize: 13 * scale, 
                                            ),
                                          ),
                                        ),
                                      )
                                    ],
                                  ),
                                ),
                                ], // end: progress (students only)
                              ],
                            ),
                          ),
                          SizedBox(width: 15 * scale), 
                          
                          Container(
                            padding: EdgeInsets.all(12 * scale),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.onPrimary.withOpacity(0.2),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.onPrimary.withOpacity(0.2), 
                                  blurRadius: 20, 
                                  spreadRadius: 5
                                )
                              ],
                            ),
                            child: Icon(
                              Icons.waving_hand_rounded, 
                              color: theme.colorScheme.onPrimary,
                              size: 56 * scale,
                            ),
                          ),
                        ],
                      ),
                    ),

                    SizedBox(height: 25 * scale), 

                    if (canChallenges) ...[
                      _buildDailyTreasureCard(context, scale, questSubtitle),
                      SizedBox(height: 32 * scale),
                    ],

                    // Faculty / Parent: no progress to continue; learning shortcuts instead.
                    if (isGuest)
                      ..._buildGuestSections(context, roles.role!, scale)
                    else ...[
                    Text(
                      'Continue Learning',
                      style: TextStyle(color: textColor, fontSize: 20 * scale, fontWeight: FontWeight.bold, letterSpacing: -0.5),
                    ),
                    SizedBox(height: 16 * scale),
                    // The two most recently opened modules, side by side.
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (int i = 0; i < 2; i++) ...[
                            if (i > 0) SizedBox(width: 14 * scale),
                            Expanded(
                              child: i < recentModules.length
                                  ? _buildContinueCard(context, recentModules[i], moduleXp[recentModules[i]] ?? 0,
                                      lastOpened[recentModules[i]], scale)
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    ], // end: Continue Learning (students only)
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  Widget _buildGlassContainer({
    required BuildContext context, 
    required Widget child, 
    required double scale, 
    Color? color
  }) {
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(24 * scale), 
      clipBehavior: Clip.antiAlias,
      child: SmartBlur(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(22 * scale),
          decoration: BoxDecoration(
            color: color ?? theme.cardColor.withOpacity(0.6),
            borderRadius: BorderRadius.circular(24 * scale),
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, 10)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildGlassStatBadge(BuildContext context, IconData icon, String value, Color iconColor, double scale) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20 * scale), 
      clipBehavior: Clip.antiAlias,
      child: SmartBlur(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 8 * scale), 
          decoration: BoxDecoration(
            color: theme.cardColor.withOpacity(0.6), 
            borderRadius: BorderRadius.circular(20 * scale), 
            border: Border.all(color: Colors.white.withOpacity(0.15), width: 1.0), 
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 18 * scale), 
              SizedBox(width: 4 * scale), 
              Text(
                value, 
                style: TextStyle(
                  color: textColor, 
                  fontSize: 14 * scale, 
                  fontWeight: FontWeight.w800, 
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class InfoSection {
  final String title;
  final String body;
  final IconData icon; 

  const InfoSection({required this.title, required this.body, required this.icon});
}

class InfoDetailScreen extends StatelessWidget {
  final String title;
  final List<InfoSection> sections;

  const InfoDetailScreen({super.key, required this.title, required this.sections});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double scale = screenWidth / 393 > 1.2 ? 1.2 : screenWidth / 393;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor, 
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: theme.iconTheme.copyWith(color: textColor),
        title: Text(
          title,
          style: TextStyle(
            color: textColor, 
            fontWeight: FontWeight.w700, 
            fontSize: 18 * scale,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 20 * scale),
        children: [
          ...sections.map((section) => Padding(
            padding: EdgeInsets.only(bottom: 28 * scale),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.title,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 16 * scale,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8 * scale),
                Text(
                  section.body,
                  style: TextStyle(
                    color: textColor.withOpacity(0.85),
                    fontSize: 14 * scale,
                    height: 1.6, 
                  ),
                  textAlign: TextAlign.justify, 
                ),
              ],
            ),
          )),
          SizedBox(height: 40 * scale),
        ],
      ),
    );
  }
}

class AboutUsScreen extends StatelessWidget {
  const AboutUsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double scale = screenWidth / 393 > 1.2 ? 1.2 : screenWidth / 393;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: theme.iconTheme.copyWith(color: textColor),
        title: Text(
          "About Us",
          style: TextStyle(
            color: textColor,
            fontWeight: FontWeight.w700,
            fontSize: 18 * scale,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 24 * scale, vertical: 20 * scale),
        children: [
          Center(
            child: Container(
              width: 100 * scale,
              height: 100 * scale,
              decoration: BoxDecoration(
                color: textColor.withOpacity(0.05),
                shape: BoxShape.circle,
                border: Border.all(color: textColor.withOpacity(0.1)),
              ),
              child: Center(
                child: Image.asset('assets/pictures/image 66.png', fit: BoxFit.contain), 
              ),
            ),
          ),
          SizedBox(height: 16 * scale),
          Center(
            child: Text(
              "HandSpeak",
              style: TextStyle(
                color: textColor,
                fontSize: 18 * scale,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 32 * scale),

          Text("Our Mission", style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
          SizedBox(height: 8 * scale),
          Text(
            "HandSpeak is a gamified Filipino Sign Language (FSL) learning adventure equipped with real-time gesture recognition. Our goal is to level up foundational literacy and boost school-wide inclusivity at Sto. Tomas North Central School (STNCS).",
            style: TextStyle(color: textColor.withOpacity(0.85), fontSize: 14 * scale, height: 1.6),
            textAlign: TextAlign.justify,
          ),
          SizedBox(height: 28 * scale),

          Text("The Developers", style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
          SizedBox(height: 8 * scale),
          Text(
            "This digital learning world was forged as a Capstone Project by developers from the College of Informatics and Computing Sciences at Batangas State University - JPLPC Malvar Campus.",
            style: TextStyle(color: textColor.withOpacity(0.85), fontSize: 14 * scale, height: 1.6),
            textAlign: TextAlign.justify,
          ),
          SizedBox(height: 16 * scale),

          _buildDevProfile(context, "Magpantay, Mea Angel S.", scale),
          SizedBox(height: 12 * scale),
          _buildDevProfile(context, "Maligalig, Heartdel D.", scale),
          SizedBox(height: 12 * scale),
          _buildDevProfile(context, "Serrano, Anthony", scale),

          SizedBox(height: 40 * scale),
        ],
      ),
    );
  }

  Widget _buildDevProfile(BuildContext context, String name, double scale) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: EdgeInsets.all(16 * scale),
      decoration: BoxDecoration(
        color: textColor.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: textColor.withOpacity(0.05)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: TextStyle(color: textColor, fontSize: 14 * scale, fontWeight: FontWeight.w600),
            ),
          ),
          Row(
            children: [
              Icon(Icons.link_rounded, color: textColor.withOpacity(0.5), size: 20 * scale),
              SizedBox(width: 12 * scale),
              Icon(Icons.email_outlined, color: textColor.withOpacity(0.5), size: 20 * scale),
            ],
          )
        ],
      ),
    );
  }
}