import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/report_exporter/report_exporter.dart';
import '../../widgets/admin/admin_activity_trend_panel.dart';
import '../../widgets/admin/admin_cases_by_type_panel.dart';
import '../../widgets/admin/admin_page_header.dart';
import '../../widgets/admin/admin_ui_theme.dart';

/// Admin-only navigation from summary tiles (wired by [AdminDashboard]).
typedef ReportsNavigateToUsers = void Function({String role});
typedef ReportsNavigateToCases = void Function({String status});

class ReportsAnalyticsScreen extends StatefulWidget {
  final bool inline;

  /// Opens User Management with an optional role filter (`all`, `client`, etc.).
  final ReportsNavigateToUsers? onNavigateToUsers;

  /// Opens Case Oversight with an optional status filter (`all`, `pending`, etc.).
  final ReportsNavigateToCases? onNavigateToCases;

  const ReportsAnalyticsScreen({
    super.key,
    this.inline = false,
    this.onNavigateToUsers,
    this.onNavigateToCases,
  });

  @override
  State<ReportsAnalyticsScreen> createState() => _ReportsAnalyticsScreenState();
}

class _ReportsAnalyticsScreenState extends State<ReportsAnalyticsScreen> {
  final AdminService _adminService = AdminService();
  bool _isLoading = true;
  bool _exporting = false;
  Map<String, dynamic>? _analytics;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
    _adminService.getActivityTrend();
  }

  Future<void> _loadAnalytics({bool showFullScreenSpinner = true}) async {
    if (showFullScreenSpinner) {
      setState(() => _isLoading = true);
    }
    try {
      final analytics = await _adminService.getAnalytics();
      if (!mounted) return;
      setState(() {
        _analytics = analytics;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
      Get.snackbar(
        'Error',
        'Failed to load analytics: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  int _intValue(dynamic v, [int fallback = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? fallback;
  }

  String _strCount(String key) => _intValue(_analytics![key]).toString();

  bool get _adminNavigationEnabled =>
      widget.onNavigateToUsers != null && widget.onNavigateToCases != null;

  Widget _buildBody() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _analytics == null
        ? const Center(child: Text('No data available'))
        : RefreshIndicator(
            onRefresh: () => _loadAnalytics(showFullScreenSpinner: false),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryTilesRow(),
                  const SizedBox(height: 20),
                  // User Statistics
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AdminUi.radius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.people_outline,
                                color: AppTheme.royalBlue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'User Statistics',
                                style: Theme.of(context).textTheme.titleMedium!
                                    .copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildStatRow(
                            'Total Users',
                            _strCount('totalUsers'),
                            onTap: _adminNavigationEnabled
                                ? () => widget.onNavigateToUsers!(role: 'all')
                                : null,
                          ),
                          _buildStatRow(
                            'Clients',
                            _strCount('clients'),
                            onTap: _adminNavigationEnabled
                                ? () =>
                                      widget.onNavigateToUsers!(role: 'client')
                                : null,
                          ),
                          _buildStatRow(
                            'Attorneys',
                            _strCount('attorneys'),
                            onTap: _adminNavigationEnabled
                                ? () => widget.onNavigateToUsers!(
                                    role: 'attorney',
                                  )
                                : null,
                          ),
                          _buildStatRow(
                            'Admins',
                            _strCount('admins'),
                            onTap: _adminNavigationEnabled
                                ? () => widget.onNavigateToUsers!(role: 'admin')
                                : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Case Statistics
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AdminUi.radius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.folder_open_outlined,
                                color: AppTheme.royalBlue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Case Statistics',
                                style: Theme.of(context).textTheme.titleMedium!
                                    .copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  'Total',
                                  _strCount('totalCases'),
                                  Colors.blue,
                                  onTap: _adminNavigationEnabled
                                      ? () => widget.onNavigateToCases!(
                                          status: 'all',
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Pending',
                                  _strCount('pendingCases'),
                                  Colors.orange,
                                  onTap: _adminNavigationEnabled
                                      ? () => widget.onNavigateToCases!(
                                          status: 'pending',
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  'In Progress',
                                  _strCount('inProgressCases'),
                                  Colors.purple,
                                  onTap: _adminNavigationEnabled
                                      ? () => widget.onNavigateToCases!(
                                          status: 'active',
                                        )
                                      : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildStatCard(
                                  'Completed',
                                  _strCount('completedCases'),
                                  Colors.green,
                                  onTap: _adminNavigationEnabled
                                      ? () => widget.onNavigateToCases!(
                                          status: 'completed',
                                        )
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Cases by Type
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AdminUi.radius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.pie_chart_outline,
                                color: AppTheme.royalBlue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Cases by Type',
                                style: Theme.of(context).textTheme.titleMedium!
                                    .copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: AppTheme.textPrimary,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildCasesByTypeSection(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AdminUi.radius),
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(20),
                      child: AdminActivityTrendPanel(),
                    ),
                  ),
                ],
              ),
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.inline) {
      return ColoredBox(
        color: AdminUi.background,
        child: Column(
          children: [
            AdminPageHeader(
              title: 'Reports & Analytics',
              actions: [
                IconButton(
                  icon: const Icon(Icons.download_rounded, color: AdminUi.primary),
                  onPressed: () => _exportReport(),
                  tooltip: 'Export Report',
                ),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports & Analytics'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: () => _exportReport(),
            tooltip: 'Export Report',
          ),
        ],
      ),
      body: body,
    );
  }

  Widget _buildStatRow(String label, String value, {VoidCallback? onTap}) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey[500]),
              ],
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return row;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: row,
      ),
    );
  }

  Widget _buildStatCard(
    String title,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) {
    const radius = BorderRadius.all(Radius.circular(12));
    final content = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: radius,
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: radius, child: content),
    );
  }

  Widget _buildSummaryTilesRow() {
    final tiles = <Widget>[
      _buildSummaryTile(
        icon: Icons.people_outline,
        label: 'Total Users',
        value: _strCount('totalUsers'),
        color: AppTheme.royalBlue,
        onTap: _adminNavigationEnabled
            ? () => widget.onNavigateToUsers!(role: 'all')
            : null,
      ),
      _buildSummaryTile(
        icon: Icons.folder_copy_rounded,
        label: 'Total Cases',
        value: _strCount('totalCases'),
        color: AppTheme.gold,
        onTap: _adminNavigationEnabled
            ? () => widget.onNavigateToCases!(status: 'all')
            : null,
      ),
      _buildSummaryTile(
        icon: Icons.pending_outlined,
        label: 'Pending',
        value: _strCount('pendingCases'),
        color: const Color(0xFFC55A3F),
        onTap: _adminNavigationEnabled
            ? () => widget.onNavigateToCases!(status: 'pending')
            : null,
      ),
      _buildSummaryTile(
        icon: Icons.trending_up_rounded,
        label: 'In Progress',
        value: _strCount('inProgressCases'),
        color: const Color(0xFF4C6FFF),
        onTap: _adminNavigationEnabled
            ? () => widget.onNavigateToCases!(status: 'active')
            : null,
      ),
      _buildSummaryTile(
        icon: Icons.check_circle_outline_rounded,
        label: 'Completed',
        value: _strCount('completedCases'),
        color: Colors.green,
        onTap: _adminNavigationEnabled
            ? () => widget.onNavigateToCases!(status: 'completed')
            : null,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width > 1400
            ? 5
            : width > 1100
            ? 4
            : width > 700
            ? 3
            : width > 420
            ? 2
            : 1;

        if (columns == 1) {
          return Column(
            children: [
              for (var i = 0; i < tiles.length; i++) ...[
                if (i > 0) const SizedBox(height: 12),
                tiles[i],
              ],
            ],
          );
        }

        final rows = <Widget>[];
        for (var i = 0; i < tiles.length; i += columns) {
          if (i > 0) rows.add(const SizedBox(height: 12));
          final chunk = tiles.sublist(
            i,
            i + columns > tiles.length ? tiles.length : i + columns,
          );
          rows.add(
            Row(
              children: [
                for (var j = 0; j < chunk.length; j++) ...[
                  if (j > 0) const SizedBox(width: 12),
                  Expanded(child: chunk[j]),
                ],
                if (chunk.length < columns)
                  ...List.generate(
                    columns - chunk.length,
                    (_) => const Expanded(child: SizedBox()),
                  ),
              ],
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }

  // Compact summary tile used at top of the page
  Widget _buildSummaryTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    VoidCallback? onTap,
  }) {
    const radius = BorderRadius.all(Radius.circular(14));
    final content = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: Colors.grey[400]),
        ],
      ),
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, borderRadius: radius, child: content),
    );
  }

  Widget _buildCasesByTypeSection() {
    return const AdminCasesByTypePanel();
  }

  Future<void> _exportReport() async {
    if (_exporting) return;
    _exporting = true;
    final waiting = _analytics == null || !AdminService.hasActivityTrendCache;
    if (waiting) {
      Get.snackbar(
        'Reports',
        'Saving PDF…',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: AppTheme.royalBlue,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    }
    try {
      final analytics = _analytics ?? await _adminService.getAnalytics();
      if (!mounted) return;
      List<Map<String, dynamic>> activityTrend = const [];
      try {
        activityTrend = await _adminService.getActivityTrend();
      } catch (_) {}
      if (!mounted) return;

      final generatedAt = DateTime.now();
      final filename =
          'analytics-report-${DateFormat('yyyyMMdd-HHmm').format(generatedAt)}.pdf';
      final pdfBytes = await _buildPdfBytes(
        analytics,
        generatedAt,
        activityTrend,
      );
      await saveBytes(
        bytes: pdfBytes,
        filename: filename,
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      if (waiting) Get.closeCurrentSnackbar();
      Get.snackbar(
        'Downloaded',
        'PDF report saved to your device.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.green,
        colorText: Colors.white,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      if (!mounted) return;
      Get.snackbar(
        'Error',
        'Failed to export report: $e',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    } finally {
      _exporting = false;
    }
  }

  Map<String, dynamic> _parseCasesByType(dynamic rawTypes) {
    if (rawTypes is Map<String, dynamic>) {
      return Map<String, dynamic>.from(rawTypes);
    }
    if (rawTypes is Map) {
      return Map<String, dynamic>.from(
        rawTypes.map((k, v) => MapEntry(k.toString(), v)),
      );
    }
    return {};
  }

  List<int> _activityShares(List<int> counts) {
    final total = counts.fold<int>(0, (sum, value) => sum + value);
    if (total <= 0) return List<int>.filled(counts.length, 0);
    final exact = [for (final value in counts) value * 100 / total];
    final floors = [for (final value in exact) value.floor()];
    var leftover = 100 - floors.fold<int>(0, (sum, value) => sum + value);
    final order = List<int>.generate(counts.length, (i) => i)
      ..sort((a, b) => (exact[b] - floors[b]).compareTo(exact[a] - floors[a]));
    var cursor = 0;
    while (leftover > 0 && order.isNotEmpty) {
      floors[order[cursor % order.length]]++;
      leftover--;
      cursor++;
    }
    return floors;
  }

  Future<Uint8List> _buildPdfBytes(
    Map<String, dynamic> analytics,
    DateTime generatedAt, [
    List<Map<String, dynamic>> activityTrend = const [],
  ]) async {
    final doc = PdfDocument();
    doc.pageSettings.orientation = PdfPageOrientation.portrait;
    const headerHeight = 78.0;
    const footerHeight = 28.0;
    doc.pageSettings.margins = PdfMargins()
      ..left = 36
      ..right = 36
      ..top = headerHeight
      ..bottom = footerHeight + 8;

    final navy = PdfColor(16, 36, 72);
    final ink = PdfColor(28, 42, 68);
    final muted = PdfColor(96, 110, 130);
    final line = PdfColor(214, 222, 232);
    final zebra = PdfColor(245, 248, 252);
    final gold = PdfColor(212, 160, 23);

    final fontBrand = PdfStandardFont(
      PdfFontFamily.helvetica,
      14,
      style: PdfFontStyle.bold,
    );
    final fontTitle = PdfStandardFont(
      PdfFontFamily.helvetica,
      13,
      style: PdfFontStyle.bold,
    );
    final fontSection = PdfStandardFont(
      PdfFontFamily.helvetica,
      11,
      style: PdfFontStyle.bold,
    );
    final fontBold = PdfStandardFont(
      PdfFontFamily.helvetica,
      9,
      style: PdfFontStyle.bold,
    );
    final font = PdfStandardFont(PdfFontFamily.helvetica, 9);
    final fontSmall = PdfStandardFont(PdfFontFamily.helvetica, 8);

    Uint8List? logoBytes;
    try {
      final data = await rootBundle.load('assets/logo.png');
      logoBytes = data.buffer.asUint8List();
    } catch (_) {}

    final pageSize = doc.pageSettings.size;
    final header = PdfPageTemplateElement(
      Rect.fromLTWH(0, 0, pageSize.width, headerHeight),
    );
    header.graphics.drawRectangle(
      brush: PdfSolidBrush(navy),
      bounds: Rect.fromLTWH(0, 0, pageSize.width, headerHeight),
    );
    header.graphics.drawRectangle(
      brush: PdfSolidBrush(gold),
      bounds: Rect.fromLTWH(0, headerHeight - 3, pageSize.width, 3),
    );
    if (logoBytes != null) {
      header.graphics.drawImage(
        PdfBitmap(logoBytes),
        const Rect.fromLTWH(36, 14, 50, 50),
      );
    }
    header.graphics.drawString(
      'Law Connect',
      fontBrand,
      brush: PdfBrushes.white,
      bounds: const Rect.fromLTWH(96, 18, 220, 18),
    );
    header.graphics.drawString(
      'Admin Console',
      fontSmall,
      brush: PdfSolidBrush(PdfColor(190, 205, 224)),
      bounds: const Rect.fromLTWH(96, 38, 220, 12),
    );
    header.graphics.drawString(
      'Reports & Analytics',
      fontTitle,
      brush: PdfBrushes.white,
      bounds: Rect.fromLTWH(280, 16, pageSize.width - 316, 18),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    header.graphics.drawString(
      DateFormat('MMMM d, yyyy  •  h:mm a').format(generatedAt),
      fontSmall,
      brush: PdfSolidBrush(PdfColor(190, 205, 224)),
      bounds: Rect.fromLTWH(280, 38, pageSize.width - 316, 12),
      format: PdfStringFormat(alignment: PdfTextAlignment.right),
    );
    doc.template.top = header;

    final footer = PdfPageTemplateElement(
      Rect.fromLTWH(0, 0, pageSize.width, footerHeight),
    );
    footer.graphics.drawLine(
      PdfPen(line, width: 0.6),
      const Offset(36, 0),
      Offset(pageSize.width - 36, 0),
    );
    footer.graphics.drawString(
      'Law Connect  ·  Justice Within Reach',
      fontSmall,
      brush: PdfSolidBrush(muted),
      bounds: Rect.fromLTWH(36, 8, pageSize.width - 180, 12),
    );
    final pageNumber = PdfPageNumberField(
      font: fontSmall,
      brush: PdfSolidBrush(muted),
    );
    final pageCount = PdfPageCountField(
      font: fontSmall,
      brush: PdfSolidBrush(muted),
    );
    PdfCompositeField(
      font: fontSmall,
      brush: PdfSolidBrush(muted),
      text: 'Page {0} of {1}',
      fields: <PdfAutomaticField>[pageNumber, pageCount],
    ).draw(footer.graphics, Offset(pageSize.width - 120, 8));
    doc.template.bottom = footer;

    PdfPage page = doc.pages.add();
    var g = page.graphics;
    var size = page.getClientSize();
    var y = 4.0;

    void continueOn(PdfPage next, double top) {
      page = next;
      g = page.graphics;
      size = page.getClientSize();
      y = top;
    }

    void ensureSpace(double needed) {
      if (y + needed <= size.height) return;
      continueOn(doc.pages.add(), 4);
    }

    void sectionTitle(String title) {
      ensureSpace(28);
      g.drawRectangle(
        brush: PdfSolidBrush(navy),
        bounds: Rect.fromLTWH(0, y + 1, 3, 12),
      );
      g.drawString(
        title,
        fontSection,
        brush: PdfSolidBrush(navy),
        bounds: Rect.fromLTWH(10, y, size.width - 10, 16),
      );
      y += 20;
    }

    PdfGrid styledGrid({
      required List<String> headers,
      required List<List<String>> rows,
      List<PdfTextAlignment>? align,
    }) {
      final grid = PdfGrid();
      grid.columns.add(count: headers.length);
      grid.headers.add(1);
      grid.style = PdfGridStyle(
        font: font,
        cellPadding: PdfPaddings(left: 8, right: 8, top: 5, bottom: 5),
      );
      for (var c = 0; c < headers.length; c++) {
        final cell = grid.headers[0].cells[c];
        cell.value = headers[c];
        cell.style.backgroundBrush = PdfSolidBrush(navy);
        cell.style.textBrush = PdfBrushes.white;
        cell.style.font = fontBold;
        cell.style.borders.all = PdfPen(navy, width: 0.2);
        cell.stringFormat = PdfStringFormat(
          alignment: align != null && c < align.length
              ? align[c]
              : PdfTextAlignment.left,
          lineAlignment: PdfVerticalAlignment.middle,
        );
      }
      for (var r = 0; r < rows.length; r++) {
        final row = grid.rows.add();
        final bg = r.isOdd ? zebra : PdfColor(255, 255, 255);
        for (var c = 0; c < headers.length; c++) {
          final cell = row.cells[c];
          cell.value = c < rows[r].length ? rows[r][c] : '';
          cell.style.font = c == 0 ? font : fontBold;
          cell.style.backgroundBrush = PdfSolidBrush(bg);
          cell.style.textBrush = PdfSolidBrush(ink);
          cell.style.borders.all = PdfPen(line, width: 0.4);
          cell.stringFormat = PdfStringFormat(
            alignment: align != null && c < align.length
                ? align[c]
                : PdfTextAlignment.left,
            lineAlignment: PdfVerticalAlignment.middle,
          );
        }
      }
      return grid;
    }

    PdfLayoutResult? drawGrid(PdfGrid grid, {double x = 0, double? width}) {
      final result = grid.draw(
        page: page,
        bounds: Rect.fromLTWH(
          x,
          y,
          width ?? size.width,
          size.height - y,
        ),
        format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
      );
      return result;
    }

    final userRows = [
      ['Total users', _intValue(analytics['totalUsers']).toString()],
      ['Clients', _intValue(analytics['clients']).toString()],
      ['Attorneys', _intValue(analytics['attorneys']).toString()],
      ['Admins', _intValue(analytics['admins']).toString()],
    ];
    final caseRows = [
      ['Total cases', _intValue(analytics['totalCases']).toString()],
      ['Pending', _intValue(analytics['pendingCases']).toString()],
      ['In progress', _intValue(analytics['inProgressCases']).toString()],
      ['Completed', _intValue(analytics['completedCases']).toString()],
    ];

    sectionTitle('Overview');
    final gap = 14.0;
    final colW = (size.width - gap) / 2;
    final leftGrid = styledGrid(
      headers: ['User statistics', 'Count'],
      rows: userRows,
      align: const [PdfTextAlignment.left, PdfTextAlignment.right],
    );
    final rightGrid = styledGrid(
      headers: ['Case statistics', 'Count'],
      rows: caseRows,
      align: const [PdfTextAlignment.left, PdfTextAlignment.right],
    );
    final leftResult = drawGrid(leftGrid, width: colW);
    final rightResult = drawGrid(rightGrid, x: colW + gap, width: colW);
    final overviewBottom = mathMax(
      leftResult?.bounds.bottom ?? y,
      rightResult?.bounds.bottom ?? y,
    );
    final overviewPage = rightResult?.page ?? leftResult?.page ?? page;
    continueOn(overviewPage, overviewBottom + 18);

    final casesByType = _parseCasesByType(analytics['casesByType']);
    final typeRows = casesByType.entries
        .map((e) => MapEntry(e.key, _intValue(e.value)))
        .where((e) => e.value > 0)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    sectionTitle('Cases by Type');
    if (typeRows.isEmpty) {
      ensureSpace(16);
      g.drawString(
        'No cases in this report.',
        font,
        brush: PdfSolidBrush(muted),
        bounds: Rect.fromLTWH(0, y, size.width, 14),
      );
      y += 22;
    } else {
      final typeGrid = styledGrid(
        headers: ['Case type', 'Count'],
        rows: [
          for (final row in typeRows) [row.key, row.value.toString()],
        ],
        align: const [PdfTextAlignment.left, PdfTextAlignment.right],
      );
      final typeResult = drawGrid(typeGrid);
      if (typeResult != null) {
        continueOn(typeResult.page, typeResult.bounds.bottom + 18);
      }
    }

    var cases = 0;
    var hearings = 0;
    var appointments = 0;
    for (final row in activityTrend) {
      cases += _intValue(row['cases']);
      hearings += _intValue(row['hearings']);
      appointments += _intValue(row['appointments']);
    }
    final shares = _activityShares([cases, hearings, appointments]);

    sectionTitle('Activity Trend');
    final summary = styledGrid(
      headers: ['Summary', 'Cases', 'Hearings', 'Appointments'],
      rows: [
        [
          'Count',
          '$cases',
          '$hearings',
          '$appointments',
        ],
        [
          'Share',
          '${shares[0]}%',
          '${shares[1]}%',
          '${shares[2]}%',
        ],
      ],
      align: const [
        PdfTextAlignment.left,
        PdfTextAlignment.center,
        PdfTextAlignment.center,
        PdfTextAlignment.center,
      ],
    );
    final summaryResult = drawGrid(summary);
    if (summaryResult != null) {
      continueOn(summaryResult.page, summaryResult.bounds.bottom + 16);
    }

    if (activityTrend.isEmpty) {
      ensureSpace(16);
      g.drawString(
        'No case, hearing, or appointment activity recorded.',
        font,
        brush: PdfSolidBrush(muted),
        bounds: Rect.fromLTWH(0, y, size.width, 14),
      );
    } else {
      ensureSpace(18);
      g.drawString(
        'Monthly activity',
        fontBold,
        brush: PdfSolidBrush(ink),
        bounds: Rect.fromLTWH(0, y, size.width, 14),
      );
      y += 16;
      final monthGrid = styledGrid(
        headers: ['Month', 'Cases', 'Hearings', 'Appointments'],
        rows: [
          for (final row in activityTrend)
            [
              _pdfMonthLabel(row['month']?.toString() ?? ''),
              _intValue(row['cases']).toString(),
              _intValue(row['hearings']).toString(),
              _intValue(row['appointments']).toString(),
            ],
        ],
        align: const [
          PdfTextAlignment.left,
          PdfTextAlignment.center,
          PdfTextAlignment.center,
          PdfTextAlignment.center,
          PdfTextAlignment.center,
        ],
      );
      drawGrid(monthGrid);
    }

    final bytes = doc.saveSync();
    doc.dispose();
    return Uint8List.fromList(bytes);
  }

  String _pdfMonthLabel(String key) {
    final parts = key.split('-');
    if (parts.length != 2) return key.isEmpty ? '-' : key;
    final year = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    if (year == null || month == null || month < 1 || month > 12) return key;
    return DateFormat('MMMM yyyy').format(DateTime(year, month));
  }

  double mathMax(double a, double b) => a > b ? a : b;
}
