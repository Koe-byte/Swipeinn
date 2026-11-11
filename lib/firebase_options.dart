import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with the Swipeinn Firebase project.
///
/// Generated configuration for Web and Android. The Firebase project ID remains
/// `rently-ph`; only the app-facing brand is Swipeinn.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'Swipeinn is configured for web and Android only. '
          'Register an iOS app before building for iOS.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD-GpYMJ5nbDIAG--tiLR6hKSEzgPtpwh8',
    appId: '1:58561207998:web:524440ca2bea980e8388ef',
    messagingSenderId: '58561207998',
    projectId: 'rently-ph',
    authDomain: 'rently-ph.firebaseapp.com',
    storageBucket: 'rently-ph.firebasestorage.app',
    measurementId: 'G-VBHCPJCW9F',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAXCuUDYGNSteYC30v4XWeMt0Ii0_U8kY4',
    appId: '1:58561207998:android:fa4e975bd1433c0a8388ef',
    messagingSenderId: '58561207998',
    projectId: 'rently-ph',
    storageBucket: 'rently-ph.firebasestorage.app',
  );
}
