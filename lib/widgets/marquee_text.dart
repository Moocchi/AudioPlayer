import 'package:flutter/material.dart';

/// Simple text widget with ellipsis overflow - no animation
class MarqueeText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final double velocity; // kept for API compatibility
  final Duration pauseDuration; // kept for API compatibility

  const MarqueeText({
    super.key,
    required this.text,
    this.style,
    this.velocity = 30.0,
    this.pauseDuration = const Duration(seconds: 1),
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: style,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
