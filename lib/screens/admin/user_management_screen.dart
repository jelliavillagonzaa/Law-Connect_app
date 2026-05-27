import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/safe_network_avatar.dart';

class UserManagementScreen extends StatefulWidget {
  final bool inline;
  /// When set (e.g. from admin dashboard stat cards), pre-selects the role filter.
  final String? initialRoleFilter;

  const UserManagementScreen({
    super.key,
    this.inline = false,
    this.initialRoleFilter,
  });

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final AdminService _adminService = AdminService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _searchController = TextEditingController();
  late String _selectedRole;
  String _searchQuery = '';

  static const _roles = {'all', 'client', 'attorney', 'staff', 'admin'};

  String _roleFromWidget() {
    final r = widget.initialRoleFilter?.trim().toLowerCase();
    if (r != null && r.isNotEmpty && _roles.contains(r)) return r;
    return 'all';
  }

  @override
  void initState() {
    super.initState();
    _selectedRole = _roleFromWidget();
  }

  @override
  void didUpdateWidget(UserManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialRoleFilter != oldWidget.initialRoleFilter) {
      final next = _roleFromWidget();
      if (next != _selectedRole) {
        setState(() => _selectedRole = next);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Build colored status pill similar to reference UI
  Widget _buildStatusChip(UserModel user) {
    String label = '';
    Color bg = Colors.grey.shade200;
    Color fg = Colors.grey.shade800;

    if (user.role == 'client') {
      if (user.isVerified) {
        label = 'Verified';
        bg = Colors.green.withOpacity(0.12);
        fg = Colors.green.shade700;
      } else {
        label = 'Not Verified';
        bg = Colors.red.withOpacity(0.1);
        fg = Colors.red.shade700;
      }
    } else if (user.role == 'attorney') {
      if (user.isAvailable == true) {
        label = 'Active';
        bg = AppTheme.royalBlue.withOpacity(0.12);
        fg = AppTheme.royalBlue;
      } else {
        label = 'Unavailable';
        bg = Colors.orange.withOpacity(0.15);
        fg = Colors.orange.shade800;
      }
    } else if (user.role == 'staff' || user.role == 'admin') {
      if (!user.isActive) {
        label = 'Sign-in disabled';
        bg = Colors.red.withOpacity(0.1);
        fg = Colors.red.shade800;
      } else {
        label = 'Active';
        bg = Colors.blueGrey.withOpacity(0.12);
        fg = Colors.blueGrey.shade700;
      }
    } else {
      label = 'Active';
      bg = Colors.blueGrey.withOpacity(0.12);
      fg = Colors.blueGrey.shade700;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: fg,
        ),
      ),
    );
  }

