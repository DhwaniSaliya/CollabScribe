import 'dart:async'; //for Timer and Streamsubscription
import 'dart:math'; //for generating rndom user color
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; //clipboard (copy) ke liye i used it
import 'package:flutter_quill/flutter_quill.dart'; //rich text editor
import 'package:flutter_quill/quill_delta.dart'; //Delta format
import 'gemini_api.dart';

class EditorScreen extends StatefulWidget {
  final String docId; //docId is passed when navigating to this screen so we know which document to open/edit
  const EditorScreen({super.key, required this.docId});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  late QuillController _controller; //controls text editor
  final TextEditingController _promptController = TextEditingController();//ai i/p
  final user = FirebaseAuth.instance.currentUser!; //logged in user
  late final Color userColor; //cursor ka color??? -- - - - - - - - - - - -!!!!!!!!!!!!!!!!!!!!!!!!
  String? _docTitle; //title of document
  final FocusNode _aiPromptFocusNode = FocusNode(); //for restoring ai i/p focus
  final FocusNode _editorFocusNode = FocusNode(); //for restoring editor focus
  Timer? _debounceTimer; //avoid saving on every keystroke
  int _lastCursorOffset = 0; //to track typing position

  bool _isLoading = true; //show loader till doc loads
  final firestore = FirebaseFirestore.instance;
  bool _isPublic = false;

  StreamSubscription? _presenceSubscription; //for presence updates
  List<Map<String, dynamic>> otherUsersPresence = []; //to tack other active collaborator

  @override
  void initState() {
    super.initState();
    //Colors.primaries is a List<Color>
    //Random.nextInt(n) generates a random no. from 0 to n-1
    userColor = Colors.primaries[Random().nextInt(Colors.primaries.length)];
    _loadDocument(); //fetch doc data from firstore
  }

