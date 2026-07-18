import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../home/home.dart';
import '../services/auth_service.dart';

class CreateAccount extends StatefulWidget {
  const CreateAccount({super.key});

  @override
  State<CreateAccount> createState() => _CreateAccountState();
}

class _CreateAccountState extends State<CreateAccount> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _idController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _confirmPassController = TextEditingController();
  final TextEditingController _sectionController = TextEditingController();

  final AuthService _authService = AuthService();
  bool _isLoading = false; 
  
  // Password visibility states
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  String? _gradeLevel;
  final List<String> _gradeOptions = ["SNED", "Grade 1", "Grade 2", "Grade 3", "Grade 4", "Grade 5", "Grade 6"]; 

  void _handleSignUp() async {
    if (!_formKey.currentState!.validate() || _gradeLevel == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill all required fields and select a grade."),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_passController.text != _confirmPassController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Passwords do not match!"),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    var user = await _authService.signUpWithStudentDetails(
      email: _emailController.text.trim(),
      password: _passController.text.trim(),
      fullName: _nameController.text.trim(),
      studentId: _idController.text.trim(),
      section: _sectionController.text.trim(),
      gradeLevel: _gradeLevel!,
    );

    setState(() => _isLoading = false);

    if (user != null) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => SnedInterafce1(userName: _nameController.text)),
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to create account. Email might be in use or invalid."),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent, 
        elevation: 0, 
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
        title: const Text(
          "Sign Up",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 22,
            letterSpacing: -0.5,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 10.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Side-by-side Images with equal sizing
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      "assets/pictures/image 1.png", 
                      width: 100, 
                      height: 100, 
                      fit: BoxFit.contain
                    ),
                    const SizedBox(width: 20),
                    Image.asset(
                      "assets/pictures/image 66.png", 
                      width: 100, 
                      height: 100, 
                      fit: BoxFit.contain
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Standard full-width fields with examples
                _buildInputField(
                  label: "Full Name", 
                  hintText: "e.g. Juan Dela Cruz",
                  controller: _nameController,
                  keyboardType: TextInputType.name,
                ),
                _buildInputField(
                  label: "Email Address", 
                  hintText: "e.g. juan@handspeak.edu",
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                ),

                // Side-by-side Row
                Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildDropdown(
                          label: "Grade Level", 
                          items: _gradeOptions, 
                          value: _gradeLevel,
                          onChanged: (v) => setState(() => _gradeLevel = v), 
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildInputField(
                          label: "Section", 
                          hintText: "e.g. Narra",
                          controller: _sectionController,
                          isBottomPadded: false, 
                        ),
                      ),
                    ],
                  ),
                ),

                // Fields below the row with examples
                _buildInputField(
                  label: "Student ID", 
                  hintText: "e.g. 26001",
                  controller: _idController,
                ),
                
                _buildInputField(
                  label: "Password", 
                  hintText: "••••••••",
                  controller: _passController, 
                  obscureText: _obscurePassword,
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: IconButton(
                      icon: Icon(
                        _obscurePassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                        color: const Color(0xFF8E8E93),
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                ),
                
                _buildInputField(
                  label: "Confirm Password", 
                  hintText: "••••••••",
                  controller: _confirmPassController, 
                  obscureText: _obscureConfirmPassword,
                  suffixIcon: Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                        color: const Color(0xFF8E8E93),
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Sign Up Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _handleSignUp,
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFFFFB800),
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
                        : const Text(
                            "Sign Up", 
                            style: TextStyle(
                              color: Colors.white, 
                              fontSize: 17, 
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.4,
                            )
                          ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Helper updated to accept hintText
  Widget _buildInputField({
    required String label, 
    required TextEditingController controller, 
    String? hintText,
    bool obscureText = false, 
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    bool isBottomPadded = true,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isBottomPadded ? 16.0 : 0.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12.0, bottom: 6.0),
            child: Text(
              label, 
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
            ),
          ),
          TextFormField(
            controller: controller,
            obscureText: obscureText,
            keyboardType: keyboardType,
            style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.w400),
            validator: (v) => v == null || v.isEmpty ? "Required" : null,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: Color(0xFFC7C7CC), fontSize: 15), 
              filled: true,
              fillColor: const Color(0xFFF2F2F7), 
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(32), 
                borderSide: BorderSide.none,
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(32),
                borderSide: const BorderSide(color: Colors.redAccent, width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(32),
                borderSide: const BorderSide(color: Colors.redAccent, width: 2),
              ),
              suffixIcon: suffixIcon,
            ),
          ),
        ],
      ),
    );
  }

  // Refactored Helper for Dropdown
  Widget _buildDropdown({
    required String label, 
    required List<String> items, 
    required Function(String?) onChanged, 
    required String? value,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12.0, bottom: 6.0),
          child: Text(
            label, 
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          height: 52, 
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F7),
            borderRadius: BorderRadius.circular(32),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              hint: const Text("Select", style: TextStyle(color: Color(0xFFC7C7CC), fontSize: 15)),
              isExpanded: true,
              icon: const Icon(CupertinoIcons.chevron_down, size: 16, color: Color(0xFF8E8E93)),
              style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.w400),
              onChanged: onChanged,
              items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
            ),
          ),
        ),
      ],
    );
  }
}