import 'package:flutter/material.dart';

/// Premium Hi-Res badge with elegant gradient - no heavy animation
class AnimatedHiResBadge extends StatelessWidget {
  const AnimatedHiResBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFF6B35),  // Orange
            Color(0xFFFF8C42),  // Light orange
          ],
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: const Color(0xFFFFD700).withOpacity(0.5),
          width: 0.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF6B35).withOpacity(0.4),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: const Text(
        'Hi-Res',
        style: TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
          shadows: [
            Shadow(
              color: Colors.black26,
              blurRadius: 2,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}
