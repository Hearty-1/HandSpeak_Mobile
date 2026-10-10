import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart'; 
import 'package:provider/provider.dart';
import '/providers/theme_provider.dart'; 
import 'create_account.dart';
import '../home/home.dart';
import '../services/auth_service.dart';

class SnedStudentLogin extends StatefulWidget {
  const SnedStudentLogin({super.key});

  @override
  State<SnedStudentLogin> createState() => _SnedStudentLoginState();
}

class _SnedStudentLoginState extends State<SnedStudentLogin> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  final AuthService _authService = AuthService();
  
  bool _isLoading = false; 
  bool _isGoogleLoading = false;
  bool _obscurePassword = true;

  // Rate Limiting & Brute Force Protection
  int _failedAttempts = 0;
  static const int _maxAttempts = 5;
  static const int _lockoutDurationSeconds = 30;
  int _remainingLockoutSeconds = 0;
  Timer? _lockoutTimer;

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _startLockoutTimer() {
    setState(() {
      _remainingLockoutSeconds = _lockoutDurationSeconds;
    });

    _lockoutTimer?.cancel();
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingLockoutSeconds <= 1) {
        timer.cancel();
        setState(() {
          _failedAttempts = 0;
          _remainingLockoutSeconds = 0;
        });
      } else {
        setState(() {
          _remainingLockoutSeconds--;
        });
      }
    });
  }

  void _handleLogin() async {
    if (_remainingLockoutSeconds > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Too many attempts. Please wait $_remainingLockoutSeconds seconds."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter both email and password"),
          behavior: SnackBarBehavior.floating, 
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    var userProfile = await _authService.signInWithStatusCheck(email, password);

    if (userProfile != null) {
      String status = userProfile['status'] ?? 'pending';
      String displayName = userProfile['name'] ?? email.split('@')[0];

      if (status == 'approved') {
        // Reset failed attempts on success
        _failedAttempts = 0;

        if (!mounted) return;
        
        await Provider.of<ThemeProvider>(context, listen: false).loadThemeFromPrefs();

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => SnedInterafce1(userName: displayName)),
        );
      } else {
        setState(() => _isLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Your account is awaiting faculty approval."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      setState(() => _isLoading = false);
      _failedAttempts++;

      if (_failedAttempts >= _maxAttempts) {
        _startLockoutTimer();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Too many failed attempts. Account temporarily locked for 30 seconds."),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        int remaining = _maxAttempts - _failedAttempts;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Login failed. Check credentials. ($remaining attempts remaining)"),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showMessage(String text, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), behavior: SnackBarBehavior.floating, backgroundColor: color),
    );
  }

  /// Google SSO: only approved student accounts are let in.
  void _handleGoogleLogin() async {
    if (_isLoading || _isGoogleLoading) return;
    setState(() => _isGoogleLoading = true);
    final result = await _authService.signInWithGoogle();
    if (!mounted) return;

    if (result.outcome == GoogleSignInOutcome.approved) {
      final profile = result.profile!;
      final displayName = profile['name'] ?? (result.email ?? 'Student').split('@')[0];
      await Provider.of<ThemeProvider>(context, listen: false).loadThemeFromPrefs();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => SnedInterafce1(userName: displayName)),
      );
      return;
    }

    setState(() => _isGoogleLoading = false);
    switch (result.outcome) {
      case GoogleSignInOutcome.cancelled:
        break;
      case GoogleSignInOutcome.pending:
        _showMessage("Your account is awaiting faculty approval.");
        break;
      case GoogleSignInOutcome.notApproved:
        _showMessage("This account is not approved for HandSpeak. Please contact your teacher.",
            color: Colors.redAccent);
        break;
      case GoogleSignInOutcome.notRegistered:
        _showMessage("No student account uses ${result.email ?? 'this Google email'}. "
            "Sign up first and wait for faculty approval.", color: Colors.redAccent);
        break;
      case GoogleSignInOutcome.needsPassword:
        _emailController.text = result.email ?? '';
        _showMessage("This email was registered with a password. Log in with your password once "
            "and Google sign-in will be linked to your account.");
        break;
      default:
        _showMessage("Google sign-in failed. Please try again.", color: Colors.redAccent);
    }
  }

  void _handleForgotPassword() async {
    String email = _emailController.text.trim();

    // Require the user to enter an email before requesting a reset
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please enter your email in the text field first."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Call the new AuthService method
    String? error = await _authService.sendPasswordResetEmail(email);

    if (!mounted) return;

    if (error == null) {
      // Success case
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("A password reset link has been sent to $email."),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
    } else {
      // Error case (e.g., user not found, badly formatted email)
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isButtonDisabled = _isLoading || _remainingLockoutSeconds > 0;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white, 
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Logo
                Image.asset(
                  "assets/pictures/logo.png", 
                  width: 75,
                ),
                const SizedBox(height: 24),

                // Character Illustration
                Image.asset(
                  "assets/pictures/image 66.png", 
                  width: 200,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 40),

                // Email Input Field
                _buildTextField(
                  hint: "Email",
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  enabled: _remainingLockoutSeconds == 0,
                ),
                const SizedBox(height: 16),

                // Password Input Field with Toggle
                _buildTextField(
                  hint: "Password",
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  enabled: _remainingLockoutSeconds == 0,
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: IconButton(
                      icon: Icon(
                        _obscurePassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                        color: const Color(0xFF8E8E93),
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
                
                // Forgot Password Button
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _handleForgotPassword,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text(
                      "Forgot Password?",
                      style: TextStyle(
                        color: Color(0xFFFFB800), 
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isButtonDisabled ? null : _handleLogin, 
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFFFFB800),
                      disabledBackgroundColor: Colors.grey.shade400,
                      foregroundColor: Colors.white, 
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(32),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24, 
                            height: 24, 
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                          )
                        : Text(
                            _remainingLockoutSeconds > 0
                                ? 'Locked out (${_remainingLockoutSeconds}s)'
                                : 'Login', 
                            style: const TextStyle(
                              color: Colors.white, 
                              fontSize: 17, 
                              fontWeight: FontWeight.w600, 
                              letterSpacing: -0.4,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 20),

                // Divider
                Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or continue with', style: TextStyle(color: Colors.black45, fontSize: 13)),
                    ),
                    Expanded(child: Divider(color: Colors.grey.shade300)),
                  ],
                ),
                const SizedBox(height: 20),

                // Google SSO (approved students only)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: OutlinedButton(
                    onPressed: isButtonDisabled || _isGoogleLoading ? null : _handleGoogleLogin,
                    style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      side: BorderSide(color: Colors.grey.shade300, width: 1.2),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                    ),
                    child: _isGoogleLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Color(0xFFFFB800), strokeWidth: 3),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _GoogleLogo(),
                              SizedBox(width: 12),
                              Text(
                                'Sign in with Google',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.3),
                              ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 36),

                // Footer "Or Sign Up"
                GestureDetector(
                  onTap: () => Navigator.push(
                    context, 
                    MaterialPageRoute(builder: (context) => const CreateAccount())
                  ),
                  child: const Column(
                    children: [
                      Text(
                        'or', 
                        style: TextStyle(
                          color: Colors.black54, 
                          fontSize: 14,
                        )
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Sign Up', 
                        style: TextStyle(
                          color: Color(0xFFFFB800), 
                          fontSize: 16, 
                          fontWeight: FontWeight.w600,
                        )
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String hint, 
    required TextEditingController controller, 
    bool obscureText = false, 
    bool enabled = true,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      enabled: enabled,
      keyboardType: keyboardType,
      style: const TextStyle(
        fontSize: 16,
        color: Colors.black,
        fontWeight: FontWeight.w400,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF8E8E93), 
          fontSize: 16,
        ),
        filled: true,
        fillColor: enabled ? const Color(0xFFF2F2F7) : Colors.grey.shade200, 
        contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18), 
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(32),
          borderSide: BorderSide.none, 
        ),
        suffixIcon: suffixIcon,
      ),
    );
  }
}

/// Google "G" mark drawn with arcs (no image asset needed).
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 22, height: 22, child: CustomPaint(painter: _GoogleLogoPainter()));
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.2;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    Paint p(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    const deg = 3.14159265 / 180;
    canvas.drawArc(rect, -140 * deg, 95 * deg, false, p(const Color(0xFFEA4335))); // red (top)
    canvas.drawArc(rect, 145 * deg, 75 * deg, false, p(const Color(0xFFFBBC05))); // yellow (left)
    canvas.drawArc(rect, 45 * deg, 100 * deg, false, p(const Color(0xFF34A853))); // green (bottom)
    canvas.drawArc(rect, 0, 45 * deg, false, p(const Color(0xFF4285F4))); // blue (right)
    // Blue crossbar.
    canvas.drawLine(
      Offset(size.width / 2, size.height / 2),
      Offset(size.width - stroke / 2, size.height / 2),
      Paint()
        ..color = const Color(0xFF4285F4)
        ..strokeWidth = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
