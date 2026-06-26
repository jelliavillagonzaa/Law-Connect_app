/// Result of writing to Firestore and Supabase in parallel (true hybrid).
class HybridWriteResult {
  const HybridWriteResult({
    required this.firestoreOk,
    required this.supabaseOk,
    this.supabaseRequired = true,
    this.id,
    this.firestoreError,
    this.supabaseError,
  });

  final bool firestoreOk;
  final bool supabaseOk;

  /// When false (Supabase not configured), only Firestore must succeed.
  final bool supabaseRequired;

  final String? id;
  final String? firestoreError;
  final String? supabaseError;

  /// At least one configured backend accepted the write.
  bool get isSuccess {
    if (supabaseRequired) return firestoreOk || supabaseOk;
    return firestoreOk;
  }

  /// Both backends accepted the write.
  bool get isFullSuccess =>
      firestoreOk && (!supabaseRequired || supabaseOk);

  String get failureMessage {
    if (isSuccess) return '';
    final parts = <String>[];
    if (!firestoreOk && firestoreError != null) {
      parts.add('Firestore: $firestoreError');
    }
    if (!supabaseOk && supabaseError != null) {
      parts.add('Supabase: $supabaseError');
    }
    if (parts.isEmpty) return 'Write failed on both backends.';
    return parts.join(' | ');
  }
}
