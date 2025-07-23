import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'editor_screen.dart';
import 'package:intl/intl.dart'; //to format the Timestamp from Firestore into readable dates

class ExploreScreen extends StatelessWidget {
  const ExploreScreen({super.key});

  //convert a Firestore Timestamp into a user-friendly date string like "Jul 23, 2025 5:30 PM".
  String _formatDate(Timestamp timestamp) {
    final date = timestamp.toDate();
    return DateFormat.yMMMd().add_jm().format(date); //.add_jm() - Adds the time part in hour:minute + AM/PM format
  }

  @override
  Widget build(BuildContext context) {
    final docsRef = FirebaseFirestore.instance
        .collection('documents')
        .where('isPublic', isEqualTo: true)
        .orderBy('updatedAt', descending: true); //sorted with latest updated docs first

    return Scaffold(
      appBar: AppBar(title: const Text("Explore Public Documents")),
      body: StreamBuilder<QuerySnapshot>(
        stream: docsRef.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            debugPrint("Firestore error: ${snapshot.error}");
            return const Center(child: Text("Something went wrong."));
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text("No public documents found."));
          }

          final docs = snapshot.data!.docs;

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final title = data['title'] ?? 'Untitled';
              final docId = docs[index].id;
              final updatedAt = data['updatedAt'] as Timestamp?;

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    updatedAt != null ? "Updated: ${_formatDate(updatedAt)}" : "No timestamp",
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 18),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EditorScreen(docId: docId),
                      ),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
