// lib/utils/color_utils.dart
import 'package:flutter/material.dart';

Color withOpacityCompat(Color color, double opacity) {
  final clamped = opacity.clamp(0.0, 1.0);
  final a = (clamped * 255.0).round() & 0xff;

  // Use component accessors recommended by analyzer (.r/.g/.b)
  final r = (color.r * 255.0).round() & 0xff;
  final g = (color.g * 255.0).round() & 0xff;
  final b = (color.b * 255.0).round() & 0xff;

  return Color.fromARGB(a, r, g, b);
}
