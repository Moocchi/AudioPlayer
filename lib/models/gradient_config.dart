import 'package:flutter/material.dart';

enum GradientType { auto, custom }

class GradientConfig {
  final GradientType type;
  final Color? color1;
  final Color? color2;

  const GradientConfig({required this.type, this.color1, this.color2});

  const GradientConfig.auto({this.color1, this.color2})
    : type = GradientType.auto;

  const GradientConfig.custom({required Color color1, required Color color2})
    : type = GradientType.custom,
      color1 = color1,
      color2 = color2;

  // Serialize to SharedPreferences
  Map<String, dynamic> toJson() {
    if (type == GradientType.auto) {
      return {
        'type': 'auto',
        if (color1 != null) 'color1': color1!.value,
        if (color2 != null) 'color2': color2!.value,
      };
    } else {
      return {
        'type': 'custom',
        'color1': color1!.value,
        'color2': color2!.value,
      };
    }
  }

  /// Get colors as a list for gradient
  List<Color> getColors() {
    if (color1 != null && color2 != null) {
      return [color1!, color2!];
    }
    // Default auto colors
    return [Colors.purple.shade800, Colors.blue.shade800];
  }

  // Deserialize from SharedPreferences
  factory GradientConfig.fromJson(Map<String, dynamic> json) {
    final type = json['type'] == 'auto'
        ? GradientType.auto
        : GradientType.custom;

    if (type == GradientType.custom) {
      return GradientConfig.custom(
        color1: Color(json['color1'] as int),
        color2: Color(json['color2'] as int),
      );
    } else {
      // Auto type - try to load saved colors if any
      if (json['color1'] != null && json['color2'] != null) {
        return GradientConfig.auto(
          color1: Color(json['color1'] as int),
          color2: Color(json['color2'] as int),
        );
      }
      return const GradientConfig.auto();
    }
  }
}
