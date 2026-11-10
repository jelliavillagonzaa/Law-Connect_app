import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../models/appointment_model.dart';
import '../../models/case_model.dart';
import '../../models/user_model.dart';
import '../../utils/case_status_filter.dart';

/// Lightweight, ultra-responsive, freeze-proof attorney portal dashboard view.
/// Built as a pure StatelessWidget for maximum performance and zero event-loop overhead.
class AttorneyModernDashboardView extends StatelessWidget {
  final Map<String, dynamic> stats;
  final List<CaseModel> myCases;
  final List<AppointmentModel> allAppointments;
  final List<AppointmentModel> pendingRequests;
  final List<AppointmentModel> upcomingAppointments;
  final UserModel? currentUser;
  final bool isDesktop;
  final VoidCallback onCreateCase;
  final VoidCallback onViewAllTasks;
  final VoidCallback? onPaymentHistory;
  final VoidCallback onViewCalendar;
  final Function(String item, {String? caseFilter}) onNavigate;
  final Function(CaseModel c) onCaseTap;
  final Function(AppointmentModel a)? onAppointmentTap;

  const AttorneyModernDashboardView({
    super.key,
    required this.stats,
    required this.myCases,
    required this.allAppointments,
    required this.pendingRequests,
    required this.upcomingAppointments,
    required this.currentUser,
    required this.isDesktop,
    required this.onCreateCase,
    required this.onViewAllTasks,
    this.onPaymentHistory,
    required this.onViewCalendar,
    required this.onNavigate,
    required this.onCaseTap,
    this.onAppointmentTap,
  });

