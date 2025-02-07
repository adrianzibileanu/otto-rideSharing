import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../services/pocketbase_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert'; // ✅ Required for jsonDecode

class MapScreen extends StatefulWidget {
  final Map<String, dynamic> userData;
  final String? rideId;

  MapScreen({super.key, required this.userData, this.rideId});

  @override
  _MapScreenState createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  List<Map<String, dynamic>> nearbyDrivers = [];
  LatLng? pickupLocation;
  LatLng? dropoffLocation;
  bool isLoading = true;
  bool isWaitingForDriver = false;
  bool showConfirmButton = true;
  String? rideId;
  Map<String, dynamic>? assignedDriver; // Holds driver details
  Map<String, dynamic>? driverVehicle; // Holds vehicle details
  double? driverETA; // Holds ETA in minutes
  bool isDriverAssigned = false;
  bool isSheetExpanded = false;
  String? rideStatus;
  String pb = "https://wide-ends-rule.loca.lt";

  @override
  void initState() {
    super.initState();
    _restoreRideState();
  }



String getProfileImageUrl(String? imagePath) {
  if (imagePath == null || imagePath.isEmpty) {
    return ""; // Return empty string if no image
  }

  // Ensure proper full URL format
  return "$pb/api/files/_pb_users_auth_/$imagePath";
}



  /// ✅ Find Nearby Drivers Based on Pickup Location
  void _findDrivers() async {
    if (pickupLocation == null) {
      print("❌ No pickup location set, skipping driver search.");
      return;
    }

    String userId = widget.userData["record"]["id"];
    double searchLat = pickupLocation!.latitude;
    double searchLng = pickupLocation!.longitude;

    print("📡 Searching for nearby drivers around pickup location: ($searchLat, $searchLng)");
    if (!mounted) return; // ✅ Prevent setState() if widget is disposed
    setState(() => isLoading = true);

    List<Map<String, dynamic>> drivers = await PocketBaseService().findNearbyDrivers(
      riderLat: searchLat,
      riderLng: searchLng,
      userId: userId,
    );

if (!mounted) return; // ✅ Prevent setState() if widget is disposed
    setState(() {
     nearbyDrivers = drivers;
     isLoading = true;
  });
    /*setState(() {
      nearbyDrivers = drivers;
      isLoading = false;
    });*/

    print("📝 Drivers received in UI: $nearbyDrivers");

    if (drivers.isEmpty) {
      print("❌ No drivers found near the pickup location.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No drivers found near pickup location!')),
      );
    } else {
      print("✅ Found ${drivers.length} drivers! Updating map...");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${drivers.length} drivers found near pickup!')),
      );
    }
  }

  /// ✅ Set Pickup Location & Search for Drivers
  void _setPickup(LatLng point) {

 if (rideId != null) {
    print("🚫 Cannot change pickup location, ride is already created.");
    return;
  }

    setState(() {
      pickupLocation = point;
    });
    print("📍 Pickup set: $point");
    _findDrivers(); // 🔄 Find drivers near the pickup location
  }

  /// ✅ Set Dropoff Location
  void _setDropoff(LatLng point) {

  if (rideId != null) {
    print("🚫 Cannot change dropoff location, ride is already created.");
    return;
  }

    setState(() {
      dropoffLocation = point;
    });
    print("📍 Dropoff set: $point");
  }

  /// ✅ Confirm Ride Request and Save in PocketBase
 void _confirmRideRequest() async {
  if (pickupLocation == null) {
    print("🚨 ERROR: Cannot confirm ride. No pickup location set!");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Please select a pickup location before confirming.')),
    );
    return;
  }

  print("📡 Sending ride request to PocketBase...");

  try {
    final String? newRideId = await PocketBaseService().saveRideRequest(
      rider: widget.userData['record']['id'],
      pickupLat: pickupLocation!.latitude,
      pickupLng: pickupLocation!.longitude,
      dropoffLat: dropoffLocation?.latitude ?? pickupLocation!.latitude,
      dropoffLng: dropoffLocation?.longitude ?? pickupLocation!.longitude,
    );

    print("✅ Ride request result: $newRideId");

    if (newRideId != null && newRideId.isNotEmpty) {
      print("✅ Ride request successfully created!");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ride request submitted!')),
      );

      _listenForDriverAssignment(); // Start listening for driver assignment

      setState(() {
        isWaitingForDriver = true;
        rideId = newRideId; // ✅ Store the ride ID correctly
      });
    } else {
      print("❌ Failed to create ride request.");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit ride request.')),
      );
    }
  } catch (e) {
    print("❌ Exception while confirming ride: $e");
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Error: ${e.toString()}')),
    );
  }
}

