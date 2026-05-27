import 'dart:io' show File;
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'local_attachment_service.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final LocalAttachmentService _localAttachmentService = LocalAttachmentService();

  // Upload user profile photo (works on both web and mobile)
  Future<String> uploadProfilePhoto({
    required String userId,
    required XFile imageFile,
  }) async {
    try {
      // Create a unique filename
      final fileName =
          'profile_${userId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final ref = _storage.ref().child('profile_photos/$userId/$fileName');

      UploadTask uploadTask;

      if (kIsWeb) {
        // For web: read file as bytes and use putData
        final bytes = await imageFile.readAsBytes();
        final metadata = SettableMetadata(contentType: 'image/jpeg');
        uploadTask = ref.putData(bytes, metadata);
      } else {
        // For mobile: use putFile with File object
        final file = File(imageFile.path);
        if (!await file.exists()) {
          throw Exception('Image file does not exist');
        }
        final metadata = SettableMetadata(contentType: 'image/jpeg');
        uploadTask = ref.putFile(file, metadata);
      }

      // Wait for upload (no timeout - allows for large files and slow connections)
      final snapshot = await uploadTask;

      // Get download URL (no timeout)
      final downloadUrl = await snapshot.ref.getDownloadURL();

      if (kDebugMode) {
        debugPrint('✅ Profile photo uploaded: $downloadUrl');
      }

      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to upload profile photo: $e');
      }
      rethrow;
    }
  }

  // Delete old profile photo (optional cleanup)
  Future<void> deleteProfilePhoto(String photoUrl) async {
    try {
      final ref = _storage.refFromURL(photoUrl);
      await ref.delete();
      if (kDebugMode) {
        debugPrint('✅ Old profile photo deleted');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Failed to delete old photo (may not exist): $e');
      }
      // Don't throw error - old photo may not exist
    }
  }

  // Upload case document (using local storage)
  Future<String> uploadCaseDocument({
    required String caseId,
    required PlatformFile file,
    String? folder,
  }) async {
    try {
      // Get file bytes
      Uint8List fileBytes;
      if (kIsWeb) {
        if (file.bytes == null) {
          throw Exception('File bytes are null');
        }
        if (file.bytes!.isEmpty) {
          throw Exception('File is empty');
        }
        fileBytes = file.bytes!;
      } else {
        if (file.path == null) {
          throw Exception('File path is null');
        }
        final fileObj = File(file.path!);
        if (!await fileObj.exists()) {
          throw Exception('File does not exist');
        }
        fileBytes = await fileObj.readAsBytes();
        if (fileBytes.isEmpty) {
          throw Exception('File is empty');
        }
      }

      // Generate unique attachment ID
      final fileName = file.name.isNotEmpty ? file.name : 'document';
      final attachmentId = LocalAttachmentService.generateAttachmentId('${caseId}_$fileName');

      // Save to local storage
      final localStorageId = await _localAttachmentService.saveAttachment(
        attachmentId: attachmentId,
        fileBytes: fileBytes,
        fileName: fileName,
        fileExtension: file.extension,
      );

      if (kDebugMode) {
        debugPrint('✅ Case document saved to local storage: $localStorageId');
      }

      return localStorageId;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to save case document: $e');
      }
      throw Exception('Failed to save document: ${e.toString()}');
    }
  }

  // Upload attorney license document for verification
  Future<String> uploadAttorneyLicense({
    required String email,
    required PlatformFile file,
  }) async {
    try {
      // Create a unique filename
      final sanitizedEmail = email.replaceAll('@', '_at_').replaceAll('.', '_');
      final fileName = file.name.isNotEmpty
          ? file.name
          : 'license_${DateTime.now().millisecondsSinceEpoch}.${file.extension ?? 'pdf'}';
      final path = 'attorney_licenses/$sanitizedEmail/$fileName';
      final ref = _storage.ref().child(path);

      UploadTask uploadTask;

      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) {
          throw Exception('File bytes are null');
        }
        String contentType = 'application/octet-stream';
        if (file.extension != null) {
          if (file.extension == 'pdf') {
            contentType = 'application/pdf';
          } else if ([
            'jpg',
            'jpeg',
            'png',
            'gif',
          ].contains(file.extension!.toLowerCase())) {
            contentType = 'image/${file.extension!.toLowerCase()}';
          }
        }
        final metadata = SettableMetadata(contentType: contentType);
        uploadTask = ref.putData(bytes, metadata);
      } else {
        if (file.path == null) {
          throw Exception('File path is null');
        }
        final fileObj = File(file.path!);
        if (!await fileObj.exists()) {
          throw Exception('File does not exist');
        }
        String contentType = 'application/octet-stream';
        if (file.extension != null) {
          if (file.extension == 'pdf') {
            contentType = 'application/pdf';
          } else if ([
            'jpg',
            'jpeg',
            'png',
            'gif',
          ].contains(file.extension!.toLowerCase())) {
            contentType = 'image/${file.extension!.toLowerCase()}';
          }
        }
        final metadata = SettableMetadata(contentType: contentType);
        uploadTask = ref.putFile(fileObj, metadata);
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      if (kDebugMode) {
        debugPrint('✅ Attorney license uploaded: $downloadUrl');
      }

      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to upload attorney license: $e');
      }
      rethrow;
    }
  }
}
