import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';

/// Cases by Type analytics (donut + vertical bars, year/month filters).
class AdminCasesByTypePanel extends StatefulWidget {
  const AdminCasesByTypePanel({super.key});

  @override
  State<AdminCasesByTypePanel> createState() => _AdminCasesByTypePanelState();
}

class _AdminCasesByTypePanelState extends State<AdminCasesByTypePanel> {
  final AdminService _adminService = AdminService();

  static const _palette = [
    AppTheme.royalBlue,
    Color(0xFF2E5C8A),
    Color(0xFF4C6FFF),
    Color(0xFF5C4BA5),
    Color(0xFF2D7A4F),
    Color(0xFFB8860B),
    Color(0xFFC55A3F),
    Color(0xFF6B8CAE),
    Color(0xFF3D8B7A),
    Color(0xFF8B6B4A),
  ];

  static const peakHighlightColor = Color(0xFF26C6DA);
  static const _legendVisibleCount = 6;

  int? _selectedYear;
  int? _selectedMonth;
  List<int> _years = [];
  bool _loading = true;
  Map<String, dynamic> _casesByType = {};
  int _totalCases = 0;
  String? _peakMonthLabel;
  int? _peakMonthNumber;
  int _peakMonthCount = 0;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      final years = await _adminService.getCaseYears();
      if (!mounted) return;
      setState(() {
        _years = years;
        _selectedYear = null;
        _selectedMonth = null;
      });
      await _loadFiltered();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFiltered() async {
    setState(() => _loading = true);
    try {
      final analytics = await _adminService.getAnalytics(
        year: _selectedYear,
        month: _selectedMonth,
      );
      if (!mounted) return;
      final raw = analytics['casesByType'];
      final map = raw is Map<String, dynamic>
          ? Map<String, dynamic>.from(raw)
          : raw is Map
          ? Map<String, dynamic>.from(
              raw.map((k, v) => MapEntry(k.toString(), v)),
            )
          : <String, dynamic>{};
      setState(() {
        _casesByType = map;
        _totalCases = _toInt(analytics['totalCases']);
        _peakMonthLabel = analytics['peakMonthLabel'] as String?;
        _peakMonthNumber = _toIntOrNull(analytics['peakMonthNumber']);
        _peakMonthCount = _toInt(analytics['peakMonthCount']);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int? _toIntOrNull(dynamic v) {
    if (v == null) return null;
    return _toInt(v);
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  List<AdminCaseTypeRow> _sortedEntries() {
    final entries = _casesByType.entries
        .map((e) => AdminCaseTypeRow(label: e.key, count: _toInt(e.value)))
        .where((e) => e.count > 0)
        .toList();
    entries.sort((a, b) => b.count.compareTo(a.count));
    return entries;
  }

  void _onYearChanged(int? year) {
    setState(() {
      _selectedYear = year;
      _selectedMonth = null;
    });
    _loadFiltered();
  }

  void _onMonthChanged(int? month) {
    setState(() => _selectedMonth = month);
    _loadFiltered();
  }

  void _onSelectBusiestMonth() {
    if (_peakMonthNumber == null) return;
    setState(() => _selectedMonth = _peakMonthNumber);
    _loadFiltered();
  }

  String _periodLabel() {
    if (_selectedYear == null) return 'All years';
    if (_selectedMonth != null) {
      return '${DateFormat.MMMM().format(DateTime(_selectedYear!, _selectedMonth!))} $_selectedYear';
    }
    return '$_selectedYear';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _sortedEntries();
    final hasData = entries.isNotEmpty;
    final total = hasData
        ? (_totalCases > 0
            ? _totalCases
            : entries.fold<int>(0, (sum, e) => sum + e.count))
        : _totalCases;
    final maxCount =
        hasData ? entries.map((e) => e.count).reduce(math.max) : 0;
    final peakEntries = hasData
        ? entries.where((e) => e.count == maxCount).toList()
        : <AdminCaseTypeRow>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminCasePeriodFilterBar(
          years: _years,
          selectedYear: _selectedYear,
          selectedMonth: _selectedMonth,
          loading: _loading,
          hasData: hasData,
          maxCount: maxCount,
          peakEntries: peakEntries,
          peakMonthLabel: _peakMonthLabel,
          peakMonthCount: _peakMonthCount,
          onYearChanged: _onYearChanged,
          onMonthChanged: _onMonthChanged,
          onSelectBusiestMonth:
              _peakMonthNumber != null ? _onSelectBusiestMonth : null,
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (!hasData)
          AdminCaseChartEmptyState(periodLabel: _periodLabel())
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 720;
              final leftPanel = AdminCaseDonutView(
                entries: entries,
                total: total,
                palette: _palette,
                legendVisibleCount: _legendVisibleCount,
                periodLabel: _periodLabel(),
              );
              final rightPanel = AdminCaseVerticalBarsView(
                entries: entries,
                maxCount: maxCount,
                palette: _palette,
              );

              if (isWide) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 240, child: leftPanel),
                    const SizedBox(width: 28),
                    Expanded(child: rightPanel),
                  ],
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: SizedBox(width: 220, child: leftPanel)),
                  const SizedBox(height: 24),
                  rightPanel,
                ],
              );
            },
          ),
      ],
    );
  }
}