/// ✅ Parse location from PocketBase response
LatLng _parseLocation(dynamic locationData) {
  if (locationData == null) {
    print("⚠️ Location data is null!");
    return LatLng(0.0, 0.0); // Default fallback
  }

  try {
    Map<String, dynamic> decodedLocation = locationData is String
        ? jsonDecode(locationData)
        : locationData;

    return LatLng(
      (decodedLocation['latitude'] as num).toDouble(),
      (decodedLocation['longitude'] as num).toDouble(),
    );
  } catch (e) {
    print("❌ Error parsing location data: $e");
    return LatLng(0.0, 0.0);
  }
}


void _showDriverInfoSheet() {
  if (assignedDriver == null || driverVehicle == null) return;

  showModalBottomSheet(
    context: context,
    isDismissible: false, // Prevent dismissing
    builder: (context) {
      return Container(
        padding: const EdgeInsets.all(16),
        height: 250,
        child: Column(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundImage: assignedDriver?['profile_picture'] != null && assignedDriver?['profile_picture'].isNotEmpty
                    ? NetworkImage((getProfileImageUrl(assignedDriver?['profile_picture'])))
                    : null,
                child: assignedDriver?['profile_picture'] == null ? const Icon(Icons.person) : null,
              ),
              title: Text("${assignedDriver?['name'] ?? 'Unknown Driver'}"),
              subtitle: Text("⭐ ${assignedDriver?['rating'] ?? 'No rating'}"),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.directions_car),
              title: Text("${driverVehicle?['make']} ${driverVehicle?['model']}"),
              subtitle: Text("Color: ${driverVehicle?['color']} | Plates: ${driverVehicle?['license_plate']}"),
            ),
            const Divider(),
            Text("⏳ Estimated Arrival: ${driverETA?.toStringAsFixed(1)} mins"),
          ],
        ),
      );
    },
  );
}


void _listenForDriverAssignment() {
  print("📡 Listening for driver assignment...");
  
  PocketBaseService().getRideUpdates().listen((rideData) async {
    if (rideData != null && rideData['status'] == 'accepted') {
      print("✅ Driver assigned! Fetching details...");

      Map<String, dynamic>? driverData = await PocketBaseService().fetchDriverDetails(rideData['driver']);
      Map<String, dynamic>? vehicleData = await PocketBaseService().fetchVehicleDetails(driverData?['linked_vehicle']);

      double eta = await PocketBaseService().calculateETA(
        driverLat: driverData?['latitude'],
        driverLng: driverData?['longitude'],
        pickupLat: pickupLocation!.latitude,
        pickupLng: pickupLocation!.longitude,
      );

      setState(() {
        assignedDriver = driverData;
        driverVehicle = vehicleData;
        driverETA = eta;
        isDriverAssigned = true;
        isWaitingForDriver = false; // ✅ Hide the "Looking for a driver..." UI
        nearbyDrivers = []; // ✅ Remove all other drivers once assigned
      });

      _showDriverInfoSheet();
    }
  });
  
}


