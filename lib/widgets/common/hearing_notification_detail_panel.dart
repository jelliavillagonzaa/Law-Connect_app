import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../services/hearing_calendar_fields.dart';
import '../../utils/court_order_display.dart';
import '../../utils/hearing_notification_formatter.dart';

final Map<String, Future<Map<String, dynamic>>> _enrichedHearingFutures =
    <String, Future<Map<String, dynamic>>>{};

/// Structured hearing details (all Firestore fields, labeled rows).
bool _seedLooksComplete(Map<String, dynamic> seed) {
  final rawCaseNo = HearingCalendarFields.asDisplayString(seed['caseNo']).isNotEmpty
      ? HearingCalendarFields.asDisplayString(seed['caseNo'])
      : HearingCalendarFields.asDisplayString(seed['caseNumber']);
  final caseNo = HearingCalendarFields.cleanCaseDocketNo(rawCaseNo);
  final client = HearingCalendarFields.asDisplayString(seed['clientName']);
  final caseTitle = HearingCalendarFields.asDisplayString(seed['caseTitle']);
  final full = HearingCalendarFields.asDisplayString(seed['fullText']);
  final hasRealFullText = full.isNotEmpty && !CourtOrderTextSources.isInboxWrapper(full);
  final loc = HearingCalendarFields.asDisplayString(seed['location']).isNotEmpty
      ? HearingCalendarFields.asDisplayString(seed['location'])
      : HearingCalendarFields.asDisplayString(seed['courtBranch']);
  final hasCompleteLocation =
      loc.isNotEmpty && !HearingCalendarFields.isBareLocation(loc);

  final titleHasCaption = caseTitle.isNotEmpty && HearingCalendarFields.hasCaseCaptionMarker(caseTitle);
  final clientIsPlaintiff = client.toLowerCase().startsWith('heirs of') ||
      (caseTitle.isNotEmpty && caseTitle.toLowerCase().startsWith(client.toLowerCase()));

  return caseNo.isNotEmpty &&
      !HearingCalendarFields.isPlaceholderCaseNo(caseNo) &&
      client.isNotEmpty &&
      !clientIsPlaintiff &&
      titleHasCaption &&
      hasCompleteLocation &&
      hasRealFullText;
}

Future<Map<String, dynamic>> _loadEnrichedHearing(
  String hearingDocId,
  Map<String, dynamic> seed, {
  List<Map<String, dynamic>> siblingRows = const [],
  bool enrichFromRelatedHearings = true,
}) async {
  if (!enrichFromRelatedHearings) {
    if (_seedLooksComplete(seed)) {
      return Map<String, dynamic>.from(seed);
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('hearings')
          .doc(hearingDocId)
          .get()
          .timeout(const Duration(seconds: 4));
      final hd = snap.data();
      if (hd == null || hd.isEmpty) return Map<String, dynamic>.from(seed);
      final out = <String, dynamic>{
        ...seed,
        ...hd,
        if (HearingCalendarFields.asDisplayString(seed['caseNo']).isNotEmpty &&
            !HearingCalendarFields.isPlaceholderCaseNo(seed['caseNo']))
          'caseNo': HearingCalendarFields.asDisplayString(seed['caseNo']),
        if (HearingCalendarFields.asDisplayString(seed['clientName']).isNotEmpty)
          'clientName': HearingCalendarFields.asDisplayString(seed['clientName']),
      };
      final venue = HearingCalendarFields.resolveVenueForDisplay(out);
      if (venue.isNotEmpty) out['location'] = venue;
      return out;
    } catch (_) {
      return Map<String, dynamic>.from(seed);
    }
  }

  if (_seedLooksComplete(seed)) {
    final prep = HearingCalendarFields.prepareForNotificationDisplay(seed);
    final venue = HearingCalendarFields.resolveVenueForDisplay(prep);
    if (venue.isNotEmpty) prep['location'] = venue;
    return prep;
  }
  try {
    Map<String, dynamic> hd = <String, dynamic>{};
    final snap = await FirebaseFirestore.instance
        .collection('hearings')
        .doc(hearingDocId)
        .get();
    if (snap.exists && snap.data() != null) {
      hd = snap.data()!;
    } else if (seed.isNotEmpty) {
      hd = Map<String, dynamic>.from(seed);
    }

    final seedCaseNo = HearingCalendarFields.asDisplayString(seed['caseNo']);
    if (seedCaseNo.isNotEmpty && !HearingCalendarFields.isPlaceholderCaseNo(seedCaseNo)) {
      hd['caseNo'] = seedCaseNo;
    }
    final seedClient = HearingCalendarFields.asDisplayString(seed['clientName']);
    if (seedClient.isNotEmpty) {
      hd['clientName'] = seedClient;
    }

    final caseMaps = await HearingCalendarFields.loadCaseMapsForHearing(hd);
    final merged = await HearingCalendarFields.loadMergedHearingForDisplay(
      hearingDocId: hearingDocId,
      hearingData: hd,
      caseMaps: caseMaps,
      siblingRows: siblingRows,
    );
    if (merged.isNotEmpty) {
      final venue = HearingCalendarFields.resolveVenueForDisplay(merged);
      if (venue.isNotEmpty) merged['location'] = venue;
      return merged;
    }
    final prepared =
        await HearingCalendarFields.prepareForNotificationDisplayAsync(hd);
    final venue = HearingCalendarFields.resolveVenueForDisplay(prepared);
    if (venue.isNotEmpty) prepared['location'] = venue;
    return prepared;
  } catch (_) {
    final fallback = await FirebaseFirestore.instance
        .collection('hearings')
        .doc(hearingDocId)
        .get();
    if (fallback.exists && fallback.data() != null) {
      final prep = await HearingCalendarFields.prepareForNotificationDisplayAsync(
        fallback.data()!,
      );
      final venue = HearingCalendarFields.resolveVenueForDisplay(prep);
      if (venue.isNotEmpty) prep['location'] = venue;
      return prep;
    }
    final merged = HearingCalendarFields.mergeHearingSources(
      [if (seed.isNotEmpty) seed, ...siblingRows],
    );
    final venue = HearingCalendarFields.resolveVenueForDisplay(merged);
    if (venue.isNotEmpty) merged['location'] = venue;
    return merged;
  }
}

