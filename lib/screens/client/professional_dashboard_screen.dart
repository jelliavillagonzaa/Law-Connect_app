import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/case_model.dart';
import '../../services/case_service.dart';
import '../../services/auth_service.dart';
import 'case_details_screen.dart';

class ProfessionalDashboardScreen extends StatefulWidget {
  const ProfessionalDashboardScreen({super.key});

  @override
  State<ProfessionalDashboardScreen> createState() => _ProfessionalDashboardScreenState();
}

class _ProfessionalDashboardScreenState extends State<ProfessionalDashboardScreen> {
  final CaseService _caseService = CaseService();
  final AuthService _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  
  String _selectedFilter = 'All';
  List<CaseModel> _allCases = [];
  List<CaseModel> _filteredCases = [];
  bool _isLoading = true;
  
  // Summary counts
  int _totalCases = 0;
  int _activeCases = 0;
  int _completedCases = 0;
  int _declinedCases = 0;
  
  String? _currentUserId;

  // Color constants
  static const Color primaryRed = Color(0xFF1A4D8F); // Royal Blue

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final user = _authService.currentUser;
      if (user != null) {
        setState(() {
          _currentUserId = user.uid;
        });
        _loadCases();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _loadCases() {
    if (_currentUserId == null) return;
    
    _caseService.getCasesForUser(_currentUserId!, 'client').listen((cases) {
      setState(() {
        _allCases = cases;
        _updateSummaryCounts();
        _applyFilter();
        _isLoading = false;
      });
    }).onError((error) {
      setState(() {
        _isLoading = false;
      });
    });
  }

  void _updateSummaryCounts() {
    _totalCases = _allCases.length;
    _activeCases = _allCases.where((c) => c.status == 'accepted' || c.status == 'in_progress').length;
    _completedCases = _allCases.where((c) => c.status == 'completed').length;
    _declinedCases = _allCases.where((c) => c.status == 'declined').length;
  }

  void _applyFilter() {
    if (_selectedFilter == 'All') {
      _filteredCases = _allCases;
    } else {
      String status = _selectedFilter.toLowerCase();
      if (status == 'accepted') {
        _filteredCases = _allCases.where((c) => c.status == 'accepted' || c.status == 'in_progress').toList();
      } else {
        _filteredCases = _allCases.where((c) => c.status == status).toList();
      }
    }
    
    // Apply search filter if any
    if (_searchController.text.isNotEmpty) {
      final query = _searchController.text.toLowerCase();
      _filteredCases = _filteredCases.where((c) {
        return c.caseTitle.toLowerCase().contains(query) ||
               c.caseType.toLowerCase().contains(query) ||
               c.caseDescription.toLowerCase().contains(query);
      }).toList();
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'criminal':
        return Icons.gavel_rounded;
      case 'civil':
        return Icons.balance_rounded;
      case 'family':
        return Icons.family_restroom_rounded;
      case 'corporate':
        return Icons.business_rounded;
      case 'real estate':
        return Icons.home_work_rounded;
      case 'immigration':
        return Icons.airplane_ticket_rounded;
      default:
        return Icons.description_rounded;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'accepted':
      case 'in_progress':
        return Colors.blue;
      case 'pending':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'declined':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _formatStatus(String status) {
    switch (status.toLowerCase()) {
      case 'in_progress':
        return 'Active';
      case 'accepted':
        return 'Accepted';
      case 'pending':
        return 'Pending';
      case 'completed':
        return 'Completed';
      case 'declined':
        return 'Declined';
      default:
        return status;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          children: [
            // Top Navbar
            _buildTopNavbar(),
            
            // Content
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () async {
                        _loadCases();
                      },
                      child: SingleChildScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Summary Cards
                            _buildSummaryCards(),
                            const SizedBox(height: 24),
                            
                            // Filter Chips
                            _buildFilterChips(),
                            const SizedBox(height: 16),
                            
                            // Cases List
                            _buildCasesList(),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopNavbar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Profile Avatar
          CircleAvatar(
            radius: 20,
            backgroundColor: primaryRed.withOpacity(0.1),
            child: Text(
              'U',
              style: TextStyle(
                color: primaryRed,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Search Bar
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (_) {
                  setState(() {
                    _applyFilter();
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search cases...',
                  hintStyle: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(Icons.search, color: Colors.grey[600], size: 20),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          
          // Messages Icon
          _buildNavIcon(Icons.chat_bubble_outline_rounded, () {
            // Navigate to messages
          }),
          const SizedBox(width: 8),
          
          // Notifications Icon
          _buildNavIcon(Icons.notifications_outlined, () {
            // Navigate to notifications
          }, hasBadge: true),
        ],
      ),
    );
  }

  Widget _buildNavIcon(IconData icon, VoidCallback onTap, {bool hasBadge = false}) {
    return Stack(
      children: [
        IconButton(
          icon: Icon(icon, color: Colors.grey[800], size: 24),
          onPressed: onTap,
        ),
        if (hasBadge)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: primaryRed,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            'Total Cases',
            _totalCases.toString(),
            Icons.folder_copy_rounded,
            primaryRed,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            'Active',
            _activeCases.toString(),
            Icons.trending_up_rounded,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            'Completed',
            _completedCases.toString(),
            Icons.check_circle_outline_rounded,
            Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildSummaryCard(
            'Declined',
            _declinedCases.toString(),
            Icons.cancel_outlined,
            Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey[900],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All', 'Accepted', 'Pending', 'Completed', 'Declined'];
    
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        itemBuilder: (context, index) {
          final filter = filters[index];
          final isSelected = _selectedFilter == filter;
          
          return Padding(
            padding: EdgeInsets.only(right: index < filters.length - 1 ? 8 : 0),
            child: FilterChip(
              label: Text(filter),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  _selectedFilter = filter;
                  _applyFilter();
                });
              },
              selectedColor: primaryRed,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.grey[700],
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              backgroundColor: Colors.white,
              side: BorderSide(
                color: isSelected ? primaryRed : Colors.grey[300]!,
                width: 1,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCasesList() {
    if (_filteredCases.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            children: [
              Icon(Icons.folder_open_rounded, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'No cases found',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredCases.length,
      itemBuilder: (context, index) {
        final caseItem = _filteredCases[index];
        return _buildCaseCard(caseItem);
      },
    );
  }

  Widget _buildCaseCard(CaseModel caseItem) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CaseDetailsScreen(caseId: caseItem.id),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: Title and Status
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category Icon
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: primaryRed.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _getCategoryIcon(caseItem.caseType),
                      color: primaryRed,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // Title and Category
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          caseItem.caseTitle,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey[900],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.category_rounded,
                              size: 14,
                              color: Colors.grey[600],
                            ),
                            const SizedBox(width: 4),
                            Text(
                              caseItem.caseType,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Status Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _getStatusColor(caseItem.status).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _getStatusColor(caseItem.status),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      _formatStatus(caseItem.status),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(caseItem.status),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
              // Description
              Text(
                caseItem.caseDescription,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  height: 1.4,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              
              const SizedBox(height: 12),
              
              // Dates
              Row(
                children: [
                  _buildDateInfo(
                    Icons.calendar_today_rounded,
                    'Created: ${DateFormat('MMM dd, yyyy').format(caseItem.createdAt)}',
                  ),
                  const SizedBox(width: 16),
                  _buildDateInfo(
                    Icons.update_rounded,
                    'Updated: ${DateFormat('MMM dd, yyyy').format(caseItem.updatedAt)}',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

}

