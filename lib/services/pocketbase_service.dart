import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:pocketbase/pocketbase.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart' show rootBundle;

class PocketBaseService {
  static final PocketBase pb = PocketBase('https://wide-ends-rule.loca.lt');
  StreamSubscription<Position>? locationStream;

    /// ✅ Listen for real-time ride updates
  Stream<Map<String, dynamic>?> getRideUpdates() {
    final controller = StreamController<Map<String, dynamic>?>();

    pb.collection('rides').subscribe('*', (e) {
      print("📡 Ride Update Received: ${e.record?.toJson()}");
      controller.add(e.record?.toJson()); // Add ride update to stream
    });

    return controller.stream;
  }

  // ✅ User Authentication
  Future<Map<String, dynamic>?> login(String identity, String password) async {
  try {
    final authData = await pb.collection('users').authWithPassword(identity, password)
        .timeout(const Duration(seconds: 20)); //TO DO in the future: make it dynamic, so everything shows after everything else loads

    final user = authData.toJson();
    print("✅ [PocketBase] Full login response: $user");

    if (user.containsKey('record') && user['record'].containsKey('id')) {
      user['id'] = user['record']['id'];
      print("✅ [PocketBase] Extracted user ID: ${user['id']}");

      // ✅ Retrieve FCM token from Firebase
      String? fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        print("✅ [Firebase] User's FCM Token: $fcmToken");
        await updateUserFcmToken(user['id'], fcmToken); // Store in PocketBase
      } else {
        print("⚠️ [Firebase] Failed to retrieve FCM token!");
      }

      await setUserActive(user['id'], true); // Mark user as active
    } else {
      print("❌ [PocketBase] ERROR: User ID is missing from response!");
      return null;
    }

    return user;
  } catch (e) {
    print("❌ [PocketBase] Login failed: $e");
    return null;
  }
}

/// ✅ Listen for new ride requests in real-time
Stream<Map<String, dynamic>?> listenForNewRides() {
  final controller = StreamController<Map<String, dynamic>?>();

  print("📡 Subscribing to new ride requests in PocketBase...");

  pb.collection('rides').subscribe('*', (e) {
    if (e.action == "create" && e.record != null) {
      final rideData = e.record!.toJson();
      print("🚗 New Ride Detected: ${rideData['id']} - Status: ${rideData['status']}");
      controller.add(rideData);
    } else {
      print("⚠️ Warning: Ride update received, but it's not a new request.");
    }
  });

  return controller.stream;
}

/// ✅ Get Driver Active Status
Future<bool> getDriverActiveStatus(String driverId) async {
  try {
    final driver = await pb.collection('users').getOne(driverId);
    return driver.toJson()['active'] ?? false; // Default to false if not found
  } catch (e) {
    print("❌ Failed to fetch driver active status: $e");
    return false;
  }
}

/// ✅ Fetch ride details by Ride ID
Future<Map<String, dynamic>?> getRideById(String rideId) async {
  try {
    final rideResponse = await pb.collection('rides').getOne(rideId);
    
    // ✅ Ensure the response is properly converted to a Map
    if (rideResponse != null) {
      return rideResponse.toJson(); // ✅ Returns a Map<String, dynamic>
    } else {
      print("🚫 Ride not found in PocketBase");
      return null;
    }
  } catch (e) {
    print("❌ Error fetching ride: $e");
    return null;
  }
}

// ✅ Update user's FCM token in PocketBase
Future<void> updateUserFcmToken(String userId, String fcmToken) async {
  try {
    await pb.collection('users').update(userId, body: {
      "fcm_token": fcmToken,
    });

    print("✅ FCM token updated for user: $userId");
  } catch (e) {
    print("❌ Failed to update FCM token: $e");
  }
}