  String _timeGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning,';
    if (hour < 17) return 'Good afternoon,';
    return 'Good evening,';
  }

  String _displayName() {
    final name = (currentUser?.fullName ?? currentUser?.name ?? '').trim();
    if (name.isNotEmpty && name.toLowerCase() != 'attorney') {
      return name;
    }
    return 'Attorney';
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 28 : 16,
        vertical: 22,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Executive Welcome Banner
          _buildWelcomeBanner(context),
          const SizedBox(height: 20),

          // 2. 4 High-Impact KPI Stat Cards
          _buildStatCardsRow(context),
          const SizedBox(height: 24),

          // 3. Middle Section: Upcoming Schedule & Quick Actions
          _buildMiddleSection(context),
          const SizedBox(height: 24),

          // 4. Bottom Section: Recent Cases (60%) + Pending Requests (40%)
          _buildBottomSection(context),
          const SizedBox(height: 36),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. EXECUTIVE WELCOME BANNER
  // ===========================================================================
  Widget _buildWelcomeBanner(BuildContext context) {
    final todayStr = DateFormat('EEEE, MMMM d, y').format(DateTime.now());

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF0A192F),
            Color(0xFF112240),
            Color(0xFF0F264A),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0A192F).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            // Decorative background legal seal
            Positioned(
              right: 20,
              top: -20,
              bottom: -20,
              child: Opacity(
                opacity: 0.05,
                child: const Icon(
                  Icons.balance_rounded,
                  size: 220,
                  color: Colors.white,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 28 : 20,
                vertical: isDesktop ? 26 : 22,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Date pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 12,
                                color: Color(0xFF60A5FA),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                todayStr,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFE2E8F0),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _timeGreeting(),
                          style: TextStyle(
                            fontSize: isDesktop ? 22 : 18,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF94A3B8),
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                _displayName(),
                                style: TextStyle(
                                  fontSize: isDesktop ? 28 : 22,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                  height: 1.2,
                                  letterSpacing: -0.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('👋', style: TextStyle(fontSize: 22)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Welcome back. Here is the operational summary of your active cases and scheduled hearings.",
                          style: TextStyle(
                            fontSize: isDesktop ? 13.5 : 12,
                            color: Colors.white.withValues(alpha: 0.75),
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDesktop) ...[
                    const SizedBox(width: 28),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'SYSTEM STATUS',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            '"Justice is not just a goal,\nit is a process."',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontStyle: FontStyle.italic,
                              color: Colors.white,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. STAT CARDS ROW
  // ===========================================================================
  Widget _buildStatCardsRow(BuildContext context) {
    final totalCases = myCases.isNotEmpty
        ? myCases.length
        : (stats['totalCases'] ?? 0);
    final activeCases = myCases.isNotEmpty
        ? myCases.where((c) => !CaseStatusFilter.isCompleted(c.status)).length
        : (stats['activeCases'] ?? 0);
    final completedCases = myCases.isNotEmpty
        ? myCases.where((c) => CaseStatusFilter.isCompleted(c.status)).length
        : (stats['completedCases'] ?? 0);

    final cards = [
      _MetricItem(
        title: 'Total Cases',
        value: '$totalCases',
        badgeText: 'Total portfolio',
        icon: Icons.folder_rounded,
        iconColor: const Color(0xFF1E6BFF),
        bgColor: const Color(0xFFEFF6FF),
        onTap: () => onNavigate('cases', caseFilter: CaseStatusFilter.all),
      ),
      _MetricItem(
        title: 'Active Cases',
        value: '$activeCases',
        badgeText: 'Active portfolio',
        icon: Icons.balance_rounded,
        iconColor: const Color(0xFF10B981),
        bgColor: const Color(0xFFECFDF5),
        onTap: () => onNavigate('cases', caseFilter: CaseStatusFilter.active),
      ),
      _MetricItem(
        title: 'Completed Cases',
        value: '$completedCases',
        badgeText: 'Archived / Closed',
        icon: Icons.task_alt_rounded,
        iconColor: const Color(0xFF6366F1),
        bgColor: const Color(0xFFEEF2FF),
        onTap: () => onNavigate('closed_cases'),
      ),
      _MetricItem(
        title: 'Upcoming Schedule',
        value: '${upcomingAppointments.length}',
        badgeText: 'Confirmed',
        icon: Icons.calendar_today_rounded,
        iconColor: const Color(0xFF0EA5E9),
        bgColor: const Color(0xFFF0F9FF),
        onTap: () => onNavigate('calendar'),
      ),
    ];

    if (isDesktop) {
      return Row(
        children: cards
            .map(
              (item) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _buildMetricCard(item),
                ),
              ),
            )
            .toList(),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        mainAxisExtent: 108,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) => _buildMetricCard(cards[index]),
    );
  }

  Widget _buildMetricCard(_MetricItem item) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(14),
          hoverColor: item.bgColor.withValues(alpha: 0.4),
          splashColor: item.iconColor.withValues(alpha: 0.1),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: item.bgColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        item.icon,
                        color: item.iconColor,
                        size: 18,
                      ),
                    ),
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2.5,
                        ),
                        decoration: BoxDecoration(
                          color: item.bgColor,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.badgeText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: item.iconColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        item.value,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                          height: 1.1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 3. MIDDLE SECTION: UPCOMING APPOINTMENT + QUICK ACTIONS
  // ===========================================================================
  Widget _buildMiddleSection(BuildContext context) {
    if (isDesktop) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: _buildUpcomingScheduleCard(context),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: _buildQuickActionsCard(context),
          ),
        ],
      );
    }

    return Column(
      children: [
        _buildUpcomingScheduleCard(context),
        const SizedBox(height: 16),
        _buildQuickActionsCard(context),
      ],
    );
  }

  Widget _buildUpcomingScheduleCard(BuildContext context) {
    final nextApt =
        upcomingAppointments.isNotEmpty ? upcomingAppointments.first : null;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.event_available_rounded,
                      color: Color(0xFF1E6BFF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Next Appointment',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: onViewCalendar,
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View Calendar',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E6BFF),
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: Color(0xFF1E6BFF),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (nextApt != null) ...[
            InkWell(
              onTap: onViewCalendar,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E6BFF),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('d').format(nextApt.appointmentDateTime),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1,
                            ),
                          ),
                          Text(
                            DateFormat('MMM').format(nextApt.appointmentDateTime),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white70,
                              height: 1.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nextApt.clientName.isNotEmpty
                                ? nextApt.clientName
                                : (nextApt.caseTitle?.isNotEmpty == true
                                    ? nextApt.caseTitle!
                                    : 'Consultation Client'),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            nextApt.notes != null && nextApt.notes!.isNotEmpty
                                ? '${DateFormat('h:mm a · EEEE').format(nextApt.appointmentDateTime)} · ${nextApt.notes!.replaceFirst('Location: ', '')}'
                                : DateFormat('h:mm a · EEEE')
                                    .format(nextApt.appointmentDateTime),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: nextApt.appointmentType == 'hearing_court'
                            ? const Color(0xFFEFF6FF)
                            : const Color(0xFFECFDF5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        nextApt.appointmentType == 'hearing_court'
                            ? 'Hearing'
                            : 'Confirmed',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: nextApt.appointmentType == 'hearing_court'
                              ? const Color(0xFF1E6BFF)
                              : const Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(
                    Icons.event_available_rounded,
                    size: 32,
                    color: Color(0xFF94A3B8),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No scheduled appointments today',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Your upcoming hearings and client meetings will appear here.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.bolt_rounded,
                  color: Color(0xFFD97706),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 460;
              final createBtn = _buildActionButton(
                icon: Icons.add_circle_outline_rounded,
                label: 'Create Case',
                isPrimary: true,
                onTap: onCreateCase,
              );
              final tasksBtn = _buildActionButton(
                icon: Icons.checklist_rounded,
                label: 'Staff Tasks',
                isPrimary: false,
                onTap: onViewAllTasks,
              );
              final paymentsBtn = _buildActionButton(
                icon: Icons.receipt_long_rounded,
                label: 'Payment History',
                isPrimary: false,
                onTap: onPaymentHistory ?? () {},
              );

              if (isWide) {
                return Row(
                  children: [
                    Expanded(child: createBtn),
                    const SizedBox(width: 10),
                    Expanded(child: tasksBtn),
                    const SizedBox(width: 10),
                    Expanded(child: paymentsBtn),
                  ],
                );
              }

              return Column(
                children: [
                  Row(
                    children: [
                      Expanded(child: createBtn),
                      const SizedBox(width: 10),
                      Expanded(child: tasksBtn),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: paymentsBtn,
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isPrimary ? const Color(0xFF1E6BFF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: isPrimary ? null : Border.all(color: const Color(0xFFCBD5E1)),
        boxShadow: isPrimary
            ? [
                BoxShadow(
                  color: const Color(0xFF1E6BFF).withValues(alpha: 0.28),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          hoverColor: isPrimary
              ? Colors.white.withValues(alpha: 0.15)
              : const Color(0xFFE2E8F0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isPrimary ? Colors.white : const Color(0xFF1E293B),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: isPrimary ? Colors.white : const Color(0xFF1E293B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 4. BOTTOM SECTION: RECENT CASES
  // ===========================================================================
  Widget _buildBottomSection(BuildContext context) {
    return _buildRecentCasesCard(context);
  }

  Widget _buildRecentCasesCard(BuildContext context) {
    final displayCases = myCases.take(5).toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.folder_shared_rounded,
                      color: Color(0xFF1E6BFF),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Recent Cases',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () => onNavigate('cases', caseFilter: CaseStatusFilter.all),
                borderRadius: BorderRadius.circular(8),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'View All',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E6BFF),
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 16,
                        color: Color(0xFF1E6BFF),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (displayCases.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
              alignment: Alignment.center,
              child: const Column(
                children: [
                  Icon(
                    Icons.folder_open_rounded,
                    size: 36,
                    color: Color(0xFF94A3B8),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'No active cases assigned yet',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF475569),
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Your active client cases will be shown here.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF94A3B8)),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayCases.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: Color(0xFFF1F5F9),
              ),
              itemBuilder: (context, index) {
                final c = displayCases[index];
                final caseNo = c.id.length >= 8
                    ? 'C-${c.id.substring(0, 8).toUpperCase()}'
                    : 'C-00${index + 1}';
                return InkWell(
                  onTap: () => onCaseTap(c),
                  borderRadius: BorderRadius.circular(10),
                  hoverColor: const Color(0xFFF8FAFC),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF6FF),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.description_outlined,
                            color: Color(0xFF1E6BFF),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.caseTitle.isNotEmpty
                                    ? c.caseTitle
                                    : 'Matter Title',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F172A),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$caseNo · ${c.caseType.isNotEmpty ? c.caseType : "General"}',
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildStatusBadge(c.status),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }



  Widget _buildStatusBadge(String rawStatus) {
    final status = rawStatus.toLowerCase().trim();
    Color bg = const Color(0xFFECFDF5);
    Color textColor = const Color(0xFF059669);
    String label = 'Active';

    if (status == 'pending' || status == 'in_progress' || status == 'in progress') {
      bg = const Color(0xFFFEF3C7);
      textColor = const Color(0xFFD97706);
      label = 'In Progress';
    } else if (status == 'closed' || status == 'completed') {
      bg = const Color(0xFFEFF6FF);
      textColor = const Color(0xFF2563EB);
      label = 'Completed';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}

class _MetricItem {
  final String title;
  final String value;
  final String badgeText;
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final VoidCallback onTap;

  const _MetricItem({
    required this.title,
    required this.value,
    required this.badgeText,
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.onTap,
  });
}
