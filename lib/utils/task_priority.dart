import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Staff task priority. Stored as int; 1 (legacy Urgent) displays as High.
class TaskPriority {
  TaskPriority._();

  static const int high = 2;
  static const int normal = 3;
  static const int low = 4;

  static String label(int? priority) {
    switch (priority) {
      case 1:
      case high:
        return 'High';
      case low:
        return 'Low';
      case normal:
      default:
        return 'Normal';
    }
  }

  static Color color(int? priority) {
    switch (priority) {
      case 1:
      case high:
        return Colors.orange;
      case low:
        return Colors.grey;
      case normal:
      default:
        return AppTheme.royalBlue;
    }
  }

  /// Dropdown / form value. Maps legacy Urgent (1) to High.
  static int coerce(int? priority) {
    switch (priority) {
      case 1:
      case high:
        return high;
      case low:
        return low;
      case normal:
      default:
        return normal;
    }
  }
}