Future<Map<String, dynamic>?> updateUser(String userId, String name, String phone) async {
  try {
    final response = await pb.collection('users').update(userId, body: {
      "name": name,
      "phone": phone,
    });

    print("✅ User updated: ${response.toJson()}");
    return response.toJson(); // Ensure we return a valid updated user object
  } catch (e) {
    print("❌ ERROR updating user: $e");
    return null;
  }
}

  // ✅ Set user as active/inactive
  Future<void> setUserActive(String userId, bool isActive) async {
    try {
      await pb.collection('users').update(userId, body: {
        "active": isActive,
      });
      print("✅ User $userId is now ${isActive ? "active" : "inactive"}.");
    } catch (e) {
      print("❌ ERROR setting user active status: $e");
    }
  }

  // ✅ Start live location updates for drivers
  Future<void> startDriverLocationUpdates(String userId) async {
    try {
      print("🚗 Starting live location updates for driver $userId");

      locationStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).listen((Position position) async {
        print("📍 New Driver Location: ${position.latitude}, ${position.longitude}");

        await pb.collection('users').update(userId, body: {
          "latitude": position.latitude,
          "longitude": position.longitude,
          "role": "driver",
          "active": true, // ✅ Ensure the driver is active
        });

        print("✅ Updated driver location in PocketBase");
      });
    } catch (e) {
      print("❌ Failed to start location updates: $e");
    }
  }

  

  // ✅ Stop live updates when driver logs out
  Future<void> stopDriverLocationUpdates(String userId) async {
    print("🛑 Stopping live location updates...");
    await locationStream?.cancel();
    
    // ✅ Mark driver as inactive on logout
    await setUserActive(userId, false);
  }

  // ✅ Start live location updates for riders
  Future<void> startRiderLocationUpdates(String userId) async {
    try {
      print("🛺 Starting live location updates for rider $userId");

      locationStream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
      ).listen((Position position) async {
        print("📍 New Rider Location: ${position.latitude}, ${position.longitude}");

        await pb.collection('users').update(userId, body: {
          "latitude": position.latitude,
          "longitude": position.longitude,
          "active": true, // ✅ Ensure rider is marked active
        });

        print("✅ Updated rider location in PocketBase");
      });
    } catch (e) {
      print("❌ Failed to start location updates: $e");
    }
  }

/// ✅ Fetch the ongoing ride for a user (excluding canceled, completed, and requested)
Future<Map<String, dynamic>?> fetchOngoingRide(String riderId) async {
  try {
    print("📡 Checking for ongoing ride...");

    final result = await pb.collection('rides').getList(
      page: 1,
      perPage: 1,
      filter: "rider = '$riderId' && (status = 'accepted' || status = 'in_progress')",
      sort: "-created",
    );

    if (result.items.isEmpty) {
      print("🚫 No ongoing ride found.");
      return null;
    }

    final ride = result.items.first.toJson();
    print("✅ Ongoing ride found: ${ride['id']} - Status: ${ride['status']}");
    return ride;
  } catch (e) {
    print("❌ ERROR fetching ongoing ride: $e");
    return null;
  }
}


/// ✅ Fetch active ride from PocketBase
Future<Map<String, dynamic>?> fetchActiveRide(String riderId) async {
  try {
    print("📡 Checking active ride for rider: $riderId");

    final result = await pb.collection('rides').getList(
      page: 1, // ✅ Fetch the latest ride only
      perPage: 1, // ✅ Now correctly placed
      filter: "rider = '$riderId' && (status = 'requested' || status = 'accepted' || status = 'in_progress')",
      sort: "-created",
    );

    if (result.items.isEmpty) {
      print("🚫 No active ride found for rider: $riderId");
      return null;
    }

    final ride = result.items.first.toJson();
    print("✅ Active ride found: ${ride['id']} - Status: ${ride['status']}");
    return ride;
  } catch (e) {
    print("❌ ERROR fetching active ride: $e");
    return null;
  }
}

  // ✅ Save ride request
// ✅ Save ride request & notify drivers
Future<String?> saveRideRequest({
  required String rider,
  required double pickupLat,
  required double pickupLng,
  required double dropoffLat,
  required double dropoffLng,
}) async {
  try {
    final requestBody = {
      "driver": "", 
      "rider": rider,
      "price": 0,
      "status": "requested",
      "invoiceSent": false,
      "invoice": "",
      "pickup_location": jsonEncode({
        "latitude": pickupLat,
        "longitude": pickupLng,
      }),
      "dropoff_location": jsonEncode({
        "latitude": dropoffLat,
        "longitude": dropoffLng,
      }),
      "distance": 0,
      "duration": 0,
      "start_time": "",
      "end_time": "",
      "payment_status": "pending",
    };

    print("📡 Sending ride request: $requestBody");

    final ride = await pb.collection('rides').create(body: requestBody);

    print("✅ Ride request saved: ${ride.toJson()}");
    return ride.id;  // ✅ Correct! Returns ride ID
  } catch (e) {
    print("❌ Failed to save ride request: $e");
    return null;
  }
}

Future<bool> updateRideStatus(String rideId, String newStatus) async {
  try {
    await pb.collection('rides').update(rideId, body: {
      "status": newStatus,
    });

    print("✅ Ride $rideId status updated to '$newStatus'");
    return true;
  } catch (e) {
    print("❌ Failed to update ride status: $e");
    return false;
  }
}

