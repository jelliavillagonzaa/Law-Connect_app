import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../theme/app_theme.dart';
import '../../services/notary_service_config.dart';
import '../client/notary_service_details_screen.dart';

class StaffNotaryManagementScreen extends StatefulWidget {
  const StaffNotaryManagementScreen({super.key});

  @override
  State<StaffNotaryManagementScreen> createState() =>
      _StaffNotaryManagementScreenState();
}

class _StaffNotaryManagementScreenState
    extends State<StaffNotaryManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'All';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _openAddOrEditDialog({NotaryDocumentItem? existing}) {
    final titleController = TextEditingController(text: existing?.title ?? '');
    final descController =
        TextEditingController(text: existing?.description ?? '');
    final exampleController =
        TextEditingController(text: existing?.example ?? '');
    final feeController =
        TextEditingController(text: existing?.estimatedFee ?? '');
    final imageUrlController =
        TextEditingController(text: existing?.sampleImageUrl ?? '');
    final templateController =
        TextEditingController(text: existing?.sampleTemplateText ?? '');
    final copiesController = TextEditingController(
      text: existing?.copiesRecommended ??
          '3 to 4 original printed sets (1 for Client, 1 for Notarial Register, 1-2 for Agency/Registry).',
    );
    final appearController = TextEditingController(
      text: existing?.whoMustAppear ??
          'All signing parties / affiants must personally appear with original valid IDs.',
    );

    String selectedCategory = existing?.category ?? 'Affidavits';
    final categories = [
      'Affidavits',
      'Authorizations & SPA',
      'Deeds & Conveyances',
      'Contracts & Agreements',
      'General Notarization',
    ];
    if (!categories.contains(selectedCategory)) {
      categories.add(selectedCategory);
    }

    final reqs = List<String>.from(
      existing?.requiredDocuments ??
          [
            'Valid Government-issued Photo ID',
            'Unsigned Document (at least 3 copies)',
          ],
    );
    final reqInputController = TextEditingController();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 24,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650, maxHeight: 800),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.royalBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.history_edu,
                            color: AppTheme.royalBlue,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            existing == null
                                ? 'Add New Notary Document'
                                : 'Edit Notary Document: ${existing.title}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close, color: Colors.grey),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Title
                            const Text(
                              'Document Name / Title *',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: titleController,
                              decoration: InputDecoration(
                                hintText:
                                    'e.g. Affidavit of Guardianship, Deed of Donation...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Category & Fee Row
                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Category *',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      DropdownButtonFormField<String>(
                                        initialValue: selectedCategory,
                                        isExpanded: true,
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8,
                                              ),
                                        ),
                                        items: categories
                                            .map(
                                              (c) => DropdownMenuItem(
                                                value: c,
                                                child: Text(
                                                  c,
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setModalState(
                                              () => selectedCategory = val,
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 2,
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Estimated Fee',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: feeController,
                                        decoration: InputDecoration(
                                          hintText: 'e.g. ₱200 - ₱400',
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              10,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 12,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Description
                            const Text(
                              'Short Description / Purpose *',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: descController,
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText:
                                    'What is this document and why is it executed?',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Practical Example
                            const Text(
                              'Practical Example / Common Use Cases *',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: exampleController,
                              maxLines: 2,
                              decoration: InputDecoration(
                                hintText:
                                    'e.g. When a grandmother needs authorization to claim benefits on behalf of grandchildren...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Requirements to Bring
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Requirements to Bring (Items)',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  '${reqs.length} items',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: reqInputController,
                                    decoration: InputDecoration(
                                      hintText:
                                          'Add requirement (e.g. Barangay Clearance, 2 Valid IDs)...',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                    ),
                                    onSubmitted: (val) {
                                      final text = val.trim();
                                      if (text.isNotEmpty) {
                                        setModalState(() {
                                          reqs.add(text);
                                          reqInputController.clear();
                                        });
                                      }
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    final text = reqInputController.text.trim();
                                    if (text.isNotEmpty) {
                                      setModalState(() {
                                        reqs.add(text);
                                        reqInputController.clear();
                                      });
                                    }
                                  },
                                  icon: const Icon(Icons.add, size: 18),
                                  label: const Text('Add'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.royalBlue,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // List of added requirements
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: reqs
                                  .map(
                                    (r) => Chip(
                                      label: Text(
                                        r,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      backgroundColor: const Color(0xFFF1F5F9),
                                      deleteIcon: const Icon(
                                        Icons.close,
                                        size: 16,
                                      ),
                                      onDeleted: () {
                                        setModalState(() => reqs.remove(r));
                                      },
                                    ),
                                  )
                                  .toList(),
                            ),
                            const SizedBox(height: 14),

                            // Sample Image URL
                            const Text(
                              'Sample Image / Photo URL (Optional)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: imageUrlController,
                              decoration: InputDecoration(
                                hintText:
                                    'https://example.com/images/sample-affidavit.png',
                                prefixIcon: const Icon(
                                  Icons.image_outlined,
                                  size: 18,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Sample Template Text
                            const Text(
                              'Sample Document Text / Wording (Optional)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: templateController,
                              maxLines: 5,
                              style: const TextStyle(
                                fontFamily: 'Courier',
                                fontSize: 12,
                              ),
                              decoration: InputDecoration(
                                hintText:
                                    'Paste or type the complete sample text of the document here...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                contentPadding: const EdgeInsets.all(12),
                              ),
                            ),
                            const SizedBox(height: 14),

                            // Who Must Appear & Copies
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Who Must Appear',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      TextField(
                                        controller: appearController,
                                        maxLines: 2,
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.all(8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Recommended Copies',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      TextField(
                                        controller: copiesController,
                                        maxLines: 2,
                                        decoration: InputDecoration(
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          contentPadding:
                                              const EdgeInsets.all(8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: () async {
                            final title = titleController.text.trim();
                            if (title.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Please provide a document title.',
                                  ),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }

                            final item = NotaryDocumentItem(
                              id: existing?.id,
                              title: title,
                              category: selectedCategory,
                              description: descController.text.trim().isNotEmpty
                                  ? descController.text.trim()
                                  : 'Notarial service for official documents.',
                              example: exampleController.text.trim().isNotEmpty
                                  ? exampleController.text.trim()
                                  : 'Bring original copies and valid government IDs to the office.',
                              requiredDocuments: reqs.isNotEmpty
                                  ? reqs
                                  : [
                                      'Valid Government-issued Photo ID',
                                      'Unsigned Document (at least 3 copies)',
                                    ],
                              estimatedFee: feeController.text.trim().isNotEmpty
                                  ? feeController.text.trim()
                                  : null,
                              sampleImageUrl:
                                  imageUrlController.text.trim().isNotEmpty
                                  ? imageUrlController.text.trim()
                                  : null,
                              sampleTemplateText:
                                  templateController.text.trim().isNotEmpty
                                  ? templateController.text.trim()
                                  : null,
                              whoMustAppear: appearController.text.trim(),
                              copiesRecommended: copiesController.text.trim(),
                              isCustom: true,
                            );

                            try {
                              await NotaryServiceConfig.saveDocument(
                                item,
                                id: existing?.id,
                                originalTitle: existing?.title,
                              );

                              if (!context.mounted) return;
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    existing == null
                                        ? 'Notary service "$title" added successfully!'
                                        : 'Notary service "$title" updated successfully!',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } catch (e) {
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to save document: $e'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(
                            existing == null
                                ? 'Add Service'
                                : 'Save Changes',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.royalBlue,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _confirmDelete(BuildContext context, NotaryDocumentItem doc) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Notary Service'),
        content: Text(
          'Are you sure you want to remove "${doc.title}" from the notary catalog? Clients will no longer see this service.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (doc.id != null) {
                try {
                  await NotaryServiceConfig.deleteDocument(doc.id!);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Removed "${doc.title}".'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error removing document: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: StreamBuilder<List<NotaryDocumentItem>>(
        stream: NotaryServiceConfig.streamDocuments(),
        builder: (context, snapshot) {
          final allDocs = snapshot.data ?? NotaryServiceConfig.documents;

          final categories = <String>{'All'};
          for (final d in allDocs) {
            categories.add(d.category);
          }

          final filtered = allDocs.where((doc) {
            final matchCat =
                _selectedCategory == 'All' || doc.category == _selectedCategory;
            if (!matchCat) return false;

            if (_searchQuery.isEmpty) return true;
            final q = _searchQuery.toLowerCase();
            return doc.title.toLowerCase().contains(q) ||
                doc.description.toLowerCase().contains(q) ||
                doc.category.toLowerCase().contains(q);
          }).toList();

          final isMobile = MediaQuery.sizeOf(context).width < 768;

          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 14 : 24,
              vertical: isMobile ? 14 : 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row
                if (isMobile)
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Notary Document Catalog',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Requirements, templates, & fees',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.icon(
                        onPressed: () => _openAddOrEditDialog(),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add Document'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.royalBlue,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Notary Services Catalog Management',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F172A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Add, edit, or customize notary document guidelines, requirements, and sample templates for clients.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openAddOrEditDialog(),
                        icon: const Icon(Icons.add_rounded, size: 20),
                        label: const Text('Add Notary Document'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.royalBlue,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 14,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 14),

                // Search & Filter Bar
                if (isMobile)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: 'Search documents, categories...',
                          hintStyle: const TextStyle(fontSize: 13),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[300]!),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: Colors.grey[200]!),
                          ),
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: categories.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final cat = categories.elementAt(index);
                            final isSel = cat == _selectedCategory;
                            return ChoiceChip(
                              label: Text(cat),
                              selected: isSel,
                              selectedColor: AppTheme.royalBlue,
                              labelStyle: TextStyle(
                                color: isSel ? Colors.white : Colors.black87,
                                fontWeight: isSel
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                fontSize: 12,
                              ),
                              backgroundColor: Colors.white,
                              side: BorderSide(
                                color: isSel
                                    ? AppTheme.royalBlue
                                    : Colors.grey[300]!,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              onSelected: (_) =>
                                  setState(() => _selectedCategory = cat),
                            );
                          },
                        ),
                      ),
                    ],
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText:
                                'Search document name, category, or keyword...',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            filled: true,
                            fillColor: Colors.white,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey[300]!),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: Colors.grey[200]!),
                            ),
                          ),
                          onChanged: (val) =>
                              setState(() => _searchQuery = val),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        flex: 3,
                        child: SizedBox(
                          height: 44,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: categories.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final cat = categories.elementAt(index);
                              final isSel = cat == _selectedCategory;
                              return ChoiceChip(
                                label: Text(cat),
                                selected: isSel,
                                selectedColor: AppTheme.royalBlue,
                                labelStyle: TextStyle(
                                  color: isSel ? Colors.white : Colors.black87,
                                  fontWeight: isSel
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 12.5,
                                ),
                                backgroundColor: Colors.white,
                                onSelected: (_) =>
                                    setState(() => _selectedCategory = cat),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),

                // Count summary
                Text(
                  'Showing ${filtered.length} of ${allDocs.length} notary document types',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 10),

                // Card List
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.folder_open_outlined,
                                size: 56,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No notary documents found.',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final doc = filtered[index];
                            final isCustom = doc.isCustom;

                            return Card(
                              elevation: 0.5,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: Colors.grey[200]!),
                              ),
                              child: Padding(
                                padding: EdgeInsets.all(isMobile ? 12 : 16),
                                child: isMobile
                                    ? _buildMobileCard(context, doc, isCustom)
                                    : _buildDesktopCard(context, doc, isCustom),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileCard(
    BuildContext context,
    NotaryDocumentItem doc,
    bool isCustom,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top row: Document icon badge + Title & chips + Edit / Delete buttons
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isCustom
                    ? Colors.purple.shade50
                    : AppTheme.royalBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isCustom
                    ? Icons.bookmark_add_outlined
                    : Icons.description_outlined,
                color: isCustom ? Colors.purple : AppTheme.royalBlue,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE2E8F0),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          doc.category,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                      if (isCustom)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.purple.shade200),
                          ),
                          child: const Text(
                            'CUSTOM',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.purple,
                            ),
                          ),
                        ),
                      if (doc.estimatedFee != null &&
                          doc.estimatedFee!.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            doc.estimatedFee!,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF92400E),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Edit Service',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              icon: const Icon(
                Icons.edit_outlined,
                color: AppTheme.royalBlue,
                size: 20,
              ),
              onPressed: () => _openAddOrEditDialog(existing: doc),
            ),
            if (isCustom) ...[
              const SizedBox(width: 4),
              IconButton(
                tooltip: 'Delete Service',
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 20,
                ),
                onPressed: () => _confirmDelete(context, doc),
              ),
            ],
          ],
        ),

        const SizedBox(height: 10),

        // Full width Description
        Text(
          doc.description,
          style: TextStyle(
            fontSize: 12.5,
            color: Colors.grey[700],
            height: 1.35,
          ),
        ),

        const SizedBox(height: 8),

        // Requirements & Image tag
        Wrap(
          spacing: 12,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.checklist, size: 14, color: Colors.grey[500]),
                const SizedBox(width: 4),
                Text(
                  '${doc.requiredDocuments.length} Requirements',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            if (doc.sampleImageUrl != null && doc.sampleImageUrl!.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.image_outlined, size: 14, color: Colors.blue[600]),
                  const SizedBox(width: 4),
                  Text(
                    'Has Image Example',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.blue[700],
                    ),
                  ),
                ],
              ),
          ],
        ),

        const SizedBox(height: 10),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        const SizedBox(height: 8),

        // Full width Preview Client View Button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              Get.to(
                () => NotaryServiceDetailsScreen(
                  serviceType: doc.title,
                  documentItem: doc,
                ),
              );
            },
            icon: const Icon(Icons.visibility_outlined, size: 15),
            label: const Text(
              'Preview Client View',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.royalBlue,
              side: BorderSide(
                color: AppTheme.royalBlue.withValues(alpha: 0.3),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopCard(
    BuildContext context,
    NotaryDocumentItem doc,
    bool isCustom,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: isCustom
                ? Colors.purple.shade50
                : AppTheme.royalBlue.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isCustom
                ? Icons.bookmark_add_outlined
                : Icons.description_outlined,
            color: isCustom ? Colors.purple : AppTheme.royalBlue,
            size: 24,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    doc.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      doc.category,
                      style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF334155),
                      ),
                    ),
                  ),
                  if (isCustom)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: const Text(
                        'CUSTOM',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple,
                        ),
                      ),
                    ),
                  if (doc.estimatedFee != null && doc.estimatedFee!.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF3C7),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        doc.estimatedFee!,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF92400E),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                doc.description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.checklist,
                    size: 15,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${doc.requiredDocuments.length} Requirements',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[600],
                    ),
                  ),
                  if (doc.sampleImageUrl != null &&
                      doc.sampleImageUrl!.isNotEmpty) ...[
                    const SizedBox(width: 14),
                    Icon(
                      Icons.image_outlined,
                      size: 15,
                      color: Colors.blue[600],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Has Image Example',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.blue[700],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: () {
                Get.to(
                  () => NotaryServiceDetailsScreen(
                    serviceType: doc.title,
                    documentItem: doc,
                  ),
                );
              },
              icon: const Icon(
                Icons.visibility_outlined,
                size: 15,
              ),
              label: const Text(
                'Preview Client View',
                style: TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Edit Service',
              icon: const Icon(
                Icons.edit_outlined,
                color: AppTheme.royalBlue,
                size: 20,
              ),
              onPressed: () => _openAddOrEditDialog(
                existing: doc,
              ),
            ),
            if (isCustom)
              IconButton(
                tooltip: 'Delete Service',
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                  size: 20,
                ),
                onPressed: () => _confirmDelete(context, doc),
              ),
          ],
        ),
      ],
    );
  }
}