  Future<void> _deleteUser(String userId) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Delete User'),
        content: const Text(
          'Delete this user from the database? A backup copy is saved automatically; '
          'you can recover the Firestore profile from Backup (Firebase Auth login is separate).',
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final result = await _adminService.deleteUser(userId);
      Get.snackbar(
        result['success'] == true ? 'Success' : 'Error',
        result['message'] ?? 'Unknown error',
        backgroundColor:
            result['success'] == true ? Colors.green : Colors.red,
        colorText: Colors.white,
      );
    }
  }

  Widget _buildBody() {
    return Column(
      children: [
        // Search and Filter
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  hintText: 'Search users by name or email...',
                  prefixIcon: const Icon(Icons.search, color: AppTheme.mutedText),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppTheme.borderGray, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppTheme.borderGray, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: AppTheme.royalBlue, width: 2),
                  ),
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value.toLowerCase());
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    'Filter by Role:',
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          color: AppTheme.mutedText,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppTheme.borderGray,
                          width: 1,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedRole,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('All')),
                            DropdownMenuItem(
                              value: 'client',
                              child: Text('Clients'),
                            ),
                            DropdownMenuItem(
                              value: 'attorney',
                              child: Text('Attorneys'),
                            ),
                            DropdownMenuItem(
                              value: 'staff',
                              child: Text('Staff'),
                            ),
                            DropdownMenuItem(
                              value: 'admin',
                              child: Text('Admins'),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedRole = value!);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // User List
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _firestore.collection('users').snapshots(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final users = snapshot.data?.docs ?? [];
              final filteredUsers = users.where((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final role = data['role'] ?? 'client';
                final name = (data['name'] ?? '').toString().toLowerCase();
                final email = (data['email'] ?? '').toString().toLowerCase();

                final roleMatch =
                    _selectedRole == 'all' || role == _selectedRole;
                final searchMatch =
                    _searchQuery.isEmpty ||
                    name.contains(_searchQuery) ||
                    email.contains(_searchQuery);

                return roleMatch && searchMatch;
              }).toList();

              if (filteredUsers.isEmpty) {
                return const Center(child: Text('No users found'));
              }

              return Column(
                children: [
                  // Header row
                  Container(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.borderGray,
                        width: 1,
                      ),
                    ),
                    child: Row(
                      children: const [
                        Expanded(flex: 2, child: Text('Name')),
                        Expanded(flex: 3, child: Text('Email')),
                        Expanded(flex: 1, child: Text('Role')),
                        Expanded(flex: 1, child: Text('Status')),
                        SizedBox(width: 40), // space for actions
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Rows
                  Expanded(
                    child: ListView.builder(
                      itemCount: filteredUsers.length,
                      itemBuilder: (context, index) {
                        final userDoc = filteredUsers[index];
                        final userData =
                            userDoc.data() as Map<String, dynamic>;
                        final user =
                            UserModel.fromFirestore(userData, userDoc.id);

                        return Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.03),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              // Name + avatar
                              Expanded(
                                flex: 2,
                                child: Row(
                                  children: [
                                    SafeNetworkAvatar(
                                      photoUrl: user.photoUrl,
                                      radius: 18,
                                      fallbackLetter: user.name.isNotEmpty
                                          ? user.name[0]
                                          : 'U',
                                      backgroundColor:
                                          AppTheme.royalBlue.withOpacity(0.12),
                                      foregroundColor: AppTheme.royalBlue,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        user.name,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium!
                                            .copyWith(
                                              fontWeight: FontWeight.w600,
                                              color: AppTheme.textPrimary,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Email
                              Expanded(
                                flex: 3,
                                child: Text(
                                  user.email,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall!
                                      .copyWith(color: AppTheme.mutedText),
                                ),
                              ),
                              // Role
                              Expanded(
                                flex: 1,
                                child: Text(
                                  user.role,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall!
                                      .copyWith(color: AppTheme.mutedText),
                                ),
                              ),
                              // Status pill
                              Expanded(
                                flex: 1,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _buildStatusChip(user),
                                ),
                              ),
                              // Actions
                              PopupMenuButton(
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    child: const Row(
                                      children: [
                                        Icon(Icons.edit, size: 20),
                                        SizedBox(width: 8),
                                        Text('Edit'),
                                      ],
                                    ),
                                    onTap: () {
                                      Future.delayed(
                                        const Duration(milliseconds: 100),
                                        () => _showEditUserDialog(user),
                                      );
                                    },
                                  ),
                                  if (user.role == 'attorney')
                                    PopupMenuItem(
                                      child: const Row(
                                        children: [
                                          Icon(Icons.block, size: 20),
                                          SizedBox(width: 8),
                                          Text('Deactivate'),
                                        ],
                                      ),
                                      onTap: () {
                                        Future.delayed(
                                          const Duration(milliseconds: 100),
                                          () => _deactivateUser(user.id),
                                        );
                                      },
                                    ),
                                  PopupMenuItem(
                                    child: const Row(
                                      children: [
                                        Icon(Icons.lock_reset, size: 20),
                                        SizedBox(width: 8),
                                        Text('Reset Password'),
                                      ],
                                    ),
                                    onTap: () {
                                      Future.delayed(
                                        const Duration(milliseconds: 100),
                                        () => _resetPassword(user.id),
                                      );
                                    },
                                  ),
                                  PopupMenuItem(
                                    child: const Row(
                                      children: [
                                        Icon(Icons.sms_outlined, size: 20),
                                        SizedBox(width: 8),
                                        Text('Send SMS'),
                                      ],
                                    ),
                                    onTap: () {
                                      Future.delayed(
                                        const Duration(milliseconds: 100),
                                        () => _showSendUserSmsDialog(user),
                                      );
                                    },
                                  ),
                                  PopupMenuItem(
                                    child: const Row(
                                      children: [
                                        Icon(Icons.swap_horiz, size: 20),
                                        SizedBox(width: 8),
                                        Text('Change Role'),
                                      ],
                                    ),
                                    onTap: () {
                                      Future.delayed(
                                        const Duration(milliseconds: 100),
                                        () => _showChangeRoleDialog(user),
                                      );
                                    },
                                  ),
                                  PopupMenuItem(
                                    child: Row(
                                      children: const [
                                        Icon(
                                          Icons.delete_outline,
                                          size: 20,
                                          color: Colors.red,
                                        ),
                                        SizedBox(width: 8),
                                        Text(
                                          'Delete User',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      Future.delayed(
                                        const Duration(milliseconds: 100),
                                        () => _deleteUser(user.id),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();

    if (widget.inline) {
      return Column(
        children: [
          // Custom header bar for inline mode
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
                  'User Management',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showAddAttorneyDialog(),
                  tooltip: 'Add Attorney',
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
        title: const Text('User Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddAttorneyDialog(),
            tooltip: 'Add Attorney',
          ),
        ],
      ),
      body: body,
    );
  }

  void _showAddAttorneyDialog() {
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final specializationController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Attorney'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: specializationController,
                decoration: const InputDecoration(
                  labelText: 'Specializations (comma-separated)',
                  border: OutlineInputBorder(),
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
              if (nameController.text.trim().isEmpty ||
                  emailController.text.trim().isEmpty) {
                Get.snackbar(
                  'Error',
                  'Please fill in all required fields',
                  backgroundColor: Colors.red,
                  colorText: Colors.white,
                );
                return;
              }

              Navigator.pop(context);

              // Show loading
              Get.dialog(
                const Center(child: CircularProgressIndicator()),
                barrierDismissible: false,
              );

              final result = await _adminService.createAttorney(
                name: nameController.text.trim(),
                email: emailController.text.trim(),
                specialization: specializationController.text.trim(),
              );

              Get.back(); // Close loading dialog

              Get.snackbar(
                result['success'] == true ? 'Success' : 'Error',
                result['message'] ?? 'Unknown error',
                backgroundColor: result['success'] == true
                    ? Colors.green
                    : Colors.red,
                colorText: Colors.white,
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showEditUserDialog(UserModel user) async {
    // Get current user data from Firestore to check isActive
    final userDoc = await _firestore.collection('users').doc(user.id).get();
    final userData = userDoc.data() ?? {};
    final isActive = userData['isActive'] ?? true;

    final nameController = TextEditingController(text: user.name);
    final emailController = TextEditingController(text: user.email);
    final specializationController = TextEditingController(
      text: (user.specialization ?? []).join(', '),
    );
    bool currentIsActive = isActive as bool;
    bool isAvailable = user.isAvailable ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit User'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
                if (user.role == 'attorney') ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: specializationController,
                    decoration: const InputDecoration(
                      labelText: 'Specializations (comma-separated)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    title: const Text('Available'),
                    value: isAvailable,
                    onChanged: (value) {
                      setState(() => isAvailable = value ?? false);
                    },
                  ),
                ],
                const SizedBox(height: 16),
                CheckboxListTile(
                  title: const Text('Active'),
                  value: currentIsActive,
                  onChanged: (value) {
                    setState(() => currentIsActive = value ?? false);
                  },
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
                Navigator.pop(context);

                Get.dialog(
                  const Center(child: CircularProgressIndicator()),
                  barrierDismissible: false,
                );

                final specializations =
                    user.role == 'attorney' &&
                        specializationController.text.trim().isNotEmpty
                    ? specializationController.text
                          .split(',')
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList()
                    : null;

                final result = await _adminService.updateUserInfo(
                  userId: user.id,
                  name: nameController.text.trim(),
                  email: emailController.text.trim(),
                  isActive: currentIsActive,
                  isAvailable: user.role == 'attorney' ? isAvailable : null,
                  specializations: specializations,
                );

                Get.back(); // Close loading dialog

                Get.snackbar(
                  result['success'] == true ? 'Success' : 'Error',
                  result['message'] ?? 'Unknown error',
                  backgroundColor: result['success'] == true
                      ? Colors.green
                      : Colors.red,
                  colorText: Colors.white,
                );
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deactivateUser(String userId) async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: const Text('Deactivate User'),
        content: const Text('Are you sure you want to deactivate this user?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Get.back(result: true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _adminService.deactivateUser(userId);
        Get.snackbar(
          'Success',
          'User deactivated successfully',
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
      } catch (e) {
        Get.snackbar(
          'Error',
          'Failed to deactivate user: $e',
          backgroundColor: Colors.red,
          colorText: Colors.white,
        );
      }
    }
  }

  Future<void> _resetPassword(String userId) async {
    try {
      await _adminService.resetUserPassword(userId);
      Get.snackbar(
        'Success',
        'Password reset email sent',
        backgroundColor: Colors.green,
        colorText: Colors.white,
      );
    } catch (e) {
      Get.snackbar(
        'Error',
        'Failed to reset password: $e',
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
    }
  }

  void _showSendUserSmsDialog(UserModel user) {
    final phoneRaw = (user.phone ?? user.phoneNumber ?? '').trim();
    final phoneController = TextEditingController(text: phoneRaw);
    final messageController = TextEditingController();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('Send SMS — ${user.name}'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone (09… or +63…)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: messageController,
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              phoneController.dispose();
              messageController.dispose();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final to = phoneController.text.trim();
              final msg = messageController.text.trim();
              if (to.isEmpty || msg.isEmpty) {
                Get.snackbar(
                  'Missing fields',
                  'Enter a phone number and message.',
                  backgroundColor: Colors.orange,
                  colorText: Colors.white,
                );
                return;
              }
              Navigator.pop(ctx);
              phoneController.dispose();
              messageController.dispose();

              Get.dialog(
                const Center(child: CircularProgressIndicator()),
                barrierDismissible: false,
              );
              final result = await _adminService.queueManualSms(
                to: to,
                body: msg,
                relatedUserId: user.id,
              );
              if (Get.isDialogOpen ?? false) Get.back();

              Get.snackbar(
                result['success'] == true ? 'SMS' : 'Error',
                result['message']?.toString() ?? 'Unknown',
                backgroundColor:
                    result['success'] == true ? Colors.green : Colors.red,
                colorText: Colors.white,
                duration: const Duration(seconds: 4),
              );
            },
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _showChangeRoleDialog(UserModel user) {
    String selectedRole = user.role;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change Role'),
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<String>(
                value: selectedRole,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'client', child: Text('Client')),
                  DropdownMenuItem(value: 'attorney', child: Text('Attorney')),
                  DropdownMenuItem(value: 'staff', child: Text('Staff')),
                  DropdownMenuItem(value: 'admin', child: Text('Admin')),
                ],
                onChanged: (value) {
                  setState(() => selectedRole = value!);
                },
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
              if (selectedRole != user.role) {
                try {
                  await _adminService.updateUserRole(user.id, selectedRole);
                  Get.snackbar(
                    'Success',
                    'User role updated successfully',
                    backgroundColor: Colors.green,
                    colorText: Colors.white,
                  );
                  Navigator.pop(context);
                } catch (e) {
                  Get.snackbar(
                    'Error',
                    'Failed to update role: $e',
                    backgroundColor: Colors.red,
                    colorText: Colors.white,
                  );
                }
              } else {
                Navigator.pop(context);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }
}
