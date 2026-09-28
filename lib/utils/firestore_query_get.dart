import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// Web Chrome has no reliable Firestore IndexedDB cache. Cache-first + 1s
/// server timeout returns empty and the automated hearing calendar disappears.
abstract final class FirestoreQueryGet {
  static Duration get hearingsTimeout =>
      Duration(seconds: kIsWeb ? 15 : 8);

  static Future<QuerySnapshot<Map<String, dynamic>>> hearings(
    Query<Map<String, dynamic>> query,
  ) async {
    if (kIsWeb) {
      return query.get().timeout(hearingsTimeout);
    }
    try {
      final cached = await query.get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty) return cached;
    } catch (_) {}
    return query.get().timeout(hearingsTimeout);
  }
}