void _restoreRideState() async {
  print("📡 Attempting to restore last ride state...");

  String userId = widget.userData["record"]["id"];
  Map<String, dynamic>? rideData = await PocketBaseService().fetchLatestOngoingRide(userId);

  if (rideData != null) {
    print("🔄 Ride Data Received: $rideData");

    setState(() {
      rideId = rideData['id'];
      isDriverAssigned = rideData['status'] == 'accepted' || rideData['status'] == 'in_progress';
      isWaitingForDriver = rideData['status'] == 'requested';
    });

    // ✅ Ensure driver details are fetched properly
    if (rideData['driver'] is String && rideData['driver'].isNotEmpty) {
      print("📡 Fetching driver details for ID: ${rideData['driver']}");

      Map<String, dynamic>? driverDetails = await PocketBaseService().fetchDriverDetails(rideData['driver']);
      if (driverDetails != null) {
        print("✅ Driver details received: $driverDetails");

        setState(() {
          assignedDriver = driverDetails;
        });

        // ✅ Fetch and store vehicle details
        if (driverDetails['linked_vehicle'] is String && driverDetails['linked_vehicle'].isNotEmpty) {
          print("📡 Fetching vehicle details for ID: ${driverDetails['linked_vehicle']}");

          Map<String, dynamic>? vehicleDetails = await PocketBaseService().fetchVehicleDetails(driverDetails['linked_vehicle']);
          if (vehicleDetails != null) {
            print("✅ Vehicle details received: $vehicleDetails");

            setState(() {
              driverVehicle = vehicleDetails;
            });
          } else {
            print("❌ Failed to fetch vehicle details.");
          }
        }
      } else {
        print("❌ Failed to fetch driver details.");
      }
    }

    // ✅ Ensure vehicle details are fetched properly if not included
    if (rideData['vehicle'] is String && rideData['vehicle'].isNotEmpty) {
      print("📡 Fetching vehicle details for ID: ${rideData['vehicle']}");

      Map<String, dynamic>? vehicleDetails = await PocketBaseService().fetchVehicleDetails(rideData['vehicle']);
      if (vehicleDetails != null) {
        print("✅ Vehicle details received: $vehicleDetails");

        setState(() {
          driverVehicle = vehicleDetails;
        });
      } else {
        print("❌ Failed to fetch vehicle details.");
      }
    }

double eta = await PocketBaseService().calculateETA(
        driverLat: assignedDriver?['latitude'],
        driverLng: assignedDriver?['longitude'],
        pickupLat: rideData["pickup_location"]["latitude"],
        pickupLng: rideData["pickup_location"]["longitude"],
      );

  //  if (rideData.containsKey('eta')) {
  //print("📡 Raw ETA value from server: ${rideData['eta']}");

 // if (rideData['eta'] is String) {
    driverETA = eta;//double.tryParse(rideData['eta']);=
//  } else if (rideData['eta'] is num) {
////    driverETA = eta;//(rideData['eta'] as num).toDouble();
 // } else {
 //   print("⚠️ Unexpected ETA format: ${eta}");
 // }

  

 /// print("✅ Parsed ETA: $driverETA");
//} else {
  //print("🚨 No ETA found in ride data!");
//}

    if (isDriverAssigned) {
      print("✅ Ride has a driver! Showing driver info...");
      _showDriverInfoSheet();
    }

    print("✅ Ride state restored successfully.");
  } else {
    print("🚫 No active ride found, resetting UI.");
    setState(() {
      rideId = null;
      isDriverAssigned = false;
      isWaitingForDriver = false;
      assignedDriver = null;
      driverVehicle = null;
      driverETA = null;
    });
  }
}

/// ✅ Warn Before Leaving If Ride is Still Requested
/// ✅ Warn Before Leaving If Ride is Still Requested
Future<bool> _handleBackNavigation() async {
  //here add the function to reload the home screen maybe
  if (isWaitingForDriver) {
    bool confirmExit = await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Cancel Ride Request?"),
          content: const Text(
              "If you go back now, your ride request will be canceled."),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("No, Keep Waiting"),
            ),
            TextButton(
              onPressed: () {
                _cancelRideRequest();
                Navigator.of(context).pop(true);
              },
              child: const Text("Yes, Cancel Ride"),
            ),
          ],
        );
      },
    );

    return confirmExit;
  } else if (isDriverAssigned && assignedDriver != null) {
    /// ✅ Preserve Active Ride State When Returning to Home Screen
    print("🚗 Active ride detected! Returning to home screen...");

    /// ✅ Ensure Rider Returns with Current Ride ID
    Navigator.pop(context, rideId);
    return false; // Prevent default back behavior
  }
  return true;
}

