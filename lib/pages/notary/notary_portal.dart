import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'notary_details_page.dart';
import '../../theme/app_theme.dart';

class NotaryPortal extends StatefulWidget {
  const NotaryPortal({super.key});

  @override
  State<NotaryPortal> createState() => _NotaryPortalState();
}

class _NotaryPortalState extends State<NotaryPortal> {
  final TextEditingController _searchController = TextEditingController();

  // Predefined notary categories and required documents (expanded per user's list)
  final Map<String, List<String>> _notaryDocs = {
    'Affidavit Notarization': [
      'Valid government ID (e.g. National ID, Driver\'s License)',
      'Affidavit (printed, unsigned)',
      'Supporting documents (old OR/CR, receipt, screenshot, police report)',
      'Examples: Affidavit of Loss, Affidavit of Undertaking, Affidavit of Support',
    ],
    'Special Power of Attorney (SPA)': [
      'Valid ID of the principal (the one giving authority)',
      'Draft SPA (or request the notary to prepare)',
      'Details of representative: full name, address, ID number',
      'Supporting proof (e.g. land title, vehicle OR/CR, billing statement)',
    ],
    'General Power of Attorney': [
      'Valid ID',
      'Statement of general authority',
      'Complete details of all involved parties',
    ],
    'Deed of Sale': [
      'Valid IDs of buyer & seller (e.g. Seller – PRC ID; Buyer – National ID)',
      'Deed of Sale (printed)',
      'OR/CR (for vehicles)',
      'Land Title / Tax Declaration (for real property)',
      'Proof of payment (optional but helpful)',
    ],
    'Deed of Donation': [
      'Valid IDs of donor & donee',
      'Description of donated item or property',
      'Title / OR-CR if applicable',
    ],
    'Contract Signing': [
      'Valid IDs of ALL signatories',
      'Complete printed contract',
      'Supporting documents if needed (e.g. proof of ownership, company letter)',
      'Examples: Rental contract, employment contract, service agreement',
    ],
    'Sworn Statement / Sworn Declaration': [
      'Valid ID',
      'Sworn statement form',
      'Examples: for school, police, or employment',
    ],
    'Promissory Note': [
      'Valid ID',
      'Total amount owed',
      'Payment schedule',
      'Terms agreed by both parties',
    ],
    'Parental Consent / Parental Advice': [
      'Parents\' valid IDs',
      'Child\'s birth certificate',
      'Consent document',
      'Examples: Passport application, school enrollment, marriage',
    ],
    'Authorization Letter (Notarized)': [
      'ID of the person authorizing',
      'ID of the authorized representative',
      'Purpose of authorization',
      'Document to be claimed (if applicable)',
    ],
    'Certificate of Appearance': [
      'Valid ID',
      'Reason or purpose for the Certificate of Appearance',
      'Company/school details (optional)',
    ],
    'Adoption / Guardianship Affidavits': [
      'Valid IDs',
      'Child\'s birth certificate',
      'Supporting documents (e.g. DSWD papers, barangay certificate)',
    ],
    'Joint Affidavit': [
      'Two valid IDs (one for each affiant)',
      'Document requiring the affidavit',
      'Witness details (if needed)',
      'Examples: cohabitation, residency, name discrepancy',
    ],
    'Lost Document Affidavit': [
      'Valid ID',
      'Details of the lost document (serial number, account number, plate number)',
      'Old copy/receipt (if available)',
      'Police report (if required by the agency)',
      'Examples: Lost ID, ATM, SIM, OR/CR',
    ],
    'Business-Related Notary': [
      'Valid IDs of all signatories',
      'SEC/BIR documents',
      'Printed contracts or forms (e.g. Articles of Incorporation, Partnership Agreement)',
    ],
  };

  List<String> get _categories => _notaryDocs.keys.toList();

  List<String> _filtered = [];

  @override
  void initState() {
    super.initState();
    _filtered = _categories;
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = _categories;
      } else {
        _filtered = _categories
            .where((c) => c.toLowerCase().contains(q))
            .toList();
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notary Portal')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search notary type (e.g. Land, Affidavit)',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _filtered.isEmpty
                ? Center(
                    child: Text(
                      'No results',
                      style: TextStyle(color: AppTheme.mutedText),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final category = _filtered[index];
                      return Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.royalBlue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.gavel,
                              color: AppTheme.royalBlue,
                            ),
                          ),
                          title: Text(
                            category,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${_notaryDocs[category]!.length} required documents',
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () {
                            final docs = _notaryDocs[category] ?? [];
                            Get.to(
                              () => NotaryDetailsPage(
                                category: category,
                                documents: docs,
                              ),
                            );
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
}
