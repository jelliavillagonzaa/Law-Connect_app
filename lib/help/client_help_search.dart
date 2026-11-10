import 'client_help_article.dart';
import 'client_help_catalog.dart';

class ClientHelpMatch {
  const ClientHelpMatch({required this.article, required this.score});

  final ClientHelpArticle article;
  final int score;
}

/// Matches a typed question to how-to guides. No network call.
class ClientHelpSearch {
  const ClientHelpSearch({this.articles = clientHelpArticles});

  final List<ClientHelpArticle> articles;

  static const _stopWords = {
    'a',
    'an',
    'the',
    'to',
    'of',
    'for',
    'and',
    'or',
    'in',
    'on',
    'at',
    'my',
    'me',
    'i',
    'im',
    'do',
    'does',
    'did',
    'how',
    'what',
    'where',
    'when',
    'why',
    'can',
    'could',
    'please',
    'is',
    'are',
    'was',
    'be',
    'with',
    'from',
    'this',
    'that',
    'it',
    'unsa',
    'unsaon',
    'asa',
    'ngano',
    'kanus-a',
    'pag',
    'ug',
    'og',
    'ang',
    'sa',
    'ako',
    'akoang',
    'nga',
    'dayon',
    'ba',
    'ko',
    'na',
    'ra',
    'siya',
    'ka',
    'mga',
  };

  /// Extra words pulled in when the question uses a related term.
  static const _synonyms = <String, List<String>>{
    'book': ['appointment', 'schedule'],
    'booking': ['appointment'],
    'schedule': ['appointment'],
    'consultation': ['appointment'],
    'consult': ['appointment'],
    'appointment': ['book', 'schedule'],
    'bayad': ['billing', 'payment', 'balance'],
    'pay': ['billing', 'payment'],
    'payment': ['billing', 'invoice', 'balance'],
    'invoice': ['billing'],
    'fee': ['billing'],
    'balance': ['billing'],
    'chat': ['message'],
    'text': ['message'],
    'message': ['chat'],
    'notarize': ['notary'],
    'notarization': ['notary'],
    'deed': ['notary'],
    'folder': ['case'],
    'cases': ['case'],
    'signup': ['register', 'account', 'otp'],
    'register': ['account', 'otp'],
    'otp': ['register', 'verify'],
    'verify': ['otp', 'register'],
    'forgot': ['password', 'reset'],
    'reset': ['password', 'forgot'],
    'password': ['forgot', 'reset'],
    'bell': ['notification'],
    'alert': ['notification'],
    'logout': ['signout'],
    'signout': ['logout'],
  };

  List<ClientHelpMatch> ask(String query, {int limit = 4}) {
    final tokens = _expand(_tokenize(query));
    if (tokens.isEmpty) return const [];

    final matches = <ClientHelpMatch>[];
    for (final article in articles) {
      final score = _score(article, tokens);
      if (score >= 4) {
        matches.add(ClientHelpMatch(article: article, score: score));
      }
    }
    matches.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.article.title.compareTo(b.article.title);
    });
    if (matches.length <= limit) return matches;
    return matches.sublist(0, limit);
  }

  int _score(ClientHelpArticle article, Set<String> tokens) {
    final keywords = article.keywords.map(_normalize).toSet();
    final titleWords = _tokenize(article.title);
    final bodyWords = _tokenize(
      '${article.summary} ${article.where} ${article.steps.join(' ')}',
    );

    var score = 0;
    for (final token in tokens) {
      if (keywords.contains(token)) {
        score += 5;
      } else if (titleWords.contains(token)) {
        score += 3;
      } else if (bodyWords.contains(token)) {
        score += 1;
      }
    }
    return score;
  }

  Set<String> _expand(Set<String> tokens) {
    final expanded = {...tokens};
    for (final token in tokens) {
      final extra = _synonyms[token];
      if (extra != null) expanded.addAll(extra);
    }
    return expanded;
  }

  Set<String> _tokenize(String raw) {
    final words = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s-]'), ' ')
        .split(RegExp(r'\s+'))
        .map(_normalize)
        .where((word) => word.length > 1 && !_stopWords.contains(word));
    return words.toSet();
  }

  String _normalize(String word) {
    final trimmed = word.trim();
    if (trimmed.endsWith('ies') && trimmed.length > 4) {
      return '${trimmed.substring(0, trimmed.length - 3)}y';
    }
    if (trimmed.endsWith('s') &&
        !trimmed.endsWith('ss') &&
        trimmed.length > 3) {
      return trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }
}