Stream<Map<String, dynamic>?> getRideStream() {
  final controller = StreamController<Map<String, dynamic>?>();

  print("📡 Subscribing to PocketBase ride updates...");

  pb.collection('rides').subscribe('*', (e) {
    if (e.record != null) {
      print("🔔 Real-time ride update received: ${e.record}");

      controller.add(e.record!.toJson()); // ✅ Send ride data to the listener
    } else {
      print("⚠️ Warning: Received an update, but the record is null!");
    }
  });

  return controller.stream;
}




// ✅ Fetch Driver Details
Future<Map<String, dynamic>?> fetchDriverDetails(String driverId) async {
  try {
    final driver = await pb.collection('users').getOne(driverId);
    return driver.toJson();
  } catch (e) {
    print("❌ Error fetching driver details: $e");
    return null;
  }
}

// ✅ Fetch Vehicle Details
Future<Map<String, dynamic>?> fetchVehicleDetails(String vehicleId) async {
  if (vehicleId == null || vehicleId.isEmpty) return null;

  try {
    final vehicle = await pb.collection('vehicles').getOne(vehicleId);
    return vehicle.toJson();
  } catch (e) {
    print("❌ Error fetching vehicle details: $e");
    return null;
  }
}

// ✅ Calculate ETA (Basic Haversine Formula)
Future<double> calculateETA({
  required double driverLat,
  required double driverLng,
  required double pickupLat,
  required double pickupLng,
}) async {
  const double speedKmPerHour = 40.0; // Assume an average urban speed
  double distanceKm = _calculateDistance(driverLat, driverLng, pickupLat, pickupLng);
  return (distanceKm / speedKmPerHour) * 60; // Convert to minutes
}

  /// ✅ Assign Ride to Driver
  Future<bool> assignRideToDriver(String rideId, String driverId) async {
  try {
    print("🔍 Checking if ride exists in PocketBase: Ride ID = $rideId");

    // ✅ Fetch ride before updating to ensure it exists
    final rideRecord = await pb.collection('rides').getOne(rideId);

    if (rideRecord == null) {
      print("❌ ERROR: Ride $rideId does not exist in PocketBase!");
      return false;
    }

    print("✅ Ride exists! Assigning driver...");

    // ✅ Update the ride with the driver ID
    await pb.collection('rides').update(rideId, body: {
      "driver": driverId,
      "status": "accepted",
    });

    print("✅ Ride $rideId successfully assigned to Driver $driverId");
    return true;
  } catch (e) {
    print("❌ Failed to assign ride to driver: $e");
    return false;
  }
}

  // ✅ Find nearby active drivers (within Xkm)
  Future<List<Map<String, dynamic>>> findNearbyDrivers({
  required double riderLat,
  required double riderLng,
  double radiusKm = 5.0, //change search radius here
  required String userId,
}) async {
  try {
    print("📡 Fetching active drivers from PocketBase...");

    // ✅ DEBUG: Fetch all users from the collection
    final users = await pb.collection('users').getFullList();

    print("🔍 Total users in DB: ${users.length}");

    if (users.isEmpty) {
      print("❌ No users found in database!");
      return [];
    }

    // ✅ DEBUG: Print all users before filtering
    for (var user in users) {
      var json = user.toJson();
      print("📝 USER: ID: ${json['id']}, Role: ${json['role']}, Active: ${json['active']}, Lat: ${json['latitude']}, Lng: ${json['longitude']}");
    }

    // ✅ Fetch only active drivers
    final activeDrivers = users
        .map((user) => user.toJson())
        .where((user) {
          if (user["role"] != "driver") {
            print("🚫 Skipping user ${user["id"]} - Not a driver.");
            return false;
          }
          if (user["active"] != true) {
            print("🚫 Skipping user ${user["id"]} - Not active.");
            return false;
          }
          if (!user.containsKey("latitude") || !user.containsKey("longitude")) {
            print("🚫 Skipping user ${user["id"]} - Missing location data.");
            return false;
          }

          double driverLat = (user["latitude"] as num).toDouble();
          double driverLng = (user["longitude"] as num).toDouble();
          double distance = _calculateDistance(riderLat, riderLng, driverLat, driverLng);

          if (user["id"] == userId) {
            print("🚫 Excluding self from search: ${user["id"]}");
            return false;
          }

          return distance <= radiusKm;
        })
        .toList();

    print("✅ Found ${activeDrivers.length} active drivers nearby.");

    return activeDrivers;
  } catch (e) {
    print("❌ Failed to find drivers: $e");
    return [];
  }
}

