import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp();
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