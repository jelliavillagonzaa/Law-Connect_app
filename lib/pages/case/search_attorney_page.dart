import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../services/search_service.dart';
import '../../models/user_model.dart';
import '../../widgets/common/rating_widget.dart';
import '../../widgets/common/safe_network_avatar.dart';
import '../chat/chat_page.dart';

class SearchAttorneyPage extends StatefulWidget {
  const SearchAttorneyPage({super.key});

  @override
  State<SearchAttorneyPage> createState() => _SearchAttorneyPageState();
}

class _SearchAttorneyPageState extends State<SearchAttorneyPage> {
  final _searchController = TextEditingController();
  final SearchService _searchService = SearchService();
  
  List<UserModel> _attorneys = [];
  List<String> _suggestions = [];
  bool _isLoading = false;
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _suggestions = _searchService.getAllCaseTypes();
    _loadAvailableAttorneys();
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    setState(() {
      _showSuggestions = query.isNotEmpty;
      _suggestions = _searchService.getCaseTypeSuggestions(query);
    });
    
    if (query.isNotEmpty) {
      _searchAttorneys(query);
    } else {
      _loadAvailableAttorneys();
    }
  }

  Future<void> _loadAvailableAttorneys() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final attorneys = await _searchService.getAvailableAttorneys();
      setState(() {
        _attorneys = attorneys;
        _isLoading = false;
      });
    } catch (e) {
      Get.snackbar('Error', 'Failed to load attorneys: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _searchAttorneys(String query) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final attorneys = await _searchService.searchAttorneysBySpecialization(query);
      setState(() {
        _attorneys = attorneys;
        _isLoading = false;
      });
    } catch (e) {
      Get.snackbar('Error', 'Failed to search attorneys: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Attorneys'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Search by case type or specialization',
                hintText: 'e.g., child abuse, theft, cybercrime',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          if (_showSuggestions && _suggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _suggestions.take(5).map((suggestion) {
                  return ListTile(
                    title: Text(suggestion),
                    onTap: () {
                      _searchController.text = suggestion;
                      setState(() {
                        _showSuggestions = false;
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _attorneys.isEmpty
                    ? const Center(
                        child: Text('No attorneys found'),
                      )
                    : ListView.builder(
                        itemCount: _attorneys.length,
                        itemBuilder: (context, index) {
                          final attorney = _attorneys[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            child: ListTile(
                              leading: SafeNetworkAvatar(
                                photoUrl: attorney.photoUrl,
                                radius: 24,
                                fallbackLetter: attorney.name.isNotEmpty
                                    ? attorney.name[0]
                                    : 'A',
                              ),
                              title: Text(attorney.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (attorney.specialization != null)
                                    Text(
                                      attorney.specialization!.join(', '),
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  const SizedBox(height: 4),
                                  RatingWidget(
                                    rating: attorney.ratingAverage ?? 0.0,
                                    size: 16,
                                  ),
                                  if (attorney.isAvailable == true)
                                    const Chip(
                                      label: Text('Available'),
                                      backgroundColor: Colors.green,
                                    ),
                                ],
                              ),
                              trailing: const Icon(Icons.arrow_forward_ios),
                              onTap: () {
                                Get.to(() => ChatPage(
                                  attorneyId: attorney.id,
                                  attorneyName: attorney.name,
                                ));
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}

