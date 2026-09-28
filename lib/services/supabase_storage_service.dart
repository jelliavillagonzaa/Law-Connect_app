import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_bootstrap.dart';
import '../supabase/supabase_config.dart';

/// Uploads profile images to the public `files` Storage bucket.
class SupabaseStorageService {
  static const String bucketName = 'files';
  static const String profileFolder = 'profile_photos';

  Future<SupabaseClient> _requireClient() async {
    if (supabaseClientOrNull != null) return supabaseClientOrNull!;

    await initializeSupabase();
    if (supabaseClientOrNull != null) return supabaseClientOrNull!;

    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (supabaseClientOrNull != null) return supabaseClientOrNull!;
    }

    throw Exception(
      'Supabase is not connected. Restart the app (full restart, not hot reload) and try again.',
    );
  }

  Future<String> uploadProfilePhoto({
    required String userId,
    required XFile imageFile,
  }) async {
    final client = await _requireClient();
    final bytes = await imageFile.readAsBytes();
    if (bytes.isEmpty) {
      throw Exception('Selected image is empty');
    }

    final path =
        '$profileFolder/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';

    try {
      // On Chrome, the SDK upload uses extra headers (x-upsert, x-client-info)
      // that often fail CORS preflight as "Failed to fetch".
      if (kIsWeb) {
        await _uploadViaRest(path, bytes);
      } else {
        await client.storage.from(bucketName).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: false,
          ),
        );
      }
    } on StorageException catch (e) {
      throw Exception(
        'Storage upload failed (${e.statusCode ?? 'unknown'}): ${e.message}',
      );
    } catch (e) {
      final text = e.toString();
      if (text.toLowerCase().contains('failed to fetch')) {
        throw Exception(
          'Chrome blocked the upload (CORS). In Supabase go to Storage → Configuration → CORS and allow origin * plus headers authorization, apikey, content-type. Then restart the app.',
        );
      }
      rethrow;
    }

    final publicUrl = client.storage.from(bucketName).getPublicUrl(path);
    if (kDebugMode) {
      // ignore: avoid_print
      print('Profile photo uploaded to Supabase: $publicUrl');
    }
    return publicUrl;
  }

  Future<void> _uploadViaRest(String path, Uint8List bytes) async {
    final base = SupabaseConfig.projectUrl.replaceAll(RegExp(r'/$'), '');
    final uri = Uri.parse('$base/storage/v1/object/$bucketName/$path');
    final res = await http.post(
      uri,
      headers: {
        'apikey': SupabaseConfig.publishableAnonKey,
        'Authorization': 'Bearer ${SupabaseConfig.publishableAnonKey}',
        'Content-Type': 'image/jpeg',
      },
      body: bytes,
    );

    if (res.statusCode >= 200 && res.statusCode < 300) return;

    throw Exception(
      'Storage upload failed (${res.statusCode}): ${res.body}',
    );
  }
}
