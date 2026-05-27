import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:image_picker/image_picker.dart';
import '../models/notary_request_model.dart';

class NotaryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  // Upload document to Firebase Storage
  Future<String> uploadDocument({
    required String requestId,
    required XFile file,
  }) async {
    try {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
      final ref = _storage.ref().child('notary_documents/$requestId/$fileName');

      UploadTask uploadTask;

      if (kIsWeb) {
        final bytes = await file.readAsBytes();
        String contentType = 'application/pdf';
        if (file.name.toLowerCase().endsWith('.jpg') ||
            file.name.toLowerCase().endsWith('.jpeg') ||
            file.name.toLowerCase().endsWith('.png')) {
          contentType = 'image/${file.name.split('.').last}';
        }
        final metadata = SettableMetadata(contentType: contentType);
        uploadTask = ref.putData(bytes, metadata);
      } else {
        final fileObj = File(file.path);
        if (!await fileObj.exists()) {
          throw Exception('File does not exist');
        }
        String contentType = 'application/pdf';
        if (file.path.toLowerCase().endsWith('.jpg') ||
            file.path.toLowerCase().endsWith('.jpeg') ||
            file.path.toLowerCase().endsWith('.png')) {
          contentType = 'image/${file.path.split('.').last}';
        }
        final metadata = SettableMetadata(contentType: contentType);
        uploadTask = ref.putFile(fileObj, metadata);
      }

      final snapshot = await uploadTask;
      final downloadUrl = await snapshot.ref.getDownloadURL();

      if (kDebugMode) {
        debugPrint('✅ Document uploaded: $downloadUrl');
      }

      return downloadUrl;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to upload document: $e');
      }
      throw Exception('Failed to upload document: ${e.toString()}');
    }
  }

  // Pick document (PDF or image)
  // Note: For PDF support, consider adding file_picker package
  // For now, this supports images which can be used for scanned documents
  Future<XFile?> pickDocument({ImageSource? source}) async {
    try {
      // Try to pick image (works for scanned documents/photos of documents)
      final XFile? file = await _picker.pickImage(
        source: source ?? ImageSource.gallery,
        imageQuality: 90,
      );
      return file;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to pick document: $e');
      }
      return null;
    }
  }

  // Create notary request
  Future<Map<String, dynamic>> createNotaryRequest({
    required String serviceType,
    required List<String> documentUrls, // Kept for backward compatibility but not used
    String? notes,
    List<Map<String, String>>? documentsWithNames, // Optional, not required
  }) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      final requestData = <String, dynamic>{
        'clientId': user.uid,
        'serviceType': serviceType,
        'status': 'pending',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      };

      // Only add documents if provided (for backward compatibility)
      if (documentsWithNames != null && documentsWithNames.isNotEmpty) {
        requestData['documents'] = documentsWithNames;
        requestData['documentUrls'] = documentsWithNames.map((doc) => doc['url']).toList();
      } else if (documentUrls.isNotEmpty) {
        requestData['documents'] = documentUrls;
      }
      // If both are empty, no documents field is added

      if (notes != null && notes.isNotEmpty) {
        requestData['notes'] = notes;
      }

      final docRef = await _firestore.collection('notary_requests').add(requestData);

      if (kDebugMode) {
        debugPrint('✅ Notary request created: ${docRef.id}');
      }

      return {
        'success': true,
        'message': 'Notary request submitted successfully',
        'requestId': docRef.id,
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to create notary request: $e');
      }
      return {'success': false, 'message': 'Failed to create request: ${e.toString()}'};
    }
  }

  // Get client's notary requests
  Stream<List<NotaryRequestModel>> getClientNotaryRequests(String clientId) {
    return _firestore
        .collection('notary_requests')
        .where('clientId', isEqualTo: clientId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotaryRequestModel.fromFirestore(doc))
            .toList());
  }

  // Get all pending notary requests (for attorneys)
  Stream<List<NotaryRequestModel>> getPendingNotaryRequests() {
    return _firestore
        .collection('notary_requests')
        .where('status', isEqualTo: 'pending')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotaryRequestModel.fromFirestore(doc))
            .toList());
  }

  // Get attorney's notary requests
  Stream<List<NotaryRequestModel>> getAttorneyNotaryRequests(String attorneyId) {
    return _firestore
        .collection('notary_requests')
        .where('attorneyId', isEqualTo: attorneyId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotaryRequestModel.fromFirestore(doc))
            .toList());
  }

  // Accept notary request
  Future<Map<String, dynamic>> acceptNotaryRequest(String requestId) async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        return {'success': false, 'message': 'User not authenticated'};
      }

      await _firestore.collection('notary_requests').doc(requestId).update({
        'attorneyId': user.uid,
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        debugPrint('✅ Notary request accepted: $requestId');
      }

      return {'success': true, 'message': 'Notary request accepted successfully'};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to accept request: $e');
      }
      return {'success': false, 'message': 'Failed to accept request: ${e.toString()}'};
    }
  }

  // Decline notary request
  Future<Map<String, dynamic>> declineNotaryRequest(
    String requestId,
    String declineReason,
  ) async {
    try {
      await _firestore.collection('notary_requests').doc(requestId).update({
        'status': 'declined',
        'declineReason': declineReason,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        debugPrint('✅ Notary request declined: $requestId');
      }

      return {'success': true, 'message': 'Notary request declined'};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to decline request: $e');
      }
      return {'success': false, 'message': 'Failed to decline request: ${e.toString()}'};
    }
  }

  // Schedule release
  Future<Map<String, dynamic>> scheduleRelease({
    required String requestId,
    required DateTime releaseDate,
    required DateTime releaseTime,
  }) async {
    try {
      await _firestore.collection('notary_requests').doc(requestId).update({
        'releaseDate': Timestamp.fromDate(releaseDate),
        'releaseTime': Timestamp.fromDate(releaseTime),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (kDebugMode) {
        debugPrint('✅ Release scheduled for request: $requestId');
      }

      return {'success': true, 'message': 'Release scheduled successfully'};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to schedule release: $e');
      }
      return {'success': false, 'message': 'Failed to schedule release: ${e.toString()}'};
    }
  }

  // Get single notary request
  Future<NotaryRequestModel?> getNotaryRequest(String requestId) async {
    try {
      final doc = await _firestore.collection('notary_requests').doc(requestId).get();
      if (!doc.exists) return null;
      return NotaryRequestModel.fromFirestore(doc);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to get request: $e');
      }
      return null;
    }
  }

  // Get client name by ID
  Future<String> getClientName(String clientId) async {
    try {
      final doc = await _firestore.collection('users').doc(clientId).get();
      if (doc.exists) {
        return doc.data()?['name'] ?? 'Unknown Client';
      }
      return 'Unknown Client';
    } catch (e) {
      return 'Unknown Client';
    }
  }
}

