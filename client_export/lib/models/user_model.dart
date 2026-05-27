class UserModel {
  final String id;
  final String role; // "client" | "attorney" | "admin" | "staff"
  final String name;
  final String? fullName; // For clients
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

  UserModel({
    required this.id,
    required this.role,
    required this.name,
    this.fullName,
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
  });

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

    return UserModel(
      id: id,
      role: data['role'] ?? 'client',
      name: data['name'] ?? data['fullName'] ?? '',
      fullName: data['fullName'],
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
    };
  }
}

