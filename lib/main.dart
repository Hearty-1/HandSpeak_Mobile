import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'package:provider/provider.dart'; 
import 'firebase_options.dart'; 
import 'providers/theme_provider.dart'; 
import 'providers/sound_provider.dart'; 
import 'home/home.dart'; 
import 'auth/login_screen.dart';

// Import the local notification service
import 'services/local_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize notifications and timezone setup
  await LocalNotificationService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SoundProvider()), 
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: themeProvider.activeTheme, 
          themeMode: themeProvider.activeThemeMode,
          navigatorObservers: [
            Provider.of<SoundProvider>(context, listen: false).navigatorObserver,
          ],
          home: StreamBuilder<User?>(
            stream: FirebaseAuth.instance.authStateChanges(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(
                    child: CircularProgressIndicator(color: Color(0xFFFFB800)),
                  ),
                );
              }
              
              if (snapshot.hasData) {
                String displayName = snapshot.data!.displayName ?? 
                                     snapshot.data!.email?.split('@')[0] ?? 
                                     "Student";
                return SnedInterafce1(userName: displayName);
              }
              
              return const MainLogin(); 
            },
          ),
        );
      },
    );
  }
}

/// One page of the welcome carousel.
class _IntroSlide {
  final String image;
  final String eyebrow;
  final String title;
  final String body;
  final List<(IconData, String)> chips;
  final Color accent;
  const _IntroSlide({
    required this.image,
    required this.eyebrow,
    required this.title,
    required this.body,
    required this.chips,
    required this.accent,
  });
}

const List<_IntroSlide> _introSlides = [
  _IntroSlide(
    image: 'assets/pictures/image 66.png',
    eyebrow: 'WELCOME TO',
    title: 'HandSpeak',
    body: 'Learn Filipino Sign Language (FSL) anytime, using only your phone and its camera.',
    chips: [(Icons.sign_language_rounded, 'FSL'), (Icons.phone_android_rounded, 'On your phone')],
    accent: Color(0xFFFFB800),
  ),
  _IntroSlide(
    image: 'assets/pictures/abc.png',
    eyebrow: 'LEARN',
    title: 'Step by step',
    body: 'Start with the alphabet and numbers, then move on to greetings.',
    chips: [(Icons.abc_rounded, 'Alphabet'), (Icons.pin_rounded, 'Numbers'), (Icons.chat_rounded, 'Phrases')],
    accent: Color(0xFFFF8A3D),
  ),
  _IntroSlide(
    image: 'assets/pictures/sign.png',
    eyebrow: 'PRACTICE',
    title: 'Your camera is your coach',
    body: 'Sign in front of the camera. HandSpeak checks your handshape and movement and tells you right away how to improve.',
    chips: [(Icons.videocam_rounded, 'Live camera'), (Icons.auto_awesome_rounded, 'Instant feedback')],
    accent: Color(0xFF7DC579),
  ),
  _IntroSlide(
    image: 'assets/pictures/civic.png',
    eyebrow: 'CULTURE',
    title: 'Sign with pride',
    body: 'Learn to sign Lupang Hinirang, so every Filipino student can take part in them.',
    chips: [(Icons.flag_rounded, 'Lupang Hinirang'), (Icons.groups_rounded, 'Civic')],
    accent: Color(0xFF3D7BFF),
  ),
  _IntroSlide(
    image: 'assets/pictures/trophy.png',
    eyebrow: 'PLAY',
    title: 'Earn, level up, compete',
    body: 'Collect XP and Stars, keep your daily streak, unlock badges and challenge your classmates in the arena.',
    chips: [(Icons.bolt_rounded, 'XP'), (Icons.local_fire_department_rounded, 'Streaks'), (Icons.emoji_events_rounded, 'Badges')],
    accent: Color(0xFFB26BE0),
  ),
  _IntroSlide(
    image: 'assets/pictures/people.png',
    eyebrow: 'OUR PURPOSE',
    title: 'A bridge, not a barrier',
    body: 'HandSpeak helps Deaf and hearing Filipinos understand each other, one sign at a time.',
    chips: [(Icons.favorite_rounded, 'Inclusion'), (Icons.diversity_3_rounded, 'For everyone')],
    accent: Color(0xFFFF5C8A),
  ),
];

class MainLogin extends StatefulWidget {
  const MainLogin({super.key});

  @override
  State<MainLogin> createState() => _MainLoginState();
}