Future<Map<String, dynamic>> _cachedEnrichedHearing(
  String hearingDocId,
  Map<String, dynamic> seed, {
  List<Map<String, dynamic>> siblingRows = const [],
  bool enrichFromRelatedHearings = true,
}) {
  final key = enrichFromRelatedHearings ? hearingDocId : 'light_$hearingDocId';
  return _enrichedHearingFutures.putIfAbsent(
    key,
    () => _loadEnrichedHearing(
      hearingDocId,
      seed,
      siblingRows: siblingRows,
      enrichFromRelatedHearings: enrichFromRelatedHearings,
    ),
  );
}

class HearingNotificationDetailPanel extends StatefulWidget {
  const HearingNotificationDetailPanel({
    super.key,
    required this.data,
    this.hearingDocId,
    this.calendarOnly = false,
    this.siblingRows = const [],
    this.enrichFromRelatedHearings = true,
  });

  final Map<String, dynamic> data;
  final String? hearingDocId;

  /// When true, only [HearingNotificationFormatter.calendarHearingKeys] are shown.
  final bool calendarOnly;

  /// Overlay / inbox rows with the same [caseNo] (avoids broad `hearings` scans).
  final List<Map<String, dynamic>> siblingRows;

  /// Client inbox: skip sibling `hearings` scans and OCR parse on expand.
  final bool enrichFromRelatedHearings;

  @override
  State<HearingNotificationDetailPanel> createState() =>
      _HearingNotificationDetailPanelState();
}

