import 'package:flutter/material.dart';

class AnimatedHiResBadge extends StatefulWidget {
  const AnimatedHiResBadge({super.key});

  @override
  State<AnimatedHiResBadge> createState() => _AnimatedHiResBadgeState();
}

class _AnimatedHiResBadgeState extends State<AnimatedHiResBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _shimmerAnimation;

  Future<void> _startAnimationLoop() async {
    while (mounted) {
      await _controller.forward(from: 0);
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1600),
      vsync: this,
    );
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // Run shimmer, then pause 2s before looping again.
    _startAnimationLoop();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _shimmerAnimation,
      builder: (context, child) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: const [
                Color(0xFFFF6B35),
                Color(0xFFFF8C42),
                Color(0xFFFFD700),
                Color(0xFFFF8C42),
                Color(0xFFFF6B35),
              ],
              stops: [
                (_shimmerAnimation.value - 1.0).clamp(0.0, 1.0),
                (_shimmerAnimation.value - 0.5).clamp(0.0, 1.0),
                _shimmerAnimation.value.clamp(0.0, 1.0),
                (_shimmerAnimation.value + 0.5).clamp(0.0, 1.0),
                (_shimmerAnimation.value + 1.0).clamp(0.0, 1.0),
              ],
            ),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF6B35).withOpacity(0.35),
                blurRadius: 6,
                spreadRadius: 0,
              ),
            ],
          ),
          child: const Text(
            'Hi-Res',
            style: TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}
