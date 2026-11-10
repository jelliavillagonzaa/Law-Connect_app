import 'package:flutter/material.dart';

import '../../help/client_help_article.dart';
import '../../help/client_help_catalog.dart';
import '../../help/client_help_search.dart';
import '../../theme/app_theme.dart';

/// How-to help for one role. Answers come only from [articles].
class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({
    super.key,
    this.articles = clientHelpArticles,
    this.intro =
        'Answers come from the client guide: appointments, cases, messages, notary, and billing.',
    this.hint = 'Example: How do I book an appointment?',
  });

  final List<ClientHelpArticle> articles;
  final String intro;
  final String hint;

  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  late final ClientHelpSearch _search;
  final _controller = TextEditingController();
  final _focus = FocusNode();

  ClientHelpArticle? _answer;
  List<ClientHelpArticle> _related = const [];
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    _search = ClientHelpSearch(articles: widget.articles);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _ask([String? preset]) {
    final text = (preset ?? _controller.text).trim();
    if (text.isEmpty) return;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    final matches = _search.ask(text);
    setState(() {
      _asked = true;
      _answer = matches.isEmpty ? null : matches.first.article;
      _related = matches.length <= 1
          ? const []
          : matches.skip(1).map((match) => match.article).toList();
    });
    _focus.unfocus();
  }

  void _browseAll() {
    setState(() {
      _asked = false;
      _answer = null;
      _related = const [];
      _controller.clear();
    });
  }

  void _openArticle(ClientHelpArticle article) {
    setState(() {
      _asked = true;
      _answer = article;
      _related = const [];
      _controller.text = article.prompt ?? article.title;
    });
  }

  @override
  Widget build(BuildContext context) {
    final prompts = widget.articles
        .where((article) => article.prompt != null)
        .toList();

    return Scaffold(
      backgroundColor: AppTheme.lightGray,
      appBar: AppBar(
        backgroundColor: const Color(0xFF07152B),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Help Center',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              Text(
                'Ask how the app works',
                style: AppTheme.heading3.copyWith(
                  color: AppTheme.royalBlue,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.intro,
                style: AppTheme.bodyMedium.copyWith(color: AppTheme.mutedText),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                focusNode: _focus,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => _ask(),
                style: const TextStyle(
                  color: AppTheme.darkText,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  hintStyle: const TextStyle(
                    color: AppTheme.mutedText,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  prefixIcon: const Icon(Icons.search, color: AppTheme.royalBlue),
                  suffixIcon: IconButton(
                    tooltip: 'Ask',
                    onPressed: _ask,
                    icon: const Icon(Icons.send_rounded),
                    color: AppTheme.royalBlue,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.borderGray),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.borderGray),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.royalBlue, width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final article in prompts)
                    ActionChip(
                      avatar: const Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: AppTheme.royalBlue,
                      ),
                      label: Text(
                        article.prompt!,
                        style: const TextStyle(
                          color: AppTheme.deepNavy,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      labelStyle: const TextStyle(
                        color: AppTheme.deepNavy,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      backgroundColor: const Color(0xFFEFF5FF),
                      side: const BorderSide(color: Color(0xFFBDD3F5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                      pressElevation: 1,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      onPressed: () => _ask(article.prompt),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              if (_answer != null) ...[
                _answerCard(_answer!),
                if (_related.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Other matches',
                    style: AppTheme.heading4.copyWith(color: AppTheme.royalBlue),
                  ),
                  const SizedBox(height: 8),
                  for (final article in _related) _guideTile(article),
                ],
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _browseAll,
                    child: const Text('Browse all guides'),
                  ),
                ),
              ] else ...[
                if (_asked) _emptyState(),
                Text(
                  'All guides',
                  style: AppTheme.heading4.copyWith(color: AppTheme.royalBlue),
                ),
                const SizedBox(height: 8),
                for (final article in widget.articles) _guideTile(article),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'That is not in the Help Center yet',
            style: AppTheme.bodyLarge.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Try a question about the screens in this account. This guide does not answer legal questions.',
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.mutedText),
          ),
        ],
      ),
    );
  }

  Widget _answerCard(ClientHelpArticle article) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            article.title,
            style: AppTheme.heading4.copyWith(
              color: AppTheme.royalBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(article.summary, style: AppTheme.bodyMedium),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.sidebarActive,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              article.where,
              style: AppTheme.bodySmall.copyWith(
                color: AppTheme.sidebarActiveText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < article.steps.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}.',
                  style: AppTheme.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.royalBlue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(article.steps[i], style: AppTheme.bodyMedium),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          Text(
            'This explains how the app works. It is not legal advice.',
            style: AppTheme.bodySmall.copyWith(color: AppTheme.mutedText),
          ),
        ],
      ),
    );
  }

  Widget _guideTile(ClientHelpArticle article) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _openArticle(article),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.borderGray),
            ),
            child: Row(
              children: [
                const Icon(Icons.menu_book_outlined, color: AppTheme.royalBlue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        article.title,
                        style: AppTheme.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        article.where,
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: AppTheme.mutedText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
