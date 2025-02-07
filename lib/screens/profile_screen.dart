import 'package:flutter/material.dart';
import '../services/pocketbase_service.dart';

class ProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userData;

  const ProfileScreen({super.key, required this.userData});

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  bool isUpdating = false;

  @override
  void initState() {
    super.initState();
    nameController.text = widget.userData['record']?['name'] ?? '';
    phoneController.text = widget.userData['record']?['phone'] ?? '';
  }

  Future<void> _updateProfile() async {
    print("🔄 [ProfileScreen] Update button clicked!");
    print("📡 [ProfileScreen] Sending update request...");

    final String? userId = widget.userData['record']?['id']?.toString(); // ✅ Fixed user ID retrieval

    if (userId == null || userId.isEmpty) {
      print("❌ [ProfileScreen] ERROR: User ID is null!");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: User ID is missing.')),
      );
      return;
    }

    try {
      final updatedUser = await PocketBaseService().updateUser(
        userId,  // ✅ Ensured correct ID retrieval
        nameController.text,
        phoneController.text,
      );

      setState(() => isUpdating = false);

      if (updatedUser != null) {
        print("✅ [ProfileScreen] Profile updated successfully!");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully!')),
        );
        Navigator.pop(context, updatedUser);
      } else {
        print("❌ [ProfileScreen] Profile update failed!");
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update profile. Please try again.')),
        );
      }
    } catch (e) {
      print("❌ [ProfileScreen] Exception while updating profile: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('An error occurred while updating profile.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Full Name'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneController,
              decoration: const InputDecoration(labelText: 'Phone Number'),
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: isUpdating ? null : _updateProfile,
              child: isUpdating
                  ? const CircularProgressIndicator()
                  : const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }
}