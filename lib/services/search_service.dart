import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';

class SearchService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Common case types for suggestions
  static const List<String> caseTypes = [
    'child abuse',
    'theft',
    'cybercrime',
    'domestic violence',
    'divorce',
    'custody',
    'immigration',
    'criminal defense',
    'personal injury',
    'employment law',
    'contract disputes',
    'real estate',
    'bankruptcy',
    'estate planning',
    'tax law',
  ];

  // Get case type suggestions based on user input
  List<String> getCaseTypeSuggestions(String query) {
    if (query.isEmpty) return caseTypes;
    
    final queryLower = query.toLowerCase();
    return caseTypes
        .where((type) => type.toLowerCase().contains(queryLower))
        .toList();
  }

  // Search attorneys by specialization
  Future<List<UserModel>> searchAttorneysBySpecialization(
    String searchQuery,
  ) async {
    try {
      final queryLower = searchQuery.toLowerCase();
      
      // Get all attorneys
      final attorneysSnapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'attorney')
          .get();

      final List<UserModel> matchingAttorneys = [];

      for (var doc in attorneysSnapshot.docs) {
        final data = doc.data();
        final specialization = data['specialization'] as List<dynamic>? ?? [];
        
        // Check if any specialization matches the search query
        final matches = specialization.any((spec) {
          return spec.toString().toLowerCase().contains(queryLower);
        });

        // Also check if case type matches
        final caseTypeMatches = caseTypes.any((type) {
          return type.toLowerCase().contains(queryLower) &&
              specialization.any((spec) =>
                  spec.toString().toLowerCase().contains(type));
        });

        if (matches || caseTypeMatches) {
          matchingAttorneys.add(UserModel.fromFirestore(data, doc.id));
        }
      }

      // Sort by rating (highest first) and availability
      matchingAttorneys.sort((a, b) {
        // Available attorneys first
        if (a.isAvailable == true && b.isAvailable != true) return -1;
        if (a.isAvailable != true && b.isAvailable == true) return 1;
        
        // Then by rating
        final ratingA = a.ratingAverage ?? 0.0;
        final ratingB = b.ratingAverage ?? 0.0;
        return ratingB.compareTo(ratingA);
      });

      return matchingAttorneys;
    } catch (e) {
      throw Exception('Failed to search attorneys: $e');
    }
  }

  // Get available attorneys
  Future<List<UserModel>> getAvailableAttorneys() async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'attorney')
          .where('isAvailable', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => UserModel.fromFirestore(doc.data(), doc.id))
          .toList()
        ..sort((a, b) {
          final ratingA = a.ratingAverage ?? 0.0;
          final ratingB = b.ratingAverage ?? 0.0;
          return ratingB.compareTo(ratingA);
        });
    } catch (e) {
      throw Exception('Failed to get available attorneys: $e');
    }
  }

  // Get attorneys by case type
  Future<List<UserModel>> getAttorneysByCaseType(String caseType) async {
    try {
      final caseTypeLower = caseType.toLowerCase();
      
      final snapshot = await _firestore
          .collection('users')
          .where('role', isEqualTo: 'attorney')
          .get();

      final List<UserModel> attorneys = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final specialization = data['specialization'] as List<dynamic>? ?? [];
        
        final matches = specialization.any((spec) {
          return spec.toString().toLowerCase().contains(caseTypeLower);
        });

        if (matches) {
          attorneys.add(UserModel.fromFirestore(data, doc.id));
        }
      }

      // Sort by rating and availability
      attorneys.sort((a, b) {
        if (a.isAvailable == true && b.isAvailable != true) return -1;
        if (a.isAvailable != true && b.isAvailable == true) return 1;
        final ratingA = a.ratingAverage ?? 0.0;
        final ratingB = b.ratingAverage ?? 0.0;
        return ratingB.compareTo(ratingA);
      });

      return attorneys;
    } catch (e) {
      throw Exception('Failed to get attorneys by case type: $e');
    }
  }

  // Get all case types
  List<String> getAllCaseTypes() {
    return caseTypes;
  }
}

