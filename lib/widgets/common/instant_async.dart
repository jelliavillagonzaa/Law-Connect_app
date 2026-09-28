import 'package:flutter/material.dart';

/// Empty fill used instead of a blocking spinner so layouts stay instant.
class InstantFill extends StatelessWidget {
  const InstantFill({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
