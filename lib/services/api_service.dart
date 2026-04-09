import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/school.dart';

class ApiService {
  static const String _schoolsCacheKey = 'schools_cache_v1';

  static final List<Uri> _schoolUris = <Uri>[
    Uri.parse(
      'https://www.edb.gov.hk/attachment/en/student-parents/sch-info/sch-search/sch-location-info/SCH_LOC_EDB.json',
    ),
    Uri.parse(
      'https://services3.arcgis.com/6j1KwZfY2fZrfNMR/ArcGIS/rest/services/Hong_Kong_School_Location_and_Information/FeatureServer/0/query?where=1%3D1&outFields=*&f=pjson',
    ),
  ];

  Future<List<School>> fetchSchools() async {
    Object? lastError;

    for (final uri in _schoolUris) {
      try {
        final response = await http
            .get(
              uri,
              headers: const <String, String>{
                'Accept': 'application/json',
              },
            )
            .timeout(const Duration(seconds: 20));

        if (response.statusCode != 200) {
          lastError = Exception('HTTP ${response.statusCode} from $uri');
          continue;
        }

        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final items = _extractSchoolItems(decoded);
        final schools = items
            .map((item) => School.fromJson(item))
            .toList(growable: false);

        final deduplicated = _deduplicateSchools(schools);
        await _saveSchoolsCache(deduplicated);
        return deduplicated;
      } on TimeoutException catch (e) {
        lastError = e;
      } on FormatException catch (e) {
        lastError = e;
      } catch (e) {
        lastError = e;
      }
    }

    final cached = await _loadSchoolsCache();
    if (cached.isNotEmpty) {
      return cached;
    }

    throw Exception('Failed to load schools from all endpoints: $lastError');
  }

  List<Map<String, dynamic>> _extractSchoolItems(dynamic decoded) {
    if (decoded is List) {
      return decoded.whereType<Map>().map(_toStringDynamicMap).toList();
    }

    if (decoded is Map<String, dynamic>) {
      final features = decoded['features'];
      if (features is List) {
        return features.whereType<Map>().map(_toStringDynamicMap).toList();
      }

      final data = decoded['data'];
      if (data is List) {
        return data.whereType<Map>().map(_toStringDynamicMap).toList();
      }
    }

    throw const FormatException('Unexpected JSON structure.');
  }

  Map<String, dynamic> _toStringDynamicMap(Map map) {
    return map.map((key, value) => MapEntry(key.toString(), value));
  }

  List<School> _deduplicateSchools(List<School> schools) {
    final unique = <String, School>{};
    for (final school in schools) {
      final key = [
        _normalize(school.schoolName),
        _normalize(school.address),
        _normalize(school.type),
        _normalize(school.district),
        _normalize(school.phone),
        _normalize(school.website),
      ].join('|');
      unique.putIfAbsent(key, () => school);
    }
    return unique.values.toList(growable: false);
  }

  String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  Future<void> _saveSchoolsCache(List<School> schools) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = schools
          .map((school) => school.toJson())
          .toList(growable: false);
      await prefs.setString(_schoolsCacheKey, jsonEncode(payload));
    } catch (_) {
      // Cache write is best-effort.
    }
  }

  Future<List<School>> _loadSchoolsCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_schoolsCacheKey);
      if (raw == null || raw.trim().isEmpty) return const <School>[];

      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <School>[];

      return decoded
          .whereType<Map>()
          .map(_toStringDynamicMap)
          .map((item) => School.fromJson(item))
          .toList(growable: false);
    } catch (_) {
      return const <School>[];
    }
  }
}
