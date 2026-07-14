import 'package:flutter/material.dart';
import 'create_account.dart';
import '../home/home.dart';
import '../services/auth_service.dart'; // Import your auth service

class SnedStudentLogin extends StatefulWidget {
  const SnedStudentLogin({super.key});

  @override
  State<SnedStudentLogin> createState() => _SnedStudentLoginState();
}

class _SnedStudentLoginState extends State<SnedStudentLogin> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  
  final AuthService _authService = AuthService();
  bool _isLoading = false; // To show a loading spinner

  void _handleLogin() async {
    String email = _emailController.text.trim();
    String password = _passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter both email and password")),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Call Firebase Auth status check structure
    var userProfile = await _authService.signInWithStatusCheck(email, password);

    setState(() => _isLoading = false);

    if (userProfile != null) {
      String status = userProfile['status'] ?? 'pending';
      String displayName = userProfile['name'] ?? email.split('@')[0];

      if (status == 'approved') {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => SnedInterafce1(userName: displayName)),
        );
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Your account is awaiting faculty approval.")),
        );
      }
    } else {
      // Failed login (invalid credentials or profile not found)
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Login failed. Please check your credentials.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(builder: (context, constraints) {
        final double scale = constraints.maxWidth / 393;

        return SingleChildScrollView(
          child: SizedBox(
            width: constraints.maxWidth,
            height: 852 * scale,
            child: Stack(
              children: [
                // Top Bar
                Positioned(
                  top: 0,
                  child: Container(
                    width: constraints.maxWidth,
                    height: 59 * scale,
                    color: Colors.black,
                  ),
                ),

                // Logo
                Positioned(
                  left: 159 * scale,
                  top: 68 * scale,
                  child: Image.asset("assets/pictures/image 1.png", width: 75 * scale),
                ),

                // Character Illustration
                Positioned(
                  left: 88 * scale,
                  top: 149 * scale,
                  child: Image.asset("assets/pictures/image 66.png", width: 194 * scale),
                ),

                // Email Input Field
                Positioned(
                  left: 33 * scale,
                  top: 392 * scale,
                  child: _buildInputField(
                    hint: "Enter Email Address",
                    controller: _emailController,
                    scale: scale,
                  ),
                ),

                // Password Input Field
                Positioned(
                  left: 33 * scale,
                  top: 460 * scale,
                  child: _buildInputField(
                    hint: "•••••••••••••",
                    controller: _passwordController,
                    isPassword: true,
                    scale: scale,
                  ),
                ),

                // Login Button
                Positioned(
                  left: 33 * scale,
                  top: 604 * scale,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleLogin, // Disable while loading
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB800),
                      fixedSize: Size(327 * scale, 56 * scale),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32 * scale)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 24, 
                            height: 24, 
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3)
                          )
                        : Text('Login', style: TextStyle(color: Colors.white, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                  ),
                ),

                // Footer "Or Sign Up"
                Positioned(
                  left: 0,
                  right: 0,
                  top: 767 * scale,
                  child: GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const CreateAccount())),
                    child: Column(
                      children: [
                        Text('or', style: TextStyle(color: Colors.black, fontSize: 14 * scale)),
                        SizedBox(height: 5 * scale),
                        Text('Sign Up', style: TextStyle(color: const Color(0xFFFFB800), fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  // Reusable input field helper to match design
  Widget _buildInputField({required String hint, required TextEditingController controller, bool isPassword = false, required double scale}) {
    return Container(
      width: 327 * scale,
      height: 48 * scale,
      padding: EdgeInsets.symmetric(horizontal: 20 * scale),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F1FA),
        borderRadius: BorderRadius.circular(32 * scale),
        border: Border.all(color: Colors.black.withOpacity(0.1)),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          contentPadding: EdgeInsets.only(bottom: 10 * scale),
        ),
      ),
    );
  }
}