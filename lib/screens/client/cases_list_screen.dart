import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../models/case_model.dart';
import '../../pages/case/case_detail_page.dart';

/// Client cases list — one-shot Firestore load + pull to refresh (no live listener).
class CasesListScreen extends StatefulWidget {
  const CasesListScreen({super.key});

  @override
  State<CasesListScreen> createState() => _CasesListScreenState();
}

class _CasesListScreenState extends State<CasesListScreen> {
  List<CaseModel> _cases = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCases();
  }

  Future<void> _loadCases() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('cases')
          .where('clientId', isEqualTo: user.uid)
          .limit(60)
          .get()
          .timeout(const Duration(seconds: 12));

      final cases = snapshot.docs
          .map((doc) => CaseModel.fromFirestore(doc))
          .where((c) => !c.isArchived)
          .toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

      if (!mounted) return;
      setState(() {
        _cases = cases;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
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
        title: const Text(
          'My Cases',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        elevation: 0,
        automaticallyImplyLeading: false,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _cases.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

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

    if (_cases.isEmpty) {
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
              'No cases yet',
              textAlign: TextAlign.center,
              style: AppTheme.heading4.copyWith(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Your attorney will create cases for you.\nPull down to refresh.',
                style: AppTheme.bodyMedium.copyWith(
                  color: AppTheme.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadCases,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        itemCount: _cases.length,
        itemBuilder: (context, index) {
          return _buildCaseCard(context, _cases[index]);
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
      case 'under_review':
        statusColor = Colors.white;
        statusBgColor = const Color(0xFFFF9500);
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
                      caseModel.status.length > 10
                          ? caseModel.status.substring(0, 10)
                          : caseModel.status,
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
