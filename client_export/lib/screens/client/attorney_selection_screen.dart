import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../theme/app_theme.dart';
import 'request_appointment_screen.dart';

/// Step 1 of the client appointment flow:
/// Let the client pick an attorney (name, specialization, availability).
class AttorneySelectionScreen extends StatefulWidget {
  const AttorneySelectionScreen({super.key});

  @override
  State<AttorneySelectionScreen> createState() =>
      _AttorneySelectionScreenState();
}

class _AttorneySelectionScreenState extends State<AttorneySelectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width > 600;

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
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _firestore
                  .collection('users')
                  .where('role', isEqualTo: 'attorney')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      'Error loading attorneys',
                      style: AppTheme.bodyMedium,
                    ),
                  );
                }

                final docs = snapshot.data?.docs ?? [];
                var attorneys = docs
                    .map((d) => UserModel.fromFirestore(d.data(), d.id))
                    .toList();

                if (_searchQuery.isNotEmpty) {
                  attorneys = attorneys.where((attorney) {
                    final name = (attorney.fullName ?? attorney.name)
                        .toLowerCase();
                    final specialization = (attorney.specialization ?? [])
                        .join(', ')
                        .toLowerCase();
                    return name.contains(_searchQuery) ||
                        specialization.contains(_searchQuery);
                  }).toList();
                }

                if (attorneys.isEmpty) {
                  return Center(
                    child: Text(
                      'No attorneys available at the moment.',
                      style: AppTheme.bodyMedium,
                    ),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.all(isWeb ? 24 : 16),
                  itemCount: attorneys.length,
                  itemBuilder: (context, index) {
                    final attorney = attorneys[index];
                    final name = attorney.fullName ?? attorney.name;
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
                          backgroundColor: AppTheme.royalBlue.withOpacity(0.1),
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
                        onTap: () {
                          Get.to(
                            () => RequestAppointmentScreen(
                              attorneyId: attorney.id,
                              attorneyName: name,
                            ),
                          );
                        },
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
