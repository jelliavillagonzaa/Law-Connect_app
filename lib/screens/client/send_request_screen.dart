import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/case_request_service.dart';
import '../../services/case_service.dart';
import '../../theme/app_theme.dart';

class SendRequestScreen extends StatefulWidget {
  final String? attorneyId; // Optional - if client already has an attorney

  const SendRequestScreen({super.key, this.attorneyId});

  @override
  State<SendRequestScreen> createState() => _SendRequestScreenState();
}

class _SendRequestScreenState extends State<SendRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  final CaseRequestService _requestService = CaseRequestService();
  final CaseService _caseService = CaseService();
  bool _isLoading = false;
  bool _messageHasFocus = false;
  String? _selectedSubject;

  final List<String> _subjectOptions = [
    'Need legal help',
    'I have a concern',
    'Question about my case',
    'Request consultation',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _messageFocusNode.addListener(() {
      if (mounted) setState(() => _messageHasFocus = _messageFocusNode.hasFocus);
    });
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    if (!_formKey.currentState!.validate()) return;

    final subject = _selectedSubject ?? _subjectController.text.trim();
    if (subject.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select or enter a subject')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please log in to send a request')),
        );
        setState(() => _isLoading = false);
        return;
      }

      // Prefer assigned attorney from any active case (not only accepted)
      String? attorneyId = widget.attorneyId;
      if (attorneyId == null) {
        attorneyId = await _caseService.findAttorneyIdForClient(user.uid);
      }

      final result = await _requestService.createCaseRequest(
        clientId: user.uid,
        attorneyId: attorneyId,
        subject: subject,
        message: _messageController.text.trim(),
      );

      if (!mounted) return;

      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Request sent successfully! Your attorney will review it.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to send request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ── Formatting helpers ──────────────────────────────────────────────────

  void _wrapSelection(String before, String after) {
    final ctrl = _messageController;
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final start = sel.start;
    final end = sel.end;
    final selected = text.substring(start, end);
    final wrapped = '$before$selected$after';
    final newText = text.replaceRange(start, end, wrapped);
    ctrl.value = ctrl.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selected.isEmpty
            ? start + before.length
            : start + wrapped.length,
      ),
    );
  }

  void _insertBullet() {
    final ctrl = _messageController;
    final text = ctrl.text;
    final sel = ctrl.selection;
    if (!sel.isValid) return;
    final offset = sel.baseOffset;
    final lineStart = text.lastIndexOf('\n', offset > 0 ? offset - 1 : 0);
    final insertAt = lineStart < 0 ? 0 : lineStart + 1;
    if (text.length > insertAt && text.substring(insertAt).startsWith('• ')) {
      return;
    }
    final newText = text.replaceRange(insertAt, insertAt, '• ');
    ctrl.value = ctrl.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: offset + 2),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    const navy = AppTheme.royalBlue;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FC),
      appBar: AppBar(
        title: const Text('Send Request / Inquiry'),
        backgroundColor: navy,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      // ── Always-visible submit bar + formatting bar above keyboard ────────
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Formatting quick-bar — slides in when message field is focused
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: _messageHasFocus
                ? _FormattingBar(
                    onBold: () => _wrapSelection('**', '**'),
                    onItalic: () => _wrapSelection('_', '_'),
                    onUnderline: () => _wrapSelection('<u>', '</u>'),
                    onBullet: _insertBullet,
                  )
                : const SizedBox.shrink(),
          ),
          // Submit button — sticky, always visible, never buried
          _SubmitBar(isLoading: _isLoading, onSubmit: _submitRequest),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            children: [
              // ── Header card ────────────────────────────────────────────
              _SectionCard(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: navy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.send_rounded,
                          color: navy, size: 22),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Send a Request',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1A2540),
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Your attorney will review and respond.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Subject ────────────────────────────────────────────────
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _FieldLabel(label: 'Subject', required: true),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _subjectOptions.map((option) {
                        final isSelected = _selectedSubject == option;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _selectedSubject = isSelected ? null : option;
                            _subjectController.text =
                                isSelected ? '' : option;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? navy : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? navy
                                    : Colors.grey.shade300,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: navy.withValues(alpha: 0.22),
                                        blurRadius: 6,
                                        offset: const Offset(0, 2),
                                      )
                                    ]
                                  : [],
                            ),
                            child: Text(
                              option,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.grey[700],
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (_selectedSubject == 'Other') ...[
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _subjectController,
                        decoration: _fieldDecoration(
                            'e.g., Need help with contract review'),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty)
                                ? 'Please enter a subject'
                                : null,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Message ────────────────────────────────────────────────
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const _FieldLabel(
                            label: 'Message', required: true),
                        const Spacer(),
                        if (!_messageHasFocus)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: navy.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Tap to format text',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: navy,
                                  fontWeight: FontWeight.w500),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _messageController,
                      focusNode: _messageFocusNode,
                      decoration: InputDecoration(
                        hintText:
                            'Describe your legal concern in detail...',
                        hintStyle: TextStyle(
                            color: Colors.grey[400], fontSize: 13),
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      maxLines: null,
                      minLines: 6,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: Color(0xFF1C1C1C),
                      ),
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return 'Please enter a message';
                        }
                        if (v.trim().length < 20) {
                          return 'Message must be at least 20 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 6),
                    Divider(color: Colors.grey.shade200, height: 1),
                    const SizedBox(height: 6),
                    // Character counter
                    ValueListenableBuilder<TextEditingValue>(
                      valueListenable: _messageController,
                      builder: (_, val, __) {
                        final len = val.text.trim().length;
                        return Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            '$len characters${len < 20 ? ' (min 20)' : ''}',
                            style: TextStyle(
                              fontSize: 11,
                              color: len < 20
                                  ? Colors.red[400]
                                  : Colors.grey[400],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF6F8FC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppTheme.royalBlue, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

// ── Formatting bar ─────────────────────────────────────────────────────────

class _FormattingBar extends StatelessWidget {
  const _FormattingBar({
    required this.onBold,
    required this.onItalic,
    required this.onUnderline,
    required this.onBullet,
  });

  final VoidCallback onBold;
  final VoidCallback onItalic;
  final VoidCallback onUnderline;
  final VoidCallback onBullet;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      color: const Color(0xFFF0F2F8),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          const Text('Format:',
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500)),
          const SizedBox(width: 4),
          _FmtBtn(
            label: 'B',
            tooltip: 'Bold  (**text**)',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            onTap: onBold,
          ),
          _FmtBtn(
            label: 'I',
            tooltip: 'Italic  (_text_)',
            style: const TextStyle(
                fontStyle: FontStyle.italic,
                fontWeight: FontWeight.w600,
                fontSize: 15),
            onTap: onItalic,
          ),
          _FmtBtn(
            label: 'U',
            tooltip: 'Underline',
            style: const TextStyle(
                decoration: TextDecoration.underline,
                fontWeight: FontWeight.w600,
                fontSize: 15),
            onTap: onUnderline,
          ),
          _FmtBtn(
            label: '•',
            tooltip: 'Bullet point',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            onTap: onBullet,
          ),
          const Spacer(),
          Text(
            'Select text then tap a button',
            style: TextStyle(fontSize: 10, color: Colors.grey[400]),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _FmtBtn extends StatelessWidget {
  const _FmtBtn({
    required this.label,
    required this.tooltip,
    required this.style,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final TextStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: 38,
          height: 38,
          child: Center(child: Text(label, style: style)),
        ),
      ),
    );
  }
}

// ── Sticky submit bar ──────────────────────────────────────────────────────

class _SubmitBar extends StatelessWidget {
  const _SubmitBar({required this.isLoading, required this.onSubmit});

  final bool isLoading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          onPressed: isLoading ? null : onSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.royalBlue,
            foregroundColor: Colors.white,
            disabledBackgroundColor:
                AppTheme.royalBlue.withValues(alpha: 0.5),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Send Request',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Reusable card & label ──────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.required = false});
  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1A2540),
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
                color: Colors.red, fontWeight: FontWeight.bold),
          ),
      ],
    );
  }
}

