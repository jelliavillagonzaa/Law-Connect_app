import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_model.dart';

class StaffModel {
  final String id;
  final String name;
  final String email;
  final String? photoUrl;
  final String? phone;
  final String? phoneNumber;
  final String? address;
  final String assignedAttorneyId; // Required - staff must be assigned to an attorney
  final bool isVerified;
  final DateTime createdAt;
  final DateTime? updatedAt;

  StaffModel({
    required this.id,
    required this.name,
    required this.email,
    this.photoUrl,
    this.phone,
    this.phoneNumber,
    this.address,
    required this.assignedAttorneyId,
    this.isVerified = true,
    required this.createdAt,
    this.updatedAt,
  });

  factory StaffModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return StaffModel(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'],
      phone: (data['phone'] ?? data['phoneNumber'])?.toString(),
      phoneNumber: data['phoneNumber']?.toString(),
      address: data['address'],
      assignedAttorneyId: data['assignedAttorneyId'] ?? '',
      isVerified: data['isVerified'] ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Create StaffModel from UserModel (for users collection with role='staff')
  factory StaffModel.fromUserModel(UserModel user) {
    if (user.assignedAttorneyId == null || user.assignedAttorneyId!.isEmpty) {
      throw ArgumentError('User must have assignedAttorneyId to be staff');
    }
    return StaffModel(
      id: user.id,
      name: user.name,
      email: user.email,
      photoUrl: user.photoUrl,
      phone: user.phone,
      phoneNumber: user.phoneNumber,
      address: user.address,
      assignedAttorneyId: user.assignedAttorneyId!,
      isVerified: user.isVerified,
      createdAt: user.createdAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'email': email,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (phone != null) 'phone': phone,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (address != null) 'address': address,
      'assignedAttorneyId': assignedAttorneyId,
      'isVerified': isVerified,
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  // Convert to UserModel for compatibility (if needed)
  Map<String, dynamic> toUserModelData() {
    return {
      'role': 'staff',
      'name': name,
      'email': email,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (phone != null) 'phone': phone,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (address != null) 'address': address,
      'assignedAttorneyId': assignedAttorneyId,
      'isVerified': isVerified,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}

