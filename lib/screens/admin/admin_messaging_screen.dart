import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../services/admin_service.dart';

class AdminMessagingScreen extends StatefulWidget {
  final bool inline;
  const AdminMessagingScreen({super.key, this.inline = false});

  @override
  State<AdminMessagingScreen> createState() => _AdminMessagingScreenState();
}

class _AdminMessagingScreenState extends State<AdminMessagingScreen> {
  final AdminService _adminService = AdminService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final List<String> _selectedRoles = [];

  @override
  void dispose() {
    _titleController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Widget _buildBody() {
    return StreamBuilder(
      stream: _adminService.firestore
          .collection('announcements')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final snapshotData = snapshot.data;
        final announcements =
            (snapshotData is QuerySnapshot && snapshotData != null)
            ? snapshotData.docs
            : <QueryDocumentSnapshot>[];

        if (announcements.isEmpty) {
          return const Center(child: Text('No announcements yet'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: announcements.length,
          itemBuilder: (context, index) {
            final announcement =
                announcements[index].data() as Map<String, dynamic>;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: const Icon(Icons.announcement, color: Colors.orange),
                title: Text(announcement['title'] ?? 'No Title'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(announcement['message'] ?? ''),
                    const SizedBox(height: 4),
                    Text(
                      'To: ${(announcement['recipientRoles'] as List<dynamic>?)?.join(', ') ?? 'All'}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.inline) {
      return Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Text(
                  'Admin Messaging Center',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showSendAnnouncementDialog(),
                  tooltip: 'Send Announcement',
                ),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Messaging Center'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showSendAnnouncementDialog(),
            tooltip: 'Send Announcement',
          ),
        ],
      ),
      body: body,
    );
  }

  void _showSendAnnouncementDialog() {
    _selectedRoles.clear();
    _titleController.clear();
    _messageController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Announcement'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(
                  labelText: 'Title',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  border: OutlineInputBorder(),
                ),
                maxLines: 5,
              ),
              const SizedBox(height: 16),
              const Text('Send to:'),
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (context, setState) => Column(
                  children: [
                    CheckboxListTile(
                      title: const Text('All Users'),
                      value: _selectedRoles.contains('all'),
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedRoles.clear();
                            _selectedRoles.add('all');
                          } else {
                            _selectedRoles.remove('all');
                          }
                        });
                      },
                    ),
                    CheckboxListTile(
                      title: const Text('Attorneys'),
                      value: _selectedRoles.contains('attorney'),
                      onChanged: _selectedRoles.contains('all')
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedRoles.add('attorney');
                                } else {
                                  _selectedRoles.remove('attorney');
                                }
                              });
                            },
                    ),
                    CheckboxListTile(
                      title: const Text('Clients'),
                      value: _selectedRoles.contains('client'),
                      onChanged: _selectedRoles.contains('all')
                          ? null
                          : (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedRoles.add('client');
                                } else {
                                  _selectedRoles.remove('client');
                                }
                              });
                            },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_titleController.text.trim().isEmpty ||
                  _messageController.text.trim().isEmpty ||
                  _selectedRoles.isEmpty) {
                Get.snackbar(
                  'Error',
                  'Please fill all fields and select recipients',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
                return;
              }

              try {
                await _adminService.sendAnnouncement(
                  title: _titleController.text.trim(),
                  message: _messageController.text.trim(),
                  recipientRoles: _selectedRoles,
                );
                Get.snackbar(
                  'Success',
                  'Announcement sent successfully',
                  backgroundColor: Colors.green,
                  colorText: Colors.white,
                );
                Navigator.pop(context);
              } catch (e) {
                Get.snackbar(
                  'Error',
                  'Failed to send announcement: $e',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
              }
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }
}
