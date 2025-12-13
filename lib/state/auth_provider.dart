// lib/state/auth_provider.dart
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/services/firebase_auth_service.dart';

class AuthProvider extends ChangeNotifier {
  final FirebaseAuthService _authService;

  User? user;
  bool isLoading = false;
  String? error;

  AuthProvider(this._authService) {
    // listen to Firebase auth state changes
    _authService.authStateChanges().listen((u) {
      user = u;
      notifyListeners();
    });
  }

  Future<void> login(String email, String password) async {
    try {
      isLoading = true;
      error = null;
      notifyListeners();
      user = await _authService.signIn(email, password);
    } on FirebaseAuthException catch (e) {
      error = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> register(String email, String password) async {
    try {
      isLoading = true;
      error = null;
      notifyListeners();
      user = await _authService.register(email, password);
    } on FirebaseAuthException catch (e) {
      error = e.message;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _authService.signOut();
  }
}
