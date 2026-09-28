import 'dart:ui';

import 'package:flutter/material.dart' hide SearchBar;
import 'package:intl/intl.dart';

import 'attorney_ui_theme.dart';

class AttorneySearchHit {
  const AttorneySearchHit({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class AttorneyTopBar extends StatefulWidget {
  const AttorneyTopBar({
    super.key,
    required this.notification,
    this.padding = const EdgeInsets.fromLTRB(0, 8, 0, 4),
    this.findHits,
    this.onQueryChanged,
    this.onSubmitted,
  });

  final Widget notification;
  final EdgeInsetsGeometry padding;
  final List<AttorneySearchHit> Function(String query)? findHits;
  final ValueChanged<String>? onQueryChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AttorneyTopBar> createState() => _AttorneyTopBarState();
}

class _AttorneyTopBarState extends State<AttorneyTopBar> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  List<AttorneySearchHit> _hits = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    List<AttorneySearchHit> hits = const [];
    try {
      final query = '${_searchController.text}';
      hits = widget.findHits?.call(query) ?? const <AttorneySearchHit>[];
    } catch (_) {
      hits = const [];
    }
    if (!mounted) return;
    setState(() => _hits = hits);
    widget.onQueryChanged?.call('${_searchController.text}');
  }

  void _submit() {
    final query = _searchController.text.trim();
    widget.onSubmitted?.call(query);
    _searchFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 1100;
    final now = DateTime.now();
    final dateLabel = DateFormat('MMM d, y').format(now);
    final weekday = DateFormat('EEEE').format(now);
    final searchField = _SearchField(
      controller: _searchController,
      focusNode: _searchFocus,
      onSubmitted: (_) => _submit(),
      onClear: () {
        _searchController.clear();
        widget.onSubmitted?.call('');
      },
    );

    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          compact
              ? Column(
                  children: [
                    searchField,
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        widget.notification,
                        const Spacer(),
                        _DateBlock(dateLabel: dateLabel, weekday: weekday),
                      ],
                    ),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 16),
                    widget.notification,
                    const SizedBox(width: 16),
                    _DateBlock(dateLabel: dateLabel, weekday: weekday),
                  ],
                ),
          if (_hits.isNotEmpty && '${_searchController.text}'.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            _SearchResults(
              hits: _hits,
              onPick: (hit) {
                hit.onTap();
                _searchFocus.unfocus();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              style: AttorneyUi.style(
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
                color: AttorneyUi.text,
              ),
              cursorColor: AttorneyUi.primary,
              decoration: InputDecoration(
                hintText: 'Search cases, clients, or appointments...',
                hintStyle: AttorneyUi.style(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: AttorneyUi.muted,
                ),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AttorneyUi.primary,
                  size: 20,
                ),
                suffixIcon: '${value.text}'.isNotEmpty &&
                        '${value.text}' != 'null' &&
                        '${value.text}' != 'undefined'
                    ? IconButton(
                        tooltip: 'Clear search',
                        onPressed: onClear,
                        icon: const Icon(Icons.close_rounded, color: AttorneyUi.muted, size: 18),
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF3F5F8),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AttorneyUi.primary, width: 1.1),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AttorneyUi.primary, width: 1.1),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: AttorneyUi.primary, width: 1.4),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.hits, required this.onPick});

  final List<AttorneySearchHit> hits;
  final ValueChanged<AttorneySearchHit> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: AttorneyUi.primary.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 280),
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 6),
          itemCount: hits.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final hit = hits[index];
            return ListTile(
              dense: true,
              leading: Icon(hit.icon, color: AttorneyUi.primary, size: 22),
              title: Text(
                hit.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AttorneyUi.style(
                  fontWeight: FontWeight.w600,
                  color: AttorneyUi.text,
                ),
              ),
              subtitle: Text(
                hit.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AttorneyUi.style(
                  fontSize: 12,
                  color: AttorneyUi.muted,
                ),
              ),
              onTap: () => onPick(hit),
            );
          },
        ),
      ),
    );
  }
}

class _DateBlock extends StatelessWidget {
  const _DateBlock({required this.dateLabel, required this.weekday});

  final String dateLabel;
  final String weekday;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          dateLabel,
          style: AttorneyUi.style(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AttorneyUi.text,
          ),
        ),
        Text(
          weekday,
          style: AttorneyUi.style(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: AttorneyUi.muted,
          ),
        ),
      ],
    );
  }
}
