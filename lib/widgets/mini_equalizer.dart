import 'package:flutter/material.dart';
import 'dart:math';
import '../theme/app_theme.dart';

class MiniEqualizer extends StatefulWidget {
  final double size;
  final Color color;

  const MiniEqualizer({
    super.key,
    this.size = 12.0,
    this.color = AppTheme.primary,
  });

  @override
  State<MiniEqualizer> createState() => _MiniEqualizerState();
}

class _MiniEqualizerState extends State<MiniEqualizer> with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  final Random _random = Random();

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(3, (index) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: 400 + _random.nextInt(400)),
      )..repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(3, (index) {
          return AnimatedBuilder(
            animation: _controllers[index],
            builder: (context, child) {
              return Container(
                width: widget.size / 4,
                height: widget.size * (0.3 + 0.7 * _controllers[index].value),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}
