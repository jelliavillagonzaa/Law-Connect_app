class UserModel {
  final String id;
  final String role; // "client" | "attorney" | "admin" | "staff"
  final String name;
  final String? fullName; // Legacy clients
  final String? firstName;
  final String? middleName;
  final String? lastName;
  final String email;
  final String? photoUrl;
  final List<String>? specialization; // for attorneys
  final double? ratingAverage;
  final DateTime createdAt;
  final bool? isAvailable; // for attorneys
  final String? phone;
  final String? phoneNumber; // For clients
  final String? address;
  final bool isVerified; // Email verification status
  final String? assignedAttorneyId; // for staff
  /// Account enabled for sign-in (staff/attorney may be false until admin approval).
  /// Missing field in Firestore is treated as true for legacy users.
  final bool isActive;

  UserModel({
    required this.id,
    required this.role,
    required this.name,
    this.fullName,
    this.firstName,
    this.middleName,
    this.lastName,
    required this.email,
    this.photoUrl,
    this.specialization,
    this.ratingAverage,
    required this.createdAt,
    this.isAvailable,
    this.phone,
    this.phoneNumber,
    this.address,
    this.isVerified = false,
    this.assignedAttorneyId,
    this.isActive = true,
  });

  static String resolveDisplayName(Map<String, dynamic> data) {
    final first = (data['firstName'] ?? '').toString().trim();
    final middle = (data['middleName'] ?? '').toString().trim();
    final last = (data['lastName'] ?? '').toString().trim();
    if (first.isNotEmpty || middle.isNotEmpty || last.isNotEmpty) {
      return [first, middle, last].where((s) => s.isNotEmpty).join(' ');
    }
    final legacy = (data['fullName'] ?? data['name'] ?? '').toString().trim();
    return legacy.isEmpty ? 'User' : legacy;
  }

  factory UserModel.fromFirestore(Map<String, dynamic> data, String id) {
    // Normalize specialization to a List<String> regardless of how it's stored.
    List<String>? specialization;
    final rawSpecialization = data['specialization'];
    if (rawSpecialization is List) {
      specialization = rawSpecialization.map((s) => s.toString()).toList();
    } else if (rawSpecialization is String &&
        rawSpecialization.trim().isNotEmpty) {
      specialization = rawSpecialization
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }

    final displayName = UserModel.resolveDisplayName(data);

    return UserModel(
      id: id,
      role: data['role'] ?? 'client',
      name: displayName,
      fullName: data['fullName']?.toString(),
      firstName: data['firstName']?.toString(),
      middleName: data['middleName']?.toString(),
      lastName: data['lastName']?.toString(),
      email: data['email'] ?? '',
      photoUrl: data['photoUrl'],
      specialization: specialization,
      ratingAverage: data['ratingAverage']?.toDouble(),
      createdAt: data['createdAt']?.toDate() ?? DateTime.now(),
      isAvailable: data['isAvailable'],
      // Ensure phone values are always treated as strings, even if stored as numbers
      phone: (data['phone'] ?? data['phoneNumber'])?.toString(),
      phoneNumber: data['phoneNumber']?.toString(),
      address: data['address'],
      isVerified: data['isVerified'] ?? false,
      assignedAttorneyId: data['assignedAttorneyId'],
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'role': role,
      'name': name,
      if (fullName != null) 'fullName': fullName,
      if (firstName != null) 'firstName': firstName,
      if (middleName != null) 'middleName': middleName,
      if (lastName != null) 'lastName': lastName,
      'email': email,
      if (photoUrl != null) 'photoUrl': photoUrl,
      if (specialization != null) 'specialization': specialization,
      if (ratingAverage != null) 'ratingAverage': ratingAverage,
      'createdAt': createdAt,
      if (isAvailable != null) 'isAvailable': isAvailable,
      if (phone != null) 'phone': phone,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      if (address != null) 'address': address,
      'isVerified': isVerified,
      if (assignedAttorneyId != null) 'assignedAttorneyId': assignedAttorneyId,
      'isActive': isActive,
    };
  }
}
