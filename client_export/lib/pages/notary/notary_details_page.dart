import 'package:flutter/material.dart';

class NotaryDetailsPage extends StatelessWidget {
  final String category;
  final List<String> documents;

  const NotaryDetailsPage({
    super.key,
    required this.category,
    required this.documents,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$category Requirements')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Documents to bring',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                itemCount: documents.length,
                separatorBuilder: (_, __) => const Divider(),
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.1),
                      child: Icon(
                        Icons.insert_drive_file,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    title: Text(documents[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