class _HearingNotificationDetailPanelState
    extends State<HearingNotificationDetailPanel> {
  List<MapEntry<String, String>>? _fields;
  Future<Map<String, dynamic>>? _enrichedFuture;

  List<MapEntry<String, String>> _fieldsFrom(Map<String, dynamic> hearing) {
    return widget.calendarOnly
        ? HearingNotificationFormatter.fieldsForCalendarHearing(hearing)
        : HearingNotificationFormatter.fieldsForHearingNotificationDetail(
            hearing,
            parseOrderText: widget.enrichFromRelatedHearings,
          );
  }

  List<MapEntry<String, String>> _seedFields() {
    return widget.calendarOnly
        ? HearingNotificationFormatter.fieldsForCalendarHearing(widget.data)
        : HearingNotificationFormatter.fieldsForHearingNotificationDetail(
            widget.data,
            parseOrderText: false,
          );
  }

  @override
  void initState() {
    super.initState();
    _fields = _seedLooksComplete(widget.data)
        ? _fieldsFrom(widget.data)
        : _seedFields();
    if (!_seedLooksComplete(widget.data)) {
      scheduleMicrotask(_prepareFields);
    }
  }

  @override
  void didUpdateWidget(covariant HearingNotificationDetailPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldHid = HearingCalendarFields.asDisplayString(
      oldWidget.hearingDocId ?? oldWidget.data['hearingDocId'],
    );
    final newHid = HearingCalendarFields.asDisplayString(
      widget.hearingDocId ?? widget.data['hearingDocId'],
    );
    if (oldHid != newHid) {
      _enrichedFuture = null;
      _fields = _seedFields();
      _prepareFields();
    }
  }

  void _prepareFields() {
    if (!mounted) return;
    final hid = HearingCalendarFields.asDisplayString(
      widget.hearingDocId ?? widget.data['hearingDocId'],
    );
    final seedFields = _seedFields();
    _fields = seedFields;

    if (hid.isEmpty) {
      setState(() {});
      return;
    }

    if (_seedLooksComplete(widget.data)) {
      setState(() => _fields = _fieldsFrom(widget.data));
      return;
    }

    _enrichedFuture ??= _cachedEnrichedHearing(
      hid,
      widget.data,
      siblingRows: widget.siblingRows,
      enrichFromRelatedHearings: widget.enrichFromRelatedHearings,
    );
    setState(() => _fields = seedFields);

    _enrichedFuture!.then((enriched) {
      if (!mounted) return;
      if (enriched.isEmpty) return;
      setState(() => _fields = _fieldsFrom(enriched));
    }).timeout(const Duration(seconds: 4), onTimeout: () {});
  }

  @override
  Widget build(BuildContext context) {
    final fields = _fields;
    if (fields == null) {
      return const SizedBox(
        height: 32,
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return _FieldsList(fields: fields);
  }
}

class _FieldsList extends StatelessWidget {
  const _FieldsList({required this.fields});

  final List<MapEntry<String, String>> fields;

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) {
      return Text(
        'No hearing details available.',
        style: TextStyle(fontSize: 14, color: Colors.grey[600]),
      );
    }

    final regular = <MapEntry<String, String>>[];
    String? fullText;
    String? involvedParty;
    String? partyRole;

    for (final row in fields) {
      if (row.key == 'Order / full text') {
        fullText = row.value;
      } else {
        if (row.key == 'Involved Party' ||
            row.key == 'Involved Parties' ||
            row.key == 'Client' ||
            row.key == 'Clients') {
          involvedParty = row.value;
        } else if (row.key == 'Your Role / Status') {
          partyRole = row.value;
        }
        regular.add(row);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (involvedParty != null && involvedParty.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.verified_user_rounded,
                  color: Color(0xFF16A34A),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Official Court Notice • Involved Party',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF15803D),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'You are named as an involved party (${partyRole != null && partyRole.isNotEmpty ? partyRole : "Named Party"}) in this court order. Please attend the scheduled hearing or coordinate with your legal counsel.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.green.shade900,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ...regular.map((row) => _DetailRow(label: row.key, value: row.value)),
        if (fullText != null &&
            fullText.isNotEmpty &&
            !CourtOrderTextSources.isInboxWrapper(fullText)) ...[
          const SizedBox(height: 4),
          _OrderFullTextSection(text: fullText),
        ],
      ],
    );
  }
}

class _OrderFullTextSection extends StatefulWidget {
  const _OrderFullTextSection({required this.text});

  final String text;

  @override
  State<_OrderFullTextSection> createState() => _OrderFullTextSectionState();
}

class _OrderFullTextSectionState extends State<_OrderFullTextSection> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final borderColor = _open
        ? AppTheme.royalBlue.withValues(alpha: 0.35)
        : Colors.grey.shade300;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: _open ? AppTheme.sidebarActive : Colors.white,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 18,
                    color: AppTheme.royalBlue,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Order / full text',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.royalBlue,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: AppTheme.royalBlue,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          clipBehavior: Clip.hardEdge,
          child: _open
              ? Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: _OrderTextView(text: widget.text),
                  ),
                )
              : const SizedBox(width: double.infinity, height: 0),
        ),
      ],
    );
  }
}

class _OrderTextView extends StatelessWidget {
  const _OrderTextView({required this.text});

  final String text;

  static const int _maxChars = 8000;

  @override
  Widget build(BuildContext context) {
    if (text.trim().isEmpty || CourtOrderTextSources.isInboxWrapper(text)) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, size: 18, color: Colors.blueGrey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Complete original court order document is archived under court branch records.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.grey.shade700,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final clipped = text.length > _maxChars
        ? '${text.substring(0, _maxChars)}…'
        : text;
    final doc = CourtOrderDisplay.parse(clipped);
    if (!doc.isPleading) {
      final plain = doc.paragraphs.join('\n\n');
      return Text(plain.isEmpty ? clipped : plain, style: _bodyStyle);
    }
    return _PleadingView(doc: doc);
  }
}

class _PleadingView extends StatelessWidget {
  const _PleadingView({required this.doc});

