import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/case_description_format.dart';

const _caseFonts = <String, String>{
  'Times New Roman': 'Times New Roman',
  'Georgia': 'Georgia',
  'Arial': 'Arial',
  'Calibri': 'Calibri',
  'Courier New': 'Courier New',
};

const _caseSizes = <String, String>{
  '10': '10',
  '11': '11',
  '12': '12',
  '14': '14',
  '16': '16',
  '18': '18',
  '24': '24',
};

QuillSimpleToolbarConfig caseDescriptionToolbarConfig({required bool oneRow}) {
  return QuillSimpleToolbarConfig(
    multiRowsDisplay: !oneRow,
    toolbarSize: oneRow ? 40 : null,
    showDividers: true,
    showFontFamily: true,
    showFontSize: true,
    showBoldButton: true,
    showItalicButton: true,
    showUnderLineButton: true,
    showStrikeThrough: true,
    showColorButton: true,
    showBackgroundColorButton: true,
    showClearFormat: true,
    showAlignmentButtons: true,
    showLeftAlignment: true,
    showCenterAlignment: true,
    showRightAlignment: true,
    showJustifyAlignment: true,
    showLineHeightButton: true,
    showHeaderStyle: true,
    showListNumbers: true,
    showListBullets: true,
    showIndent: true,
    showQuote: true,
    showLink: true,
    showUndo: true,
    showRedo: true,
    showSearchButton: true,
    showSubscript: true,
    showSuperscript: true,
    showInlineCode: false,
    showCodeBlock: false,
    showListCheck: false,
    buttonOptions: const QuillSimpleToolbarButtonOptions(
      fontFamily: QuillToolbarFontFamilyButtonOptions(
        items: _caseFonts,
        defaultDisplayText: 'Times New Roman',
      ),
      fontSize: QuillToolbarFontSizeButtonOptions(
        items: _caseSizes,
        defaultDisplayText: '12',
      ),
    ),
  );
}

/// One-row font tools pinned on the phone so they stay in reach while typing.
class CaseDescriptionFormatBar extends StatelessWidget {
  const CaseDescriptionFormatBar({super.key, required this.controller});

  final QuillController controller;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF4F6F9),
      child: SizedBox(
        height: 40,
        child: QuillSimpleToolbar(
          controller: controller,
          config: caseDescriptionToolbarConfig(oneRow: true),
        ),
      ),
    );
  }
}

/// Word-like case narrative editor: fonts, size, bold/italic/underline,
/// justify, line spacing, lists, indent, undo/redo, and search.
class CaseDescriptionEditor extends StatefulWidget {
  const CaseDescriptionEditor({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.minHeight = 280,
    this.hint = 'Describe the case and the client\'s legal concern…',
    this.validator,
    this.showInlineToolbar = true,
    this.focusNode,
  });

  final QuillController controller;
  final bool readOnly;
  final double minHeight;
  final String hint;
  final String? Function(String plainText)? validator;

  /// Optional external FocusNode so the parent can react to focus changes.
  final FocusNode? focusNode;

  /// Website keeps the toolbar on the editor. The phone pins it instead.
  final bool showInlineToolbar;

  @override
  State<CaseDescriptionEditor> createState() => _CaseDescriptionEditorState();
}

class _CaseDescriptionEditorState extends State<CaseDescriptionEditor> {
  // Use external focusNode if provided, otherwise manage our own.
  late final FocusNode _focusNode =
      widget.focusNode ?? FocusNode();
  late final ScrollController _scrollController = ScrollController();

  bool get _ownsOwnFocusNode => widget.focusNode == null;

  @override
  void dispose() {
    // Only dispose focusNode if we created it ourselves
    if (_ownsOwnFocusNode) _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 720;
    final editorHeight = widget.minHeight < 280
        ? widget.minHeight
        : (compact ? 220.0 : widget.minHeight);

    return FormField<String>(
      validator: (_) {
        final plain = caseDescriptionPlainText(widget.controller);
        if (widget.validator != null) return widget.validator!(plain);
        return null;
      },
      builder: (field) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: field.hasError
                      ? Theme.of(context).colorScheme.error
                      : const Color(0xFF1A3A6C),
                ),
              ),
              child: Column(
                children: [
                  if (!widget.readOnly && widget.showInlineToolbar) ...[
                    Material(
                      color: const Color(0xFFF4F6F9),
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(7),
                      ),
                      child: QuillSimpleToolbar(
                        controller: widget.controller,
                        config: caseDescriptionToolbarConfig(oneRow: false),
                      ),
                    ),
                    const Divider(height: 1),
                  ],
                  Material(
                    color: Colors.white,
                    child: SizedBox(
                      height: editorHeight,
                      child: QuillEditor.basic(
                      controller: widget.controller,
                      focusNode: _focusNode,
                      scrollController: _scrollController,
                      config: QuillEditorConfig(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        placeholder: widget.readOnly ? null : widget.hint,
                        scrollable: true,
                        autoFocus: false,
                        expands: false,
                        customStyles: DefaultStyles(
                          paragraph: DefaultTextBlockStyle(
                            GoogleFonts.tinos(
                              fontSize: 16,
                              height: 1.5,
                              color: const Color(0xFF1C1C1C),
                            ),
                            HorizontalSpacing.zero,
                            const VerticalSpacing(8, 0),
                            VerticalSpacing.zero,
                            null,
                          ),
                        ),
                      ),
                    ),
                    ),
                  ),
                ],
              ),
            ),
            if (!widget.readOnly)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ListenableBuilder(
                  listenable: widget.controller,
                  builder: (context, _) {
                    return Text(
                      '${caseDescriptionWordCount(widget.controller)} words',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    );
                  },
                ),
              ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  field.errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

