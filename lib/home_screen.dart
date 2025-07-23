import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collab_scribe/editor_screen.dart';
import 'package:collab_scribe/explore_screen.dart';
import 'package:collab_scribe/my_doc_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';//to store recent document IDs locally on the device
import 'package:uuid/uuid.dart'; //to generate a unique document ID (6 characters)

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _docCodeController = TextEditingController(); //handles the i/p of doc code to open
  List<String> recentDocs = []; //stores recent document codes locally using SharedPreferences

  @override
  void initState() {
    super.initState();
    _loadRecentDocs(); //loads the recent document list when the screen opens.
  }

  //load recent docs
  Future<void> _loadRecentDocs() async {
    //SharedPreferences.getInstance(): A method that gives you access to the device's local key-value storage 
    //(like a small file for saving data locally).
    final prefs = await SharedPreferences.getInstance();
    setState(() {//triggers a rebuild of the widget with updated data (updating ui state)
      //get a list of str stored under key 'recentDocs' from sharedpreferences else empty list
      recentDocs = prefs.getStringList('recentDocs') ?? [];
    });
  }

  Future<void> _saveRecentDoc(String docId) async {
    final prefs = await SharedPreferences.getInstance();//loads the preferences from device storage
    
    if (!recentDocs.contains(docId)) {//if doc id is not inthe recentDocs list
      recentDocs.insert(0, docId);//insert at beginning, thus it keeps the most recently accessed documents at the top
      //if the list has more than 10 items, it trims it to just the first 10
      if (recentDocs.length > 10) recentDocs = recentDocs.sublist(0, 10);
      await prefs.setStringList('recentDocs', recentDocs);//saves the updated recentDocs list to local storage using the key 'recentDocs'
    }
    //jab app restart hoga tab it can load recent docs using _loadRecentDocs()
  }

  Future<void> _createNewDoc() async {
    final titleController = TextEditingController();

    //creates a dialog to enter a title
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("New Document"),
        content: TextField(
          controller: titleController,
          decoration: const InputDecoration(labelText: "Enter document title"),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {//asynchronous function so we can use await to perform firestore and sharedpreferences operations
              final title = titleController.text.trim().isEmpty
                  ? 'Untitled Document' //default title is untitled
                  : titleController.text.trim();

              Navigator.pop(ctx); //close the dialog

              //generates a unique 6 character id using the uuid package
              //v4() gives a random UUID like b6dcd78b-..., but .substring(0, 6) keeps only first 6 characters
              final docId = const Uuid().v4().substring(0, 6);
              final docRef = FirebaseFirestore.instance //points to a new Firestore document inside the "documents" collection
                  .collection('documents')
                  .doc(docId);

              await docRef.set({
                'title': title,
                'content': [//initializes with an empty line in Quill editor format
                  {'insert': '\n'},
                ],
                'createdAt': Timestamp.now(),
                'updatedAt': Timestamp.now(),
                'createdBy': FirebaseAuth.instance.currentUser!.uid, //stores current user's UID
                'isPublic': false,
                'sharedWith': [],
              });

              await _saveRecentDoc(docId);//adds the docId to recent documents in SharedPreferences
              _openDocumentById(docId);//navigate to editor screen for newly created doc
            },
            child: const Text("Create"),
          ),
        ],
      ),
    );
  }

  void _openDocumentById(String docId) {//go to editor screen with given doc id
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => EditorScreen(docId: docId)),
    );
  }

  void _openDocument() {//called when user enters a code and clicks "Open document"
    final docId = _docCodeController.text.trim();
    if (docId.isEmpty) return;
    _saveRecentDoc(docId);//add docid to recent docs
    _openDocumentById(docId);//go to editor screen
  }

  void _goToExplore() {//go to explore scren
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExploreScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("CollabScribe"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              onPressed: _createNewDoc,
              label: const Text("Create new document"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.explore),
              onPressed: _goToExplore,
              label: const Text("Explore Public Documents"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.article),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyDocumentsScreen()),
                );
              },
              label: const Text("View My Documents"),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _docCodeController,
              decoration: const InputDecoration(
                labelText: "Enter document code",
              ),
              onSubmitted: (_) => _openDocument(),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _openDocument,
              label: const Text("Open document"),
              icon: const Icon(Icons.folder_open),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
            ),
            const SizedBox(height: 24),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                "Recent Documents",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: recentDocs.isEmpty
                  ? const Center(child: Text("No recent documents."))
                  : ListView.builder(
                      itemCount: recentDocs.length,
                      itemBuilder: (context, index) {
                        final docId = recentDocs[index];
                        //will fetch data from firestore using future builder.
                        //as FirebaseFirestore.instance.doc(...).get() is asynchronous — it returns a Future
                        return FutureBuilder(
                          future: FirebaseFirestore.instance
                              .collection('documents')
                              .doc(docId)
                              .get(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {//while doc is still being fetched
                              return const ListTile(
                                title: Text("Loading..."),
                                trailing: CircularProgressIndicator(),
                              );
                            }

                            final data =snapshot.data!.data();
                            final title = data?['title'] ?? 'Untitled Document';

                            return ListTile(
                              title: Text(title),
                              subtitle: Text("Code: $docId"),
                              trailing: const Icon(Icons.arrow_forward),
                              onTap: () => _openDocumentById(docId),
                            );
                          },
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

//note: humne futurebuilder hi kyun use kiya? why not streambuilder?
//get() is a one-time request to fetch the document
//We're just using the doc info to display in a recent documents list
//We're not interested in live updates to the doc in this screen — just need the title once
//agar hume title or content chahiye hota to auto-update in real-time (like chat messages or live document edits) -> stream builder
//let's understand the diff:
/* Future builder:
   One-time async call , Fetch data once , Rebuilds once when Future completes
   Stream builder:
   Continuous stream of data , Listen to live changes over time , rebuilds every time new data comes from the stream
*/
