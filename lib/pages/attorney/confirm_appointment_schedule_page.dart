import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../models/appointment_model.dart';
import '../../services/enhanced_appointment_service.dart';
import '../../widgets/common/schedule_full_dialog.dart';
import '../../widgets/staff/staff_ui_theme.dart';

class ConfirmAppointmentSchedulePage extends StatefulWidget {
  final AppointmentModel pendingRequest;

  const ConfirmAppointmentSchedulePage({
    super.key,
    required this.pendingRequest,
  });

  @override
  State<ConfirmAppointmentSchedulePage> createState() =>
      _ConfirmAppointmentSchedulePageState();
}

class _ConfirmAppointmentSchedulePageState
    extends State<ConfirmAppointmentSchedulePage> {
  final EnhancedAppointmentService _appointmentService =
      EnhancedAppointmentService();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String _appointmentType = 'In-office';
  final TextEditingController _notesController = TextEditingController();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Default to the requested date/time to keep things intuitive
    final requestDateTime = widget.pendingRequest.appointmentDateTime;
    _selectedDate = DateTime(
      requestDateTime.year,
      requestDateTime.month,
      requestDateTime.day,
    );
    _selectedTime = TimeOfDay(
      hour: requestDateTime.hour,
      minute: requestDateTime.minute,
    );

    // Intelligently infer requested appointment type
    final rawType = widget.pendingRequest.appointmentType.toLowerCase();
    if (rawType.contains('phone')) {
      _appointmentType = 'Phone Call';
    } else if (rawType.contains('online') ||
        rawType.contains('meet') ||
        rawType.contains('video')) {
      _appointmentType = 'Online Meeting';
    } else {
      _appointmentType = 'In-office';
    }

    _notesController.text = widget.pendingRequest.notes ?? '';
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  String _getClientInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return 'CL';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initialDate = _selectedDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(now) ? now : initialDate,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: StaffUi.navyDeep,
              onPrimary: Colors.white,
              onSurface: StaffUi.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  Future<void> _pickTime() async {
    final initialTime = _selectedTime ?? TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: StaffUi.navyDeep,
              onPrimary: Colors.white,
              onSurface: StaffUi.text,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _selectedTime = picked;
      });
    }
  }

  Future<void> _handleSave() async {
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select both date and time.'),
          backgroundColor: StaffUi.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final finalDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    setState(() {
      _isSaving = true;
    });

    final result = await _appointmentService.createConfirmedAppointment(
      request: widget.pendingRequest,
      finalDateTime: finalDateTime,
      appointmentType: _appointmentType,
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    if (result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(result['message'] ?? 'Appointment successfully confirmed!'),
              ),
            ],
          ),
          backgroundColor: StaffUi.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Get.back();
    } else if (EnhancedAppointmentService.isScheduleFull(result)) {
      await showScheduleFullDialog(context, date: finalDateTime);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(result['message'] ?? 'Failed to confirm appointment'),
              ),
            ],
          ),
          backgroundColor: StaffUi.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      backgroundColor: StaffUi.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: StaffUi.navyDeep,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          tooltip: 'Back',
          onPressed: _isSaving ? null : () => Get.back(),
        ),
        title: Text(
          'Confirm Appointment Schedule',
          style: StaffUi.style(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
          ),
        ),
        centerTitle: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isDesktop ? 680 : double.infinity,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: isDesktop ? 24 : 16,
              vertical: 24,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: StaffUi.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: StaffUi.line),
                boxShadow: StaffUi.cardShadow,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Top Hero / Header Section
                  _buildHeaderBanner(),

                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Client Information Summary Card
                        _buildClientCard(),

                        const SizedBox(height: 24),

                        // Section 1: Final Schedule (Date & Time)
                        _buildSectionLabel(
                          icon: Icons.calendar_month_rounded,
                          title: 'Final Schedule',
                          subtitle: 'Select the confirmed consultation date and time',
                        ),
                        const SizedBox(height: 12),
                        _buildSchedulePickers(),

                        const SizedBox(height: 24),

                        // Section 2: Appointment Type
                        _buildSectionLabel(
                          icon: Icons.meeting_room_outlined,
                          title: 'Appointment Type',
                          subtitle: 'Mode of consultation for this schedule',
                        ),
                        const SizedBox(height: 12),
                        _buildAppointmentTypeSelector(),

                        const SizedBox(height: 24),

                        // Section 3: Notes & Instructions
                        _buildSectionLabel(
                          icon: Icons.edit_note_rounded,
                          title: 'Notes (Optional)',
                          subtitle: 'Add consultation guidelines or venue instructions',
                        ),
                        const SizedBox(height: 12),
                        _buildNotesField(),

                        const SizedBox(height: 20),

                        // Confirmation notice callout
                        _buildNoticeCallout(),

                        const SizedBox(height: 28),

                        // Actions Footer
                        _buildActionButtons(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: StaffUi.navyDeep,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(19),
          topRight: Radius.circular(19),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF07152B),
            Color(0xFF0D2547),
            Color(0xFF143765),
          ],
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
              ),
            ),
            child: const Icon(
              Icons.event_available_rounded,
              color: StaffUi.goldGlow,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Confirm Appointment Schedule',
                  style: StaffUi.style(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Finalize the date, time, and consultation method for this client request.',
                  style: StaffUi.style(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: StaffUi.warningLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: StaffUi.gold.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: StaffUi.goldDeep,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Pending',
                  style: StaffUi.style(
                    color: StaffUi.goldDeep,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientCard() {
    final clientName = widget.pendingRequest.clientName.trim().isEmpty
        ? 'Client'
        : widget.pendingRequest.clientName.trim();
    final initials = _getClientInitials(clientName);
    final requestedFormatted = DateFormat('EEE, MMM dd, yyyy • hh:mm a')
        .format(widget.pendingRequest.appointmentDateTime);
    final caseTitle = widget.pendingRequest.caseTitle;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: StaffUi.infoLight.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: StaffUi.info.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: StaffUi.navyDeep,
            child: Text(
              initials,
              style: StaffUi.style(
                color: StaffUi.goldGlow,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        clientName,
                        style: StaffUi.style(
                          color: StaffUi.text,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                if (caseTitle != null && caseTitle.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Case: ${caseTitle.trim()}',
                    style: StaffUi.style(
                      color: StaffUi.navy,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: StaffUi.line),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.access_time_rounded,
                        size: 14,
                        color: StaffUi.muted,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Requested: $requestedFormatted',
                        style: StaffUi.style(
                          color: StaffUi.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: StaffUi.navy),
            const SizedBox(width: 8),
            Text(
              title,
              style: StaffUi.style(
                color: StaffUi.text,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Padding(
          padding: const EdgeInsets.only(left: 26),
          child: Text(
            subtitle,
            style: StaffUi.style(
              color: StaffUi.muted,
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSchedulePickers() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 460;

        final datePickerCard = _buildPickerCard(
          label: 'Final Date',
          value: _selectedDate != null
              ? DateFormat('EEE, MMM dd, yyyy').format(_selectedDate!)
              : 'Select date',
          icon: Icons.calendar_today_rounded,
          onTap: _isSaving ? null : _pickDate,
        );

        final timePickerCard = _buildPickerCard(
          label: 'Final Time',
          value: _selectedTime != null
              ? _selectedTime!.format(context)
              : 'Select time',
          icon: Icons.access_time_rounded,
          onTap: _isSaving ? null : _pickTime,
        );

        if (isNarrow) {
          return Column(
            children: [
              datePickerCard,
              const SizedBox(height: 12),
              timePickerCard,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: datePickerCard),
            const SizedBox(width: 14),
            Expanded(child: timePickerCard),
          ],
        );
      },
    );
  }

  Widget _buildPickerCard({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFBFBFD),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: StaffUi.line, width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: StaffUi.navyDeep.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: StaffUi.navyDeep, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: StaffUi.style(
                        color: StaffUi.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: StaffUi.style(
                        color: StaffUi.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.unfold_more_rounded,
                color: StaffUi.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppointmentTypeSelector() {
    final types = [
      {
        'value': 'In-office',
        'title': 'In-office',
        'subtitle': 'At Firm',
        'icon': Icons.apartment_rounded,
      },
      {
        'value': 'Online Meeting',
        'title': 'Online Meeting',
        'subtitle': 'Video Call',
        'icon': Icons.videocam_rounded,
      },
      {
        'value': 'Phone Call',
        'title': 'Phone Call',
        'subtitle': 'Voice Consultation',
        'icon': Icons.phone_in_talk_rounded,
      },
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 480;

        final items = types.map((item) {
          final isSelected = _appointmentType == item['value'];

          final widgetCard = Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _isSaving
                  ? null
                  : () {
                      setState(() {
                        _appointmentType = item['value'] as String;
                      });
                    },
              borderRadius: BorderRadius.circular(14),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected
                      ? StaffUi.navyDeep.withValues(alpha: 0.05)
                      : const Color(0xFFFBFBFD),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected ? StaffUi.navyDeep : StaffUi.line,
                    width: isSelected ? 1.8 : 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? StaffUi.navyDeep
                            : StaffUi.navyDeep.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        item['icon'] as IconData,
                        size: 18,
                        color: isSelected ? Colors.white : StaffUi.navyDeep,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item['title'] as String,
                            style: StaffUi.style(
                              color: isSelected ? StaffUi.navyDeep : StaffUi.text,
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w600,
                            ),
                          ),
                          Text(
                            item['subtitle'] as String,
                            style: StaffUi.style(
                              color: StaffUi.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: StaffUi.navyDeep,
                        size: 18,
                      ),
                  ],
                ),
              ),
            ),
          );

          return widgetCard;
        }).toList();

        if (isNarrow) {
          return Column(
            children: items
                .map((card) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: card,
                    ))
                .toList(),
          );
        }

        return Row(
          children: items
              .map((card) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: card,
                    ),
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _buildNotesField() {
    return TextField(
      controller: _notesController,
      maxLines: 4,
      enabled: !_isSaving,
      style: StaffUi.style(
        color: StaffUi.text,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText:
            'Add consultation details, instructions, room number, or meeting link for the client...',
        hintStyle: StaffUi.style(
          color: StaffUi.muted.withValues(alpha: 0.7),
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        filled: true,
        fillColor: const Color(0xFFFBFBFD),
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: StaffUi.line, width: 1.2),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: StaffUi.line, width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: StaffUi.navyDeep, width: 1.6),
        ),
      ),
    );
  }

  Widget _buildNoticeCallout() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StaffUi.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: StaffUi.navyLight,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Confirming locks this consultation schedule on the calendar and sends an automated notification to the client.',
              style: StaffUi.style(
                color: StaffUi.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton(
          onPressed: _isSaving ? null : () => Get.back(),
          style: OutlinedButton.styleFrom(
            foregroundColor: StaffUi.textSecondary,
            side: const BorderSide(color: StaffUi.line, width: 1.2),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            'Cancel',
            style: StaffUi.style(
              color: StaffUi.textSecondary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 14),
        ElevatedButton(
          onPressed: _isSaving ? null : _handleSave,
          style: ElevatedButton.styleFrom(
            backgroundColor: StaffUi.navyDeep,
            foregroundColor: Colors.white,
            elevation: 1,
            shadowColor: StaffUi.navyDeep.withValues(alpha: 0.3),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle_outline_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Confirm Schedule',
                      style: StaffUi.style(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
