import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/report_exporter/report_exporter.dart';
import '../../widgets/admin/admin_cases_by_type_panel.dart';

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
  Map<String, dynamic>? _analytics;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
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
                      borderRadius: BorderRadius.circular(16),
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
                      borderRadius: BorderRadius.circular(16),
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
                      borderRadius: BorderRadius.circular(16),
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
                ],
              ),
            ),
          );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.inline) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Text(
                  'Reports & Analytics',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.download),
                  onPressed: () => _exportReport(),
                  tooltip: 'Export Report',
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
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
    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );

    try {
      // Prefer using already-loaded analytics to match what's on-screen.
      // Fall back to service call if needed.
      final analytics = _analytics ?? await _adminService.getAnalytics();

      Get.back(); // Close loading

      final generatedAt = DateTime.now();
      final filenameBase =
          'analytics-report-${DateFormat('yyyyMMdd-HHmm').format(generatedAt)}';

      final textBytes = _buildPlainTextBytes(analytics, generatedAt);
      final wordBytes = _buildWordDocBytes(analytics, generatedAt);
      final pdfBytes = _buildPdfBytes(analytics, generatedAt);

      // Show export actions (downloadable files), not raw JSON.
      Get.dialog(
        AlertDialog(
          title: const Text('Export Successful'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your analytics report is ready to download.'),
                const SizedBox(height: 12),
                Text(
                  'Generated: ${DateFormat('MMM dd, yyyy • hh:mm a').format(generatedAt)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      try {
                        await saveBytes(
                          bytes: textBytes,
                          filename: '$filenameBase.txt',
                          mimeType: 'text/plain',
                        );
                        Get.snackbar(
                          'Downloaded',
                          'Text report saved. Open with Notepad or any text app.',
                          backgroundColor: Colors.green,
                          colorText: Colors.white,
                        );
                      } catch (e) {
                        Get.snackbar(
                          'Error',
                          'Failed to download text report: $e',
                          backgroundColor: Colors.red,
                          colorText: Colors.white,
                        );
                      }
                    },
                    icon: const Icon(Icons.text_snippet_outlined),
                    label: const Text('Download Text (.txt)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.royalBlue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          try {
                            await saveBytes(
                              bytes: wordBytes,
                              filename: '$filenameBase.rtf',
                              mimeType: 'application/rtf',
                            );
                            Get.snackbar(
                              'Downloaded',
                              'RTF report saved. Open with Microsoft Word or Google Docs.',
                              backgroundColor: Colors.green,
                              colorText: Colors.white,
                            );
                          } catch (e) {
                            Get.snackbar(
                              'Error',
                              'Failed to download RTF report: $e',
                              backgroundColor: Colors.red,
                              colorText: Colors.white,
                            );
                          }
                        },
                        icon: const Icon(Icons.description_outlined),
                        label: const Text('Word (RTF)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            await saveBytes(
                              bytes: pdfBytes,
                              filename: '$filenameBase.pdf',
                              mimeType: 'application/pdf',
                            );
                            Get.snackbar(
                              'Downloaded',
                              'PDF report saved to your device.',
                              backgroundColor: Colors.green,
                              colorText: Colors.white,
                            );
                          } catch (e) {
                            Get.snackbar(
                              'Error',
                              'Failed to download PDF report: $e',
                              backgroundColor: Colors.red,
                              colorText: Colors.white,
                            );
                          }
                        },
                        icon: const Icon(Icons.picture_as_pdf_outlined),
                        label: const Text('PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.gold,
                          foregroundColor: Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Tip: Use Text (.txt) for readable stats in Notepad. RTF is for Word only — do not open RTF in Notepad.',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Get.back(), child: const Text('Close')),
          ],
        ),
      );
    } catch (e) {
      Get.back(); // Close loading
      Get.snackbar(
        'Error',
        'Failed to export report: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
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

  /// Human-readable lines matching the on-screen analytics report.
  List<String> _buildReportLines(
    Map<String, dynamic> analytics,
    DateTime generatedAt,
  ) {
    final casesByType = _parseCasesByType(analytics['casesByType']);
    final generated = DateFormat('MMMM dd, yyyy - hh:mm a').format(generatedAt);

    final lines = <String>[
      'Reports & Analytics',
      '',
      'Generated: $generated',
      '',
      'User Statistics',
      'Total Users: ${_intValue(analytics['totalUsers'])}',
      'Clients: ${_intValue(analytics['clients'])}',
      'Attorneys: ${_intValue(analytics['attorneys'])}',
      'Admins: ${_intValue(analytics['admins'])}',
      '',
      'Case Statistics',
      'Total Cases: ${_intValue(analytics['totalCases'])}',
      'Pending Cases: ${_intValue(analytics['pendingCases'])}',
      'In Progress Cases: ${_intValue(analytics['inProgressCases'])}',
      'Completed Cases: ${_intValue(analytics['completedCases'])}',
    ];

    if (casesByType.isNotEmpty) {
      lines.addAll(['', 'Cases by Type']);
      for (final e in casesByType.entries) {
        lines.add('${e.key}: ${_intValue(e.value)}');
      }
    }

    return lines;
  }

  Uint8List _buildPlainTextBytes(
    Map<String, dynamic> analytics,
    DateTime generatedAt,
  ) {
    final body = _buildReportLines(analytics, generatedAt).join('\r\n');
    return Uint8List.fromList(utf8.encode(body));
  }

  String _escapeRtf(String text) {
    final buffer = StringBuffer();
    for (final codeUnit in text.runes) {
      if (codeUnit == 0x5c) {
        buffer.write(r'\\');
      } else if (codeUnit == 0x7b) {
        buffer.write(r'\{');
      } else if (codeUnit == 0x7d) {
        buffer.write(r'\}');
      } else if (codeUnit < 0x80) {
        buffer.writeCharCode(codeUnit);
      } else {
        final signed = codeUnit > 0x7fff ? codeUnit - 0x10000 : codeUnit;
        buffer.write('\\u$signed?');
      }
    }
    return buffer.toString();
  }

  bool _isReportHeading(String line) {
    return line == 'Reports & Analytics' ||
        line == 'User Statistics' ||
        line == 'Case Statistics' ||
        line == 'Cases by Type';
  }

  Uint8List _buildWordDocBytes(
    Map<String, dynamic> analytics,
    DateTime generatedAt,
  ) {
    final lines = _buildReportLines(analytics, generatedAt);
    final rtf = StringBuffer()
      ..write(r'{\rtf1\ansi\deff0{\fonttbl{\f0\fswiss Arial;}}')
      ..write(r'\f0\fs24');

    for (final line in lines) {
      if (line.isEmpty) {
        rtf.write(r'\par');
        continue;
      }
      if (_isReportHeading(line)) {
        rtf.write(r'\b ');
        rtf.write(_escapeRtf(line));
        rtf.write(r'\b0\par');
      } else {
        rtf.write(_escapeRtf(line));
        rtf.write(r'\par');
      }
    }

    rtf.write('}');
    return Uint8List.fromList(utf8.encode(rtf.toString()));
  }

  Uint8List _buildPdfBytes(
    Map<String, dynamic> analytics,
    DateTime generatedAt,
  ) {
    final doc = PdfDocument();
    final page = doc.pages.add();
    final fontTitle = PdfStandardFont(
      PdfFontFamily.helvetica,
      18,
      style: PdfFontStyle.bold,
    );
    final fontH = PdfStandardFont(
      PdfFontFamily.helvetica,
      12,
      style: PdfFontStyle.bold,
    );
    final font = PdfStandardFont(PdfFontFamily.helvetica, 11);

    double y = 0;
    void line(String text, {PdfFont? f, double gap = 18}) {
      page.graphics.drawString(
        text,
        f ?? font,
        bounds: Rect.fromLTWH(0, y, page.getClientSize().width, 20),
      );
      y += gap;
    }

    final reportLines = _buildReportLines(analytics, generatedAt);
    for (final reportLine in reportLines) {
      if (reportLine.isEmpty) {
        y += 8;
        continue;
      }
      if (reportLine == 'Reports & Analytics') {
        line(reportLine, f: fontTitle, gap: 24);
        continue;
      }
      if (_isReportHeading(reportLine)) {
        y += 6;
        line(reportLine, f: fontH);
        continue;
      }
      line(reportLine);
    }

    final bytes = doc.saveSync();
    doc.dispose();
    return Uint8List.fromList(bytes);
  }
}
