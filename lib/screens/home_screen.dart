import 'dart:async';
import 'package:flutter/material.dart';
import '../services/pocketbase_service.dart';
import '../screens/profile_screen.dart';
import '../screens/map_screen.dart';
import 'package:geolocator/geolocator.dart';

///TO DO!!! ADD MORE WAIT TIME FOR:
///1. login to home screen
///2. loading the map

class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  HomeScreen({super.key, required this.userData});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<dynamic> rideHistory = [];
  bool isLoading = true;
  Map<String, dynamic>? selectedLocations;
  List<Map<String, dynamic>> nearbyDrivers = [];
  Timer? driverUpdateTimer; // ✅ Declare it here
  bool isDriver = false;
  Map<String, dynamic>? incomingRide; // Stores the incoming ride request
  StreamSubscription? rideListener;
  bool isActive = false;
  String? rideStatus;
  String? rideId;
  Map<String, dynamic>? ongoingRide;
  StreamSubscription? rideStatusListener;
  bool isDataLoaded = false; // ✅ Ensures UI waits for data
  bool _canConfirmPickup = false;

  @override
  void initState() {
    super.initState();
    _checkOngoingRide();

    print("🔍 [HomeScreen] Received userData: ${widget.userData}");

    List<String> roles = [];
    if (widget.userData.containsKey("record") &&
        widget.userData["record"].containsKey("role")) {
      var roleField = widget.userData["record"]["role"];
      if (roleField is String) {
        roles = [roleField];
      } else if (roleField is List) {
        roles = roleField.cast<String>();
      }
    }

    isDriver = roles.contains("driver");
    bool isRider = roles.contains("rider");

    _fetchRides();
    _startDriverUpdates();
    _listenForRideUpdates(); // ✅ Start listening for ride updates

    if (isDriver) {
      PocketBaseService()
          .startDriverLocationUpdates(widget.userData["record"]["id"]);
      _listenForNewRides(); // ✅ Start listening for ride requests if driver
    } else if (isRider) {
      PocketBaseService()
          .startRiderLocationUpdates(widget.userData["record"]["id"]);
    }

    if (isDriver) {
      _checkDriverActiveRide();

      Timer.periodic(const Duration(seconds: 3), (timer) {
        if (!mounted || (incomingRide?['status'] == "in_progress")) {
          print(
              "⏹️ Stopping distance checks. Ride in progress or screen closed.");
          timer.cancel(); // ✅ Stop checking when ride starts
        } else {
          print("🔄 Checking if driver is near the rider...");
          _checkDriverActiveRide();
        }
      });
    }
  }

  void _listenForRideUpdates() {
    print("📡 Listening for ride status updates...");

    rideStatusListener =
        PocketBaseService().getRideUpdates().listen((rideData) {
      if (rideData != null && rideData['id'] == rideId && !isDriver) {
        print("🔄 Ride update received: ${rideData['status']}");

        setState(() {
          rideStatus = rideData['status'];

          /// ✅ If ride is completed or canceled, remove it from UI
          if (rideStatus == "completed" || rideStatus == "canceled") {
            print("🚗 Ride completed/canceled, clearing data...");
            rideId = null;
            ongoingRide = null;
          }
        });
      }
    });
  }

  void _checkDriverActiveRide() async {
    print("📡 Checking for driver's active ride...");

    Map<String, dynamic>? activeRide = await PocketBaseService()
        .fetchDriverActiveRide(widget.userData["record"]["id"]);

    if (activeRide != null) {
      print("✅ Driver has an active ride: ${activeRide['id']}");

      if (mounted) {
        setState(() {
          incomingRide = activeRide; // ✅ Store the ride in memory
          _canConfirmPickup = true; // ✅ Enable the Confirm Pickup button
        });
      }
    } else {
      print("🚫 No active ride found for driver.");
    }
  }

  /// ✅ Check if there is an active ride and store it
  void _checkOngoingRide() async {
    final ride = await PocketBaseService()
        .fetchOngoingRide(widget.userData["record"]["id"]);
    if (ride != null) {
      setState(() {
        ongoingRide = ride;
        rideId = ride['id']; // ✅ Ensure this updates correctly
        rideStatus = ride['status'];
      });
    }
    setState(() {
      isDataLoaded = true; // ✅ Mark data as fully loaded
    });
  }

  Future<void> _fetchRides() async {
    setState(() => isLoading = true);

    final rides = await PocketBaseService().fetchRides();

    setState(() {
      rideHistory = rides;
      isLoading = false;
    });

    print("✅ Ride history updated: ${rideHistory.length} rides loaded.");
  }

  void _startDriverUpdates() {
    if (!isDriver) return;

    driverUpdateTimer =
        Timer.periodic(const Duration(seconds: 5), (timer) async {
      LocationPermission permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        print("❌ Location permission denied! Requesting permission...");
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          print("❌ Location permission denied by user.");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Please enable location services for Otto in Settings.')),
          );
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        print(
            "🚨 Location permission permanently denied! Ask user to enable manually.");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Go to Settings > Otto to enable location.')),
        );
        return;
      }

      if (!await Geolocator.isLocationServiceEnabled()) {
        print("🚨 Location services are turned off!");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Please enable Location Services in Settings.')),
        );
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      print(
          "📡 Sending driver location update: (${position.latitude}, ${position.longitude})");

      await PocketBaseService().updateDriverLocation(
        driverId: widget.userData["record"]["id"],
        latitude: position.latitude,
        longitude: position.longitude,
      );

      print(
          "✅ Driver location updated: (${position.latitude}, ${position.longitude})");
    });
  }

  @override
  void dispose() {
    rideStatusListener?.cancel();
    driverUpdateTimer?.cancel();
    rideListener?.cancel(); // ✅ Stop listening when leaving
    if (isDriver) {
      PocketBaseService()
          .stopDriverLocationUpdates(widget.userData["record"]["id"]);
    }
    super.dispose();
  }

