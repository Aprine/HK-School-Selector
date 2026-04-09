import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/school.dart';

class SchoolImageService {
  static const String _mappingAssetPath = 'assets/data/school_images.json';

  Future<Map<String, String>> loadImageMap() async {
    try {
      final raw = await rootBundle.loadString(_mappingAssetPath);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const <String, String>{};

      final result = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key.toString().trim();
        final value = entry.value?.toString().trim() ?? '';
        if (key.isEmpty || value.isEmpty) continue;
        result[_normalizeKey(key)] = value;
      }
      return result;
    } catch (_) {
      return const <String, String>{};
    }
  }

  String? imagePathForSchool(School school, Map<String, String> imageMap) {
    final candidates = <String>[
      school.id,
      school.schoolName,
      '${school.schoolName}|${school.district}',
    ];

    for (final candidate in candidates) {
      final key = _normalizeKey(candidate);
      final path = imageMap[key];
      if (path != null && path.isNotEmpty) return path;
    }
    return null;
  }

  String normalizeForMapping(String value) => _normalizeKey(value);

  String _normalizeKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
