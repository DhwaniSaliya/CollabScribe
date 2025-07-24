import 'package:app_links/app_links.dart'; //to handle app deep linking (e.g., open a specific document from a link)
import 'package:collab_scribe/editor_screen.dart';
import 'package:collab_scribe/home_screen.dart';
import 'package:collab_scribe/login_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart'; //for ui
import 'package:firebase_core/firebase_core.dart'; //core firebase initialization
import 'package:flutter_dotenv/flutter_dotenv.dart'; //for loading environment variables like api keys
import 'package:flutter_localizations/flutter_localizations.dart';//The flutter_quill package requires localizations to be set up 
//in the app’s MaterialApp, so it can display proper labels (like for toolbar buttons, formatting options, etc.).
import 'package:flutter_quill/flutter_quill.dart'; 

void main() async {
  //ensures that flutter is fully initialized before doing any async work
  WidgetsFlutterBinding.ensureInitialized();

  //load env variables from .env file
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print("Warning: .env file not found: $e");
  }
  //before using any firebase features we need to initialize firebase
  await Firebase.initializeApp();
  //will remove if the issue that persisted sorts out
  print(
    "Current user: ${FirebaseAuth.instance.currentUser}",
  ); //i added this debug to know current user
  runApp(const MyApp()); // obviously to start the flutter app...:)
}

class MyApp extends StatefulWidget {
  //it is stateful widget coz we need to handle deep links dynamically
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  //to allow navigation from outside the widget tree (for deep links)
  //It allows us to control navigation from anywhere, even without BuildContext directly available.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  late final AppLinks
  _appLinks; //Used for listening to incoming app links (deep links)

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks(); // Initialize the AppLinks handler
    _initDeepLinks(); // Set up deep link listener
  }

  Future<void> _initDeepLinks() async {
    try {
      //if app is opened via a link while it was closed (cold start)
      final uri = await _appLinks.getInitialLink();
      if (uri != null) _handleUri(uri);

      //if app is running and receives a link (foreground mode)
      _appLinks.uriLinkStream.listen((uri) {
        _handleUri(uri);
      });
    } catch (e) {
      debugPrint("Deep link error: $e");
    }
  }

  void _handleUri(Uri uri) {
    //when a deep link is received this func is used.
    //uri parameter is Of Uri type, which represents the entire URL

    //!mounted ensures that widget is still in  the widget tree
    //uri.pathSegments splits url's path into parts
    if (!mounted || uri.pathSegments.isEmpty) return;

    //check if the url is of form /doc/docId
    if (uri.pathSegments.first == 'doc') {
      //if first part of the path is doc
      final docId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
      //If we successfully got a docId, navigate to the EditorScreen, passing that ID.
      //This is what allows the user to land directly inside the document editor when opening the link
      if (docId != null) {
        _navigatorKey.currentState?.push(
          MaterialPageRoute(
            //If currentState is not null, then call .push(...) on it.
            builder: (_) => EditorScreen(docId: docId),
          ),
        );
      }
    }
    //for e.g. special URL like https://collabscribe.com/doc/ABC123
    //path has 2 segments ['doc', 'ABC123'], the second segment (ABC123) as the docId
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CollabScribe',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey, //enables navigation via deep links
      home: StreamBuilder(
        stream: FirebaseAuth.instance
            .authStateChanges(), //listen to login/logout
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          //if user has logged in then show home screen else login screen
          return snapshot.hasData ? const HomeScreen() : const LoginScreen();
        },
      ),
      // Localization delegates allow Material, Cupertino, and FlutterQuill widgets
      // to display translated text and adapt to locale-specific formatting (like date/time).
      // Even though we only support English now, this ensures correct rendering.
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate, // Material widgets (SnackBar, Dialog)
        GlobalWidgetsLocalizations.delegate,  //text direction, general localization
        FlutterQuillLocalizations.delegate, //i used flutter_quill so for it, inside editor screen bold/italic and more labels etc
        //are used, so for that we require it
      ],
      supportedLocales: const [Locale('en')],
    );
  }
}

//note: usage of _ and context
//context - If you're going to use the context, e.g., for themes, showing dialogs, accessing ancestors.
//_ - If you don't need the context and want to avoid unused variable warnings. Clean, short.
