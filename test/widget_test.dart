import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hk_school_selector/models/school.dart';
import 'package:hk_school_selector/screens/home_screen.dart';
import 'package:hk_school_selector/services/api_service.dart';
import 'package:hk_school_selector/services/auth_service.dart';

void main() {
  testWidgets('App renders school selector title', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});

    await tester.pumpWidget(
      MaterialApp(
        home: HomeScreen(
          currentUser: 'tester',
          authService: AuthService(),
          enableLocation: false,
          apiService: _FakeApiService(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('HK School Selector'), findsWidgets);
  });
}

class _FakeApiService extends ApiService {
  @override
  Future<List<School>> fetchSchools() async {
    return const <School>[
      School(
        schoolName: 'Test School',
        type: 'Primary',
        address: '1 Test Road',
        district: 'TAI PO',
        phone: '12345678',
        website: 'https://example.edu.hk',
        latitude: 22.0,
        longitude: 114.0,
      ),
    ];
  }
}
