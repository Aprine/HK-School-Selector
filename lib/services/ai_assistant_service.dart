import 'dart:convert';

import 'package:http/http.dart' as http;

class AiSuggestion {
  const AiSuggestion({
    required this.message,
    this.district,
    this.type,
    this.favoritesOnly,
    this.sort,
    this.searchQuery,
  });

  final String message;
  final String? district;
  final String? type;
  final bool? favoritesOnly;
  final String? sort;
  final String? searchQuery;
}

class AiAssistantService {
  static const String _proxyUrl = String.fromEnvironment('AI_PROXY_URL');

  Future<AiSuggestion> suggest({
    required String query,
    required List<String> districts,
    required List<String> supportedTypes,
  }) async {
    if (_proxyUrl.isNotEmpty) {
      final remote = await _callProxy(
        query: query,
        districts: districts,
        supportedTypes: supportedTypes,
      );
      if (remote != null) return remote;
    }

    return _localFallback(
      query: query,
      districts: districts,
      supportedTypes: supportedTypes,
    );
  }

  Future<AiSuggestion?> _callProxy({
    required String query,
    required List<String> districts,
    required List<String> supportedTypes,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(_proxyUrl),
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(<String, dynamic>{
          'query': query,
          'districts': districts,
          'types': supportedTypes,
        }),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final map = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );

      final filters = map['filters'];
      Map<String, dynamic> filterMap = const <String, dynamic>{};
      if (filters is Map) {
        filterMap = filters.map((k, v) => MapEntry(k.toString(), v));
      }

      return AiSuggestion(
        message: map['message']?.toString() ?? 'AI suggestion applied.',
        district: filterMap['district']?.toString(),
        type: filterMap['type']?.toString(),
        favoritesOnly: filterMap['favoritesOnly'] is bool
            ? filterMap['favoritesOnly'] as bool
            : null,
        sort: filterMap['sort']?.toString(),
        searchQuery: filterMap['searchQuery']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  AiSuggestion _localFallback({
    required String query,
    required List<String> districts,
    required List<String> supportedTypes,
  }) {
    final q = query.toLowerCase();
    String? district;
    for (final d in districts) {
      if (q.contains(d.toLowerCase())) {
        district = d;
        break;
      }
    }

    String? type;
    if (q.contains('primary')) type = 'Primary';
    if (q.contains('secondary')) type = 'Secondary';
    if (q.contains('government')) type = 'Government';
    if (q.contains('aided') || q.contains('aid')) type = 'Aided';
    if (q.contains('plk') || q.contains('po leung kuk')) type = 'PLK';
    if (q.contains('kindergarten')) type = 'All Types';

    if (!supportedTypes.contains(type)) type = null;

    final favoritesOnly = q.contains('favorite');
    final nearby = q.contains('near') || q.contains('nearby') || q.contains('closest');
    final farthest =
        q.contains('farthest') || q.contains('furthest') || q.contains('most far');

    return AiSuggestion(
      message: 'Applied AI filters from your request.',
      district: district,
      type: type,
      favoritesOnly: favoritesOnly ? true : null,
      sort: farthest
          ? 'distance_desc'
          : (nearby ? 'distance' : null),
      searchQuery: null,
    );
  }
}
