/// One client guide about how the app works. Not legal advice.
class ClientHelpArticle {
  const ClientHelpArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.where,
    required this.steps,
    required this.keywords,
    this.prompt,
  });

  final String id;
  final String title;
  final String summary;
  final String where;
  final List<String> steps;

  /// Words used to match a typed question.
  final List<String> keywords;

  /// Short question shown as a suggestion chip. Null hides the chip.
  final String? prompt;
}
