import 'package:flutter/material.dart';

import '../../utils/safe_network_image.dart';

/// Circle avatar that never throws when a profile URL returns HTML or 404.
class SafeNetworkAvatar extends StatelessWidget {
  final String? photoUrl;
  final double radius;
  final String fallbackLetter;
  final Color? backgroundColor;
  final Color? foregroundColor;

  const SafeNetworkAvatar({
    super.key,
    this.photoUrl,
    required this.radius,
    required this.fallbackLetter,
    this.backgroundColor,
    this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final letter = fallbackLetter.isNotEmpty
        ? fallbackLetter.substring(0, 1).toUpperCase()
        : '?';

    if (!isValidNetworkImageUrl(photoUrl)) {
      return _letterAvatar(letter);
    }

    final size = radius * 2;
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Colors.grey.shade200,
      child: ClipOval(
        child: Image.network(
          photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _letterChild(letter),
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return SizedBox(
              width: size,
              height: size,
              child: Center(
                child: SizedBox(
                  width: radius * 0.6,
                  height: radius * 0.6,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: foregroundColor,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _letterAvatar(String letter) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? Colors.grey.shade200,
      child: _letterChild(letter),
    );
  }

  Widget _letterChild(String letter) {
    return Text(
      letter,
      style: TextStyle(
        fontSize: radius * 0.85,
        fontWeight: FontWeight.bold,
        color: foregroundColor ?? Colors.grey.shade700,
      ),
    );
  }
}
