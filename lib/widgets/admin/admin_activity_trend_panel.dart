import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import 'admin_cases_by_type_panel.dart';

/// Case, hearing, and appointment counts for admin Reports.
class AdminActivityTrendPanel extends StatefulWidget {
  const AdminActivityTrendPanel({super.key});

  @override
  State<AdminActivityTrendPanel> createState() =>
      _AdminActivityTrendPanelState();
}

class _MonthCounts {
  final int cases;
  final int hearings;
  final int appointments;

  const _MonthCounts({
    this.cases = 0,
    this.hearings = 0,
    this.appointments = 0,
  });

  int get total => cases + hearings + appointments;

  _MonthCounts operator +(_MonthCounts other) {
    return _MonthCounts(
      cases: cases + other.cases,
      hearings: hearings + other.hearings,
      appointments: appointments + other.appointments,
    );
  }
}

class _ActivityPoint {
  final String label;
  final int year;
  final int? month;
  final _MonthCounts counts;

  const _ActivityPoint({
    required this.label,
    required this.year,
    required this.month,
    required this.counts,
  });
}

enum _ActivitySeries { cases, hearings, appointments }

class _AdminActivityTrendPanelState extends State<AdminActivityTrendPanel> {
  final AdminService _adminService = AdminService();

  static const _casesColor = Color(0xFF26C6DA);
  static const _hearingsColor = Color(0xFF1A3A6C);
  static const _appointmentsColor = Color(0xFFD4A017);

