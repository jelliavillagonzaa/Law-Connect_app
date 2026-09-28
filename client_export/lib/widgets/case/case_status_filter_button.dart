import 'package:flutter/material.dart';

import '../../utils/case_status_filter.dart';

class CaseStatusFilterButton extends StatelessWidget {
  const CaseStatusFilterButton({
    super.key,
    required this.selected,
    required this.onSelected,
    this.iconColor,
  });

  final String selected;
  final ValueChanged<String> onSelected;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Filter: ${CaseStatusFilter.label(selected)}',
      onSelected: onSelected,
      itemBuilder: (context) => [
        for (final value in CaseStatusFilter.values)
          PopupMenuItem<String>(
            value: value,
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: value == selected
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                ),
                Expanded(child: Text(CaseStatusFilter.menuLabel(value))),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          Icons.filter_list,
          color: iconColor ?? IconTheme.of(context).color,
        ),
      ),
    );
  }
}
