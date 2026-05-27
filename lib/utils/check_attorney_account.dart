import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Diagnostic tool to check attorney account and client connections
/// Run this to verify why attorney@gmail.com has no clients
class AttorneyAccountChecker {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Check attorney account and return diagnostic information
  Future<Map<String, dynamic>> checkAttorneyAccount(String attorneyEmail) async {
    final results = <String, dynamic>{
      'attorneyEmail': attorneyEmail,
      'attorneyFound': false,
      'attorneyUid': null,
      'attorneyData': null,
      'casesCount': 0,
      'casesWithAttorneyId': 0,
      'casesWithClientId': 0,
      'acceptedCases': 0,
      'pendingCases': 0,
      'clientIds': <String>[],
      'issues': <String>[],
    };

    try {
      // Step 1: Find attorney by email in Firebase Auth
      final authUsers = await _auth.fetchSignInMethodsForEmail(attorneyEmail);
      if (authUsers.isEmpty) {
        results['issues'].add('Attorney email not found in Firebase Authentication');
        return results;
      }

      // Step 2: Get attorney UID from Firestore users collection
      final usersSnapshot = await _firestore
          .collection('users')
          .where('email', isEqualTo: attorneyEmail)
          .where('role', isEqualTo: 'attorney')
          .limit(1)
          .get();

      if (usersSnapshot.docs.isEmpty) {
        results['issues'].add(
          'Attorney email found in Auth but no user document in Firestore with role="attorney"',
        );
        return results;
      }

      final attorneyDoc = usersSnapshot.docs.first;
      final attorneyUid = attorneyDoc.id;
      final attorneyData = attorneyDoc.data();

      results['attorneyFound'] = true;
      results['attorneyUid'] = attorneyUid;
      results['attorneyData'] = {
        'name': attorneyData['name'] ?? 'N/A',
        'email': attorneyData['email'] ?? 'N/A',
        'role': attorneyData['role'] ?? 'N/A',
        'isActive': attorneyData['isActive'] ?? false,
        'isVerified': attorneyData['isVerified'] ?? false,
        'pendingApproval': attorneyData['pendingApproval'] ?? false,
      };

      // Step 3: Check all cases in the system
      final allCasesSnapshot = await _firestore.collection('cases').get();
      results['casesCount'] = allCasesSnapshot.docs.length;

      // Step 4: Check cases with this attorney's UID
      final attorneyCases = allCasesSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['attorneyId'] == attorneyUid;
      }).toList();

      results['casesWithAttorneyId'] = attorneyCases.length;

      // Step 5: Check cases with clientId
      final casesWithClientId = attorneyCases.where((doc) {
        final data = doc.data();
        return data['clientId'] != null && (data['clientId'] as String).isNotEmpty;
      }).toList();

      results['casesWithClientId'] = casesWithClientId.length;

      // Step 6: Check case statuses
      final acceptedCases = attorneyCases.where((doc) {
        final data = doc.data();
        return data['status'] == 'accepted' || data['status'] == 'in_progress';
      }).toList();

      final pendingCases = attorneyCases.where((doc) {
        final data = doc.data();
        return data['status'] == 'pending';
      }).toList();

      results['acceptedCases'] = acceptedCases.length;
      results['pendingCases'] = pendingCases.length;

      // Step 7: Extract unique client IDs
      final clientIdsSet = <String>{};
      for (var doc in casesWithClientId) {
        final data = doc.data();
        final clientId = data['clientId'] as String?;
        if (clientId != null && clientId.isNotEmpty) {
          clientIdsSet.add(clientId);
        }
      }
      results['clientIds'] = clientIdsSet.toList();

      // Step 8: Identify issues
      if (results['casesWithAttorneyId'] == 0) {
        results['issues'].add(
          'No cases found with attorneyId="$attorneyUid". '
          'Clients need to create cases and attorneys need to accept them.',
        );
      } else if (results['casesWithClientId'] == 0) {
        results['issues'].add(
          'Cases exist for this attorney but none have a clientId field set.',
        );
      } else if (results['acceptedCases'] == 0 && results['pendingCases'] > 0) {
        results['issues'].add(
          'Attorney has ${results['pendingCases']} pending cases that need to be accepted. '
          'Accept cases from the attorney dashboard to link clients.',
        );
      } else if (results['clientIds'].isEmpty) {
        results['issues'].add(
          'Cases exist but no valid client IDs found.',
        );
      }

      // Step 9: Check if attorney is active
      if (attorneyData['isActive'] != true) {
        results['issues'].add('Attorney account is not active (isActive=false)');
      }

      if (attorneyData['pendingApproval'] == true) {
        results['issues'].add('Attorney account is pending approval');
      }

    } catch (e) {
      results['issues'].add('Error checking attorney account: $e');
    }

    return results;
  }

  /// Print diagnostic results in a readable format
  void printDiagnostics(Map<String, dynamic> results) {
    print('\n=== ATTORNEY ACCOUNT DIAGNOSTICS ===');
    print('Email: ${results['attorneyEmail']}');
    print('Found: ${results['attorneyFound']}');
    
    if (results['attorneyFound'] == true) {
      print('\n--- Attorney Info ---');
      print('UID: ${results['attorneyUid']}');
      final data = results['attorneyData'] as Map<String, dynamic>?;
      if (data != null) {
        print('Name: ${data['name']}');
        print('Active: ${data['isActive']}');
        print('Verified: ${data['isVerified']}');
        print('Pending Approval: ${data['pendingApproval']}');
      }

      print('\n--- Cases Analysis ---');
      print('Total cases in system: ${results['casesCount']}');
      print('Cases with this attorneyId: ${results['casesWithAttorneyId']}');
      print('Cases with clientId: ${results['casesWithClientId']}');
      print('Accepted/In Progress cases: ${results['acceptedCases']}');
      print('Pending cases: ${results['pendingCases']}');
      print('Unique client IDs found: ${results['clientIds'].length}');
      
      if ((results['clientIds'] as List).isNotEmpty) {
        print('Client IDs: ${results['clientIds']}');
      }
    }

    print('\n--- Issues Found ---');
    final issues = results['issues'] as List<String>;
    if (issues.isEmpty) {
      print('✅ No issues found! Attorney account looks good.');
    } else {
      for (var issue in issues) {
        print('⚠️  $issue');
      }
    }
    print('\n===============================\n');
  }
}