  bool _loading = true;
  String? _error;
  final Map<String, _MonthCounts> _byMonth = {};
  List<int> _years = const [];
  int? _selectedYear;
  int? _selectedMonth;
  int? _selectedIndex;
  final Set<_ActivitySeries> _hidden = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _adminService.getActivityTrend(refresh: refresh);
      if (!mounted) return;
      final byMonth = <String, _MonthCounts>{};
      final years = <int>{};
      for (final row in rows) {
        final key = row['month']?.toString() ?? '';
        final parts = key.split('-');
        if (parts.length != 2) continue;
        final year = int.tryParse(parts[0]);
        final month = int.tryParse(parts[1]);
        if (year == null || month == null) continue;
        years.add(year);
        byMonth[key] = _MonthCounts(
          cases: _toInt(row['cases']),
          hearings: _toInt(row['hearings']),
          appointments: _toInt(row['appointments']),
        );
      }
      final yearList = years.toList()..sort((a, b) => b.compareTo(a));
      setState(() {
        _byMonth
          ..clear()
          ..addAll(byMonth);
        _years = yearList;
        if (_selectedYear != null && !yearList.contains(_selectedYear)) {
          _selectedYear = null;
          _selectedMonth = null;
        }
        _selectedIndex = null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load activity trend';
        _loading = false;
      });
    }
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }

  _MonthCounts _countsFor(int year, int month) {
    final key = '$year-${month.toString().padLeft(2, '0')}';
    return _byMonth[key] ?? const _MonthCounts();
  }

  bool get _yearly {
    if (_selectedYear != null) return false;
    return _years.length > 1;
  }

  List<_ActivityPoint> get _points {
    if (_yearly) {
      final years = _years.reversed.toList();
      return [
        for (final year in years)
          _ActivityPoint(
            label: '$year',
            year: year,
            month: null,
            counts: List.generate(12, (i) => _countsFor(year, i + 1)).fold(
              const _MonthCounts(),
              (sum, row) => sum + row,
            ),
          ),
      ];
    }
    final year = _selectedYear ??
        (_years.isNotEmpty ? _years.first : DateTime.now().year);
    return [
      for (var month = 1; month <= 12; month++)
        _ActivityPoint(
          label: DateFormat('MMM').format(DateTime(year, month)),
          year: year,
          month: month,
          counts: _countsFor(year, month),
        ),
    ];
  }

  _MonthCounts get _periodCounts {
    if (_selectedYear != null && _selectedMonth != null) {
      return _countsFor(_selectedYear!, _selectedMonth!);
    }
    return _points.fold(
      const _MonthCounts(),
      (sum, point) => sum + point.counts,
    );
  }

  String get _rangeLabel {
    if (_selectedYear != null && _selectedMonth != null) {
      return DateFormat('MMMM yyyy').format(
        DateTime(_selectedYear!, _selectedMonth!),
      );
    }
    if (_selectedYear != null) return '$_selectedYear';
    if (_yearly) return 'All years';
    final year = _years.isNotEmpty ? _years.first : DateTime.now().year;
    return '$year';
  }

  void _toggle(_ActivitySeries series) {
    setState(() {
      if (!_hidden.add(series)) _hidden.remove(series);
    });
  }

  int _valueOf(_MonthCounts counts, _ActivitySeries series) {
    switch (series) {
      case _ActivitySeries.cases:
        return counts.cases;
      case _ActivitySeries.hearings:
        return counts.hearings;
      case _ActivitySeries.appointments:
        return counts.appointments;
    }
  }

  Map<_ActivitySeries, int> _shares(_MonthCounts counts) {
    final series = _ActivitySeries.values;
    final values = [for (final item in series) _valueOf(counts, item)];
    final total = values.fold<int>(0, (sum, value) => sum + value);
    if (total <= 0) {
      return {for (final item in series) item: 0};
    }
    final exact = [for (final value in values) value * 100 / total];
    final floors = [for (final value in exact) value.floor()];
    var leftover = 100 - floors.fold<int>(0, (sum, value) => sum + value);
    final order = List<int>.generate(series.length, (i) => i)
      ..sort(
        (a, b) => (exact[b] - floors[b]).compareTo(exact[a] - floors[a]),
      );
    var cursor = 0;
    while (leftover > 0 && order.isNotEmpty) {
      floors[order[cursor % order.length]]++;
      leftover--;
      cursor++;
    }
    return {for (var i = 0; i < series.length; i++) series[i]: floors[i]};
  }

  @override
  Widget build(BuildContext context) {
    final points = _points;
    final period = _periodCounts;
    final shares = _shares(period);
    final highlighted = _selectedYear != null && _selectedMonth != null
        ? points.indexWhere((point) => point.month == _selectedMonth)
        : _selectedIndex;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.show_chart_rounded, color: AppTheme.royalBlue),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Activity Trend',
                    style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    _rangeLabel,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: _loading ? null : () => _load(refresh: true),
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Filter by period',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            AdminCaseYearDropdown(
              years: _years,
              selectedYear: _selectedYear,
              onChanged: (year) {
                setState(() {
                  _selectedYear = year;
                  _selectedMonth = null;
                  _selectedIndex = null;
                });
              },
            ),
            AdminCaseMonthDropdown(
              selectedMonth: _selectedMonth,
              enabled: _selectedYear != null && !_loading,
              onChanged: (month) {
                setState(() {
                  _selectedMonth = month;
                  _selectedIndex = null;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loading)
          const SizedBox(
            height: 220,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          SizedBox(height: 120, child: Center(child: Text(_error!)))
        else ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _shareChip(
                _ActivitySeries.cases,
                'Cases',
                period.cases,
                shares[_ActivitySeries.cases] ?? 0,
                _casesColor,
              ),
              _shareChip(
                _ActivitySeries.hearings,
                'Hearings',
                period.hearings,
                shares[_ActivitySeries.hearings] ?? 0,
                _hearingsColor,
              ),
              _shareChip(
                _ActivitySeries.appointments,
                'Appointments',
                period.appointments,
                shares[_ActivitySeries.appointments] ?? 0,
                _appointmentsColor,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _chartPanel(points, highlighted),
          if (highlighted != null &&
              highlighted >= 0 &&
              highlighted < points.length) ...[
            const SizedBox(height: 10),
            _selectedDetail(points[highlighted]),
          ],
        ],
      ],
    );
  }

  Widget _shareChip(
    _ActivitySeries series,
    String label,
    int count,
    int percent,
    Color color,
  ) {
    final hidden = _hidden.contains(series);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _toggle(series),
        child: Opacity(
          opacity: hidden ? 0.4 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text(
                  '$label $count · $percent%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chartPanel(List<_ActivityPoint> points, int? highlighted) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE6EAF2)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              children: [
                _legendDot(_ActivitySeries.cases, 'Cases', _casesColor),
                _legendDot(_ActivitySeries.hearings, 'Hearings', _hearingsColor),
                _legendDot(
                  _ActivitySeries.appointments,
                  'Appointments',
                  _appointmentsColor,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 196,
            width: double.infinity,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) {
                    if (_selectedYear != null && _selectedMonth != null) {
                      return;
                    }
                    final index = _indexForX(
                      details.localPosition.dx,
                      constraints.maxWidth,
                      points.length,
                    );
                    setState(() {
                      _selectedIndex = _selectedIndex == index ? null : index;
                    });
                  },
                  child: CustomPaint(
                    painter: _ActivityTrendPainter(
                      points: points,
                      selected: highlighted,
                      hidden: _hidden,
                      casesColor: _casesColor,
                      hearingsColor: _hearingsColor,
                      appointmentsColor: _appointmentsColor,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(_ActivitySeries series, String label, Color color) {
    final hidden = _hidden.contains(series);
    return InkWell(
      onTap: () => _toggle(series),
      borderRadius: BorderRadius.circular(8),
      child: Opacity(
        opacity: hidden ? 0.35 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: Color(0xFF3D4C63),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectedDetail(_ActivityPoint point) {
    final shares = _shares(point.counts);
    final when = point.month == null
        ? '${point.year}'
        : DateFormat('MMMM yyyy').format(DateTime(point.year, point.month!));
    String piece(_ActivitySeries series, String label, int count) {
      return '$label $count (${shares[series]}%)';
    }

    return Text(
      '$when · ${piece(_ActivitySeries.cases, 'Cases', point.counts.cases)} · '
      '${piece(_ActivitySeries.hearings, 'Hearings', point.counts.hearings)} · '
      '${piece(_ActivitySeries.appointments, 'Appointments', point.counts.appointments)}',
      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
    );
  }

  int _indexForX(double x, double width, int count) {
    if (count <= 1) return 0;
    const left = 36.0;
    const right = 8.0;
    final plot = math.max(1.0, width - left - right);
    final t = ((x - left) / plot).clamp(0.0, 1.0);
    return (t * (count - 1)).round();
  }
}

class _ActivityTrendPainter extends CustomPainter {
  final List<_ActivityPoint> points;
  final int? selected;
  final Set<_ActivitySeries> hidden;
  final Color casesColor;
  final Color hearingsColor;
  final Color appointmentsColor;

  _ActivityTrendPainter({
    required this.points,
    required this.selected,
    required this.hidden,
    required this.casesColor,
    required this.hearingsColor,
    required this.appointmentsColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const left = 36.0;
    const right = 8.0;
    const top = 8.0;
    const bottom = 22.0;
    final plot = Rect.fromLTWH(
      left,
      top,
      math.max(1, size.width - left - right),
      math.max(1, size.height - top - bottom),
    );

    int read(_ActivityPoint point, _ActivitySeries series) {
      switch (series) {
        case _ActivitySeries.cases:
          return point.counts.cases;
        case _ActivitySeries.hearings:
          return point.counts.hearings;
        case _ActivitySeries.appointments:
          return point.counts.appointments;
      }
    }

    final visible = _ActivitySeries.values.where((s) => !hidden.contains(s));
    var maxValue = 0;
    for (final point in points) {
      for (final series in visible) {
        maxValue = math.max(maxValue, read(point, series));
      }
    }
    final yMax = _niceMax(maxValue <= 0 ? 1 : maxValue);

    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    const labelStyle = TextStyle(color: Color(0xFF6B7A90), fontSize: 10);

    for (var i = 0; i < 4; i++) {
      final t = i / 3;
      final y = plot.bottom - plot.height * t;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final value = yMax * t;
      _paintLabel(
        canvas,
        value == value.roundToDouble() ? '${value.round()}' : value.toStringAsFixed(1),
        Offset(0, y - 6),
        labelStyle,
        plot.left - 4,
        TextAlign.right,
      );
    }

    if (points.isEmpty || visible.isEmpty) return;

    List<Offset> seriesOf(_ActivitySeries series) {
      return List<Offset>.generate(points.length, (i) {
        final x = points.length == 1
            ? plot.center.dx
            : plot.left + plot.width * (i / (points.length - 1));
        final y = plot.bottom - plot.height * (read(points[i], series) / yMax);
        return Offset(x, y);
      });
    }

    void draw(_ActivitySeries series, Color color, double width, double radius) {
      if (hidden.contains(series)) return;
      final pts = seriesOf(series);
      if (series == _ActivitySeries.cases && pts.length > 1) {
        final fill = Path()..moveTo(pts.first.dx, plot.bottom);
        for (final point in pts) {
          fill.lineTo(point.dx, point.dy);
        }
        fill
          ..lineTo(pts.last.dx, plot.bottom)
          ..close();
        canvas.drawPath(
          fill,
          Paint()
            ..shader = ui.Gradient.linear(
              Offset(plot.center.dx, plot.top),
              Offset(plot.center.dx, plot.bottom),
              [
                color.withValues(alpha: 0.28),
                color.withValues(alpha: 0.02),
              ],
            ),
        );
      }
      _stroke(canvas, pts, color, width);
      _dots(canvas, pts, color, radius);
    }

    draw(_ActivitySeries.appointments, appointmentsColor, 1.8, 3.2);
    draw(_ActivitySeries.hearings, hearingsColor, 2.0, 3.4);
    draw(_ActivitySeries.cases, casesColor, 2.4, 4.0);

    const monthStyle = TextStyle(color: Color(0xFF5C6B82), fontSize: 10);
    final step = points.length > 8 ? 2 : 1;
    for (var i = 0; i < points.length; i += step) {
      final x = points.length == 1
          ? plot.center.dx
          : plot.left + plot.width * (i / (points.length - 1));
      _paintLabel(
        canvas,
        points[i].label,
        Offset(x - 18, plot.bottom + 4),
        monthStyle,
        36,
        TextAlign.center,
      );
    }

    if (selected != null && selected! >= 0 && selected! < points.length) {
      final x = points.length == 1
          ? plot.center.dx
          : plot.left + plot.width * (selected! / (points.length - 1));
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = const Color(0xFF1A3A6C)
          ..strokeWidth = 1,
      );
    }
  }

  void _stroke(Canvas canvas, List<Offset> pts, Color color, double width) {
    if (pts.length < 2) return;
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _dots(Canvas canvas, List<Offset> pts, Color color, double radius) {
    final fill = Paint()..color = color;
    final ring = Paint()
      ..color = const Color(0xFFF7F9FC)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final point in pts) {
      canvas.drawCircle(point, radius, fill);
      canvas.drawCircle(point, radius, ring);
    }
  }

  void _paintLabel(
    Canvas canvas,
    String text,
    Offset offset,
    TextStyle style,
    double width,
    TextAlign align,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
      textAlign: align,
    )..layout(maxWidth: width);
    painter.paint(canvas, offset);
  }

  double _niceMax(int value) {
    if (value <= 1) return 1;
    final asDouble = value.toDouble();
    final exp = math.pow(10, (math.log(asDouble) / math.ln10).floor()).toDouble();
    final frac = asDouble / exp;
    final nice = frac <= 1
        ? 1
        : frac <= 2
        ? 2
        : frac <= 5
        ? 5
        : 10;
    return nice * exp;
  }

  @override
  bool shouldRepaint(covariant _ActivityTrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.selected != selected ||
        oldDelegate.hidden != hidden;
  }
}
