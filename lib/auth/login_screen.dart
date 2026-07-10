import 'package:flutter/material.dart';
import 'create_account.dart';
import '../home/home.dart';

class SnedStudentLogin extends StatefulWidget {
  const SnedStudentLogin({super.key});

  @override
  State<SnedStudentLogin> createState() => _SnedStudentLoginState();
}

class _SnedStudentLoginState extends State<SnedStudentLogin> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

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

                // Name Input Field
                Positioned(
                  left: 33 * scale,
                  top: 392 * scale,
                  child: _buildInputField(
                    hint: "Enter Name",
                    controller: _nameController,
                    scale: scale,
                  ),
                ),

                // Password Input Field
                Positioned(
                  left: 33 * scale,
                  top: 460 * scale, // Adjusted spacing based on visual layout
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
                    onPressed: () {
                      String customName = _nameController.text.trim();
                      if (customName.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Please enter your name")),
                        );
                        return;
                      }
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => SnedInterafce1(userName: customName)),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFB800),
                      fixedSize: Size(327 * scale, 56 * scale),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32 * scale)),
                    ),
                    child: Text('Login', style: TextStyle(color: Colors.white, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
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
        color: const Color(0xFFF1F1FA), // Light grey/white background from layout
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