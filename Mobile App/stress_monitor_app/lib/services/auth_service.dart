/// Firebase Authentication service.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class AuthService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentUser != null;
  String get userId => _auth.currentUser?.uid ?? '';

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Map<String, dynamic>? _pendingProfile;

  /// The sign-up answers not yet written to local storage (null otherwise).
  /// Returns them once; the caller is responsible for persisting them.
  Map<String, dynamic>? takePendingProfile() {
    final p = _pendingProfile;
    _pendingProfile = null;
    return p;
  }

  /// Sign in with email & password.
  Future<String?> signIn(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapError(e.code);
    } catch (e) {
      return e.toString();
    }
  }

  /// Register a new account with full profile fields.
  Future<String?> register(
    String email,
    String password, {
    String displayName = '',
    String studentId = '',
    String course = '',
    String yearLevel = '',
    int age = 0,
    String sex = '',
    String emergencyName = '',
    String emergencyEmail = '',
    String emergencyPhone = '',
  }) async {
    // Hold the sign-up answers in memory *before* the account exists: creating
    // the user fires the auth stream immediately, and the session gate needs
    // these to seed local storage (the login screen may already be gone).
    _pendingProfile = {
      'display_name': displayName,
      'student_id': studentId,
      'emergency_name': emergencyName,
      'emergency_email': emergencyEmail,
      'emergency_phone': emergencyPhone,
    };
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user;
      if (user != null) {
        // Update Firebase display name
        if (displayName.isNotEmpty) {
          await user.updateDisplayName(displayName);
        }

        // Create full Firestore profile immediately
        await _firestore.collection('users').doc(user.uid).set({
          'email': email.trim(),
          'display_name': displayName,
          'student_id': studentId,
          'course': course,
          'year_level': yearLevel,
          'age': age,
          'sex': sex,
          'emergency_name': emergencyName,
          'emergency_email': emergencyEmail,
          'emergency_phone': emergencyPhone,
          'onboarding_complete': false,
          'created_at': FieldValue.serverTimestamp(),
          'last_sync': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      _pendingProfile = null;
      return _mapError(e.code);
    } catch (e) {
      _pendingProfile = null;
      return e.toString();
    }
  }

  /// Update the account's display name (what greetings across the app use).
  Future<void> updateDisplayName(String name) async {
    final user = _auth.currentUser;
    if (user == null || name.trim().isEmpty || user.displayName == name.trim()) return;
    try {
      await user.updateDisplayName(name.trim());
      await user.reload();
      notifyListeners();
    } catch (e) {
      debugPrint('[Auth] display name update failed: $e');
    }
  }

  /// Send password reset email.
  Future<String?> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapError(e.code);
    } catch (e) {
      return e.toString();
    }
  }

  /// Sign out.
  Future<void> signOut() async {
    await _auth.signOut();
    notifyListeners();
  }

  /// Delete current user account.
  Future<String?> deleteAccount() async {
    if (_auth.currentUser == null) return 'No user signed in';
    try {
      final uid = _auth.currentUser!.uid;
      // Remove the cloud profile and its sessions first (while still signed in,
      // so security rules allow it), then the login itself.
      final userDoc = _firestore.collection('users').doc(uid);
      final sessions = await userDoc.collection('sessions').get();
      for (final s in sessions.docs) {
        await _deleteCollection(s.reference.collection('readings'));
        await _deleteCollection(s.reference.collection('raw_readings'));
      }
      for (final sub in ['sessions', 'baseline', 'live']) {
        await _deleteCollection(userDoc.collection(sub));
      }
      await _firestore.collection('outcome_demographics').doc(uid).delete();
      await userDoc.delete();
      await _auth.currentUser!.delete();
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      if (e.code == 'requires-recent-login') {
        return 'Please sign out and sign back in, then try again.';
      }
      return e.message ?? e.code;
    } catch (e) {
      return e.toString();
    }
  }

  /// Delete every document in [col] in batches (Firestore has no recursive delete).
  Future<void> _deleteCollection(CollectionReference<Map<String, dynamic>> col) async {
    while (true) {
      final page = await col.limit(400).get();
      if (page.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final d in page.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    }
  }

  String _mapError(String code) {
    switch (code) {
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
        return 'Incorrect password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return 'Authentication error: $code';
    }
  }
}
