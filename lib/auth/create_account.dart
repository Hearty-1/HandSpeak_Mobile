import 'package:flutter/material.dart';
import '../home/home.dart';

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

  String? _gradeLevel;
  final List<String> _gradeOptions = ["SNED", "Grade 1", "Grade 2", "Grade 3", "Grade 4", "Grade 5", "Grade 6"];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0, iconTheme: const IconThemeData(color: Colors.black)),
      body: LayoutBuilder(builder: (context, constraints) {
        final double scale = constraints.maxWidth / 393;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 33 * scale),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                Image.asset("assets/pictures/image 1.png", width: 75 * scale),
                SizedBox(height: 10 * scale),
                Image.asset("assets/pictures/image 66.png", width: 150 * scale),
                SizedBox(height: 20 * scale),

                // Standard full-width fields
                _buildInputField("Full Name", _nameController, scale),
                _buildInputField("Email Address", _emailController, scale),

                // Side-by-side Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildDropdown("Grade Level", _gradeOptions, (v) => setState(() => _gradeLevel = v), _gradeLevel, scale, width: 155 * scale),
                    _buildInputField("Section", _sectionController, scale, width: 155 * scale),
                  ],
                ),

                // Fields below the row
                _buildInputField("Student ID", _idController, scale),
                _buildInputField("Password", _passController, scale, isPassword: true),
                _buildInputField("Confirm Password", _confirmPassController, scale, isPassword: true),

                SizedBox(height: 20 * scale),

                ElevatedButton(
                  onPressed: () {
                    if (_formKey.currentState!.validate() && _gradeLevel != null) {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => SnedInterafce1(userName: _nameController.text)),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Please fill all required fields.")),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB800),
                    fixedSize: Size(327 * scale, 56 * scale),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32 * scale)),
                  ),
                  child: Text("Sign Up", style: TextStyle(color: Colors.white, fontSize: 16 * scale, fontWeight: FontWeight.bold)),
                ),
                SizedBox(height: 40 * scale),
              ],
            ),
          ),
        );
      }),
    );
  }

  // Helper with flexible width parameter
  Widget _buildInputField(String label, TextEditingController controller, double scale, {bool isPassword = false, double? width}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 10 * scale, bottom: 5 * scale),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14 * scale)),
          ),
          Container(
            width: width ?? 327 * scale, // Use provided width or default
            height: 48 * scale,
            padding: EdgeInsets.symmetric(horizontal: 20 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F1FA),
              borderRadius: BorderRadius.circular(32 * scale),
              border: Border.all(color: Colors.black.withOpacity(0.1)),
            ),
            child: TextFormField(
              controller: controller,
              obscureText: isPassword,
              validator: (v) => v == null || v.isEmpty ? "Required" : null,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
        ],
      ),
    );
  }

  // Helper with flexible width parameter
  Widget _buildDropdown(String label, List<String> items, Function(String?) onChanged, String? value, double scale, {double? width}) {
    return Padding(
      padding: EdgeInsets.only(bottom: 16 * scale),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(left: 10 * scale, bottom: 5 * scale),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14 * scale)),
          ),
          Container(
            width: width ?? 327 * scale,
            height: 48 * scale,
            padding: EdgeInsets.symmetric(horizontal: 20 * scale),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F1FA),
              borderRadius: BorderRadius.circular(32 * scale),
              border: Border.all(color: Colors.black.withOpacity(0.1)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: value,
                hint: const Text("Select"),
                isExpanded: true,
                onChanged: onChanged,
                items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}