// new
  void _listenForNewRides() {
    if (!isDriver) return; // ✅ Only listen if the user is a driver

    print("📡 Listening for new ride requests...");

    rideListener = PocketBaseService().getRideStream().listen((newRide) {
      if (newRide != null) {
        print("🚗 New Ride Detected: $newRide");

        setState(() {
          incomingRide = newRide;
        });

        _showRideRequestPopup(newRide);
      } else {
        print("⚠️ Warning: Received a null ride update.");
      }
    });
  }

  void _showRideRequestPopup(Map<String, dynamic> ride) {
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing without response
      builder: (context) {
        return AlertDialog(
          title: const Text("🚗 New Ride Available!"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Pickup: ${ride['pickup_location']}"),
              Text("Dropoff: ${ride['dropoff_location']}"),
              const SizedBox(height: 10),
              const Text("Do you want to accept this ride?",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                print("❌ Ride Declined!");
                setState(() {
                  incomingRide = null;
                });
              },
              child: const Text("Decline"),
            ),
            ElevatedButton(
              onPressed: () => _acceptRide(ride),
              child: const Text("Accept"),
            ),
          ],
        );
      },
    );
  }

  /// ✅ Accept Ride Request and Assign to Driver
  void _acceptRide(Map<String, dynamic> ride) async {
    String? rideId = ride['id']; // Extract ride ID

    if (rideId == null || rideId.isEmpty) {
      print("🚨 ERROR: Ride ID is missing or invalid!");
      return;
    }

    print("📡 Verifying ride in database: Ride ID = $rideId");

    bool success = await PocketBaseService().assignRideToDriver(
      rideId,
      widget.userData["record"]["id"],
    );

    if (success) {
      print("✅ Ride accepted! Assigned to driver.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride accepted! Heading to pickup.')),
      );
      Navigator.pop(context);
    } else {
      print("❌ Failed to accept ride.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to accept ride. Try again.')),
      );
      Navigator.pop(context);
    }
    setState(() {
      incomingRide = null; // Clear the incoming ride after handling
    });
  }

//new end

  /// ✅ Toggle Driver Active State
  void _toggleActiveState(bool value) async {
    setState(() {
      isActive = value;
    });

    bool success = await PocketBaseService().updateDriverActiveStatus(
      widget.userData["record"]["id"],
      isActive,
    );

    if (!success) {
      setState(() {
        isActive = !value; // Revert on failure
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to update active status.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text("Welcome, ${widget.userData['record']['name'] ?? 'Unknown'}"),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person, size: 50),
              title: Text(widget.userData['record']['name'] ?? 'No name'),
              subtitle: Text(
                  "User ID: ${widget.userData['record']['id'] ?? 'No ID'}"),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ProfileScreen(userData: widget.userData),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 20),

          //If ride not accepted or in progress, show "Open Map"
          if (isDataLoaded &&
              !isDriver &&
              (rideStatus != "accepted") &&
              (rideStatus != "in_progress")) ...[
            ElevatedButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => MapScreen(userData: widget.userData),
                  ),
                ).then((_) {
                  // 👈 This runs when the user returns from MapScreen
                  _checkOngoingRide(); // ✅ Refresh home screen data
                });
              },
              child: const Text("Open Map"),
            ),

            /// ✅ Show "Ongoing Ride" if there is an active ride
          ] else if (isDataLoaded &&
              !isDriver &&
              rideId != null &&
              rideStatus != null) ...[
            if (rideStatus == "accepted" || rideStatus == "in_progress") ...[
              Card(
                elevation: 4,
                margin: const EdgeInsets.symmetric(vertical: 10),
                child: ListTile(
                  leading: const Icon(Icons.directions_car,
                      size: 40, color: Colors.orange),
                  title: const Text("Ongoing Ride"),
                  subtitle: Text("Status: $rideStatus"),
                  trailing: IconButton(
                    icon: const Icon(Icons.arrow_forward),
                    onPressed: () {
                      /// ✅ Navigate back to the active ride
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MapScreen(
                            userData: widget.userData,
                            rideId: rideId, // ✅ Use existing rideId
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ],
          if (isDriver) ...[ 
            const Text("Driver Mode: Toggle Availability",
                style: TextStyle(fontSize: 18)),
            SwitchListTile(
              title: Text(isActive
                  ? "🟢 Active (Available for rides)"
                  : "🔴 Inactive (Not receiving rides)"),
              value: isActive,
              onChanged: _toggleActiveState,
            ),
            const SizedBox(height: 20),
          ],

          if (isDriver && incomingRide!['status'] != "in_progress") ...[
            ElevatedButton(
              onPressed: _canConfirmPickup
                  ? () async {
                      bool success = await PocketBaseService()
                          .updateRideStatus(incomingRide!['id'], "in_progress");

                      if (success) {
                        setState(() {
                          incomingRide!['status'] =
                              "in_progress"; // ✅ Update UI
                        });
                        print("✅ Ride status updated to IN PROGRESS");
                      } else {
                        print("❌ Failed to update ride status.");
                      }
                    }
                  : null, // ❌ Disabled if driver is too far
              child: const Text("Confirm Pickup"),
            ),
          ],
        ],
      ),
    );
  }
}
