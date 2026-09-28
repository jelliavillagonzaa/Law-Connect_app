import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/appointment_model.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';

/// Upcoming-appointment row that always resolves the client's real name
/// from their user profile (first + last name), not the word "Client".
class UpcomingAppointmentTile extends StatefulWidget {
  final AppointmentModel appointment;

  const UpcomingAppointmentTile({super.key, required this.appointment});

  @override
  State<UpcomingAppointmentTile> createState() =>
      _UpcomingAppointmentTileState();
}

class _UpcomingAppointmentTileState extends State<UpcomingAppointmentTile> {
  String _name = '';
  String _email = '';

  @override
  void initState() {
    super.initState();
    _seedFromAppointment();
    _loadProfile();
  }

  @override
  void didUpdateWidget(covariant UpcomingAppointmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.appointment.id != widget.appointment.id ||
        oldWidget.appointment.clientId != widget.appointment.clientId) {
      _seedFromAppointment();
      _loadProfile();
    }
  }

  void _seedFromAppointment() {
    final stored = widget.appointment.clientName.trim();
    if (_looksLikeEmail(stored)) {
      _email = stored;
    } else if (stored.isNotEmpty && !_isGeneric(stored)) {
      _name = stored;
    }
  }

  bool _looksLikeEmail(String value) {
    final text = value.trim();
    return text.contains('@') && text.contains('.');
  }

  bool _isGeneric(String value) {
    final text = value.trim().toLowerCase();
    return text.isEmpty ||
        text == 'client' ||
        text == 'user' ||
        text == 'someone';
  }

  Future<void> _loadProfile() async {
    try {
      final firestore = FirebaseFirestore.instance;
      Map<String, dynamic>? data;

      final clientId = widget.appointment.clientId.trim();
      if (clientId.isNotEmpty) {
        final doc = await firestore.collection('users').doc(clientId).get();
        if (doc.exists) data = doc.data();
      }

      final emailHint = _looksLikeEmail(widget.appointment.clientName)
          ? widget.appointment.clientName.trim()
          : _email;
      if (data == null && emailHint.isNotEmpty) {
        final snap = await firestore
            .collection('users')
            .where('email', isEqualTo: emailHint)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) data = snap.docs.first.data();
      }

      if (data == null || !mounted) return;

      final resolved = UserModel.resolveDisplayName(data).trim();
      final first = (data['firstName'] ?? data['first_name'] ?? '')
          .toString()
          .trim();
      final last = (data['lastName'] ?? data['last_name'] ?? '')
          .toString()
          .trim();
      final combined = [first, last].where((s) => s.isNotEmpty).join(' ');
      final displayNameField = (data['displayName'] ?? data['display_name'] ?? '')
          .toString()
          .trim();
      final picked = [
        resolved,
        combined,
        displayNameField,
      ].firstWhere(
        (s) => s.isNotEmpty && !_looksLikeEmail(s) && !_isGeneric(s),
        orElse: () => '',
      );
      final email = (data['email'] ?? '').toString().trim();

      setState(() {
        if (picked.isNotEmpty &&
            !_looksLikeEmail(picked) &&
            !_isGeneric(picked)) {
          _name = picked;
        }
        if (email.isNotEmpty) _email = email;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final appointment = widget.appointment;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.royalBlue.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.event_available,
              color: AppTheme.royalBlue,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat(
                    'MMM dd, yyyy – hh:mm a',
                  ).format(appointment.appointmentDateTime),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                if (_name.isNotEmpty)
                  Text(
                    _name,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1C1C1C),
                    ),
                  ),
                if (_email.isNotEmpty)
                  Text(
                    _email,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6D6D6D),
                    ),
                  ),
                if (appointment.caseTitle != null &&
                    appointment.caseTitle!.trim().isNotEmpty)
                  Text(
                    appointment.caseTitle!,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6D6D6D),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