  final CourtOrderDisplay doc;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sideBySide =
            doc.caseMeta.isNotEmpty && constraints.maxWidth >= 520;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (doc.header.isNotEmpty) ...[
              for (final line in doc.header) _HeaderLine(line: line),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 72,
                  height: 1,
                  color: Colors.grey.shade300,
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (sideBySide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _PartyColumn(parties: doc.parties)),
                  const SizedBox(width: 16),
                  SizedBox(
                    width: 180,
                    child: _CaseMeta(lines: doc.caseMeta, alignEnd: true),
                  ),
                ],
              )
            else ...[
              if (doc.caseMeta.isNotEmpty) ...[
                _CaseMeta(lines: doc.caseMeta, alignEnd: false),
                const SizedBox(height: 12),
              ],
              _PartyColumn(parties: doc.parties),
            ],
            if (doc.heading != null) ...[
              const SizedBox(height: 16),
              Text(
                doc.heading!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: AppTheme.deepNavy,
                ),
              ),
              const SizedBox(height: 12),
            ],
            for (final paragraph in doc.paragraphs) ...[
              _Paragraph(text: paragraph),
              const SizedBox(height: 10),
            ],
            if (doc.soOrdered) ...[
              const SizedBox(height: 4),
              const Text(
                'SO ORDERED.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                  color: AppTheme.deepNavy,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (doc.closing != null) ...[
              Text(
                doc.closing!,
                textAlign: TextAlign.center,
                style: _bodyStyle,
              ),
              const SizedBox(height: 14),
            ],
            for (final line in doc.signature)
              Text(
                line,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  fontWeight: line.toLowerCase().contains('judge')
                      ? FontWeight.w500
                      : FontWeight.w700,
                  fontStyle: line.toLowerCase().contains('judge')
                      ? FontStyle.italic
                      : FontStyle.normal,
                  color: AppTheme.deepNavy,
                ),
              ),
            if (doc.footnotes.isNotEmpty) ...[
              const SizedBox(height: 14),
              for (final note in doc.footnotes)
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ],
        );
      },
    );
  }
}

const _bodyStyle = TextStyle(
  fontSize: 13.5,
  height: 1.55,
  color: Color(0xFF1C1C1C),
);

class _HeaderLine extends StatelessWidget {
  const _HeaderLine({required this.line});

  final String line;

  @override
  Widget build(BuildContext context) {
    final lower = line.toLowerCase();
    final contact = lower.startsWith('email') || lower.startsWith('contact');
    final court = line == line.toUpperCase() && !contact;
    return Text(
      line,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: contact ? 11.5 : (court ? 13 : 12.5),
        height: 1.45,
        fontWeight: court ? FontWeight.w700 : FontWeight.w500,
        letterSpacing: court ? 0.3 : 0,
        color: contact ? Colors.grey[700] : AppTheme.deepNavy,
      ),
    );
  }
}

class _PartyColumn extends StatelessWidget {
  const _PartyColumn({required this.parties});

  final List<CourtOrderPartyLine> parties;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final line in parties)
          Padding(
            padding: EdgeInsets.only(bottom: line.centered ? 2 : 8),
            child: Text(
              line.text,
              textAlign: line.centered ? TextAlign.center : TextAlign.left,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                fontWeight: line.centered ? FontWeight.w600 : FontWeight.w500,
                color: AppTheme.darkText,
              ),
            ),
          ),
      ],
    );
  }
}

class _CaseMeta extends StatelessWidget {
  const _CaseMeta({required this.lines, required this.alignEnd});

  final List<String> lines;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              line,
              textAlign: alignEnd ? TextAlign.right : TextAlign.left,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                fontWeight: line.toLowerCase().startsWith('civil case') ||
                        line.toLowerCase().startsWith('criminal case')
                    ? FontWeight.w700
                    : FontWeight.w500,
                color: AppTheme.deepNavy,
              ),
            ),
          ),
      ],
    );
  }
}

class _Paragraph extends StatelessWidget {
  const _Paragraph({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final wherefore = text.toUpperCase().startsWith('WHEREFORE');
    if (!wherefore) {
      return Text(text, textAlign: TextAlign.justify, style: _bodyStyle);
    }
    return Text.rich(
      TextSpan(
        style: _bodyStyle,
        children: [
          const TextSpan(
            text: 'WHEREFORE',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          TextSpan(text: text.substring('WHEREFORE'.length)),
        ],
      ),
      textAlign: TextAlign.justify,
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.grey[600],
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 4),
          kIsWeb
              ? Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.grey[900],
                  ),
                )
              : SelectableText(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: Colors.grey[900],
                  ),
                ),
        ],
      ),
    );
  }
}
