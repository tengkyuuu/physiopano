/// Firebase Phone Authentication helper.
///
/// Flow:
///   1. sendCode('+639XXXXXXXXX')  → triggers SMS
///   2. verifyCode(smsCode)        → signs in / links the phone to account
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class PhoneAuthService extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;

  String? _verificationId;
  int? _resendToken;
  bool _isSending = false;
  bool get isSending => _isSending;

  /// Step 1 — send SMS code to [phoneNumber] (e.g. '+639171234567').
  /// [onCodeSent] is called when SMS is on its way.
  /// [onAutoVerified] is called if Android auto-reads the SMS (no user input needed).
  /// Returns an error string, or null on success.
  Future<String?> sendCode(
    String phoneNumber, {
    required void Function() onCodeSent,
    void Function()? onAutoVerified,
  }) async {
    _isSending = true;
    notifyListeners();

    String? error;
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      forceResendingToken: _resendToken,
      timeout: const Duration(seconds: 60),

      // Android auto-retrieval: OTP is read automatically from SMS
      verificationCompleted: (PhoneAuthCredential credential) async {
        await _auth.signInWithCredential(credential);
        onAutoVerified?.call();
        notifyListeners();
      },

      verificationFailed: (FirebaseAuthException e) {
        error = _mapError(e.code);
        _isSending = false;
        notifyListeners();
      },

      codeSent: (String verificationId, int? resendToken) {
        _verificationId = verificationId;
        _resendToken = resendToken;
        _isSending = false;
        notifyListeners();
        onCodeSent();
      },

      codeAutoRetrievalTimeout: (String verificationId) {
        _verificationId = verificationId;
      },
    );

    return error;
  }

  /// Step 2 — verify the OTP the user typed in.
  /// Returns null on success, or an error string on failure.
  Future<String?> verifyCode(String smsCode) async {
    if (_verificationId == null) return 'Please request a code first.';
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      await _auth.signInWithCredential(credential);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapError(e.code);
    }
  }

  /// Link phone number to an existing email/password account.
  /// Use this if users already have accounts and want to add phone as 2FA.
  Future<String?> linkPhone(String smsCode) async {
    if (_verificationId == null) return 'Please request a code first.';
    try {
      final credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: smsCode,
      );
      await _auth.currentUser?.linkWithCredential(credential);
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapError(e.code);
    }
  }

  String _mapError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'Invalid phone number. Use format +639XXXXXXXXX';
      case 'invalid-verification-code':
        return 'Wrong OTP code. Please try again.';
      case 'session-expired':
        return 'Code expired. Please request a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Try again later.';
      case 'quota-exceeded':
        return 'SMS quota exceeded. Contact support.';
      default:
        return 'Phone auth error: $code';
    }
  }
}