class AdminCaseTypeRow {
  final String label;
  final int count;

  AdminCaseTypeRow({required this.label, required this.count});
}

class AdminCasePeriodFilterBar extends StatelessWidget {
  final List<int> years;
  final int? selectedYear;
  final int? selectedMonth;
  final bool loading;
  final bool hasData;
  final int maxCount;
  final List<AdminCaseTypeRow> peakEntries;
  final String? peakMonthLabel;
  final int peakMonthCount;
  final ValueChanged<int?> onYearChanged;
  final ValueChanged<int?> onMonthChanged;
  final VoidCallback? onSelectBusiestMonth;

  const AdminCasePeriodFilterBar({
    super.key,
    required this.years,
    required this.selectedYear,
    required this.selectedMonth,
    required this.loading,
    required this.hasData,
    required this.maxCount,
    required this.peakEntries,
    required this.peakMonthLabel,
    required this.peakMonthCount,
    required this.onYearChanged,
    required this.onMonthChanged,
    this.onSelectBusiestMonth,
  });

  @override
  Widget build(BuildContext context) {
    final peakLabel = !hasData
        ? '—'
        : peakEntries.length == 1
        ? peakEntries.first.label
        : peakEntries.map((e) => e.label).join(', ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Filter by period',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          AdminCaseYearDropdown(
            years: years,
            selectedYear: selectedYear,
            onChanged: onYearChanged,
          ),
          AdminCaseMonthDropdown(
            selectedMonth: selectedMonth,
            enabled: selectedYear != null,
            onChanged: onMonthChanged,
          ),
          if (loading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (hasData)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _AdminCasesByTypePanelState.peakHighlightColor
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _AdminCasesByTypePanelState.peakHighlightColor
                      .withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.trending_up_rounded,
                    size: 14,
                    color: _AdminCasesByTypePanelState.peakHighlightColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Top type: $peakLabel ($maxCount)',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1A6B7A),
                    ),
                  ),
                ],
              ),
            ),
          if (hasData &&
              peakMonthLabel != null &&
              peakMonthCount > 0 &&
              selectedMonth == null &&
              onSelectBusiestMonth != null)
            InkWell(
              onTap: onSelectBusiestMonth,
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppTheme.gold.withValues(alpha: 0.5),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month_rounded,
                      size: 14,
                      color: AppTheme.deepNavy.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Busiest month: $peakMonthLabel ($peakMonthCount)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.deepNavy.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class AdminCaseChartEmptyState extends StatelessWidget {
  final String periodLabel;

  const AdminCaseChartEmptyState({super.key, required this.periodLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Icon(Icons.pie_chart_outline, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          Text(
            'No cases for $periodLabel',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Try All years or pick another year/month above.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }
}

class AdminCaseDonutView extends StatelessWidget {
  final List<AdminCaseTypeRow> entries;
  final int total;
  final List<Color> palette;
  final int legendVisibleCount;
  final String periodLabel;

  const AdminCaseDonutView({
    super.key,
    required this.entries,
    required this.total,
    required this.palette,
    required this.legendVisibleCount,
    required this.periodLabel,
  });

  @override
  Widget build(BuildContext context) {
    final visible = entries.take(legendVisibleCount).toList();
    final hiddenCount = entries.length - visible.length;

    return Column(
      children: [
        SizedBox(
          height: 200,
          width: 200,
          child: CustomPaint(
            painter: AdminCaseDonutRingPainter(
              entries: entries,
              total: total,
              colors: palette,
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$total',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.royalBlue,
                    ),
                  ),
                  Text(
                    'Total Cases',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    periodLabel,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (var i = 0; i < visible.length; i++)
              AdminCaseLegendChip(
                color: palette[i % palette.length],
                label: visible[i].label,
                value: visible[i].count,
                isPeak: visible[i].count == entries.first.count,
              ),
            if (hiddenCount > 0)
              Text(
                '+$hiddenCount more',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
          ],
        ),
      ],
    );
  }
}

class AdminCaseLegendChip extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  final bool isPeak;

  const AdminCaseLegendChip({
    super.key,
    required this.color,
    required this.label,
    required this.value,
    this.isPeak = false,
  });

  @override
  Widget build(BuildContext context) {
    final chipColor =
        isPeak ? _AdminCasesByTypePanelState.peakHighlightColor : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isPeak ? chipColor : chipColor.withValues(alpha: 0.25),
          width: isPeak ? 1.5 : 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: chipColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 72),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: chipColor,
            ),
          ),
          if (isPeak) ...[
            const SizedBox(width: 4),
            Icon(Icons.star_rounded, size: 12, color: chipColor),
          ],
        ],
      ),
    );
  }
}

