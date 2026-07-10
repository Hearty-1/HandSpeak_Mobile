import 'package:flutter/material.dart';
import '../auth/login_screen.dart';

void main() => runApp(const MaterialApp(home: MainLogin(), debugShowCheckedModeBanner: false));

class MainLogin extends StatelessWidget {
  const MainLogin({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        final scale = constraints.maxWidth / 393;
        return Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.white,
          child: Stack(
            children: [
              // Image 1
              Positioned(
                top: 85 * scale, 
                left: 133 * scale, 
                child: Image.asset("assets/pictures/image 1.png", width: 117 * scale)
              ),
              
              // Image 66 (Added here)
              Positioned(
                left: -3 * scale,
                top: 236 * scale,
                child: Image.asset(
                  "assets/pictures/image 66.png", 
                  width: 390 * scale, 
                  height: 420 * scale, 
                  fit: BoxFit.fill
                ),
              ),

              // Proceed Button
              Positioned(
                bottom: 40 * scale, 
                left: 15 * scale,
                child: GestureDetector(
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => SnedStudentLogin())),
                  child: Container(
                    width: 364 * scale, 
                    height: 65 * scale,
                    decoration: BoxDecoration(color: const Color(0xFFFFB800), borderRadius: BorderRadius.circular(16)),
                    child: const Center(child: Text('Proceed to Login', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}