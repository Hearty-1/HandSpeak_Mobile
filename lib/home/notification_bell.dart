import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../home/notifications.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _bellAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Bell swinging animation (rings back and forth)
    _bellAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.15).chain(CurveTween(curve: Curves.easeOut)), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.15, end: -0.15).chain(CurveTween(curve: Curves.easeInOut)), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.15, end: 0.10).chain(CurveTween(curve: Curves.easeInOut)), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.10, end: -0.05).chain(CurveTween(curve: Curves.easeInOut)), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.05, end: 0.0).chain(CurveTween(curve: Curves.easeIn)), weight: 1),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 10), // Pause between rings
    ]).animate(_animationController);

    // Badge pulsing animation
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeInOut), // Pulse syncs with the start of the ring
      ),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.colorScheme.onSurface;
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(currentUserId).snapshots(),
      builder: (context, snapshot) {
        bool hasUnreadNotifications = false;
        if (snapshot.hasData && snapshot.data!.exists) {
          final userData = snapshot.data!.data() as Map<String, dynamic>?;
          final List<dynamic> rawNotifications = userData?['notifications'] ?? [];
          hasUnreadNotifications = rawNotifications.any(
            (n) => (n is Map) && (n['isRead'] == false),
          );
        }

        if (hasUnreadNotifications) {
          if (!_animationController.isAnimating) _animationController.repeat();
        } else {
          _animationController.reset();
          _animationController.stop();
        }

        return Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.cardColor.withOpacity(0.4),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.2), 
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        // The Bell Icon (Animated)
                        AnimatedBuilder(
                          animation: _bellAnimation,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _bellAnimation.value * math.pi,
                              alignment: Alignment.topCenter,
                              child: Icon(
                                Icons.notifications_rounded,
                                color: hasUnreadNotifications ? theme.primaryColor : textColor.withOpacity(0.8),
                                size: 24,
                              ),
                            );
                          },
                        ),

                        // The Glowing Red Badge (Animated)
                        if (hasUnreadNotifications)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: AnimatedBuilder(
                              animation: _pulseAnimation,
                              builder: (context, child) {
                                return Transform.scale(
                                  scale: _pulseAnimation.value,
                                  child: Container(
                                    width: 11,
                                    height: 11,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF34B1B),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: theme.cardColor,
                                        width: 1.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFF34B1B).withOpacity(0.6),
                                          blurRadius: 6 * _pulseAnimation.value,
                                          spreadRadius: 1.5 * _pulseAnimation.value,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const NotificationsScreen()),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}