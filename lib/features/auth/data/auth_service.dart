// lib/features/auth/data/auth_service.dart
//
// Thin wrapper around Supabase auth + the current user's profile.
// Kept deliberately simple for now — no Riverpod yet. We'll introduce
// state management once more screens need to share the current profile.

import 'package:supabase_flutter/supabase_flutter.dart';

class Profile {
  final String id;
  final String? communityId;
  final String fullName;
  final String? phone;
  final String? employeeNumber;

  Profile({
    required this.id,
    required this.communityId,
    required this.fullName,
    required this.phone,
    required this.employeeNumber,
  });

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        communityId: map['community_id'] as String?,
        fullName: map['full_name'] as String? ?? '',
        phone: map['phone'] as String?,
        employeeNumber: map['employee_number'] as String?,
      );
}

class AuthService {
  AuthService(this._client);
  final SupabaseClient _client;

  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;
  User? get currentUser => _client.auth.currentUser;

  Future<void> signUp({
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName}, // read by the handle_new_user() trigger
    );
  }

  Future<void> signIn({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Fetches the profile row for the current user (auto-created by a
  /// database trigger the moment they sign up).
  Future<Profile?> fetchCurrentProfile() async {
    final user = currentUser;
    if (user == null) return null;

    final row = await _client
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) return null;
    return Profile.fromMap(row);
  }
}
