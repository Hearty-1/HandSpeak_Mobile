import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';

class CreateAccount extends StatefulWidget {
  const CreateAccount({super.key});

  @override
  State<CreateAccount> createState() => _CreateAccountState();
}

class _CreateAccountState extends State<CreateAccount> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
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
          content: Text("Please fix the errors in the form and select a grade."),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    var user = await _authService.signUpWithStudentDetails(
      email: _emailController.text.trim(),
      password: _passController.text.trim(),
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      studentId: _idController.text.trim(),
      section: _sectionController.text.trim(),
      gradeLevel: _gradeLevel!,
    );

    setState(() => _isLoading = false);

    if (user != null) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Account created successfully! Please wait for faculty approval."),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.green,
        ),
      );
      
      Navigator.pop(context); 
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Failed to create account. Email might be in use or invalid."),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.redAccent,
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      "assets/pictures/logo.png", 
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

                _buildInputField(
                  label: "First Name", 
                  hintText: "e.g. Juan",
                  controller: _firstNameController,
                  keyboardType: TextInputType.name,
                  maxLength: 50, // Industry standard for single name fields
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s\-\.]'))],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return "First name is required";
                    if (!RegExp(r'^[a-zA-Z\s\-\.]+$').hasMatch(v)) return "Letters, spaces, and hyphens only";
                    return null;
                  },
                ),
                
                _buildInputField(
                  label: "Middle Name (Optional)", 
                  hintText: "e.g. Santos",
                  controller: _middleNameController,
                  keyboardType: TextInputType.name,
                  isRequired: false, 
                  maxLength: 50,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s\-\.]'))],
                  validator: (v) {
                    if (v != null && v.trim().isNotEmpty && !RegExp(r'^[a-zA-Z\s\-\.]+$').hasMatch(v)) {
                      return "Letters, spaces, and hyphens only";
                    }
                    return null;
                  },
                ),
                
                _buildInputField(
                  label: "Last Name", 
                  hintText: "e.g. Dela Cruz",
                  controller: _lastNameController,
                  keyboardType: TextInputType.name,
                  maxLength: 50,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s\-\.]'))],
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return "Last name is required";
                    if (!RegExp(r'^[a-zA-Z\s\-\.]+$').hasMatch(v)) return "Letters, spaces, and hyphens only";
                    return null;
                  },
                ),

                _buildInputField(
                  label: "Email Address", 
                  hintText: "e.g. juan@handspeak.edu",
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 254, // RFC 5321 Standard for maximum email length
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return "Email is required";
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) {
                      return "Enter a valid email format (e.g. name@domain.com)";
                    }
                    return null;
                  },
                ),

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
                          maxLength: 20, 
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z\s\-\.]'))],
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return "Section required";
                            if (!RegExp(r'^[a-zA-Z\s\-\.]+$').hasMatch(v)) return "Letters only";
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                _buildInputField(
                  label: "Student ID", 
                  hintText: "e.g. 26001",
                  controller: _idController,
                  maxLength: 20, // Standard limit for alphanumeric IDs
                  validator: (v) => v == null || v.trim().isEmpty ? "Student ID is required" : null,
                ),
                
                _buildInputField(
                  label: "Password", 
                  hintText: "••••••••",
                  controller: _passController, 
                  obscureText: _obscurePassword,
                  maxLength: 128, // Complies with NIST SP 800-63B allowing long passphrases
                  validator: (v) {
                    if (v == null || v.isEmpty) return "Password is required";
                    if (v.length < 8) return "Must be at least 8 characters long";
                    return null;
                  },
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
                  maxLength: 128,
                  validator: (v) {
                    if (v == null || v.isEmpty) return "Please confirm your password";
                    if (v != _passController.text) return "Passwords do not match";
                    return null;
                  },
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

  Widget _buildInputField({
    required String label, 
    required TextEditingController controller, 
    String? hintText,
    bool obscureText = false, 
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
    bool isBottomPadded = true,
    bool isRequired = true,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
  }) {
    List<TextInputFormatter> formatters = [];
    if (maxLength != null) {
      formatters.add(LengthLimitingTextInputFormatter(maxLength));
    }
    if (inputFormatters != null) {
      formatters.addAll(inputFormatters);
    }

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
            inputFormatters: formatters, 
            autovalidateMode: AutovalidateMode.onUserInteraction,
            style: const TextStyle(fontSize: 16, color: Colors.black, fontWeight: FontWeight.w400),
            validator: validator ?? (isRequired ? (v) => v == null || v.trim().isEmpty ? "Required" : null : null),
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
                borderSide: const BorderSide(color: Colors.red, width: 1.5),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(32),
                borderSide: const BorderSide(color: Colors.red, width: 2.5),
              ),
              errorStyle: const TextStyle(
                height: 1.0, 
                color: Colors.red, 
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
              suffixIcon: suffixIcon,
            ),
          ),
        ],
      ),
    );
  }

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