/// ✅ Cancel the Ride Request
void _cancelRideRequest() async {
  if (rideId == null || rideId!.isEmpty) {
    print("🚨 ERROR: No active ride to cancel! Ride ID is NULL or empty.");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('No active ride to cancel.')),
    );
    return;
  }

  print("❌ Canceling ride: $rideId...");

  bool success = await PocketBaseService().updateRideStatus(rideId!, "canceled");

  if (success) {
    print("✅ Ride canceled successfully!");

    setState(() {
      isWaitingForDriver = false;
      showConfirmButton = true;
      rideId = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ride request canceled.')),
    );
  } else {
    print("❌ Failed to cancel ride.");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Failed to cancel ride request.')),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _handleBackNavigation,
    child: Scaffold(
      appBar: AppBar(title: const Text("Live Driver Map")),
      body: Stack(
  children: [
    /// ✅ Main Map Display
    FlutterMap(
      options: MapOptions(
        center: pickupLocation ?? LatLng(44.3900, 26.0920),
        zoom: 15.0,
        onTap: (tapPosition, point) {
          if (pickupLocation == null) {
            _setPickup(point);
          } else {
            _setDropoff(point);
          }
        },
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
          subdomains: ['a', 'b', 'c'],
        ),
        MarkerLayer(
          markers: [
            if (pickupLocation != null)
              Marker(
                width: 40.0,
                height: 40.0,
                point: pickupLocation!,
                child: const Icon(Icons.location_on, color: Colors.green, size: 40),
              ),
            if (dropoffLocation != null)
              Marker(
                width: 40.0,
                height: 40.0,
                point: dropoffLocation!,
                child: const Icon(Icons.location_on, color: Colors.red, size: 40),
              ),
            // ✅ Show all nearby drivers BEFORE a ride is accepted
            if (!isDriverAssigned)
              ...nearbyDrivers.map(
                (driver) => Marker(
                  width: 40.0,
                  height: 40.0,
                  point: LatLng(
                    (driver['latitude'] as num).toDouble(),
                    (driver['longitude'] as num).toDouble(),
                  ),
                  child: const Icon(Icons.directions_car, color: Colors.blue, size: 40),
                ),
              ),
            // ✅ Show ONLY assigned driver AFTER ride is accepted
            if (isDriverAssigned && assignedDriver != null)
              Marker(
                width: 40.0,
                height: 40.0,
                point: LatLng(
                  (assignedDriver?['latitude'] as num).toDouble(),
                  (assignedDriver?['longitude'] as num).toDouble(),
                ),
                child: const Icon(Icons.directions_car, color: Colors.orange, size: 40), // 🔥 Highlight assigned driver
              ),
          ],
        ),
      ],
    ),

    /// ✅ Confirm Ride Button (Remains as before)
    if (showConfirmButton && !isDriverAssigned && assignedDriver == null)
      Positioned(
        bottom: 50,
        left: 20,
        right: 20,
        child: ElevatedButton(
          onPressed: _confirmRideRequest,
          child: const Text("Confirm Ride"),
        ),
      ),

    /// ✅ "Looking for a driver" Pop-up (Disappears when driver is assigned)
    if (isWaitingForDriver)
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Looking for a driver...", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const CircularProgressIndicator(),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _cancelRideRequest,
                child: const Text("Cancel Ride"),
              ),
            ],
          ),
        ),
      ),

    /// ✅ Draggable Driver Info Panel (Now allows map interaction)
    if (isDriverAssigned && assignedDriver != null)
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: GestureDetector(
          onVerticalDragUpdate: (details) {
            // Drag up or down to interact
            if (details.primaryDelta! < 0) {
              setState(() {
                isSheetExpanded = true;
              });
            } else {
              setState(() {
                isSheetExpanded = false;
              });
            }
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            height: isSheetExpanded ? 250 : 80,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 5)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                /// 📌 Drag Handle
                Container(
                  width: 40,
                  height: 5,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),

                if (isSheetExpanded) ...[
                  ListTile(
                    leading: CircleAvatar(
                      backgroundImage: assignedDriver?['profile_picture'] != null && assignedDriver?['profile_picture'].isNotEmpty
                          ? NetworkImage(assignedDriver?['profile_picture'])
                          : null,
                      child: assignedDriver?['profile_picture'] == null ? const Icon(Icons.person) : null,
                    ),
                    title: Text("${assignedDriver?['name'] ?? 'Unknown Driver'}"),
                    subtitle: Text("⭐ ${assignedDriver?['rating'] ?? 'No rating'}"),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.directions_car),
                    title: Text("${driverVehicle?['make']} ${driverVehicle?['model']}"),
                    subtitle: Text("Color: ${driverVehicle?['color']} | Plates: ${driverVehicle?['license_plate']}"),
                  ),
                  const Divider(),
                  Text("⏳ Estimated Arrival: ${driverETA?.toStringAsFixed(1)} mins",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
                if (!isSheetExpanded)
                  const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Text("Swipe up for details", style: TextStyle(fontSize: 14, color: Colors.grey)),
                  ),
              ],
            ),
          ),
        ),
      ),
  ],
),
    ),
    );
  }
}