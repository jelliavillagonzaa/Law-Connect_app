import 'package:cloud_firestore/cloud_firestore.dart';

/// Signed-up Client accounts for firm users (attorney/staff/admin).
class ClientDirectoryService {
  ClientDirectoryService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// All users with role `client`, plus [ensureClientId] if it is missing.
  Future<List<Map<String, dynamic>>> loadSignedUpClients({
    String? ensureClientId,
  }) async {
    final clientsMap = <String, Map<String, dynamic>>{};

    final snapshot = await _firestore
        .collection('users')
        .where('role', isEqualTo: 'client')
        .get();

    for (final doc in snapshot.docs) {
      final mapped = _mapClient(doc.id, doc.data());
      if (mapped != null) {
        clientsMap[doc.id] = mapped;
      }
    }

    final extraId = ensureClientId?.trim() ?? '';
    if (extraId.isNotEmpty && !clientsMap.containsKey(extraId)) {
      final extraDoc = await _firestore.collection('users').doc(extraId).get();
      if (extraDoc.exists) {
        final mapped = _mapClient(extraDoc.id, extraDoc.data()!, requireClientRole: false);
        if (mapped != null) {
          clientsMap[extraDoc.id] = mapped;
        }
      }
    }

    final clientsList = clientsMap.values.toList();
    clientsList.sort((a, b) {
      final nameA = (a['displayName'] as String? ?? '').toLowerCase();
      final nameB = (b['displayName'] as String? ?? '').toLowerCase();
      return nameA.compareTo(nameB);
    });
    return clientsList;
  }

  Map<String, dynamic>? _mapClient(
    String id,
    Map<String, dynamic> data, {
    bool requireClientRole = true,
  }) {
    if (id.trim().isEmpty) return null;

    if (requireClientRole) {
      final role = (data['role'] as String? ?? '').trim().toLowerCase();
      if (role != 'client') return null;
    }

    final name = data['name'] as String? ?? '';
    final fullName =
        data['fullName'] as String? ?? data['full_name'] as String? ?? '';
    final email = data['email'] as String? ?? '';
    final phone = (data['phoneNumber'] ?? data['phone'] ?? data['contactNumber'] ?? '').toString().trim();
    final address = (data['address'] ?? data['location'] ?? '').toString().trim();
    final isVerified = data['isVerified'] as bool? ?? false;

    String displayName;
    if (fullName.trim().isNotEmpty) {
      displayName = fullName.trim();
    } else if (name.trim().isNotEmpty) {
      displayName = name.trim();
    } else if (email.isNotEmpty) {
      displayName = email;
    } else {
      displayName = 'Client';
    }

    return {
      'id': id,
      'name': name,
      'fullName': fullName,
      'displayName': displayName,
      'email': email,
      'phone': phone,
      'address': address,
      'isVerified': isVerified,
    };
  }
}
