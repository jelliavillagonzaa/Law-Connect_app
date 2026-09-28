import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';
import 'request_appointment_screen.dart';

bool _isBookableAttorney(Map<String, dynamic> data) {
  if (data['isActive'] == false) return false;
  if (data['pendingApproval'] == true) return false;
  return true;
}

String attorneyDisplayName(UserModel attorney) {
  final name = (attorney.fullName ?? attorney.name).trim();
  return name.isEmpty ? 'Attorney' : name;
}

UserModel? parseBookableAttorney(
  QueryDocumentSnapshot<Map<String, dynamic>> doc,
) {
  try {
    final data = doc.data();
    if (!_isBookableAttorney(data)) return null;
    return UserModel.fromFirestore(data, doc.id);
  } catch (_) {
    return null;
  }
}

void sortBookableAttorneys(List<UserModel> attorneys) {
  attorneys.sort((a, b) {
    if (a.isAvailable == true && b.isAvailable != true) return -1;
    if (a.isAvailable != true && b.isAvailable == true) return 1;
    return attorneyDisplayName(a).toLowerCase().compareTo(
      attorneyDisplayName(b).toLowerCase(),
    );
  });
}

Future<List<UserModel>> loadBookableAttorneys() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('users')
      .where('role', isEqualTo: 'attorney')
      .get();
  final bookable = snapshot.docs
      .map(parseBookableAttorney)
      .whereType<UserModel>()
      .toList();
  sortBookableAttorneys(bookable);
  return bookable;
}

/// Opens the request-appointment flow without flashing Choose Attorney
/// when the firm has only one bookable attorney.
Future<void> openRequestAppointmentFlow() async {
  Get.dialog(
    const Center(child: CircularProgressIndicator()),
    barrierDismissible: false,
    barrierColor: Colors.black26,
  );

  try {
    final attorneys = await loadBookableAttorneys();
    if (Get.isDialogOpen == true) {
      Get.back();
    }

    if (attorneys.length == 1) {
      final attorney = attorneys.first;
      await Get.to(
        () => RequestAppointmentScreen(
          attorneyId: attorney.id,
          attorneyName: attorneyDisplayName(attorney),
        ),
      );
      return;
    }

    await Get.to(
      () => AttorneySelectionScreen(initialAttorneys: attorneys),
    );
  } catch (_) {
    if (Get.isDialogOpen == true) {
      Get.back();
    }
    await Get.to(() => const AttorneySelectionScreen());
  }
}

/// Shown only when the firm has multiple bookable attorneys (or none).
class AttorneySelectionScreen extends StatefulWidget {
  final List<UserModel>? initialAttorneys;

  const AttorneySelectionScreen({super.key, this.initialAttorneys});

  @override
  State<AttorneySelectionScreen> createState() =>
      _AttorneySelectionScreenState();
}

class _AttorneySelectionScreenState extends State<AttorneySelectionScreen> {
  String _searchQuery = '';
  late bool _loading;
  String? _error;
  late List<UserModel> _attorneys;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialAttorneys;
    if (initial != null) {
      _attorneys = initial;
      _loading = false;
    } else {
      _attorneys = const [];
      _loading = true;
      _loadAttorneys();
    }
  }

  Future<void> _loadAttorneys() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final bookable = await loadBookableAttorneys();
      if (!mounted) return;
      setState(() {
        _attorneys = bookable;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error loading attorneys';
      });
    }
  }

  void _openRequest(UserModel attorney) {
    Get.to(
      () => RequestAppointmentScreen(
        attorneyId: attorney.id,
        attorneyName: attorneyDisplayName(attorney),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 600;

    if (_loading) {
      return Scaffold(
        backgroundColor: AppTheme.lightBackground,
        appBar: AppBar(title: const Text('Choose Attorney')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: AppTheme.lightBackground,
        appBar: AppBar(title: const Text('Choose Attorney')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, style: AppTheme.bodyMedium),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadAttorneys,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    var attorneys = _attorneys;
    if (_searchQuery.isNotEmpty) {
      attorneys = attorneys.where((attorney) {
        final name = attorneyDisplayName(attorney).toLowerCase();
        final specialization = (attorney.specialization ?? [])
            .join(', ')
            .toLowerCase();
        return name.contains(_searchQuery) ||
            specialization.contains(_searchQuery);
      }).toList();
    }

    return Scaffold(
      backgroundColor: AppTheme.lightBackground,
      appBar: AppBar(title: const Text('Choose Attorney')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by name or specialization',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.borderGray),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppTheme.borderGray),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _searchQuery = value.trim().toLowerCase();
                });
              },
            ),
          ),
          Expanded(
            child: attorneys.isEmpty
                ? Center(
                    child: Text(
                      'No attorneys available at the moment.',
                      style: AppTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.all(isWeb ? 24 : 16),
                    itemCount: attorneys.length,
                    itemBuilder: (context, index) {
                      final attorney = attorneys[index];
                      final name = attorneyDisplayName(attorney);
                      final specialization = (attorney.specialization ?? [])
                          .join(', ')
                          .toString();
                      final availability = attorney.isAvailable == true
                          ? 'Available'
                          : 'Offline';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.shadowColor,
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.royalBlue.withOpacity(
                              0.1,
                            ),
                            child: Text(
                              name.substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: AppTheme.royalBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          title: Text(
                            name,
                            style: AppTheme.bodyLarge.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(specialization, style: AppTheme.bodySmall),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(
                                    Icons.access_time,
                                    size: 14,
                                    color: AppTheme.mutedText,
                                  ),
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      availability,
                                      style: AppTheme.caption,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          trailing: const Icon(
                            Icons.chevron_right,
                            color: AppTheme.mutedText,
                          ),
                          onTap: () => _openRequest(attorney),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