class AdminCaseVerticalBarsView extends StatelessWidget {
  final List<AdminCaseTypeRow> entries;
  final int maxCount;
  final List<Color> palette;

  const AdminCaseVerticalBarsView({
    super.key,
    required this.entries,
    required this.maxCount,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Distribution by count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const Spacer(),
              Text(
                'Max: $maxCount',
                style: TextStyle(fontSize: 11, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AdminCaseColumnChart(
            entries: entries,
            maxCount: maxCount,
            palette: palette,
          ),
        ],
      ),
    );
  }
}

class AdminCaseYearDropdown extends StatelessWidget {
  final List<int> years;
  final int? selectedYear;
  final ValueChanged<int?> onChanged;

  const AdminCaseYearDropdown({
    super.key,
    required this.years,
    required this.selectedYear,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int?>(
          value: selectedYear,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down, size: 18),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.royalBlue,
          ),
          items: [
            const DropdownMenuItem<int?>(
              value: null,
              child: Text('All years'),
            ),
            ...years.map(
              (y) => DropdownMenuItem<int?>(value: y, child: Text('$y')),
            ),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class AdminCaseMonthDropdown extends StatelessWidget {
  final int? selectedMonth;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  const AdminCaseMonthDropdown({
    super.key,
    required this.selectedMonth,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.borderGray),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int?>(
            value: enabled ? selectedMonth : null,
            isDense: true,
            icon: const Icon(Icons.keyboard_arrow_down, size: 18),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.royalBlue,
            ),
            items: [
              const DropdownMenuItem<int?>(
                value: null,
                child: Text('All months'),
              ),
              ...List.generate(12, (i) {
                final m = i + 1;
                return DropdownMenuItem<int?>(
                  value: m,
                  child: Text(DateFormat.MMMM().format(DateTime(2000, m))),
                );
              }),
            ],
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ),
    );
  }
}

class AdminCaseColumnChart extends StatelessWidget {
  final List<AdminCaseTypeRow> entries;
  final int maxCount;
  final List<Color> palette;

  const AdminCaseColumnChart({
    super.key,
    required this.entries,
    required this.maxCount,
    required this.palette,
  });

  List<double> _yTicks() {
    if (maxCount <= 0) return [0];
    if (maxCount <= 5) {
      return List<double>.generate(maxCount + 1, (i) => i.toDouble());
    }
    final step = (maxCount / 4).ceil().toDouble();
    final ticks = <double>[0];
    var v = step;
    while (v < maxCount) {
      ticks.add(v);
      v += step;
    }
    ticks.add(maxCount.toDouble());
    return ticks;
  }

