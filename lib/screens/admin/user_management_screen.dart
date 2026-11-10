import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/admin_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/admin/admin_page_header.dart';
import '../../widgets/admin/admin_ui_theme.dart';
import '../../widgets/common/safe_network_avatar.dart';

class UserManagementScreen extends StatefulWidget {
  final bool inline;
  /// When set (e.g. from admin dashboard stat cards), pre-selects the role filter.
  final String? initialRoleFilter;
  /// When set (e.g. from admin header search), pre-fills the name/email search.
  final String? initialSearchQuery;

  const UserManagementScreen({
    super.key,
    this.inline = false,
    this.initialRoleFilter,
    this.initialSearchQuery,
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

  void _applyInitialSearch() {
    final q = widget.initialSearchQuery?.trim() ?? '';
    _searchController.value = TextEditingValue(
      text: q,
      selection: TextSelection.collapsed(offset: q.length),
    );
    _searchQuery = q.toLowerCase();
  }

  @override
  void initState() {
    super.initState();
    _selectedRole = _roleFromWidget();
    _applyInitialSearch();
  }

  @override
  void didUpdateWidget(UserManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final roleChanged =
        widget.initialRoleFilter != oldWidget.initialRoleFilter;
    final searchChanged =
        widget.initialSearchQuery != oldWidget.initialSearchQuery;
    if (!roleChanged && !searchChanged) return;
    setState(() {
      if (roleChanged) {
        _selectedRole = _roleFromWidget();
      }
      if (searchChanged) {
        _applyInitialSearch();
      }
    });
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
                  prefixIcon: const Icon(Icons.search, color: AdminUi.muted),
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
                    borderRadius: BorderRadius.circular(AdminUi.radius),
                    borderSide:
                        const BorderSide(color: AdminUi.line, width: 1),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AdminUi.radius),
                    borderSide:
                        const BorderSide(color: AdminUi.line, width: 1),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AdminUi.radius),
                    borderSide:
                        const BorderSide(color: AdminUi.primary, width: 2),
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
                        borderRadius: BorderRadius.circular(AdminUi.radius),
                        border: Border.all(
                          color: AdminUi.line,
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
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
                return const SizedBox.shrink();
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
                      borderRadius: BorderRadius.circular(AdminUi.radius),
                      boxShadow: AdminUi.cardShadow,
                      border: Border.all(
                        color: AdminUi.line,
                        width: 1,
                      ),
                    ),
                    child: const Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Text(
                            'Name',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AdminUi.text,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Text(
                            'Email',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AdminUi.text,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Role',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AdminUi.text,
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            'Status',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: AdminUi.text,
                            ),
                          ),
                        ),
                        SizedBox(width: 40),
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
                            borderRadius: BorderRadius.circular(AdminUi.radius),
                            boxShadow: AdminUi.cardShadow,
                            border: Border.all(color: AdminUi.line),
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
      return ColoredBox(
        color: AdminUi.background,
        child: Column(
          children: [
            AdminPageHeader(
              title: 'User Management',
              actions: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AdminUi.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.person_add_rounded, size: 18),
                  label: const Text('Add Member', style: TextStyle(fontWeight: FontWeight.w600)),
                  onPressed: () => _showAddMemberDialog(),
                ),
              ],
            ),
            Expanded(child: body),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded),
            onPressed: () => _showAddMemberDialog(),
            tooltip: 'Add Member (Attorney / Staff)',
          ),
        ],
      ),
      body: body,
    );
  }

  static const List<String> _defaultSpecializations = [
    'Criminal Law',
    'Family Law',
    'Labor & Employment',
    'Civil Litigation',
    'Corporate & Commercial',
    'Real Estate & Property',
    'Immigration Law',
    'Taxation Law',
    'Intellectual Property',
    'Agrarian Law',
    'Human Rights',
    'Environmental Law',
  ];

  void _showAddMemberDialog({String? initialRole}) {
    String currentRole = initialRole ?? (_selectedRole == 'staff' ? 'staff' : 'attorney');
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final passwordController = TextEditingController(text: 'LawConnect2026!');
    final customSpecController = TextEditingController();

    // Attorney state
    final selectedSpecializations = <String>{'General Law', 'Criminal Law'};
    bool isAvailable = true;

    // Staff state
    String selectedTitle = 'Paralegal';
    String selectedAttorneyId = '';
    List<Map<String, dynamic>> attorneysList = [];
    bool isLoadingAttorneys = true;
    bool obscurePassword = false;
    bool isSubmitting = false;

    // Preload attorneys for staff assignment
    _adminService.getAllAttorneys().then((list) {
      attorneysList = list;
      isLoadingAttorneys = false;
    }).catchError((_) {
      isLoadingAttorneys = false;
    });

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (isLoadingAttorneys && attorneysList.isEmpty) {
            _adminService.getAllAttorneys().then((list) {
              if (dialogCtx.mounted) {
                setDialogState(() {
                  attorneysList = list;
                  isLoadingAttorneys = false;
                });
              }
            });
          }

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 580),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AdminUi.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.person_add_rounded, color: AdminUi.primary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Add Organization Member',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  'Create a new ${currentRole == 'attorney' ? 'Attorney' : 'Staff'} account with direct credentials',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Role Switcher Tabs
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: isSubmitting ? null : () => setDialogState(() => currentRole = 'attorney'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    color: currentRole == 'attorney' ? AdminUi.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.gavel_rounded,
                                        size: 16,
                                        color: currentRole == 'attorney' ? Colors.white : Colors.grey.shade700,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Attorney / Lawyer',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: currentRole == 'attorney' ? Colors.white : Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: isSubmitting ? null : () => setDialogState(() => currentRole = 'staff'),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 9),
                                  decoration: BoxDecoration(
                                    color: currentRole == 'staff' ? AdminUi.primary : Colors.transparent,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        Icons.badge_outlined,
                                        size: 16,
                                        color: currentRole == 'staff' ? Colors.white : Colors.grey.shade700,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Staff / Assistant',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: currentRole == 'staff' ? Colors.white : Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Basic Details
                      TextField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: currentRole == 'attorney' ? 'Attorney Full Name *' : 'Staff Full Name *',
                          hintText: currentRole == 'attorney' ? 'e.g. Atty. Juan Dela Cruz' : 'e.g. Maria Santos',
                          prefixIcon: const Icon(Icons.person_outline_rounded, size: 20),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email Address *',
                          hintText: 'e.g. user@lawfirm.com',
                          prefixIcon: Icon(Icons.email_outlined, size: 20),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      TextField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Phone Number (Optional)',
                          hintText: 'e.g. +63 912 345 6789',
                          prefixIcon: Icon(Icons.phone_outlined, size: 20),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Password Field
                      TextField(
                        controller: passwordController,
                        obscureText: obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Initial Password *',
                          helperText: 'User can log in with this initial password immediately.',
                          prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                  size: 20,
                                ),
                                tooltip: obscurePassword ? 'Show password' : 'Hide password',
                                onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                              ),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 18),
                                tooltip: 'Copy password',
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: passwordController.text));
                                  Get.snackbar(
                                    'Copied',
                                    'Password copied to clipboard',
                                    snackPosition: SnackPosition.BOTTOM,
                                    duration: const Duration(seconds: 2),
                                  );
                                },
                              ),
                            ],
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Role Specific Fields
                      if (currentRole == 'attorney') ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: const [
                            Icon(Icons.verified_outlined, size: 16, color: AdminUi.primary),
                            SizedBox(width: 6),
                            Text(
                              'Specializations / Practice Areas',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Select the fields of law this attorney specializes in (used for client matching):',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            ..._defaultSpecializations.map((spec) {
                              final isSelected = selectedSpecializations.contains(spec);
                              return FilterChip(
                                label: Text(spec),
                                selected: isSelected,
                                selectedColor: AdminUi.primary.withOpacity(0.18),
                                checkmarkColor: AdminUi.primary,
                                labelStyle: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? AdminUi.primary : Colors.grey.shade800,
                                ),
                                onSelected: (selected) {
                                  setDialogState(() {
                                    if (selected) {
                                      selectedSpecializations.add(spec);
                                    } else {
                                      selectedSpecializations.remove(spec);
                                    }
                                  });
                                },
                              );
                            }),
                            ...selectedSpecializations
                                .where((s) => !_defaultSpecializations.contains(s))
                                .map((customSpec) {
                              return Chip(
                                label: Text(customSpec),
                                backgroundColor: AdminUi.primary.withOpacity(0.18),
                                deleteIcon: const Icon(Icons.close, size: 14),
                                onDeleted: () {
                                  setDialogState(() {
                                    selectedSpecializations.remove(customSpec);
                                  });
                                },
                              );
                            }),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: customSpecController,
                                decoration: const InputDecoration(
                                  hintText: 'Add custom specialization...',
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                ),
                                onSubmitted: (val) {
                                  final t = val.trim();
                                  if (t.isNotEmpty) {
                                    setDialogState(() {
                                      selectedSpecializations.add(t);
                                      customSpecController.clear();
                                    });
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.add, size: 16),
                              label: const Text('Add Tag'),
                              onPressed: () {
                                final t = customSpecController.text.trim();
                                if (t.isNotEmpty) {
                                  setDialogState(() {
                                    selectedSpecializations.add(t);
                                    customSpecController.clear();
                                  });
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Available for New Consultations', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Clients can book consultations and assign new cases immediately', style: TextStyle(fontSize: 11)),
                          value: isAvailable,
                          onChanged: (val) => setDialogState(() => isAvailable = val),
                        ),
                      ] else ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          children: const [
                            Icon(Icons.assignment_ind_outlined, size: 16, color: AdminUi.primary),
                            SizedBox(width: 6),
                            Text(
                              'Staff Role & Assignment',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: selectedTitle,
                          decoration: const InputDecoration(
                            labelText: 'Staff Position / Title',
                            prefixIcon: Icon(Icons.work_outline_rounded, size: 20),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Paralegal', child: Text('Paralegal')),
                            DropdownMenuItem(value: 'Legal Secretary', child: Text('Legal Secretary')),
                            DropdownMenuItem(value: 'Legal Assistant', child: Text('Legal Assistant')),
                            DropdownMenuItem(value: 'Administrative Officer', child: Text('Administrative Officer')),
                            DropdownMenuItem(value: 'Case Coordinator', child: Text('Case Coordinator')),
                          ],
                          onChanged: (val) {
                            if (val != null) setDialogState(() => selectedTitle = val);
                          },
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selectedAttorneyId,
                          decoration: const InputDecoration(
                            labelText: 'Assigned Attorney',
                            prefixIcon: Icon(Icons.gavel_outlined, size: 20),
                            border: OutlineInputBorder(),
                            isDense: true,
                            helperText: 'Staff will have access to cases and calendar for this attorney.',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('(None / General Firm Support)'),
                            ),
                            ...attorneysList.map((attorney) {
                              final attyId = attorney['id'] as String? ?? '';
                              final attyName = attorney['name'] as String? ?? 'Attorney';
                              return DropdownMenuItem(
                                value: attyId,
                                child: Text('Atty. $attyName'),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            if (val != null) setDialogState(() => selectedAttorneyId = val);
                          },
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Action Buttons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AdminUi.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: isSubmitting
                                ? null
                                : () async {
                                    final name = nameController.text.trim();
                                    final email = emailController.text.trim();
                                    final password = passwordController.text.trim();
                                    final phone = phoneController.text.trim();

                                    if (name.isEmpty || email.isEmpty) {
                                      Get.snackbar(
                                        'Required Fields',
                                        'Please provide both name and email address.',
                                        backgroundColor: Colors.red,
                                        colorText: Colors.white,
                                      );
                                      return;
                                    }

                                    if (password.length < 6) {
                                      Get.snackbar(
                                        'Weak Password',
                                        'Password must be at least 6 characters.',
                                        backgroundColor: Colors.red,
                                        colorText: Colors.white,
                                      );
                                      return;
                                    }

                                    setDialogState(() => isSubmitting = true);

                                    Map<String, dynamic> result;
                                    if (currentRole == 'attorney') {
                                      result = await _adminService.createAttorney(
                                        name: name,
                                        email: email,
                                        password: password,
                                        phone: phone.isNotEmpty ? phone : null,
                                        specializations: selectedSpecializations.toList(),
                                        isAvailable: isAvailable,
                                      );
                                    } else {
                                      result = await _adminService.createStaffUser(
                                        email: email,
                                        name: name,
                                        password: password,
                                        assignedAttorneyId: selectedAttorneyId.isNotEmpty ? selectedAttorneyId : null,
                                        staffTitle: selectedTitle,
                                        phone: phone.isNotEmpty ? phone : null,
                                      );
                                    }

                                    if (!dialogCtx.mounted) return;

                                    if (result['success'] == true) {
                                      Navigator.pop(dialogCtx);
                                      setState(() {});

                                      // Show credentials confirmation dialog
                                      Get.dialog(
                                        AlertDialog(
                                          title: Row(
                                            children: const [
                                              Icon(Icons.check_circle, color: Colors.green),
                                              SizedBox(width: 8),
                                              Text('Account Created!'),
                                            ],
                                          ),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'The ${currentRole == 'attorney' ? 'Attorney' : 'Staff'} account for "$name" was successfully registered.',
                                              ),
                                              const SizedBox(height: 12),
                                              Container(
                                                padding: const EdgeInsets.all(12),
                                                decoration: BoxDecoration(
                                                  color: Colors.grey.shade100,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.grey.shade300),
                                                ),
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text('Email: $email', style: const TextStyle(fontWeight: FontWeight.bold)),
                                                    const SizedBox(height: 4),
                                                    Text('Password: $password', style: const TextStyle(fontWeight: FontWeight.bold)),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          actions: [
                                            OutlinedButton.icon(
                                              icon: const Icon(Icons.copy, size: 16),
                                              label: const Text('Copy Login Info'),
                                              onPressed: () {
                                                Clipboard.setData(ClipboardData(
                                                  text: 'LawConnect Account Credentials:\nEmail: $email\nPassword: $password',
                                                ));
                                                Get.snackbar('Copied', 'Login details copied to clipboard');
                                              },
                                            ),
                                            ElevatedButton(
                                              onPressed: () => Get.back(),
                                              child: const Text('Done'),
                                            ),
                                          ],
                                        ),
                                      );
                                    } else {
                                      setDialogState(() => isSubmitting = false);
                                      Get.snackbar(
                                        'Error',
                                        result['message'] ?? 'Failed to create account',
                                        backgroundColor: Colors.red,
                                        colorText: Colors.white,
                                      );
                                    }
                                  },
                            icon: isSubmitting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                  )
                                : const Icon(Icons.check_circle_outline, size: 18),
                            label: Text(
                              isSubmitting
                                  ? 'Creating...'
                                  : (currentRole == 'attorney' ? 'Add Attorney' : 'Add Staff'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
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

    if (!mounted) return;
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

  /// "From admin: …." — careful wording, always ends with a period.
  String? _adminSmsBody(String raw) {
    var text = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.isEmpty) return null;
    final letters = RegExp(r'[A-Za-z]').allMatches(text).length;
    if (letters < 3) return null;
    text = text[0].toUpperCase() + text.substring(1);
    if (!text.endsWith('.')) {
      text = text.replaceFirst(RegExp(r'[!?]+$'), '');
      text = '$text.';
    }
    final lower = text.toLowerCase();
    if (lower.startsWith('from admin:') || lower.startsWith('from admin ')) {
      return text;
    }
    return 'From admin: $text';
  }

  void _showSendUserSmsDialog(UserModel user) {
    final phoneRaw = (user.phone ?? user.phoneNumber ?? '').trim();
    final phoneController = TextEditingController(text: phoneRaw);
    final messageController = TextEditingController();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final preview = _adminSmsBody(messageController.text);
          return AlertDialog(
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
              const Text(
                'From admin',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Added automatically. Write a clear sentence. It will end with a period.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: messageController,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Message',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
                maxLines: 4,
              ),
              if (preview != null) ...[
                const SizedBox(height: 8),
                Text(
                  preview,
                  style: const TextStyle(fontSize: 13, height: 1.3),
                ),
              ],
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
              final msg = _adminSmsBody(messageController.text);
              if (to.isEmpty || msg == null) {
                Get.snackbar(
                  'Missing fields',
                  'Enter a phone number and a clear message. It is sent as “From admin: ….”',
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
      );
        },
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
