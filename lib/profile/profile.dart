import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/progress_service.dart'; 
import '../auth/login_screen.dart';        
import '../home/home.dart'; 
import '../module/module.dart'; 
import '../leaderboard/leaderboard.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFFFF9E5),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.account_circle, size: 80, color: Color(0xFFFFB800)),
              const SizedBox(height: 16),
              const Text('No student account found.', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF222222))),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFB800), 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                ),
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const SnedStudentLogin()), (route) => false),
                child: const Text('Go to Login', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              )
            ],
          ),
        ),
      );
    }

    final ProgressService progressService = ProgressService();

    return Scaffold(
      backgroundColor: const Color(0xFFFFF9E5),
      
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFB800),
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: true, 
        iconTheme: const IconThemeData(color: Colors.black), 
        title: const Text(
          "My Profile",
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Image.asset("assets/pictures/image 66.png", width: 45),
          ),
        ],
      ),

      bottomNavigationBar: SafeArea(
        child: Container(
          width: double.infinity,
          height: 78,
          margin: const EdgeInsets.only(bottom: 12, left: 10, right: 10),
          decoration: ShapeDecoration(
            color: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            shadows: const [BoxShadow(color: Color(0x0C132C4A), blurRadius: 16, offset: Offset(0, 5))],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                icon: const Icon(Icons.home, color: Colors.grey, size: 28), 
                onPressed: () {
                  String displayName = currentUser.displayName ?? currentUser.email?.split('@')[0] ?? "Student";
                  Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (context) => SnedInterafce1(userName: displayName)), (route) => false);
                },
              ),
              IconButton(
                icon: const Icon(Icons.auto_stories, color: Colors.grey, size: 28), 
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SnedInterface2())),
              ),
              IconButton(
                icon: const Icon(Icons.emoji_events, color: Colors.grey, size: 28), 
                onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LeaderboardScreen())),
              ),
              IconButton(
                icon: const Icon(Icons.person, color: Colors.black, size: 28), 
                onPressed: () {}, 
              ),
            ],
          ),
        ),
      ),
      
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot>(
          stream: progressService.getUserProgressStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFB800))));
            }

            String name = currentUser.displayName ?? "Guest Student";
            String email = currentUser.email ?? "student@handspeak.edu";
            String avatarUrl = currentUser.photoURL ?? "";
            int stars = 0, xp = 0, streak = 0, followers = 0, following = 0;
            Map<String, dynamic> progressMap = {};

            if (snapshot.hasData && snapshot.data!.exists) {
              final userData = snapshot.data!.data() as Map<String, dynamic>?;
              if (userData != null) {
                name = userData['name'] ?? name;
                email = userData['email'] ?? email;
                avatarUrl = userData['avatar'] ?? avatarUrl;
                stars = userData['stars'] ?? 0;
                streak = userData['streak'] ?? 0;
                followers = userData['followers'] ?? 0;
                following = userData['following'] ?? 0;
                
                if (userData.containsKey('progress') && userData['progress'] is Map) {
                  progressMap = Map<String, dynamic>.from(userData['progress']);
                  xp = userData['xp'] ?? 0;
                  if (xp == 0) progressMap.forEach((key, val) { if (val is num) xp += val.toInt(); });
                }
              }
            }

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Stack(
  alignment: Alignment.bottomRight,
  children: [
    ClipOval(
      child: avatarUrl.isNotEmpty
          ? Image.network(
              avatarUrl,
              width: 100,
              height: 100,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                // If the link is bad, show the default icon instead of crashing
                return Container(
                  width: 100, height: 100, color: const Color(0xFFFFEFA7),
                  child: const Icon(Icons.person_rounded, size: 60, color: Color(0xFFFFB800)),
                );
              },
            )
          : Container(
              width: 100, height: 100, color: const Color(0xFFFFEFA7),
              child: const Icon(Icons.person_rounded, size: 60, color: Color(0xFFFFB800)),
            ),
    ),
    Container(
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: IconButton(
        icon: const Icon(Icons.edit, size: 20, color: Color(0xFF222222)),
        onPressed: () => _showSettingsDialog(context, currentUser, currentName: name, currentAvatar: avatarUrl),
      ),
    )
  ],
),
                  const SizedBox(height: 16),
                  Text(name, style: const TextStyle(color: Color(0xFF222222), fontSize: 24, fontWeight: FontWeight.w700)),
                  Text(email, style: const TextStyle(color: Color(0x7F222222), fontSize: 14, decoration: TextDecoration.underline)),
                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Column(
                        children: [
                          Text('$followers', style: const TextStyle(color: Color(0xFF222222), fontSize: 20, fontWeight: FontWeight.bold)),
                          const Text('Followers', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      Container(
                        height: 30,
                        width: 1.5,
                        color: Colors.grey.shade300,
                        margin: const EdgeInsets.symmetric(horizontal: 25),
                      ),
                      Column(
                        children: [
                          Text('$following', style: const TextStyle(color: Color(0xFF222222), fontSize: 20, fontWeight: FontWeight.bold)),
                          const Text('Following', style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),

                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFB800), 
                      borderRadius: BorderRadius.circular(16), 
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 5))]
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatItem("Streak", "$streak", Icons.local_fire_department_rounded),
                        _buildStatItem("Stars", "$stars", Icons.star_rounded),
                        _buildStatItem("XP", "$xp", Icons.bolt_rounded),
                      ],
                    ),
                  ),
                  const SizedBox(height: 30),

                  const Align(alignment: Alignment.centerLeft, child: Text('My Badges', style: TextStyle(color: Color(0xFF222222), fontSize: 20, fontWeight: FontWeight.bold))),
                  const SizedBox(height: 15),

                  GridView.count(
                    crossAxisCount: 3, 
                    shrinkWrap: true, 
                    physics: const NeverScrollableScrollPhysics(), 
                    mainAxisSpacing: 16, 
                    crossAxisSpacing: 16, 
                    childAspectRatio: 0.8,
                    children: [
                      _buildBadge("First Sign", "assets/pictures/alphabet.png", isUnlocked: xp > 0),
                      _buildBadge("Star Scholar", "assets/pictures/large star.png", isUnlocked: stars >= 10),
                      _buildBadge("Sign Master", "assets/pictures/sign.png", isUnlocked: xp >= 1000), 
                    ],
                  ),
                  const SizedBox(height: 40),

                  SizedBox(
                    width: double.infinity, 
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () => _handleSignOut(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFFEFA7), 
                        elevation: 0, 
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFFFB800), width: 1.5))
                      ),
                      child: const Text('Sign Out', style: TextStyle(color: Color(0xFFFFB800), fontSize: 18, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // --- SETTINGS / EDIT PROFILE DIALOG ---
  void _showSettingsDialog(BuildContext context, User user, {String? currentName, String? currentAvatar}) {
    final TextEditingController nameController = TextEditingController(text: currentName ?? user.displayName ?? "");
    final TextEditingController avatarController = TextEditingController(text: currentAvatar ?? user.photoURL ?? "");
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        bool isSaving = false;

        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.manage_accounts, color: Color(0xFFFFB800)),
                  SizedBox(width: 8),
                  Text("Edit Profile", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                ],
              ),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Display Name Field
                    TextFormField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: "Display Name",
                        prefixIcon: const Icon(Icons.person_outline, color: Colors.grey),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFFFFB800), width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return "Name cannot be empty";
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    // Avatar URL Field
                    TextFormField(
                      controller: avatarController,
                      decoration: InputDecoration(
                        labelText: "Avatar Image URL",
                        hintText: "https://example.com/image.png",
                        prefixIcon: const Icon(Icons.image_outlined, color: Colors.grey),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Color(0xFFFFB800), width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text("Cancel", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  onPressed: isSaving 
                    ? null 
                    : () async {
                        if (formKey.currentState!.validate()) {
                          setState(() => isSaving = true);
                          
                          try {
                            final newName = nameController.text.trim();
                            final newAvatar = avatarController.text.trim();
                            
                            // 1. Update Firebase Auth Profile
                            await user.updateDisplayName(newName);
                            if (newAvatar.isNotEmpty) {
                              await user.updatePhotoURL(newAvatar);
                            }
                            
                            // 2. Update Firestore Database Document
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(user.uid)
                                .set({
                                  'name': newName,
                                  'avatar': newAvatar,
                                }, SetOptions(merge: true));

                            if (context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Profile updated successfully!"), backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            setState(() => isSaving = false);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Error updating profile: $e"), backgroundColor: Colors.red),
                              );
                            }
                          }
                        }
                      },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFB800),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: isSaving 
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Text("Save", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          }
        );
      }
    );
  }

  void _handleSignOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (context) => const SnedStudentLogin()), (route) => false);
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: Colors.white, size: 28), const SizedBox(height: 8),
        Text(value, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: Color(0xFF222222), fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildBadge(String label, String imagePath, {required bool isUnlocked}) {
    return Opacity(
      opacity: isUnlocked ? 1.0 : 0.35,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70, height: 70,
            decoration: BoxDecoration(
              color: isUnlocked ? Colors.white : Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isUnlocked ? const Color(0xFFFFB800) : Colors.transparent, width: 1.5),
              image: DecorationImage(image: AssetImage(imagePath), fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 8),
          Text(label, textAlign: TextAlign.center, style: TextStyle(color: isUnlocked ? const Color(0xFF222222) : Colors.grey[600], fontSize: 11, fontWeight: isUnlocked ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }
}