DefaultStyles _caseDescriptionReadStyles() {
  return DefaultStyles(
    paragraph: DefaultTextBlockStyle(
      GoogleFonts.tinos(
        fontSize: 17,
        height: 1.7,
        color: const Color(0xFF1C1C1C),
      ),
      HorizontalSpacing.zero,
      const VerticalSpacing(10, 0),
      VerticalSpacing.zero,
      null,
    ),
  );
}

class CaseDescriptionView extends StatefulWidget {
  const CaseDescriptionView({
    super.key,
    required this.plainText,
    this.deltaJson,
  });

  final String plainText;
  final String? deltaJson;

  @override
  State<CaseDescriptionView> createState() => _CaseDescriptionViewState();
}

class _CaseDescriptionViewState extends State<CaseDescriptionView> {
  late QuillController _controller = _createController();
  late final FocusNode _focusNode = FocusNode();
  late final ScrollController _scrollController = ScrollController();

  QuillController _createController() {
    return createCaseDescriptionController(
      deltaJson: widget.deltaJson,
      plainFallback: widget.plainText,
    )..readOnly = true;
  }

  @override
  void didUpdateWidget(CaseDescriptionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plainText != widget.plainText ||
        oldWidget.deltaJson != widget.deltaJson) {
      _controller.dispose();
      _controller = _createController();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _openFullDescription() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => CaseDescriptionFullPage(
          plainText: widget.plainText,
          deltaJson: widget.deltaJson,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plain = caseDescriptionPlainText(_controller);
    if (plain.isEmpty) {
      return Text(
        widget.plainText.trim().isEmpty ? 'No description' : widget.plainText,
        style: GoogleFonts.tinos(fontSize: 16, height: 1.7),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD8DEE6)),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox(
              height: 220,
              child: QuillEditor.basic(
                controller: _controller,
                focusNode: _focusNode,
                scrollController: _scrollController,
                config: QuillEditorConfig(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  scrollable: true,
                  autoFocus: false,
                  expands: false,
                  customStyles: _caseDescriptionReadStyles(),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _openFullDescription,
            icon: const Icon(Icons.open_in_full, size: 18),
            label: const Text('View full description'),
          ),
        ),
      ],
    );
  }
}

class CaseDescriptionFullPage extends StatefulWidget {
  const CaseDescriptionFullPage({
    super.key,
    required this.plainText,
    this.deltaJson,
  });

  final String plainText;
  final String? deltaJson;

  @override
  State<CaseDescriptionFullPage> createState() =>
      _CaseDescriptionFullPageState();
}

class _CaseDescriptionFullPageState extends State<CaseDescriptionFullPage> {
  late final QuillController _controller = createCaseDescriptionController(
    deltaJson: widget.deltaJson,
    plainFallback: widget.plainText,
  )..readOnly = true;
  late final FocusNode _focusNode = FocusNode();
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final words = caseDescriptionWordCount(_controller);

    return Scaffold(
      backgroundColor: const Color(0xFFEEF1F5),
      appBar: AppBar(
        title: const Text('Case Description'),
        actions: [
          if (words > 0)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '$words words',
                  style: const TextStyle(fontSize: 13, color: Colors.white70),
                ),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final paperWidth = constraints.maxWidth < 800
              ? constraints.maxWidth
              : 800.0;
          final paperHeight = constraints.maxHeight > 40
              ? constraints.maxHeight - 40
              : constraints.maxHeight;
          return Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              child: SizedBox(
                width: paperWidth,
                height: paperHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x1A000000),
                        blurRadius: 12,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: QuillEditor.basic(
                      controller: _controller,
                      focusNode: _focusNode,
                      scrollController: _scrollController,
                      config: QuillEditorConfig(
                        padding: const EdgeInsets.fromLTRB(28, 24, 28, 32),
                        scrollable: true,
                        autoFocus: false,
                        expands: true,
                        customStyles: _caseDescriptionReadStyles(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