  @override
  void dispose() {
    _presenceSubscription?.cancel(); //stop listening to presence
    _aiPromptFocusNode.dispose();
    _promptController.dispose();
    _debounceTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  //Delta is a special data format used by text editors like Quill to represent document changes like insertions, deltions, updations
  //for more knowledge... scroll down at the bottom :)
  Delta? getDeltaDiff(Delta oldDelta, Delta newDelta) {//oldDelta -prev. doc content, newDelta -curr. doc content
    try {
      final baseDoc = Document.fromDelta(oldDelta); //Creates a Quill Document using a Delta object
      //baseDoc becomes our base document from oldDelta
      final inverted = oldDelta.invert(baseDoc.toDelta()); //invert() takes a base Delta to compare against
      final diff = inverted.compose(newDelta);//apply newDelta on top of the inverse of oldDelta to get the true difference
      return diff; //contains the set of operations that transform oldDelta into newDelta
    } catch (e) {
      debugPrint('Error computing delta diff: $e');
      return null;
    }
  }

  //called when a remote user edits doc and curr user receive updated content
  void _onRemoteUpdate(Delta newDelta) { //func receives new Delta from firestore or other user
    final currentDelta = _controller.document.toDelta(); //get the current local document’s content in Delta form

    //if current content and the remote content is same then do nothing
    if (currentDelta.toJson().toString() == newDelta.toJson().toString()) {
      return;
    }

    final oldSelection = _controller.selection; //save the user’s current cursor position before making any changes
    //so it can be restored after the update (so the cursor doesn’t jump)

    //if user’s cursor moved since the last recorded position, assume they're typing
    final isUserTyping = _controller.selection.baseOffset != _lastCursorOffset;
    if (isUserTyping) return; //don’t apply the update if user still typing

    // Apply delta safely
    try {
      _controller.document = Document.fromDelta(newDelta); //overwrite the current document with the new remote Delta

      //after applying the document, restore the user's previous cursor position
      //ChangeSource.remote tells Quill this change came from outside the user (used for syncing properly)
      if (oldSelection.isValid &&
          oldSelection.baseOffset <= _controller.document.length) {
        _controller.updateSelection(oldSelection, ChangeSource.remote);
      }

      // Restore focus
      //after the widget tree is rebuilt (in the next frame), give focus back to the editor
      //ensures that user can keep typing without manually tapping the editor again
      WidgetsBinding.instance.addPostFrameCallback((_) {
        FocusScope.of(context).requestFocus(_editorFocusNode);
      });
    } catch (e) {
      debugPrint("Remote update failed: $e");
    }
  }

  Future<void> _loadDocument() async {
    try {
      final docRef = firestore.collection('documents').doc(widget.docId); //reference to specific doc in firestore using docid
      final snapshot = await docRef.get(); //fetch doc snapshto from firestore

      //if the document doesn't exist, show error and go back
      if (!snapshot.exists) {
        if (!mounted) return; //ensure widget is still in the tree
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Document not found!")));
        Navigator.pop(context); //go back to prev screen
        return;
      }

      //extract data from the document
      final data = snapshot.data();
      _docTitle = data?['title'] ?? 'Untitled'; //set title
      final content = data?['content']; //get doc content
      _isPublic = data?['isPublic'] ?? false; //is it public or not
 
      Delta delta;
      try {
        //convert firestore content(json) to delta if it's valid
        if (content is List && content.isNotEmpty) {//is the content a list of items and not empty
        //note- humne firestore mein quill doc data ko list of json maps ke format mein store kara hai

          // converts the list of JSON objects (List<dynamic>) into a list of Map<String, dynamic>, which is what Delta.fromJson() expects
          delta = Delta.fromJson(
            content.map((e) => Map<String, dynamic>.from(e)).toList(),
          );
        } else {
          delta = Delta()..insert('\n'); //fallback to empty doc
          //short for:
          //delta = Delta();
          //delta.insert('\n');
        }
      } catch (e) {
        delta = Delta()..insert('\n');
      }
      
      //initialize quill ediotr controller with the document delta
      _controller = QuillController(
        document: Document.fromDelta(delta),
        selection: const TextSelection.collapsed(offset: 0), //start at top
      );

      //listen to changes in ediotor (from user typing)
      _controller.changes.listen((event) {
        if (event.source == ChangeSource.local) {
          final currentOffset = _controller.selection.baseOffset;
          _lastCursorOffset = currentOffset;

          //update cursor presence immediately in firestore
          /* keep in mind that you don’t see other users’ cursors in your editor.
            Because even though their cursor position is stored and read, the app does not visually render the cursor 
            inside the document UI for other users. But yeah, you can see what other wrote in doc after justa few secs....
          */
          _updateCursorPosition(currentOffset);

          //line*
          _debounceTimer?.cancel();//if there's a pending timer already running (from the last letter typed), cancel it.
          //prevents multiple saves being queued

          //now start a new timer for 800 millisecond
          //If the user doesn't type again within 800ms, _updateDocumentContent() is called.
          // if they do type again? This timer is canceled (see line*), and a new one starts.
          _debounceTimer = Timer(const Duration(milliseconds: 800), () {
            _updateDocumentContent();
          });
        }
      });

      docRef.snapshots().listen((docSnap) { //listen to live updates from firestore on current doc
      //if someonle else edits the doc, firestore will notify your app
        if (!docSnap.exists) return;
        final data = docSnap.data();
        _isPublic = data?['isPublic'] ?? false; //updates ispublic status
        final content = data?['content']; //updates new content

        if (content is List) {
          final newDelta = Delta.fromJson(
            content.map((e) => Map<String, dynamic>.from(e)).toList(),
          );
          _onRemoteUpdate(newDelta); //call it to update your editor
        }
      });

      //listen to presence updates jaise other user active on this doc
      _listenToOtherUsersPresence();

      //set loading to false so that editor can be shown
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e, stack) {
      debugPrint("Error loading document: $e");
      debugPrintStack(stackTrace: stack);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("Failed to load document")));
        Navigator.pop(context);
      }
    }
  }

  //function is called whenever a user stops typing. It takes the current editor content, converts it to JSON, and updates it in 
  //Firestore under the right document ID. It also stores the current time to track the last update
  Future<void> _updateDocumentContent() async {
    final json = _controller.document.toDelta().toJson();
    await firestore.collection('documents').doc(widget.docId).update({
      'content': json,
      'updatedAt': Timestamp.now(),
    });
  }

  //updates the user's cursor position, name, color, and last activity timestamp in the Firestore under the document’s presence subcollection.
  //This helps track who is editing and where in real-time collaboration.
  Future<void> _updateCursorPosition(int offset) async {
    final presenceRef = firestore
        .collection('documents')
        .doc(widget.docId)
        .collection('presence')
        .doc(user.uid);

    await presenceRef.set({
      'name': user.displayName ?? user.email ?? 'User',
      'cursorOffset': offset, //stores where the user’s cursor currently is 
      'color': '#${userColor.value.toRadixString(16).padLeft(8, '0')}', //toRadixString(16) converts the color to hex.
      'lastActive': FieldValue.serverTimestamp(), //reccords the time the user was last active
    });
  }

  // detecting which other users are currently active and editing the same document
  void _listenToOtherUsersPresence() {
    _presenceSubscription = firestore
        .collection('documents')
        .doc(widget.docId)
        .collection('presence')
        .snapshots() //snapshots() gives real-time updates whenever any user's presence info changes
        .listen((snapshot) { //start listening to those real-time updates.
          final now = DateTime.now();

          final users = snapshot.docs
              .where((doc) {
                if (doc.id == user.uid) return false; //obviously, u don't want to count yourself in others list

                final data = doc.data();
                final ts = data['lastActive'];
                if (ts is Timestamp) {
                  final lastActiveTime = ts.toDate();
                  // Only consider users active within last 10 seconds
                  return now.difference(lastActiveTime).inSeconds <= 10;
                }
                return false;
              })
              .map((doc) => doc.data()) //Convert filtered user documents into a list of plain maps (Map<String, dynamic>), 
              .toList();                //which we can use in the UI.

          //update the state to refresh the UI with this latest list of active users
          setState(() {
            otherUsersPresence = List<Map<String, dynamic>>.from(users);
          });
        });
  }

  //sends user ka input to Gemini, inserts response into document,
  // and saves prompt+response in Firestore under ai_prompts subcollection.
  Future<void> _handleAIPrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    _promptController.clear();

    try {
      final aiText = await GeminiAPI.getAIResponse(prompt);
      final pos = _controller.selection.baseOffset;

      if (pos >= 0) {
        _controller.document.insert(pos, '$aiText\n');
      } else {
        _controller.document.insert(0, '$aiText\n');
      }

      await firestore
          .collection('documents')
          .doc(widget.docId)
          .collection('ai_prompts')
          .add({
            'prompt': prompt,
            'response': aiText,
            'timestamp': Timestamp.now(),
          });
    } catch (e) {
      if(!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("AI Error: $e")));
    }
  }

  //lets the current user share a document with other users via their email addresses
  Future<void> _shareWithEmail(BuildContext context) async {
    final emailController = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Share Document'),
        content: TextField(
          controller: emailController,
          decoration: const InputDecoration(
            labelText: 'Enter emails (comma-separated)',
            hintText: 'e.g. user1@example.com, user2@example.com',
          ),
          keyboardType: TextInputType.emailAddress,
          maxLines: null,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final rawInput = emailController.text.trim();//Gets the user's input and exits early if it's empty
              if (rawInput.isEmpty) return;

              //Converts the comma-separated input string into a list of valid (non-empty) email addresses
              final emails = rawInput
                  .split(',')
                  .map((e) => e.trim())
                  .where((e) => e.isNotEmpty)
                  .toList();
              final sharedUids = <String>[]; //user IDs found in the database
              final notFoundEmails = <String>[]; //emails that weren’t found.

              for (final email in emails) {//Looks in the users collection for a user with this email
                final userQuery = await FirebaseFirestore.instance
                    .collection('users')
                    .where('email', isEqualTo: email)
                    .limit(1)
                    .get();

                if (userQuery.docs.isNotEmpty) {//if the email is found, add that user’s UID to sharedUids
                  final sharedUid = userQuery.docs.first.id;
                  sharedUids.add(sharedUid);
                } else {
                  notFoundEmails.add(email);//if not found, add email to notFoundEmails
                }
              }
              //f some users were found, update the sharedWith array in the document by adding those UIDs
              if (sharedUids.isNotEmpty) {
                await FirebaseFirestore.instance
                    .collection('documents')
                    .doc(widget.docId)
                    .update({'sharedWith': FieldValue.arrayUnion(sharedUids)});
              }

              if (!context.mounted) return;
              Navigator.pop(ctx);

              if (notFoundEmails.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Users added successfully.')),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Some users were not found: ${notFoundEmails.join(', ')}',
                    ),
                  ),
                );
              }
            },
            child: const Text('Share'),
          ),
        ],
      ),
    );
  }

  Future<void> _togglePublicStatus() async {
    setState(() => _isPublic = !_isPublic);
    await firestore.collection('documents').doc(widget.docId).update({
      'isPublic': _isPublic,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isPublic ? 'Document made public' : 'Document made private',
        ),
      ),
    );
  }

  Widget _buildAIPromptBar() {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _promptController,
              focusNode: _aiPromptFocusNode,
              //ocusNode lets you control and track focus manually for input widgets like TextField. 
              //It’s useful when you want to customize focus behavior, like moving focus, restoring it, or reacting when focus changes
              decoration: const InputDecoration(
                hintText: "Ask AI to generate content...",
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.send), onPressed: _handleAIPrompt),
        ],
      ),
    );
  }

  Widget _buildPresenceOverlay() {
    if (otherUsersPresence.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(20),
      ),
      child: GestureDetector(
        onTap: () {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text("Active Users"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: otherUsersPresence.map((user) {
                  final name = user['name'] ?? 'User';
                  final colorString = user['color'] ?? '#000000';
                  Color parsedColor = Colors.grey;
                  try {//converting hex string to Color
                    if (colorString.startsWith('#')) {
                      parsedColor = Color(
                        int.parse(colorString.substring(1), radix: 16), //interpret the string as a base-16 (hexadecimal) number
                      ).withAlpha(0xFF); //full opacity
                    }
                  } catch (_) {}

                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: parsedColor,
                      radius: 10,
                    ),
                    title: Text(name, style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text("Close"),
                ),
              ],
            ),
          );
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.people, size: 16),
            const SizedBox(width: 6),
            Text(
              "${otherUsersPresence.length} editing",
              style: const TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_docTitle ?? "Editing..."),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: widget.docId)); //will later integrate proper links for sharing (e.g. https://..//widget.docId)
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Document ID copied")),
              );
            },
          ),
          IconButton(
            icon: Icon(_isPublic ? Icons.visibility : Icons.visibility_off),
            onPressed: _togglePublicStatus,
            tooltip: _isPublic ? 'Make Private' : 'Make Public',
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () => _shareWithEmail(context),
          ),
        ],
      ),
      body: Column(
        children: [
          QuillSimpleToolbar(
            controller: _controller,
            config: QuillSimpleToolbarConfig(
              multiRowsDisplay: false,
              showBackgroundColorButton: true,
              showAlignmentButtons: true,
              showCodeBlock: true,
              showListBullets: true,
              showHeaderStyle: true,
            ),
          ),
          _buildPresenceOverlay(),
          //This is the main text editor where users type, expands to take all remaining space.
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: QuillEditor.basic(
                controller: _controller,
                focusNode: _editorFocusNode, //req for focus restoration
              ),
            ),
          ),
          _buildAIPromptBar(),
        ],
      ),
    );
  }
}

/* A Delta object is a list of operations like:
[
  {"insert": "Hello"},
  {"insert": " world", "attributes": {"bold": true}},
  {"insert": "\n"}
]
looks like a list of json-like operations
*/

/*
Each time you type a single letter, like:
H → save to Firebase, e → save to Firebase, l → save to Firebase ...and so on.
That would trigger dozens of Firestore writes — which is slow, expensive, and bad for performance.
Solution- Debouncing
Wait until the user has stopped typing for a short while (e.g. 800ms), then save just once.

_debounceTimer?.cancel(); // Line 1 — cancel any previous timer
_debounceTimer = Timer(const Duration(milliseconds: 800), () {
  _updateDocumentContent(); // save after 800ms of no typing
});

imagine you're typing fast:
You type "H" - a timer is started.
Before 800ms passes, you type "e".
That triggers this block again: cancel() - cancels the previous timer
                                Timer(...) - starts a new 800ms timer
You type "l" - same process repeats

It keeps resetting until you pause typing for 800ms. Then only the last timer finishes and updateDocumentContent() is called.

*/
