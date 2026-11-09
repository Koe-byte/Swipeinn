import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Generated configuration supporting Web, Android, and iOS for Rently.
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
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
    apiKey: 'AIzaSyD-GpYMJ5nbDIAG--tiLR6hKSEzgPtpwh8',
    appId: '1:58561207998:android:524440ca2bea980e8388ef',
    messagingSenderId: '58561207998',
    projectId: 'rently-ph',
    storageBucket: 'rently-ph.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyD-GpYMJ5nbDIAG--tiLR6hKSEzgPtpwh8',
    appId: '1:58561207998:ios:524440ca2bea980e8388ef',
    messagingSenderId: '58561207998',
    projectId: 'rently-ph',
    storageBucket: 'rently-ph.firebasestorage.app',
    iosBundleId: 'com.example.rently',
  );
}
