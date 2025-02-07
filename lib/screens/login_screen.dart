import 'package:flutter/material.dart';
import '../services/pocketbase_service.dart';
import '../screens/home_screen.dart';

class LoginScreen extends StatefulWidget {
  @override
  _LoginScreenState createState() => _LoginScreenState();

  const LoginScreen({super.key});
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController identityController = TextEditingController(); // ✅ Renamed from emailController
  final TextEditingController passwordController = TextEditingController();
  bool isLoading = false;

Future<void> login() async {
  setState(() => isLoading = true);

  final user = await PocketBaseService().login(
    identityController.text, // ✅ Use identity instead of email
    passwordController.text,
  );

  setState(() => isLoading = false);

  if (user != null) {
    print("Login successful!");
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => HomeScreen(userData: user)),
    );
  } else {
    print("Login failed!");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Login failed. Please check your credentials.')),
    );
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Login')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(controller: identityController, decoration: InputDecoration(labelText: 'Email or Username')), // ✅ Updated label
            TextField(controller: passwordController, decoration: InputDecoration(labelText: 'Password'), obscureText: true),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: isLoading ? null : login,
              child: isLoading ? CircularProgressIndicator() : Text('Login'),
            ),
          ],
        ),
      ),
    );
  }
}