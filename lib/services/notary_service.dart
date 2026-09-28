import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode, debugPrint;
import 'package:image_picker/image_picker.dart';
import '../models/notary_request_model.dart';
import 'attorney_request_notify.dart';

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

  // Pick a PDF or image of a required notary document.
  Future<XFile?> pickNotaryFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return null;
      final file = result.files.first;
      if (file.bytes != null && file.bytes!.isNotEmpty) {
        return XFile.fromData(file.bytes!, name: file.name);
      }
      if (file.path != null && file.path!.isNotEmpty) {
        return XFile(file.path!, name: file.name);
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to pick notary file: $e');
      }
      return null;
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
    required List<String> documentUrls,
    String? notes,
    List<Map<String, String>>? documentsWithNames,
    String? attorneyId,
    DateTime? preferredDateTime,
    List<String>? bringDocuments,
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

      if (attorneyId != null && attorneyId.isNotEmpty) {
        requestData['attorneyId'] = attorneyId;
      }

      if (documentsWithNames != null && documentsWithNames.isNotEmpty) {
        requestData['documents'] = documentsWithNames;
        requestData['documentUrls'] =
            documentsWithNames.map((doc) => doc['url']).toList();
      } else if (documentUrls.isNotEmpty) {
        requestData['documents'] = documentUrls;
      }

      if (notes != null && notes.isNotEmpty) {
        requestData['notes'] = notes;
      }
      if (preferredDateTime != null) {
        requestData['preferredDateTime'] = Timestamp.fromDate(preferredDateTime);
      }
      if (bringDocuments != null && bringDocuments.isNotEmpty) {
        requestData['bringDocuments'] = bringDocuments;
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

  Future<Map<String, dynamic>> updateNotaryDocuments({
    required String requestId,
    required List<Map<String, String>> documentsWithNames,
  }) async {
    try {
      await _firestore.collection('notary_requests').doc(requestId).update({
        'documents': documentsWithNames,
        'documentUrls': documentsWithNames.map((doc) => doc['url']).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return {'success': true};
    } catch (e) {
      return {
        'success': false,
        'message': 'Failed to save uploaded documents: ${e.toString()}',
      };
    }
  }

  Future<void> notifyNewNotaryRequest({
    required String requestId,
    required String serviceType,
    String? attorneyId,
    DateTime? preferredDateTime,
  }) async {
    try {
      final user = _auth.currentUser;
      final clientName = (user?.displayName ?? '').trim().isEmpty
          ? 'A client'
          : user!.displayName!;
      var when = '';
      if (preferredDateTime != null) {
        final date =
            '${preferredDateTime.month}/${preferredDateTime.day}/${preferredDateTime.year}';
        final hour = preferredDateTime.hour.toString().padLeft(2, '0');
        final minute = preferredDateTime.minute.toString().padLeft(2, '0');
        when = ' Preferred visit: $date $hour:$minute.';
      }
      final title = 'New Notary Request';
      final message =
          '$clientName requested $serviceType. Client will bring originals to the office.$when';
      final data = <String, dynamic>{
        'requestId': requestId,
        'clientId': user?.uid ?? '',
      };
      final aid = (attorneyId ?? '').trim();
      var staffIds = aid.isEmpty
          ? await _allStaffIds()
          : await _staffIdsForAttorney(aid);
      if (staffIds.isEmpty) {
        staffIds = await _allStaffIds();
      }
      for (final staffId in staffIds) {
        await AttorneyRequestNotify.notifyParty(
          userId: staffId,
          title: title,
          message: message,
          type: 'notary_request',
          sendSms: false,
          sendPush: true,
          data: data,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Notary notify failed: $e');
      }
    }
  }

  Stream<List<NotaryRequestModel>> watchClientNotaryRequests(String clientId) {
    return _firestore
        .collection('notary_requests')
        .where('clientId', isEqualTo: clientId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => NotaryRequestModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
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
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => NotaryRequestModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  Stream<List<NotaryRequestModel>> getAttorneyNotaryRequests(String attorneyId) {
    return _firestore
        .collection('notary_requests')
        .where('attorneyId', isEqualTo: attorneyId)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => NotaryRequestModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Staff-only actor for accept / decline / schedule. Attorney cannot decide.
  Future<({String? error, String staffUid, String attorneyId})>
      _staffNotaryActor(String existingAttorneyId) async {
    final user = _auth.currentUser;
    if (user == null) {
      return (error: 'User not authenticated', staffUid: '', attorneyId: '');
    }
    final userDoc = await _firestore.collection('users').doc(user.uid).get();
    final role =
        (userDoc.data()?['role'] as String?)?.toLowerCase().trim() ?? '';
    if (role != 'staff') {
      return (
        error: 'Only assigned staff can accept or decline notary requests.',
        staffUid: '',
        attorneyId: '',
      );
    }
    final assigned =
        (userDoc.data()?['assignedAttorneyId'] as String?)?.trim() ?? '';
    if (assigned.isEmpty) {
      return (
        error: 'No assigned attorney. Ask admin to link your account.',
        staffUid: '',
        attorneyId: '',
      );
    }
    if (existingAttorneyId.isNotEmpty && existingAttorneyId != assigned) {
      return (
        error: 'This notary request belongs to another attorney.',
        staffUid: '',
        attorneyId: '',
      );
    }
    return (error: null, staffUid: user.uid, attorneyId: assigned);
  }

  // Accept notary request. Staff only (does not replace attorneyId with staff uid).
  Future<Map<String, dynamic>> acceptNotaryRequest(String requestId) async {
    try {
      final request = await getNotaryRequest(requestId);
      if (request == null) {
        return {'success': false, 'message': 'Request not found'};
      }

      final actor = await _staffNotaryActor((request.attorneyId ?? '').trim());
      if (actor.error != null) {
        return {'success': false, 'message': actor.error};
      }

      await _firestore.collection('notary_requests').doc(requestId).update({
        'status': 'accepted',
        'updatedAt': FieldValue.serverTimestamp(),
        'acceptedByUid': actor.staffUid,
        'acceptedByRole': 'staff',
        'attorneyId': actor.attorneyId,
        'handledByStaffId': actor.staffUid,
      });

      unawaited(
        notifyNotaryDecision(
          request: request,
          attorneyId: actor.attorneyId,
          accepted: true,
        ),
      );

      if (kDebugMode) {
        debugPrint('✅ Notary request accepted: $requestId by staff');
      }

      return {'success': true, 'message': 'Notary request accepted successfully'};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Failed to accept request: $e');
      }
      return {'success': false, 'message': 'Failed to accept request: ${e.toString()}'};
    }
  }

  // Decline notary request. Staff only, on behalf of assigned attorney.
  Future<Map<String, dynamic>> declineNotaryRequest(
    String requestId,
    String declineReason,
  ) async {
    try {
      final request = await getNotaryRequest(requestId);
      if (request == null) {
        return {'success': false, 'message': 'Request not found'};
      }

      var existingAttorney = (request.attorneyId ?? '').trim();
      final actor = await _staffNotaryActor(existingAttorney);
      if (actor.error != null) {
        return {'success': false, 'message': actor.error};
      }
      existingAttorney = actor.attorneyId;

      await _firestore.collection('notary_requests').doc(requestId).update({
        'status': 'declined',
        'declineReason': declineReason,
        'updatedAt': FieldValue.serverTimestamp(),
        'declinedByUid': actor.staffUid,
        'declinedByRole': 'staff',
        'attorneyId': existingAttorney,
        'handledByStaffId': actor.staffUid,
      });

      unawaited(
        notifyNotaryDecision(
          request: request,
          attorneyId: existingAttorney,
          accepted: false,
          declineReason: declineReason,
        ),
      );

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

  /// Pending firm queue + this attorney's requests (for assigned staff).
  Stream<List<NotaryRequestModel>> watchStaffNotaryQueue(String attorneyId) {
    final aid = attorneyId.trim();
    late final StreamController<List<NotaryRequestModel>> controller;
    StreamSubscription<List<NotaryRequestModel>>? s1;
    StreamSubscription<List<NotaryRequestModel>>? s2;
    var pending = <NotaryRequestModel>[];
    var assigned = <NotaryRequestModel>[];

    void emit() {
      if (controller.isClosed) return;
      final map = <String, NotaryRequestModel>{};
      for (final r in [...pending, ...assigned]) {
        final owner = (r.attorneyId ?? '').trim();
        final pendingRow = r.status.toLowerCase() == 'pending';
        if (pendingRow && (owner.isEmpty || owner == aid)) {
          map[r.id] = r;
        } else if (owner == aid) {
          map[r.id] = r;
        }
      }
      final out = map.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      controller.add(out);
    }

    controller = StreamController<List<NotaryRequestModel>>(
      onListen: () {
        controller.add(const <NotaryRequestModel>[]);
        s1 = getPendingNotaryRequests().listen(
          (rows) {
            pending = rows;
            emit();
          },
          onError: (e, st) {
            if (!controller.isClosed) controller.addError(e, st);
          },
        );
        if (aid.isEmpty) return;
        s2 = getAttorneyNotaryRequests(aid).listen(
          (rows) {
            assigned = rows;
            emit();
          },
          onError: (e, st) {
            if (!controller.isClosed) controller.addError(e, st);
          },
        );
      },
      onCancel: () {
        s1?.cancel();
        s2?.cancel();
      },
    );
    return controller.stream;
  }

  // Schedule or move the office visit. Staff only. Calendar follows releaseDate.
  Future<Map<String, dynamic>> scheduleRelease({
    required String requestId,
    required DateTime releaseDate,
    required DateTime releaseTime,
    String? moveReason,
  }) async {
    try {
      final request = await getNotaryRequest(requestId);
      if (request == null) {
        return {'success': false, 'message': 'Request not found'};
      }
      final actor = await _staffNotaryActor((request.attorneyId ?? '').trim());
      if (actor.error != null) {
        return {'success': false, 'message': actor.error};
      }

      final isMove = request.releaseDate != null;
      final purpose = (moveReason ?? '').trim();
      if (isMove && purpose.isEmpty) {
        return {
          'success': false,
          'message': 'Please enter why you are moving this schedule.',
        };
      }

      final when = DateTime(
        releaseDate.year,
        releaseDate.month,
        releaseDate.day,
        releaseTime.hour,
        releaseTime.minute,
      );
      final patch = <String, dynamic>{
        'releaseDate': Timestamp.fromDate(releaseDate),
        'releaseTime': Timestamp.fromDate(when),
        'updatedAt': FieldValue.serverTimestamp(),
        'handledByStaffId': actor.staffUid,
      };
      if (isMove) {
        patch['scheduleMoveReason'] = purpose;
      }

      await _firestore.collection('notary_requests').doc(requestId).update(patch);

      await notifyNotaryDecision(
        request: request,
        attorneyId: actor.attorneyId,
        accepted: true,
        scheduleUpdate: true,
        reschedule: isMove,
        moveReason: isMove ? purpose : null,
        scheduledOverride: when,
      );

      if (kDebugMode) {
        debugPrint('✅ Release scheduled for request: $requestId');
      }

      return {
        'success': true,
        'moved': isMove,
        'whenText': _formatNotaryWhen(when),
        'message': isMove
            ? 'Visit moved to ${_formatNotaryWhen(when)}.'
            : 'Please go to the office on ${_formatNotaryWhen(when)}.',
      };
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

  String _formatNotaryWhen(DateTime when) {
    final hour = when.hour % 12 == 0 ? 12 : when.hour % 12;
    final ampm = when.hour < 12 ? 'AM' : 'PM';
    final minute = when.minute.toString().padLeft(2, '0');
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[when.month - 1]} ${when.day}, ${when.year} $hour:$minute $ampm';
  }

  Future<List<String>> _staffIdsForAttorney(String attorneyId) async {
    final aid = attorneyId.trim();
    if (aid.isEmpty) return const [];
    final ids = <String>{};
    try {
      final users = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'staff')
          .where('assignedAttorneyId', isEqualTo: aid)
          .get()
          .timeout(const Duration(seconds: 8));
      for (final doc in users.docs) {
        ids.add(doc.id);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Staff lookup (users) failed: $e');
    }
    try {
      final staff = await _firestore
          .collection('staff')
          .where('assignedAttorneyId', isEqualTo: aid)
          .get()
          .timeout(const Duration(seconds: 8));
      for (final doc in staff.docs) {
        ids.add(doc.id);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Staff lookup (staff) failed: $e');
    }
    return ids.toList();
  }

  Future<List<String>> _allStaffIds() async {
    final ids = <String>{};
    try {
      final users = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'staff')
          .limit(40)
          .get()
          .timeout(const Duration(seconds: 8));
      for (final doc in users.docs) {
        ids.add(doc.id);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ All-staff lookup failed: $e');
    }
    return ids.toList();
  }

  Future<void> notifyNotaryDecision({
    required NotaryRequestModel request,
    required String attorneyId,
    required bool accepted,
    String? declineReason,
    DateTime? scheduledOverride,
    bool scheduleUpdate = false,
    bool reschedule = false,
    String? moveReason,
  }) async {
    try {
      final service = request.serviceType.trim().isEmpty
          ? 'notary request'
          : request.serviceType.trim();
      final clientName = await getClientName(request.clientId);
      final when = scheduledOverride ?? calendarDateForRequest(request);
      final whenText = when == null ? '' : _formatNotaryWhen(when);
      final reason = (declineReason ?? request.declineReason ?? '').trim();
      final purpose = (moveReason ?? request.scheduleMoveReason ?? '').trim();

      late final String clientTitle;
      late final String clientMsg;
      late final String clientSms;
      late final String firmTitle;
      late final String firmMsg;
      late final String firmSms;
      late final String type;

      if (scheduleUpdate) {
        type = reschedule ? 'notary_rescheduled' : 'notary_scheduled';
        if (reschedule) {
          final why = purpose.isEmpty ? '' : ' Reason: $purpose';
          clientTitle = 'Notary visit moved';
          clientMsg = whenText.isEmpty
              ? 'Your $service office visit was moved.$why'
              : 'Your $service office visit was moved. Please go to the office on $whenText.$why';
          clientSms = whenText.isEmpty
              ? 'Law Connect: Your notary visit ($service) was moved.$why'
              : 'Law Connect: Your notary ($service) schedule was moved. Please go to the office on $whenText.$why';
          firmTitle = clientTitle;
          firmMsg = whenText.isEmpty
              ? '$service for $clientName was moved.$why'
              : '$service for $clientName moved. Go to the office on $whenText.$why';
          firmSms = whenText.isEmpty
              ? 'Law Connect: Notary ($service) for $clientName was moved.$why'
              : 'Law Connect: Notary ($service) for $clientName moved to $whenText.$why';
        } else {
          clientTitle = 'Go to the office';
          clientMsg = whenText.isEmpty
              ? 'Please go to the office for your $service.'
              : 'Please go to the office on $whenText for your $service.';
          clientSms = whenText.isEmpty
              ? 'Law Connect: Please go to the office for your notary ($service).'
              : 'Law Connect: Please go to the office on $whenText for your notary ($service).';
          firmTitle = clientTitle;
          firmMsg = whenText.isEmpty
              ? '$service for $clientName: client should go to the office.'
              : '$service for $clientName: go to the office on $whenText.';
          firmSms = whenText.isEmpty
              ? 'Law Connect: Notary ($service) for $clientName — client should go to the office.'
              : 'Law Connect: Notary ($service) for $clientName — go to the office on $whenText.';
        }
      } else if (accepted) {
        type = 'notary_accepted';
        clientTitle = 'Notary request accepted';
        clientMsg = whenText.isEmpty
            ? 'Your $service request was accepted.'
            : 'Your $service request was accepted. Schedule: $whenText.';
        clientSms = whenText.isEmpty
            ? 'Law Connect: Your notary request ($service) was accepted.'
            : 'Law Connect: Your notary request ($service) was accepted. Schedule: $whenText.';
        firmTitle = clientTitle;
        firmMsg = whenText.isEmpty
            ? '$service for $clientName was accepted.'
            : '$service for $clientName was accepted. Schedule: $whenText.';
        firmSms = whenText.isEmpty
            ? 'Law Connect: Notary request ($service) for $clientName was accepted.'
            : 'Law Connect: Notary request ($service) for $clientName was accepted. Schedule: $whenText.';
      } else {
        type = 'notary_declined';
        clientTitle = 'Notary request declined';
        clientMsg = reason.isEmpty
            ? 'Your $service request was declined.'
            : 'Your $service request was declined. Reason: $reason';
        clientSms = reason.isEmpty
            ? 'Law Connect: Your notary request ($service) was declined.'
            : 'Law Connect: Your notary request ($service) was declined. Reason: $reason';
        firmTitle = clientTitle;
        firmMsg = reason.isEmpty
            ? '$service for $clientName was declined.'
            : '$service for $clientName was declined. Reason: $reason';
        firmSms = reason.isEmpty
            ? 'Law Connect: Notary request ($service) for $clientName was declined.'
            : 'Law Connect: Notary request ($service) for $clientName was declined. Reason: $reason';
      }

      final data = <String, dynamic>{
        'requestId': request.id,
        'clientId': request.clientId,
        'status': accepted ? 'accepted' : 'declined',
        if (scheduleUpdate) 'officeVisit': whenText,
        if (reschedule) 'moved': true,
        if (purpose.isNotEmpty) 'moveReason': purpose,
      };

      await AttorneyRequestNotify.notifyParty(
        userId: request.clientId,
        title: clientTitle,
        message: clientMsg,
        type: type,
        smsBody: clientSms,
        isClient: true,
        data: data,
      );

      final aid = attorneyId.trim();
      if (aid.isNotEmpty && aid != request.clientId) {
        await AttorneyRequestNotify.notifyParty(
          userId: aid,
          title: firmTitle,
          message: firmMsg,
          type: type,
          smsBody: firmSms,
          sendSms: true,
          sendPush: true,
          sendInApp: true,
          data: data,
        );
      }

      for (final staffId in await _staffIdsForAttorney(aid)) {
        if (staffId == request.clientId || staffId == aid) continue;
        await AttorneyRequestNotify.notifyParty(
          userId: staffId,
          title: firmTitle,
          message: firmMsg,
          type: type,
          sendSms: false,
          sendPush: true,
          sendInApp: true,
          data: data,
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('⚠️ Notary decision notify failed: $e');
      }
    }
  }

  DateTime? calendarDateForRequest(NotaryRequestModel r) {
    final release = r.releaseDate;
    if (release != null) {
      final t = r.releaseTime;
      if (t != null) {
        return DateTime(
          release.year,
          release.month,
          release.day,
          t.hour,
          t.minute,
        );
      }
      return release;
    }
    return r.preferredDateTime;
  }

  List<Map<String, dynamic>> toCalendarRows(List<NotaryRequestModel> requests) {
    final out = <Map<String, dynamic>>[];
    for (final r in requests) {
      final status = r.status.toLowerCase();
      if (status != 'accepted' && status != 'completed') continue;
      final when = calendarDateForRequest(r);
      if (when == null) continue;
      out.add({
        'id': 'notary_${r.id}',
        'title': r.serviceType,
        'eventType': 'notary',
        'eventDate': when,
        'clientId': r.clientId,
        'source': 'notary_request',
        'notaryRequestId': r.id,
        'status': r.status,
      });
    }
    return out;
  }

  Stream<List<Map<String, dynamic>>> watchNotaryCalendarRows(String attorneyId) {
    return watchStaffNotaryQueue(attorneyId).map(toCalendarRows);
  }

  static bool isNotaryCalendarRow(Map<String, dynamic> ev) {
    if ((ev['notaryRequestId'] as String?)?.trim().isNotEmpty == true) {
      return true;
    }
    if ((ev['source'] as String?) == 'notary_request') return true;
    return (ev['eventType'] as String?)?.toLowerCase() == 'notary';
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

