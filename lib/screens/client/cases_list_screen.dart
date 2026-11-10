import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/case_model.dart';
import '../../pages/case/case_detail_page.dart';
import '../../utils/case_status_filter.dart';
import '../../utils/case_result.dart';
import '../../utils/quiet_console.dart';
import 'send_request_screen.dart';

/// Client cases list — one-shot Firestore load + pull to refresh (no live listener).
class CasesListScreen extends StatefulWidget {
  const CasesListScreen({super.key});

  @override
  State<CasesListScreen> createState() => _CasesListScreenState();
}

class _CasesListScreenState extends State<CasesListScreen> {
  List<CaseModel> _cases = const [];
  String? _error;
  bool _viewClosed = false;
  bool _inFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_loadCases());
    });
  }

  Future<void> _loadCases() async {
    if (_inFlight) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _inFlight = true;
    final query = FirebaseFirestore.instance
        .collection('cases')
        .where('clientId', isEqualTo: user.uid)
        .limit(20);

    try {
      try {
        final cached = await query
            .get(const GetOptions(source: Source.cache))
            .timeout(const Duration(milliseconds: 600));
        if (mounted && cached.docs.isNotEmpty) {
          await _applyDocs(cached.docs);
        }
      } catch (_) {}

      try {
        final snapshot = await query.get().timeout(const Duration(seconds: 1));
        if (!mounted) return;
        await _applyDocs(snapshot.docs);
      } catch (e) {
        if (mounted && _cases.isEmpty) {
          setState(() => _error = safeErrorString(e));
        }
      }
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _applyDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final cases = <CaseModel>[];
    for (var i = 0; i < docs.length; i++) {
      try {
        final model = CaseModel.fromFirestore(docs[i]);
        if (CaseStatusFilter.visibleToClient(model)) {
          cases.add(model);
        }
      } catch (_) {}
      if (i % 8 == 7) {
        await Future<void>.delayed(Duration.zero);
        if (!mounted) return;
      }
    }
    cases.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    if (!mounted) return;
    setState(() {
      _cases = cases;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return Scaffold(
        backgroundColor: AppTheme.lightBackground,
        appBar: AppBar(
          backgroundColor: AppTheme.navy,
          title: const Text(
            'Cases',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
          elevation: 0,
          automaticallyImplyLeading: false,
        ),
        body: const Center(
          child: Text('Please log in to view your cases'),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(
        backgroundColor: AppTheme.navy,
        title: Text(
          _viewClosed ? 'Closed Cases' : 'My Cases',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: Colors.white),
            tooltip: 'Send Case Request',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SendRequestScreen(),
                ),
              );
            },
          ),
          TextButton(
            onPressed: () => setState(() => _viewClosed = !_viewClosed),
            child: Text(
              _viewClosed ? 'My Cases' : 'Closed',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final visible = _cases.where((c) {
      return _viewClosed
          ? CaseStatusFilter.isCompleted(c.status)
          : !CaseStatusFilter.isCompleted(c.status);
    }).toList();

    if (_error != null && _cases.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                'Error loading cases',
                style: AppTheme.heading4,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadCases,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadCases,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
            Icon(
              Icons.folder_open,
              size: 64,
              color: AppTheme.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              _viewClosed ? 'No closed cases' : 'No cases yet',
              textAlign: TextAlign.center,
              style: AppTheme.heading4.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _viewClosed
                    ? 'Completed cases will appear here.'
                    : 'Your attorney will create cases for you based on your legal requests.\nTap below to send a request.',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            if (!_viewClosed) ...[
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SendRequestScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.send, size: 16),
                  label: const Text('Send Case Request'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.royalBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCases,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: visible.length,
        itemBuilder: (context, index) {
          return _buildCaseCard(context, visible[index]);
        },
      ),
    );
  }

  Widget _buildCaseCard(BuildContext context, CaseModel caseModel) {
    Color statusColor;
    Color statusBgColor;
    switch (caseModel.status.toLowerCase()) {
      case 'active':
      case 'in_progress':
      case 'open':
      case 'ongoing':
        statusColor = Colors.white;
        statusBgColor = const Color(0xFF4A90E2);
        break;
      case 'pending':
        statusColor = Colors.white;
        statusBgColor = const Color(0xFFFF9500);
        break;
      case 'accepted':
        statusColor = Colors.white;
        statusBgColor = AppTheme.navy;
        break;
      case 'completed':
      case 'closed':
        statusColor = Colors.white;
        statusBgColor = const Color(0xFFFF6B6B);
        break;
      default:
        statusColor = Colors.white;
        statusBgColor = AppTheme.textSecondary;
    }

    String? hearingDateStr;
    if (caseModel.progress != null) {
      final hearingDate = caseModel.progress!['hearingDate'];
      if (hearingDate != null) {
        try {
          final date = hearingDate is DateTime
              ? hearingDate
              : DateTime.parse(hearingDate.toString());
          hearingDateStr = DateFormat('MMM dd, yyyy').format(date);
        } catch (_) {}
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CaseDetailPage(caseId: caseModel.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.navy.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.folder_copy_rounded,
                      color: AppTheme.navy,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          caseModel.caseTitle,
                          style: AppTheme.heading4.copyWith(
                            color: AppTheme.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          caseModel.caseType,
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      CaseStatusFilter.statusLabel(caseModel.status),
                      style: AppTheme.caption.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.arrow_forward_ios_rounded,
                    color: AppTheme.textSecondary,
                    size: 16,
                  ),
                ],
              ),
              if (CaseStatusFilter.isCompleted(caseModel.status) &&
                  CaseResult.label(caseModel.caseResult).isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Result: ${CaseResult.label(caseModel.caseResult)}',
                  style: AppTheme.bodySmall.copyWith(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (hearingDateStr != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Hearing: $hearingDateStr',
                      style: AppTheme.bodySmall.copyWith(
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
