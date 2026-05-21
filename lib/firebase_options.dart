import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        throw UnsupportedError('iOS configuration not provided');
      case TargetPlatform.macOS:
        throw UnsupportedError('MacOS configuration not provided');
      case TargetPlatform.windows:
        throw UnsupportedError('Windows configuration not provided');
      case TargetPlatform.linux:
        throw UnsupportedError('Linux configuration not provided');
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyDnAZPJ_gtZDypWjOBpHqd3hbNZAcmtHJY",
    appId: "1:1084030875192:web:43234ccb49f2b0ff5058cd",
    messagingSenderId: "1084030875192",
    projectId: "hotel-project-fa6f3",
    authDomain: "hotel-project-fa6f3.firebaseapp.com",
    storageBucket: "hotel-project-fa6f3.firebasestorage.app",
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyDnAZPJ_gtZDypWjOBpHqd3hbNZAcmtHJY",
    appId: "1:1084030875192:android:81872a8ef6e91d6f5058cd",
    messagingSenderId: "1084030875192",
    projectId: "hotel-project-fa6f3",
    storageBucket: "hotel-project-fa6f3.firebasestorage.app",
  );
}