  @override
  Widget build(BuildContext context) {
    const chartHeight = 200.0;
    const yAxisWidth = 36.0;
    final yTicks = _yTicks();
    final yMax = yTicks.last;

    return SizedBox(
      height: chartHeight + 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: yAxisWidth,
            height: chartHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: yTicks.reversed.map((t) {
                return Text(
                  t == t.roundToDouble() ? '${t.toInt()}' : t.toStringAsFixed(1),
                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                );
              }).toList(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                SizedBox(
                  height: chartHeight,
                  child: Stack(
                    children: [
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: List.generate(
                          yTicks.length,
                          (_) => Container(
                            height: 1,
                            color: Colors.grey.withValues(alpha: 0.25),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final barSlot = constraints.maxWidth / entries.length;
                            final barWidth = math.min(44.0, barSlot * 0.65);

                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: math.max(
                                  constraints.maxWidth,
                                  entries.length * barSlot,
                                ),
                                height: chartHeight,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: List.generate(entries.length, (i) {
                                    final e = entries[i];
                                    final isPeak = e.count == maxCount;
                                    final ratio =
                                        yMax > 0 ? e.count / yMax : 0.0;
                                    final barHeight = (chartHeight - 24) *
                                        ratio.clamp(0.0, 1.0);
                                    final color = isPeak
                                        ? _AdminCasesByTypePanelState
                                            .peakHighlightColor
                                        : palette[i % palette.length]
                                            .withValues(alpha: 0.45);

                                    return SizedBox(
                                      width: barSlot,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          if (isPeak)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 4,
                                              ),
                                              child: Text(
                                                '${e.count}',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: Color(0xFF1A6B7A),
                                                ),
                                              ),
                                            ),
                                          Container(
                                            width: barWidth,
                                            height: barHeight,
                                            decoration: BoxDecoration(
                                              color: color,
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                top: Radius.circular(6),
                                              ),
                                              border: Border.all(
                                                color: isPeak
                                                    ? const Color(0xFF1A6B7A)
                                                    : Colors.black26,
                                                width: isPeak ? 1.5 : 1,
                                              ),
                                              boxShadow: isPeak
                                                  ? [
                                                      BoxShadow(
                                                        color:
                                                            _AdminCasesByTypePanelState
                                                                .peakHighlightColor
                                                                .withValues(
                                                          alpha: 0.35,
                                                        ),
                                                        blurRadius: 6,
                                                        offset: const Offset(0, 2),
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final barSlot = constraints.maxWidth / entries.length;
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: math.max(
                            constraints.maxWidth,
                            entries.length * barSlot,
                          ),
                          child: Row(
                            children: List.generate(entries.length, (i) {
                              final label = entries[i].label;
                              return SizedBox(
                                width: barSlot,
                                child: Transform.rotate(
                                  angle: -0.65,
                                  alignment: Alignment.topCenter,
                                  child: Text(
                                    label,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: entries[i].count == maxCount
                                          ? FontWeight.w700
                                          : FontWeight.w500,
                                      color: entries[i].count == maxCount
                                          ? const Color(0xFF1A6B7A)
                                          : AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AdminCaseDonutRingPainter extends CustomPainter {
  final List<AdminCaseTypeRow> entries;
  final int total;
  final List<Color> colors;

  AdminCaseDonutRingPainter({
    required this.entries,
    required this.total,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (total <= 0 || entries.isEmpty) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    const stroke = 28.0;
    final rect = Rect.fromCircle(center: center, radius: radius - stroke / 2);
    final maxCount = entries.map((e) => e.count).reduce(math.max);

    var startAngle = -math.pi / 2;
    for (var i = 0; i < entries.length; i++) {
      final sweep = (entries[i].count / total) * 2 * math.pi;
      if (sweep <= 0) continue;

      final isPeak = entries[i].count == maxCount;
      final paint = Paint()
        ..color = isPeak
            ? _AdminCasesByTypePanelState.peakHighlightColor
            : colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }

    final innerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius - stroke - 4, innerPaint);
  }

  @override
  bool shouldRepaint(covariant AdminCaseDonutRingPainter oldDelegate) {
    return oldDelegate.entries != entries || oldDelegate.total != total;
  }
}

/// Back-compat alias — use [AdminCasesByTypePanel].
@Deprecated('Use AdminCasesByTypePanel')
typedef CasesByTypeChart = AdminCasesByTypePanel;
