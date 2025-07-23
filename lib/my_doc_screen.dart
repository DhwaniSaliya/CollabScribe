import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'editor_screen.dart';

class MyDocumentsScreen extends StatefulWidget {
  const MyDocumentsScreen({super.key});

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  final firestore = FirebaseFirestore.instance;
  final user = FirebaseAuth.instance.currentUser!;
  List<DocumentSnapshot> myDocs = [];
  List<DocumentSnapshot> sharedDocs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDocuments(); //call to fetch data
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true); //initially jab tak data fetch ho raha hai show loading spinner

    try {
      final myDocsFuture = firestore //docs created by user
          .collection('documents')
          .where('createdBy', isEqualTo: user.uid)
          .orderBy('updatedAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true) //firestore index requirement
          .get();

      final sharedDocsFuture = firestore //docs shared with the user
          .collection('documents')
          .where('sharedWith', arrayContains: user.uid)
          .orderBy('updatedAt', descending: true)
          .orderBy(FieldPath.documentId, descending: true) // for index compliance
          .get();

      final results = await Future.wait([myDocsFuture, sharedDocsFuture]); //wait for both queries together

      final myDocsSnapshot = results[0];
      final sharedDocsSnapshot = results[1];

      //filter sharedDocs to exclude user's own doc
      final sharedOnly = sharedDocsSnapshot.docs
          .where((doc) => doc['createdBy'] != user.uid)
          .toList();

      setState(() {
        myDocs = myDocsSnapshot.docs;
        sharedDocs = sharedOnly;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint("Error loading docs: $e");
      if(!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to load documents")),
      );
    }
  }

  Widget _buildDocTile(DocumentSnapshot doc, {required bool isOwner}) {
  final data = doc.data() as Map<String, dynamic>;
  final title = data['title'] ?? 'Untitled';
  final isPublic = data['isPublic'] ?? false;
  final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate();

  return Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: ListTile(
      title: Text(title),
      subtitle: Row(
        children: [
          Icon(
            isOwner ? Icons.check_circle : Icons.link,
            size: 16,
            color: isOwner ? Colors.green : Colors.blue,
          ),
          const SizedBox(width: 6),
          Text(
            isOwner ? 'You created this' : 'Shared with you',
            style: TextStyle(
              color: isOwner ? Colors.green : Colors.blue,
              fontSize: 14,
            ),
          ),
        ],
      ),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isPublic ? Icons.public : Icons.lock,
                size: 16,
                color: Colors.grey[700],
              ),
              const SizedBox(width: 4),
              Text(
                isPublic ? "Public" : "Private",
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          if (updatedAt != null)
            Text(
              'Edited: ${TimeOfDay.fromDateTime(updatedAt).format(context)}',
              style: const TextStyle(fontSize: 12),
            ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => EditorScreen(docId: doc.id),
          ),
        );
      },
    ),
  );
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Documents'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDocuments,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : myDocs.isEmpty && sharedDocs.isEmpty
              ? const Center(child: Text("No documents found."))
              : ListView(
                  padding: const EdgeInsets.all(8),
                  children: [
                    //... -> spread operator (used to conditionally insert multiple widgets into a list)
                    //here, inside childre:[] of ListView
                    if (myDocs.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.all(4),
                        child: Row(
                          children: [
                            Icon(Icons.description, size: 18,),
                            SizedBox(width:6,),
                            Text(
                              "Your Documents",
                              style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                      ...myDocs.map((doc) => _buildDocTile(doc, isOwner: true)),
                      //... used to insert all elements of a list or iterable into another list
                      //.map() - to turn each document in myDocs into a widget
                      //_buildDocTile(...) - your custom widget builder for each document.
                      //... (spread operator) - to unpack the resulting list of widgets and insert them into the parent widget list 
                      //(like in a Column or ListView).
                    ],
                    if (sharedDocs.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(top: 16, left: 4),
                        child: Row(
                          children: [
                            Icon(Icons.inbox, size: 18,),
                            SizedBox(width: 6,),
                            Text(
                          "Shared With You",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                          ],
                        ),
                      ),
                      ...sharedDocs.map((doc) => _buildDocTile(doc, isOwner: false)),
                    ],
                  ],
                ),
    );
  }
}
