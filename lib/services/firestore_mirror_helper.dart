import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/hybrid_write_result.dart';
import 'hybrid_datastore.dart';
export 'hybrid_datastore.dart';
export '../models/hybrid_write_result.dart';

/// Backward-compatible alias — all writes go through [HybridDatastore] (parallel).
class FirestoreMirror {
  FirestoreMirror._();

  static Future<HybridWriteResult> set({
    required String collection,
    required String id,
    required Map<String, dynamic> data,
    SetOptions? options,
  }) =>
      HybridDatastore.set(
        collection: collection,
        id: id,
        data: data,
        options: options,
      );

  static Future<HybridWriteResult> doc({
    required String collection,
    required String id,
    required Map<String, dynamic> data,
  }) =>
      HybridDatastore.set(collection: collection, id: id, data: data);

  static Future<HybridWriteResult> patch({
    required String collection,
    required String id,
    required Map<String, dynamic> patch,
  }) =>
      HybridDatastore.update(collection: collection, id: id, patch: patch);

  static Future<HybridWriteResult> add({
    required String collection,
    required Map<String, dynamic> data,
  }) =>
      HybridDatastore.add(collection: collection, data: data);

  /// Parallel write to both backends using an existing document id.
  static Future<HybridWriteResult> afterAdd(
    DocumentReference<Map<String, dynamic>> ref,
    Map<String, dynamic> data,
  ) =>
      HybridDatastore.set(
        collection: ref.parent.id,
        id: ref.id,
        data: data,
      );
}
