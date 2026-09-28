import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../theme/app_theme.dart';
import '../../services/notary_service.dart';
import '../../services/notary_service_config.dart';
import 'attorney_selection_screen.dart';

class NotaryServiceDetailsScreen extends StatefulWidget {
  final String serviceType;

  const NotaryServiceDetailsScreen({
    super.key,
    required this.serviceType,
  });

  @override
  State<NotaryServiceDetailsScreen> createState() =>
      _NotaryServiceDetailsScreenState();
}

class _NotaryServiceDetailsScreenState
    extends State<NotaryServiceDetailsScreen> {
  final NotaryService _notaryService = NotaryService();
  final TextEditingController _notesController = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  bool _isSubmitting = false;

  List<String> get _bringDocuments =>
      NotaryServiceConfig.getRequiredDocuments(widget.serviceType);

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 90)),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedDate = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedTime = picked);
  }

  Future<void> _submit() async {
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please choose a preferred date and time.'),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      String? attorneyId;
      try {
        final attorneys = await loadBookableAttorneys()
            .timeout(const Duration(seconds: 3));
        if (attorneys.length == 1) attorneyId = attorneys.first.id;
      } catch (_) {}

      final preferred = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      final created = await _notaryService
          .createNotaryRequest(
            serviceType: widget.serviceType,
            documentUrls: const [],
            notes: _notesController.text.trim(),
            attorneyId: attorneyId,
            preferredDateTime: preferred,
            bringDocuments: _bringDocuments,
          )
          .timeout(const Duration(seconds: 20));
      if (created['success'] != true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              created['message']?.toString() ?? 'Failed to submit request.',
            ),
          ),
        );
        return;
      }

      unawaited(
        _notaryService.notifyNewNotaryRequest(
          requestId: created['requestId']?.toString() ?? '',
          serviceType: widget.serviceType,
          attorneyId: attorneyId,
          preferredDateTime: preferred,
        ),
      );

      if (!mounted) return;
      setState(() => _isSubmitting = false);
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Request saved'),
          content: const Text(
            'Your notary request was submitted. Bring the original documents to the office. Do not send them here.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) Get.back();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit notary request.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'Notary Service Details',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.royalBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoCard(
              title: widget.serviceType,
              body: NotaryServiceConfig.getDescription(widget.serviceType),
            ),
            const SizedBox(height: 12),
            _exampleCard(NotaryServiceConfig.getExample(widget.serviceType)),
            const SizedBox(height: 12),
            _privacyNote(),
            const SizedBox(height: 24),
            const Text(
              'Bring to the office',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Originals only. Do not upload or send copies here.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            const SizedBox(height: 12),
            ..._bringDocuments.map(_bringRow),
            const SizedBox(height: 16),
            const Text(
              'Preferred date',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            _pickerField(
              icon: Icons.calendar_today_rounded,
              label: _selectedDate == null
                  ? 'Select date'
                  : DateFormat('MMM dd, yyyy').format(_selectedDate!),
              onTap: _pickDate,
            ),
            const SizedBox(height: 16),
            const Text(
              'Preferred time',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            _pickerField(
              icon: Icons.access_time,
              label: _selectedTime == null
                  ? 'Select time'
                  : _selectedTime!.format(context),
              onTap: _pickTime,
            ),
            const SizedBox(height: 16),
            const Text(
              'Purpose',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText:
                    'Example: Deed of Donation for my child. Do not include ID numbers, title numbers, or tax details.',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSubmitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.royalBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : const Text(
                        'Submit Request',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({required String title, required String body}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exampleCard(String example) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.royalBlue.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.royalBlue.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Example',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppTheme.royalBlue,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            example,
            style: const TextStyle(fontSize: 14, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _privacyNote() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFE082)),
      ),
      child: const Text(
        'Do not send IDs, titles, tax papers, or other confidential files here. Bring originals to the office for notarization.',
        style: TextStyle(fontSize: 13, color: Colors.black87, height: 1.35),
      ),
    );
  }

  Widget _bringRow(String docName) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.royalBlue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.inventory_2_outlined,
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
                    docName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    NotaryServiceConfig.getDocumentHint(docName),
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pickerField({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: AppTheme.royalBlue),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
