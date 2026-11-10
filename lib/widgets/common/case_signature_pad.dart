import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/user_model.dart';
import '../../theme/app_theme.dart';

/// Ink drawn on the create-case form, then saved with the case.
class CaseSignatureController extends ChangeNotifier {
  final List<List<Offset>> _strokes = [];
  Size _size = Size.zero;
  bool _signed = false;
  String signerName = '';

  bool get hasSignature => _signed;

  void updateSize(Size size) {
    if (size.width < 2 || size.height < 2) return;
    _size = size;
  }

  void startStroke(Offset point) {
    _strokes.add([point]);
    _publish();
  }

  void extendStroke(Offset point) {
    if (_strokes.isEmpty) {
      startStroke(point);
      return;
    }
    _strokes.last.add(point);
    _publish();
  }

  void endStroke() {}

  void clear() {
    _strokes.clear();
    _publish();
  }

  void _publish() {
    final signed = _strokes.any((stroke) => stroke.isNotEmpty);
    final changed = signed != _signed;
    _signed = signed;
    if (changed || signed) notifyListeners();
  }

  Future<Uint8List?> toPngBytes() async {
    final width = _size.width;
    final height = _size.height;
    if (!_signed || width < 2 || height < 2) return null;

    const pixelRatio = 2.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(pixelRatio);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, height),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    final paint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in _strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(
          stroke.first,
          1.4,
          Paint()..color = const Color(0xFF1A1A1A),
        );
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
    final image = await recorder.endRecording().toImage(
          (width * pixelRatio).round(),
          (height * pixelRatio).round(),
        );
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) return null;
    return bytes.buffer.asUint8List();
  }

  Future<Map<String, dynamic>?> toCaseRecord({
    required String signerId,
    required String signerName,
    required String signerRole,
  }) async {
    final png = await toPngBytes();
    if (png == null || png.isEmpty) return null;
    return {
      'imageBase64': base64Encode(png),
      'signerId': signerId,
      'signerName': signerName,
      'signerRole': signerRole,
      'signedAt': DateTime.now().toIso8601String(),
    };
  }
}

class CaseSignatureField extends StatefulWidget {
  const CaseSignatureField({
    super.key,
    required this.controller,
    required this.roleLabel,
  });

  final CaseSignatureController controller;
  final String roleLabel;

  @override
  State<CaseSignatureField> createState() => _CaseSignatureFieldState();
}

class _CaseSignatureFieldState extends State<CaseSignatureField> {
  final GlobalKey _padKey = GlobalKey();
  String _signerName = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onInk);
    _loadSignerName();
  }

  @override
  void didUpdateWidget(CaseSignatureField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onInk);
      widget.controller.addListener(_onInk);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onInk);
    super.dispose();
  }

  void _onInk() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSignerName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    var name = (user.displayName ?? '').trim();
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data();
      if (data != null) {
        final resolved = UserModel.resolveDisplayName(data);
        if (resolved.isNotEmpty && resolved != 'User') name = resolved;
      }
    } catch (_) {}
    if (!mounted) return;
    widget.controller.signerName = name;
    setState(() => _signerName = name);
  }

  /// Window coordinates on the website do not match the box. Map them onto it.
  Offset? _padPoint(PointerEvent event, {required bool clamp}) {
    final box = _padKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final local = box.globalToLocal(event.position);
    final inside = local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= box.size.width &&
        local.dy <= box.size.height;
    if (!inside && !clamp) return null;
    return Offset(
      local.dx.clamp(0.0, box.size.width),
      local.dy.clamp(0.0, box.size.height),
    );
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.roleLabel.trim();
    final name = _signerName.trim();
    final caption = name.isEmpty || name.toLowerCase() == role.toLowerCase()
        ? role
        : '$name, $role';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'E-Signature *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed:
                  widget.controller.hasSignature ? widget.controller.clear : null,
              child: const Text('Clear'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, 160);
            widget.controller.updateSize(size);
            return RawGestureDetector(
              gestures: {
                EagerGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                  EagerGestureRecognizer.new,
                  (EagerGestureRecognizer instance) {},
                ),
              },
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) {
                  final point = _padPoint(event, clamp: false);
                  if (point != null) widget.controller.startStroke(point);
                },
                onPointerMove: (event) {
                  final point = _padPoint(event, clamp: true);
                  if (point != null) widget.controller.extendStroke(point);
                },
                onPointerUp: (_) => widget.controller.endStroke(),
                onPointerCancel: (_) => widget.controller.endStroke(),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CustomPaint(
                    key: _padKey,
                    foregroundPainter: _SignaturePainter(widget.controller),
                    child: Container(
                      height: 160,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(
                          color: widget.controller.hasSignature
                              ? AppTheme.royalBlue
                              : Colors.grey.shade400,
                        ),
                      ),
                      child: widget.controller.hasSignature
                          ? const SizedBox.shrink()
                          : Text(
                              'Sign here',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          caption,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Required. The person creating this case signs here.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      ],
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter(this.controller) : super(repaint: controller);

  final CaseSignatureController controller;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A1A1A)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in controller._strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(
          stroke.first,
          1.4,
          Paint()..color = const Color(0xFF1A1A1A),
        );
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

/// Saved signature on a case that already exists.
class CaseSignatureView extends StatelessWidget {
  const CaseSignatureView({super.key, required this.progress});

  final Map<String, dynamic>? progress;

  @override
  Widget build(BuildContext context) {
    final raw = progress?['signature'];
    if (raw is! Map) return const SizedBox.shrink();
    final data = Map<String, dynamic>.from(raw);
    final encoded = (data['imageBase64'] ?? '').toString().trim();
    if (encoded.isEmpty) return const SizedBox.shrink();
    Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } catch (_) {
      return const SizedBox.shrink();
    }
    if (bytes.isEmpty) return const SizedBox.shrink();

    final name = (data['signerName'] ?? '').toString().trim();
    final role = (data['signerRole'] ?? '').toString().trim();
    final who = name.isEmpty
        ? role
        : (role.isEmpty || name.toLowerCase() == role.toLowerCase())
            ? name
            : '$name, $role';
    final parsed = DateTime.tryParse((data['signedAt'] ?? '').toString());
    final when = parsed == null
        ? ''
        : DateFormat('MMM d, yyyy h:mm a').format(parsed.toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Text(
          'E-Signature',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 280,
          height: 120,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Image.memory(bytes, fit: BoxFit.contain),
        ),
        if (who.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            who,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
        if (when.isNotEmpty)
          Text(
            'Signed $when',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
      ],
    );
  }
}
