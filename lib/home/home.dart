import 'dart:ui'; 
import 'dart:convert';
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
import '/providers/language_provider.dart';

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
        errorBuilder: (_, _, _) => Icon(Icons.person, color: theme.primaryColor, size: 26 * scale),
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
    if (t == null) return L.t('Start learning', 'Simulan ang pag-aaral');
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return L.t('Just now', 'Ngayon lang');
    if (d.inMinutes < 60) return L.t('${d.inMinutes}m ago', '${d.inMinutes}m na ang nakalipas');
    if (d.inHours < 24) return L.t('${d.inHours}h ago', '${d.inHours}h na ang nakalipas');
    if (d.inDays == 1) return L.t('Yesterday', 'Kahapon');
    if (d.inDays < 7) return L.t('${d.inDays} days ago', '${d.inDays} araw na ang nakalipas');
    return '${t.month}/${t.day}/${t.year}';
  }

  /// L.t('Continue Learning', 'Ipagpatuloy ang Pag-aaral') shortcut: module art, name, last opened and the
  /// module's XP progress; tapping resumes the module.
  Widget _buildContinueCard(BuildContext context, String moduleKey, int xp, DateTime? opened, double scale) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final (String title, String imagePath, Widget Function(int) screen) = switch (moduleKey) {
      'numbers' => (L.t('Numbers', 'Mga Numero'), 'assets/pictures/numbers.png', (int x) => NumbersInterface(currentXp: x, targetXp: _moduleTargetXp)),
      'common words' => (L.t('Words/Phrases', 'Mga Salita/Parirala'), 'assets/pictures/words.png', (int x) => PhraseInterface(currentXp: x, targetXp: _moduleTargetXp)),
      'civic' => (L.t('Civic Observances', 'Pagdiriwang Pansibiko'), 'assets/pictures/civic.png', (int x) => CivicInterface(currentXp: x, targetXp: _moduleTargetXp)),
      _ => (L.t('Alphabet', 'Alpabeto'), 'assets/pictures/abc.png', (int x) => AlphabetInterface(currentXp: x, targetXp: _moduleTargetXp)),
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
              color: theme.cardColor.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(24 * scale),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.0),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10))],
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
                        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 5))],
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
                    Icon(Icons.history_rounded, size: 13 * scale, color: textColor.withValues(alpha: 0.5)),
                    SizedBox(width: 4 * scale),
                    Flexible(
                      child: Text(
                        _timeAgo(opened),
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: textColor.withValues(alpha: 0.55), fontSize: 12 * scale, fontWeight: FontWeight.w600),
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
                      backgroundColor: theme.dividerColor.withValues(alpha: 0.15),
                      color: accent,
                    ),
                  ),
                  SizedBox(height: 6 * scale),
                  Text(
                    complete ? L.t('Completed', 'Tapos na') : '$shownXp / $_moduleTargetXp XP',
                    style: TextStyle(color: complete ? Colors.green : textColor.withValues(alpha: 0.6), fontSize: 11.5 * scale, fontWeight: FontWeight.w700),
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

  static List<({String key, String title, String blurb, String image, IconData icon})> get _guestModules => [
    (key: 'alphabet', title: L.t('Alphabet', 'Alpabeto'), blurb: L.t('A–Z hand signs', 'Mga senyas ng A–Z'), image: 'assets/pictures/abc.png', icon: Icons.abc_rounded),
    (key: 'numbers', title: L.t('Numbers', 'Mga Numero'), blurb: L.t('Counting signs', 'Mga senyas sa pagbilang'), image: 'assets/pictures/numbers.png', icon: Icons.pin_rounded),
    (key: 'common words', title: L.t('Words/Phrases', 'Mga Salita/Parirala'), blurb: L.t('Everyday greetings', 'Pang-araw-araw na pagbati'), image: 'assets/pictures/words.png', icon: Icons.forum_rounded),
    (key: 'civic', title: L.t('Civic Observances', 'Pagdiriwang Pansibiko'), blurb: 'Lupang Hinirang', image: 'assets/pictures/civic.png', icon: Icons.flag_rounded),
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
          Text(subtitle, style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 13 * scale, fontWeight: FontWeight.w500)),
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
                color: theme.scaffoldBackgroundColor.withValues(alpha: 0.8),
                child: Image.asset(
                  'assets/pictures/$letter.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(
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
                    L.t('Letter $letter', 'Letra $letter'),
                    style: TextStyle(color: textColor, fontSize: 24 * scale, fontWeight: FontWeight.w900, letterSpacing: -0.6),
                  ),
                  SizedBox(height: 2 * scale),
                  Text(
                    L.t('Copy the handshape, then try it on camera.', 'Gayahin ang porma ng kamay, saka subukan sa camera.'),
                    style: TextStyle(color: textColor.withValues(alpha: 0.65), fontSize: 13 * scale, fontWeight: FontWeight.w500, height: 1.3),
                  ),
                  SizedBox(height: 10 * scale),
                  Row(
                    children: [
                      Icon(Icons.videocam_rounded, size: 16 * scale, color: theme.primaryColor),
                      SizedBox(width: 6 * scale),
                      Text(L.t('Practice this sign', 'Sanayin ang senyas na ito'),
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
              color: theme.cardColor.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(22 * scale),
              border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.0),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 16, offset: const Offset(0, 8))],
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
                        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(m.image, fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => Icon(m.icon, color: theme.primaryColor)),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_forward_rounded, size: 18 * scale, color: textColor.withValues(alpha: 0.4)),
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
                  style: TextStyle(color: textColor.withValues(alpha: 0.6), fontSize: 12 * scale, fontWeight: FontWeight.w600),
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
            L.t('Learn together', 'Sabay na matuto'),
            L.t('Pick one sign a day and practise it with your child. Let them teach it back to you. It is the fastest way to remember.', 'Pumili ng isang senyas araw-araw at sanayin ito kasama ang anak mo. Hayaan siyang ituro ito pabalik sa iyo. Ito ang pinakamabilis na paraan para matandaan.'),
          )
        : (
            Icons.co_present_rounded,
            L.t('Teaching tip', 'Tip sa pagtuturo'),
            L.t('Use the tutorial videos to introduce a sign in class. Students log in with their own accounts to play activities and earn XP.', 'Gamitin ang mga tutorial video para ipakilala ang senyas sa klase. Mag-log in ang mga estudyante sa sarili nilang account para maglaro at makakuha ng XP.'),
          );
    return _buildGlassContainer(
      context: context,
      scale: scale,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(10 * scale),
            decoration: BoxDecoration(color: theme.colorScheme.secondary.withValues(alpha: 0.18), shape: BoxShape.circle),
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
                    style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 13 * scale, fontWeight: FontWeight.w500, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGuestSections(BuildContext context, UserRole role, double scale) => [
        _sectionTitle(context, L.t('Sign of the Day', 'Senyas ng Araw'), scale),
        _buildSignOfTheDay(context, scale),
        SizedBox(height: 28 * scale),
        _sectionTitle(context, L.t('Explore the Modules', 'Tuklasin ang mga Module'), scale, subtitle: L.t('Watch the tutorials and practise each sign on camera.', 'Panoorin ang mga tutorial at sanayin ang bawat senyas sa camera.')),
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
        color: const Color(0xFFFF8227).withValues(alpha: 0.85), 
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(10 * scale),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
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
                    L.t('Daily Challenges!', 'Mga Hamon Ngayong Araw!'), 
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
                      color: Colors.white.withValues(alpha: 0.9), 
                      fontSize: 13 * scale, 
                      fontWeight: FontWeight.w600,
                    ), 
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withValues(alpha: 0.8), size: 20 * scale),
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
    // Screen width can be 0 for a frame (startup / resize): never scale to 0
    // (a 0-height progress bar is an assertion error).
    final double scale = (screenWidth / 393).clamp(0.6, 1.2).toDouble(); 

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
        String questSubtitle = L.t('Your personalised quests are ready!', 'Handa na ang mga quest para sa iyo!');

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
                  ? {'starter': L.t('Getting Started', 'Nagsisimula'), 'steady': L.t('Steady Pace', 'Tuloy-tuloy'), 'balanced': L.t('Balanced', 'Balanse'), 'fast': L.t('Fast Track', 'Mabilis')}[lp['pace']]
                  : null;
              questSubtitle = claimedToday >= quests.length
                  ? L.t('All ${quests.length} quests done today. Great work!', 'Tapos na ang lahat ng ${quests.length} quest ngayong araw. Magaling!')
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
            backgroundColor: theme.cardColor.withValues(alpha: 0.95), 
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
                        L.t('Menu', 'Menu'), 
                        style: TextStyle(
                          color: theme.colorScheme.onPrimary,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (isGuest) ...[
                        const SizedBox(height: 4),
                        Text(
                          L.t('${roles.roleLabel} access', 'Access ng ${roles.roleLabel}'),
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary.withValues(alpha: 0.85),
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
                        title: Text(L.t('Settings', 'Mga Setting'), style: TextStyle(color: textColor, fontWeight: FontWeight.w600)), 
                        onTap: () {
                          Navigator.pop(context); 
                          Navigator.push(context, _fadeRoute(const SettingsScreen()));
                        }, 
                      ),
                      ListTile(
                        leading: Icon(Icons.help_outline, color: theme.primaryColor), 
                        title: Text(L.t('Help & Support', 'Tulong at Suporta'), style: TextStyle(color: textColor, fontWeight: FontWeight.w600)), 
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, _fadeRoute(InfoDetailScreen(
                            title: L.t('Help & Support', 'Tulong at Suporta'),
                            sections: [
                              InfoSection(
                                title: L.t('The Learning Loop', 'Ang Paraan ng Pag-aaral'),
                                body: L.t('Your Filipino Sign Language learning path is divided into four stages: Tutorials, Practice, Activities, and Challenges. Achieve 1000 XP points to unlock the next module.', 'Ang pag-aaral mo ng Filipino Sign Language ay may apat na yugto: Tutorials, Practice, Activities at Challenges. Makakuha ng 1000 XP para mabuksan ang susunod na module.'),
                                icon: Icons.loop_rounded,
                              ),
                              InfoSection(
                                title: L.t('Camera Combat', 'Camera Combat'),
                                body: L.t('Ensure you are in a well-lit area and use the Mirror-Mode Camera. A green checkmark means you scored a hit, while a red "X" means you need to adjust your form.', 'Siguraduhing maliwanag ang lugar at gamitin ang Mirror-Mode Camera. Ang berdeng tsek ay tama, at ang pulang "X" ay kailangan pang ayusin ang porma.'),
                                icon: Icons.camera_alt_rounded,
                              ),
                              InfoSection(
                                title: L.t('Leveling Up & Streaks', 'Pag-level Up at Streaks'),
                                body: L.t('Keep practicing to earn Experience Points (XP) and fill your Level Progress Bar. Enable Streak Reminders to keep your momentum going.', 'Patuloy na magsanay para makakuha ng XP at mapuno ang Level Progress Bar. I-on ang Streak Reminders para tuloy-tuloy ang pag-aaral.'),
                                icon: Icons.local_fire_department_rounded,
                              ),
                              InfoSection(
                                title: L.t('Multiplayer Challenges', 'Multiplayer Challenges'),
                                body: L.t('Challenge your classmates by tapping "Join a Room" and entering a Room Code, or act as the host by selecting "Create a Room".', 'Hamunin ang mga kaklase: pindutin ang "Join a Room" at ilagay ang Room Code, o maging host sa pagpili ng "Create a Room".'),
                                icon: Icons.group_rounded,
                              ),
                              InfoSection(
                                title: L.t('Customizing Experience', 'Pag-customize ng App'),
                                body: L.t('Visit the Settings screen to change your game Theme (like Galaxy Explorer or Deep Ocean), and toggle your Background Music on or off.', 'Pumunta sa Settings para palitan ang Tema (tulad ng Galaxy Explorer o Deep Ocean) at i-on o i-off ang Background Music.'),
                                icon: Icons.palette_rounded,
                              ),
                              InfoSection(
                                title: L.t('Reporting Bugs', 'Pag-uulat ng Problema'),
                                body: L.t('Teachers can submit a bug report directly to the admin using the "Feedback & Support" tool. Students should report issues to their teachers.', 'Maaaring magpadala ang mga guro ng bug report sa admin gamit ang "Feedback & Support". Ang mga estudyante ay mag-ulat sa kanilang guro.'),
                                icon: Icons.bug_report_rounded,
                              ),
                            ],
                          )));
                        }, 
                      ),
                      ListTile(
                        leading: Icon(Icons.info_outline, color: theme.primaryColor), 
                        title: Text(L.t('About Us', 'Tungkol sa Amin'), style: TextStyle(color: textColor, fontWeight: FontWeight.w600)), 
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, _fadeRoute(const AboutUsScreen()));
                        }, 
                      ),
                      ListTile(
                        leading: Icon(Icons.gavel_rounded, color: theme.primaryColor), 
                        title: Text(L.t('Terms & Privacy Policy', 'Mga Tuntunin at Privacy Policy'), style: TextStyle(color: textColor, fontWeight: FontWeight.w600)), 
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(context, _fadeRoute(InfoDetailScreen(
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
  title: Text(isGuest ? L.t('Change Role', 'Palitan ang Role') : L.t('Sign Out', 'Mag-sign Out'), style: const TextStyle(color: Color(0xFFF34B1B), fontWeight: FontWeight.w600)), 
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
            backgroundColor: theme.cardColor.withValues(alpha: 0.4),
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
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.0),
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
                    color: theme.primaryColor.withValues(alpha: 0.25),
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
                    color: theme.colorScheme.secondary.withValues(alpha: 0.15),
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
                        child: _buildGlassStatBadge(context, roles.role!.icon, L.t('${roles.roleLabel} · Guest', '${roles.roleLabel} · Bisita'), theme.primaryColor, scale),
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
                              color: theme.cardColor.withValues(alpha: 0.6),
                              border: Border.all(color: theme.primaryColor.withValues(alpha: 0.5), width: 1.5),
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
                      color: theme.primaryColor.withValues(alpha: 0.85), 
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                        crossAxisAlignment: CrossAxisAlignment.center, 
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start, 
                              children: [
                                Text(
                                  L.t('Mabuhay,', 'Mabuhay,'), 
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
                                        ? L.t('Learn Filipino Sign Language with your child, one sign at a time.', 'Matuto ng Filipino Sign Language kasama ang anak mo, isang senyas sa bawat araw.')
                                        : L.t('Explore the lessons your students learn, sign by sign.', 'Tingnan ang mga aralin ng iyong mga estudyante, senyas sa senyas.'),
                                    style: TextStyle(color: theme.colorScheme.onPrimary.withValues(alpha: 0.9), fontSize: 14 * scale, fontWeight: FontWeight.w600, height: 1.3),
                                  ),
                                  SizedBox(height: 12 * scale),
                                  Wrap(
                                    spacing: 8 * scale,
                                    runSpacing: 6 * scale,
                                    children: [
                                      for (final (icon, label) in [
                                        (Icons.play_circle_rounded, L.t('Tutorials', 'Mga Tutorial')),
                                        (Icons.videocam_rounded, L.t('Camera practice', 'Pagsasanay sa camera')),
                                      ])
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 10 * scale, vertical: 5 * scale),
                                          decoration: BoxDecoration(
                                            color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
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
                                  L.t('Level $currentLevel', 'Level $currentLevel'), 
                                  style: TextStyle(color: theme.colorScheme.onPrimary.withValues(alpha: 0.9), fontSize: 16 * scale, fontWeight: FontWeight.w700), 
                                ),
                                SizedBox(height: 6 * scale), 
                                
                                Container(
                                  height: 26 * scale, 
                                  width: double.infinity, 
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.onPrimary.withValues(alpha: 0.3), 
                                    borderRadius: BorderRadius.circular(13 * scale), 
                                  ),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: (MediaQuery.of(context).size.width - 150) * progressRatio.clamp(0.0, 1.0),  
                                        decoration: BoxDecoration(
                                          color: theme.colorScheme.onPrimary, 
                                          borderRadius: BorderRadius.circular(13 * scale), 
                                          boxShadow: [BoxShadow(color: theme.colorScheme.onPrimary.withValues(alpha: 0.5), blurRadius: 8)],
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
                              color: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: theme.colorScheme.onPrimary.withValues(alpha: 0.2), 
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
                      L.t('Continue Learning', 'Ipagpatuloy ang Pag-aaral'),
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
            color: color ?? theme.cardColor.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(24 * scale),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.0),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 20, offset: const Offset(0, 10)),
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
            color: theme.cardColor.withValues(alpha: 0.6), 
            borderRadius: BorderRadius.circular(20 * scale), 
            border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 1.0), 
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
    // Screen width can be 0 for a frame (startup / resize): never scale to 0
    // (a 0-height progress bar is an assertion error).
    final double scale = (screenWidth / 393).clamp(0.6, 1.2).toDouble();

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
                    color: textColor.withValues(alpha: 0.85),
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
    // Screen width can be 0 for a frame (startup / resize): never scale to 0
    // (a 0-height progress bar is an assertion error).
    final double scale = (screenWidth / 393).clamp(0.6, 1.2).toDouble();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        centerTitle: true,
        iconTheme: theme.iconTheme.copyWith(color: textColor),
        title: Text(
          L.t('About Us', 'Tungkol sa Amin'),
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
                color: textColor.withValues(alpha: 0.05),
                shape: BoxShape.circle,
                border: Border.all(color: textColor.withValues(alpha: 0.1)),
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

          Text(L.t('Our Mission', 'Ang Aming Misyon'), style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
          SizedBox(height: 8 * scale),
          Text(
            L.t('HandSpeak is a gamified Filipino Sign Language (FSL) learning adventure equipped with real-time gesture recognition. Our goal is to level up foundational literacy and boost school-wide inclusivity at Sto. Tomas North Central School (STNCS).', 'Ang HandSpeak ay isang larong pag-aaral ng Filipino Sign Language (FSL) na may real-time na pagkilala ng senyas. Layunin naming paunlarin ang batayang literasiya at ang inklusibong pag-aaral sa Sto. Tomas North Central School (STNCS).'),
            style: TextStyle(color: textColor.withValues(alpha: 0.85), fontSize: 14 * scale, height: 1.6),
            textAlign: TextAlign.justify,
          ),
          SizedBox(height: 28 * scale),

          Text(L.t('The Developers', 'Ang mga Developer'), style: TextStyle(color: textColor, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
          SizedBox(height: 8 * scale),
          Text(
            L.t('This digital learning world was forged as a Capstone Project by developers from the College of Informatics and Computing Sciences at Batangas State University - JPLPC Malvar Campus.', 'Ang digital na mundong ito ng pag-aaral ay ginawa bilang Capstone Project ng mga developer mula sa College of Informatics and Computing Sciences ng Batangas State University - JPLPC Malvar Campus.'),
            style: TextStyle(color: textColor.withValues(alpha: 0.85), fontSize: 14 * scale, height: 1.6),
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
        color: textColor.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12 * scale),
        border: Border.all(color: textColor.withValues(alpha: 0.05)),
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
              Icon(Icons.link_rounded, color: textColor.withValues(alpha: 0.5), size: 20 * scale),
              SizedBox(width: 12 * scale),
              Icon(Icons.email_outlined, color: textColor.withValues(alpha: 0.5), size: 20 * scale),
            ],
          )
        ],
      ),
    );
  }
}