class _MainLoginState extends State<MainLogin> with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  late final AnimationController _floatController;
  double _page = 0;

  bool get _isLast => _page.round() >= _introSlides.length - 1;

  @override
  void initState() {
    super.initState();
    _floatController = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat(reverse: true);
    _pageController.addListener(() {
      final p = _pageController.page ?? 0;
      if (p != _page) setState(() => _page = p);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_isLast) {
      _begin();
    } else {
      _pageController.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  void _begin() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => const SnedStudentLogin()));
  }

  /// Accent colour blended between the two slides around the current scroll position.
  Color get _accent {
    final i = _page.floor().clamp(0, _introSlides.length - 1);
    final j = (i + 1).clamp(0, _introSlides.length - 1);
    return Color.lerp(_introSlides[i].accent, _introSlides[j].accent, _page - _page.floor())!;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final accent = _accent;
    final onSurface = theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Soft colour blobs that shift with the current slide.
          Positioned(
            top: -size.width * 0.35,
            right: -size.width * 0.3,
            child: _Blob(size: size.width * 0.95, color: accent.withValues(alpha: 0.22)),
          ),
          Positioned(
            bottom: -size.width * 0.45,
            left: -size.width * 0.35,
            child: _Blob(size: size.width * 1.0, color: accent.withValues(alpha: 0.14)),
          ),
          SafeArea(
            child: Column(
              children: [
                // Top bar: school logo + Skip.
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      Image.asset('assets/pictures/image 1.png', height: 40, fit: BoxFit.contain),
                      const Spacer(),
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 250),
                        opacity: _isLast ? 0 : 1,
                        child: TextButton(
                          onPressed: _isLast
                              ? null
                              : () => _pageController.animateToPage(_introSlides.length - 1,
                                  duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic),
                          child: Text('Skip',
                              style: TextStyle(color: onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const BouncingScrollPhysics(),
                    itemCount: _introSlides.length,
                    itemBuilder: (context, i) => _IntroPage(
                      slide: _introSlides[i],
                      offset: _page - i, // -1..1 while swiping: drives the parallax
                      float: _floatController,
                    ),
                  ),
                ),
                // Indicator + main button.
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0; i < _introSlides.length; i++)
                            Builder(builder: (context) {
                              final t = (1 - (_page - i).abs()).clamp(0.0, 1.0);
                              return Container(
                                margin: const EdgeInsets.symmetric(horizontal: 4),
                                height: 8,
                                width: 8 + 20 * t,
                                decoration: BoxDecoration(
                                  color: Color.lerp(onSurface.withValues(alpha: 0.18), accent, t),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              );
                            }),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _PrimaryButton(
                        color: accent,
                        label: _isLast ? "Let's Begin" : 'Next',
                        icon: _isLast ? Icons.arrow_forward_rounded : Icons.chevron_right_rounded,
                        onPressed: _next,
                      ),
                    ],
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

class _IntroPage extends StatelessWidget {
  final _IntroSlide slide;
  final double offset;
  final Animation<double> float;
  const _IntroPage({required this.slide, required this.offset, required this.float});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    final fade = (1 - offset.abs()).clamp(0.0, 1.0);

    return LayoutBuilder(builder: (context, c) {
      final art = (c.maxHeight * 0.48).clamp(160.0, 320.0);
      return SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: c.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Illustration: glowing disc, floating, with parallax.
                Transform.translate(
                  offset: Offset(offset * -80, 0),
                  child: AnimatedBuilder(
                    animation: float,
                    builder: (context, child) => Transform.translate(
                      offset: Offset(0, -8 + 16 * Curves.easeInOutSine.transform(float.value)),
                      child: child,
                    ),
                    child: SizedBox(
                      width: art,
                      height: art,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: art * 0.92,
                            height: art * 0.92,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(colors: [
                                slide.accent.withValues(alpha: 0.35),
                                slide.accent.withValues(alpha: 0.08),
                              ]),
                              boxShadow: [
                                BoxShadow(color: slide.accent.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 2),
                              ],
                            ),
                          ),
                          Container(
                            width: art * 0.74,
                            height: art * 0.74,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: theme.cardColor.withValues(alpha: 0.9),
                            ),
                          ),
                          Padding(
                            padding: EdgeInsets.all(art * 0.16),
                            child: Image.asset(slide.image, fit: BoxFit.contain),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(height: art * 0.12),
                Opacity(
                  opacity: fade,
                  child: Transform.translate(
                    offset: Offset(offset * -30, 0),
                    child: Column(
                      children: [
                        Text(
                          slide.eyebrow,
                          style: TextStyle(
                            color: slide.accent,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 2.2,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: onSurface,
                            fontSize: 30,
                            height: 1.1,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            fontFamily: 'Inter',
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          slide.body,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: onSurface.withValues(alpha: 0.65),
                            fontSize: 15.5,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Wrap(
                          alignment: WrapAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final (icon, label) in slide.chips)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                decoration: BoxDecoration(
                                  color: slide.accent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(30),
                                  border: Border.all(color: slide.accent.withValues(alpha: 0.35)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(icon, size: 16, color: slide.accent),
                                    const SizedBox(width: 6),
                                    Text(label,
                                        style: TextStyle(
                                            color: onSurface.withValues(alpha: 0.8),
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w700)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  const _Blob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
}

class _PrimaryButton extends StatelessWidget {
  final Color color;
  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  const _PrimaryButton({required this.color, required this.label, required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a),
              child: child,
            ),
          ),
          // FittedBox: small screens / large font settings never overflow.
          child: FittedBox(
            key: ValueKey(label),
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 0.4)),
                const SizedBox(width: 10),
                Icon(icon, size: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
