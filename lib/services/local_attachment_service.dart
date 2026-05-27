import 'dart:convert';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart' show kDebugMode;

class LocalAttachmentService {
  // Save attachment to local storage
  // Returns a unique identifier that can be stored in Firestore
  Future<String> saveAttachment({
    required String attachmentId,
    required Uint8List fileBytes,
    required String fileName,
    String? fileExtension,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Convert to base64
      final base64File = base64Encode(fileBytes);
      
      // Store file data
      await prefs.setString('attachment_data_$attachmentId', base64File);
      
      // Store metadata
      final metadata = {
        'fileName': fileName,
        'fileExtension': fileExtension ?? '',
        'size': fileBytes.length,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString('attachment_meta_$attachmentId', jsonEncode(metadata));
      
      if (kDebugMode) {
        print('✅ Attachment saved locally: $attachmentId (${(fileBytes.length / 1024).toStringAsFixed(2)} KB)');
      }
      
      // Return identifier that indicates local storage
      return 'local_storage_$attachmentId';
    } catch (e) {
      if (e.toString().contains('QuotaExceeded') || e.toString().contains('quota')) {
        throw Exception('Storage quota exceeded. Please use a smaller file or clear some attachments.');
      }
      throw Exception('Failed to save attachment locally: ${e.toString()}');
    }
  }

  // Get attachment from local storage
  Future<Uint8List?> getAttachment(String attachmentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final base64File = prefs.getString('attachment_data_$attachmentId');
      
      if (base64File == null || base64File.isEmpty) {
        return null;
      }
      
      return base64Decode(base64File);
    } catch (e) {
      if (kDebugMode) {
        print('Error getting attachment: $e');
      }
      return null;
    }
  }

  // Get attachment metadata
  Future<Map<String, dynamic>?> getAttachmentMetadata(String attachmentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final metadataStr = prefs.getString('attachment_meta_$attachmentId');
      
      if (metadataStr == null || metadataStr.isEmpty) {
        return null;
      }
      
      return jsonDecode(metadataStr) as Map<String, dynamic>;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting attachment metadata: $e');
      }
      return null;
    }
  }

  // Delete attachment from local storage
  Future<void> deleteAttachment(String attachmentId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('attachment_data_$attachmentId');
      await prefs.remove('attachment_meta_$attachmentId');
      
      if (kDebugMode) {
        print('✅ Attachment deleted locally: $attachmentId');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error deleting attachment: $e');
      }
    }
  }

  // Extract attachment ID from local storage identifier
  // Input: "local_storage_1234567890_abc.pdf"
  // Output: "1234567890_abc.pdf"
  static String? extractAttachmentId(String localStorageId) {
    if (!localStorageId.startsWith('local_storage_')) {
      return null;
    }
    return localStorageId.substring('local_storage_'.length);
  }

  // Check if an identifier is a local storage identifier
  static bool isLocalStorage(String identifier) {
    return identifier.startsWith('local_storage_');
  }

  // Generate unique attachment ID
  static String generateAttachmentId(String fileName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitizedFileName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    return '${timestamp}_$sanitizedFileName';
  }

  // Get all attachment IDs stored locally (for cleanup purposes)
  Future<List<String>> getAllLocalAttachmentIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final attachmentIds = <String>[];
      
      for (final key in keys) {
        if (key.startsWith('attachment_data_')) {
          final id = key.substring('attachment_data_'.length);
          attachmentIds.add(id);
        }
      }
      
      return attachmentIds;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting all attachment IDs: $e');
      }
      return [];
    }
  }

  // Clean up old attachments (optional - can be called periodically)
  Future<void> cleanupOldAttachments({int maxAgeDays = 90}) async {
    try {
      final attachmentIds = await getAllLocalAttachmentIds();
      final cutoffTime = DateTime.now().subtract(Duration(days: maxAgeDays)).millisecondsSinceEpoch;
      
      int deletedCount = 0;
      for (final id in attachmentIds) {
        final metadata = await getAttachmentMetadata(id);
        if (metadata != null) {
          final savedAt = metadata['savedAt'] as int?;
          if (savedAt != null && savedAt < cutoffTime) {
            await deleteAttachment(id);
            deletedCount++;
          }
        }
      }
      
      if (kDebugMode && deletedCount > 0) {
        print('✅ Cleaned up $deletedCount old attachments');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error cleaning up old attachments: $e');
      }
    }
  }
}

