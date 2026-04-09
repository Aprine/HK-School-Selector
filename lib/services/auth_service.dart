import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String _usersKey = 'auth_users_v1';
  static const String _currentUserKey = 'auth_current_user_v1';

  Future<String?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentUserKey);
  }

  Future<bool> register({
    required String username,
    required String password,
  }) async {
    final normalized = _normalizeUsername(username);
    if (normalized.isEmpty || password.isEmpty) return false;

    final users = await _loadUsers();
    if (users.containsKey(normalized)) return false;

    users[normalized] = password;
    await _saveUsers(users);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, normalized);
    return true;
  }

  Future<bool> login({
    required String username,
    required String password,
  }) async {
    final normalized = _normalizeUsername(username);
    final users = await _loadUsers();
    final stored = users[normalized];
    if (stored == null || stored != password) return false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_currentUserKey, normalized);
    return true;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_currentUserKey);
  }

  String favoritesKeyForUser(String username) {
    return 'favorite_school_ids_${_normalizeUsername(username)}';
  }

  Future<Map<String, String>> _loadUsers() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_usersKey);
    if (raw == null || raw.trim().isEmpty) return <String, String>{};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map<String, String>(
        (key, value) => MapEntry(
          _normalizeUsername(key.toString()),
          value.toString(),
        ),
      );
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _saveUsers(Map<String, String> users) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usersKey, jsonEncode(users));
  }

  String _normalizeUsername(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
