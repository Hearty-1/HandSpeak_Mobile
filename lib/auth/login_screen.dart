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

  void _handleForgotPassword() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("Forgot Password tapped!"),
        behavior: SnackBarBehavior.floating,
      ),
    );
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
                  "assets/pictures/image 1.png", 
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
                const SizedBox(height: 48),

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