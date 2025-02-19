import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/login_screen.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
    await setupRemoteConfig(); // ✅ Load Remote Config
    print("✅ Firebase successfully initialized!");
  } catch (e) {
    print("❌ Firebase initialization failed: $e");
  }

  FirebaseMessaging messaging = FirebaseMessaging.instance;

  // Request push notification permissions
  NotificationSettings settings = await messaging.requestPermission(
    alert: true,
    badge: true,
    sound: true,
  );

  if (settings.authorizationStatus == AuthorizationStatus.authorized) {
    print("✅ Push notifications enabled!");
  } else {
    print("❌ Push notifications denied!");
  }

  // Handle messages when app is in foreground
  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print("📩 New notification received: ${message.notification?.title}");
    if (message.notification != null) {
      print("📜 Message: ${message.notification?.body}");
    }
  });

  // Handle notification taps when app is opened from background
  FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
    print("📩 Opened notification: ${message.notification?.title}");
  });
  
  runApp(const MyApp());
}



PocketBase? pb; // ✅ Declare PocketBase globally
Future<void> setupRemoteConfig() async {

  final remoteConfig = FirebaseRemoteConfig.instance;

  await remoteConfig.setConfigSettings(RemoteConfigSettings(
    fetchTimeout: const Duration(seconds: 10), // ✅ Max time to wait for fetch
    minimumFetchInterval: const Duration(minutes: 5), // ✅ Refresh every 5 minutes
  ));

  await remoteConfig.fetchAndActivate(); // ✅ Fetch latest values

  String pocketBaseUrl = remoteConfig.getString("pocketbase_url");

  if (pocketBaseUrl.isNotEmpty) {
    print("✅ PocketBase URL from Firebase: $pocketBaseUrl");
  } else {
    print("❌ Failed to get PocketBase URL, using default.");
    pocketBaseUrl = "http://5.75.142.186"; // ✅ Fallback URL
  }

  // ✅ Initialize PocketBase globally with dynamic URL
  pb = PocketBase(pocketBaseUrl);
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'oTTo - Ride Sharing',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const LoginScreen(),
      },
    );
  }
}