Future<Map<String, dynamic>?> fetchLatestOngoingRide(String userId) async {
  try {
    print("📡 Fetching the latest ongoing ride for user: $userId...");

    final result = await pb.collection('rides').getList(
      page: 1, 
      perPage: 1, 
      filter: "rider = '$userId' && (status = 'accepted' || status = 'in_progress')",
      sort: "-created",
    );

    if (result.items.isEmpty) {
      print("🚫 No active ride found for user: $userId");
      return null;
    }

    final ride = result.items.first.toJson();
    print("✅ Latest ongoing ride found: ${ride['id']} - Status: ${ride['status']}");
    return ride;
  } catch (e) {
    print("❌ ERROR fetching latest ongoing ride: $e");
    return null;
  }
}

  // ✅ Fetch ride history
  Future<List<dynamic>> fetchRides() async {
    try {
      final records = await pb.collection('rides').getFullList();
      List<dynamic> rideList = records.map((record) => record.toJson()).toList();
      print("✅ Fetched ${rideList.length} rides.");
      return rideList;
    } catch (e) {
      print("❌ Error fetching rides: $e");
      return [];
    }
  }

  /// ✅ Check ride status for a rider
Future<String?> checkRideStatus(String riderId) async {
  try {
    final rides = await pb.collection('rides').getFullList(
      filter: "rider = '$riderId' AND status != 'completed'",
    );

    if (rides.isNotEmpty) {
      final latestRide = rides.last.toJson();
      print("📝 Ride Status: ${latestRide['status']}");
      return latestRide['status'];
    }
    return null;
  } catch (e) {
    print("❌ ERROR checking ride status: $e");
    return null;
  }
}

    /// ✅ Update Driver Active Status in PocketBase
  Future<bool> updateDriverActiveStatus(String driverId, bool isActive) async {
    try {
      await pb.collection('users').update(driverId, body: {
        "active": isActive,
      });

      print("✅ Driver active status updated: $isActive");
      return true;
    } catch (e) {
      print("❌ Failed to update driver active status: $e");
      return false;
    }
  }

  // ✅ Send push notifications to nearby drivers
Future<void> _sendPushNotificationToDrivers(double pickupLat, double pickupLng) async {
  try {
    final drivers = await findNearbyDrivers(
      riderLat: pickupLat,
      riderLng: pickupLng,
      userId: "",
    );

    if (drivers.isEmpty) {
      print("❌ No active drivers found, skipping push notifications.");
      return;
    }

    // Load the Firebase service account credentials
    final serviceAccount = jsonDecode(await rootBundle.loadString('assets/service-account.json'));

    final client = await clientViaServiceAccount(
      ServiceAccountCredentials.fromJson(serviceAccount),
      ['https://www.googleapis.com/auth/firebase.messaging'],
    );

    for (var driver in drivers) {
      String? token = driver["fcm_token"] as String?;

      if (token == null || token.isEmpty) {
        print("⚠️ Driver ${driver['id']} has an invalid FCM token!");
        continue;
      }

      final Map<String, dynamic> notificationData = {
        "message": {
          "token": token,
          "notification": {
            "title": "🚗 New Ride Request",
            "body": "A rider near you is looking for a ride!",
          },
          "data": {
            "pickup_latitude": pickupLat.toString(),
            "pickup_longitude": pickupLng.toString(),
          }
        }
      };

      final response = await client.post(
        Uri.parse("https://fcm.googleapis.com/v1/projects/otto---ride-sharing/messages:send"),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode(notificationData),
      );

      if (response.statusCode == 200) {
        print("✅ Notification successfully sent to Driver: ${driver['id']}");
      } else {
        print("❌ Failed to send notification to ${driver['id']}. Error: ${response.body}");
      }
    }

    client.close();
  } catch (e) {
    print("❌ Failed to send push notifications: $e");
  }
}

  // ✅ Update driver location
  Future<void> updateDriverLocation({
    required String driverId,
    required double latitude,
    required double longitude,
  }) async {
    try {
      await pb.collection('users').update(driverId, body: {
        "latitude": latitude,
        "longitude": longitude,
      });
      print("✅ Driver $driverId location updated: ($latitude, $longitude)");
    } catch (e) {
      print("❌ Failed to update driver location: $e");
    }
  }

  // ✅ Helper function: Calculate distance between two coordinates
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371;
    double dLat = _degToRad(lat2 - lat1);
    double dLon = _degToRad(lon2 - lon1);
    double a = sin(dLat / 2) * sin(dLat / 2) +
               cos(_degToRad(lat1)) * cos(_degToRad(lat2)) *
               sin(dLon / 2) * sin(dLon / 2);
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degToRad(double deg) {
    return deg * (pi / 180);
  }
}