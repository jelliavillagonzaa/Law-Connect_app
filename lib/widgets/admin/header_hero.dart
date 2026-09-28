import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'admin_ui_theme.dart';

class AdminSearchHit {
  const AdminSearchHit({
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

class HeaderHero extends StatefulWidget {
  const HeaderHero({
    super.key,
    this.adminName,
    this.badgeCount = 0,
    this.findHits,
    this.onSubmitted,
    this.onBellTap,
  });

  final String? adminName;
  final int badgeCount;
  final List<AdminSearchHit> Function(String query)? findHits;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onBellTap;

  @override
  State<HeaderHero> createState() => _HeaderHeroState();
}

class _HeaderHeroState extends State<HeaderHero> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  List<AdminSearchHit> _hits = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onQueryChanged);
  }

  @override
  void didUpdateWidget(HeaderHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.findHits != widget.findHits) {
      _onQueryChanged();
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onQueryChanged);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    List<AdminSearchHit> hits = const [];
    try {
      hits = widget.findHits?.call(_searchController.text) ?? const [];
    } catch (_) {
      hits = const [];
    }
    if (!mounted) return;
    setState(() => _hits = hits);
  }

  void _submit() {
    final query = _searchController.text.trim();
    widget.onSubmitted?.call(query);
    _searchFocus.unfocus();
  }

  void _clearSearch() {
    _searchController.clear();
    widget.onSubmitted?.call('');
    setState(() => _hits = const []);
  }

  void _pickHit(AdminSearchHit hit) {
    hit.onTap();
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() => _hits = const []);
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 980;
    final name = (widget.adminName ?? 'admin').trim().isEmpty
        ? 'admin'
        : widget.adminName!.trim();
    final now = DateTime.now();
    final dateLabel = DateFormat('EEEE, MMMM d, y').format(now);
    final showHits =
        _hits.isNotEmpty && _searchController.text.trim().isNotEmpty;
    final searchField = _GlassSearch(
      controller: _searchController,
      focusNode: _searchFocus,
      onSubmitted: (_) => _submit(),
      onClear: _clearSearch,
    );

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: AdminUi.heroGradient,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(AdminUi.heroRadius),
          bottomRight: Radius.circular(AdminUi.heroRadius),
        ),
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AdminUi.heroRadius),
          bottomRight: Radius.circular(AdminUi.heroRadius),
        ),
        child: Stack(
          children: [
            Positioned(
              right: compact ? -48 : -24,
              top: compact ? -28 : -36,
              bottom: compact ? -28 : -36,
              width: compact ? 160 : 220,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.14,
                  child: Image.asset(
                    'assets/Landingpage.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.centerRight,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.balance,
                      size: compact ? 120 : 160,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              right: compact ? 8 : 28,
              top: 12,
              bottom: 12,
              child: IgnorePointer(
                child: Icon(
                  Icons.balance,
                  size: compact ? 96 : 140,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 20,
                compact ? 12 : 14,
                compact ? 14 : 20,
                compact ? 14 : 16,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (compact) ...[
                    searchField,
                    if (showHits) ...[
                      const SizedBox(height: 8),
                      _SearchResults(hits: _hits, onPick: _pickHit),
                    ],
                    const SizedBox(height: 10),
                    _GlassDate(label: dateLabel),
                  ] else ...[
                    Row(
                      children: [
                        Expanded(child: searchField),
                        const SizedBox(width: 10),
                        _GlassDate(label: dateLabel),
                      ],
                    ),
                    if (showHits) ...[
                      const SizedBox(height: 8),
                      _SearchResults(hits: _hits, onPick: _pickHit),
                    ],
                  ],
                  SizedBox(height: compact ? 12 : 14),
                  Text(
                    'Welcome back, $name!',
                    style: GoogleFonts.inter(
                      fontSize: compact ? 20 : 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      height: 1.15,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Here's what's happening with your system today.",
                    style: GoogleFonts.inter(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassSearch extends StatelessWidget {
  const _GlassSearch({
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
        final hasText = value.text.trim().isNotEmpty;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                hintText: 'Search users, cases, logs...',
                hintStyle: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
                suffixIcon: hasText
                    ? IconButton(
                        tooltip: 'Clear search',
                        onPressed: onClear,
                        icon: Icon(
                          Icons.close_rounded,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.10),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: Colors.white.withValues(alpha: 0.28),
                  ),
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

  final List<AdminSearchHit> hits;
  final ValueChanged<AdminSearchHit> onPick;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 8,
      shadowColor: AdminUi.primary.withValues(alpha: 0.22),
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
              leading: Icon(hit.icon, color: AdminUi.primary, size: 22),
              title: Text(
                hit.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w600,
                  color: AdminUi.text,
                ),
              ),
              subtitle: Text(
                hit.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: AdminUi.muted,
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

class _GlassDate extends StatelessWidget {
  const _GlassDate({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: 16,
            color: Colors.white.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.92),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
