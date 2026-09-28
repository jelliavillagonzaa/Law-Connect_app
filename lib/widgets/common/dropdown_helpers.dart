import 'package:flutter/material.dart';

/// Single-line label for [DropdownButtonFormField] menu items (prevents APK overflow).
Widget dropdownEllipsisText(
  String text, {
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
}) {
  return Text(
    text,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    softWrap: false,
    style: TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
    ),
  );
}

/// Collapsed dropdown label — keeps selected text on one horizontal line.
Widget dropdownSelectedLabel(
  String text, {
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
}) {
  return Align(
    alignment: AlignmentDirectional.centerStart,
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: TextStyle(
        fontSize: fontSize ?? 16,
        fontWeight: fontWeight,
        color: color,
      ),
    ),
  );
}

List<Widget> dropdownSelectedLabels(
  List<String> labels, {
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
}) {
  return labels
      .map(
        (label) => dropdownSelectedLabel(
          label,
          fontSize: fontSize,
          fontWeight: fontWeight,
          color: color,
        ),
      )
      .toList();
}
