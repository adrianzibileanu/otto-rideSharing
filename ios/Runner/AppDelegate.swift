import UIKit
import Flutter
import FirebaseCore
import FirebaseMessaging
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    print("🚀 App is starting...")

    // ✅ Initialize Firebase (Ensure it's done only once)
    if FirebaseApp.app() == nil {
      FirebaseApp.configure()
      print("✅ Firebase successfully initialized in AppDelegate.swift")
    }

    // ✅ Ensure Firebase Messaging Delegate is Set
    Messaging.messaging().delegate = self 

    // ✅ Register plugins
    GeneratedPluginRegistrant.register(with: self)

    // ✅ Setup push notifications
    requestPushNotificationPermissions(application)

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // ✅ Request push notification permissions
  private func requestPushNotificationPermissions(_ application: UIApplication) {
    let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
    UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
      if granted {
        print("✅ Notification permission granted!")
      } else {
        print("❌ Notification permission denied! Error: \(String(describing: error))")
      }
    }

    DispatchQueue.main.async {
      application.registerForRemoteNotifications()
    }
  }

  // ✅ Handle successful registration for push notifications
  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Messaging.messaging().apnsToken = deviceToken
    let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    print("✅ Successfully registered for push notifications! APNs Token: \(tokenString)")
  }

  // ✅ Handle failure to register for push notifications
  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    print("❌ Failed to register for remote notifications: \(error.localizedDescription)")
  }

  // ✅ Handle incoming push notifications while the app is in the foreground
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    print("📩 Received push notification in foreground: \(notification.request.content.userInfo)")
    completionHandler([.alert, .sound, .badge])
  }

  // ✅ Handle notification taps when the app is opened from a notification
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let userInfo = response.notification.request.content.userInfo
    print("📩 Opened notification: \(userInfo)")
    completionHandler()
  }
}

// ✅ Implement MessagingDelegate in an extension (Avoids Redundant Protocol Conformance)
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    print("✅ Firebase registration token received: \(String(describing: fcmToken))")
    // Send the token to your backend if needed
  }
}