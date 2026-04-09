class School {
  const School({
    required this.schoolName,
    required this.type,
    required this.address,
    required this.district,
    required this.phone,
    required this.website,
    this.latitude,
    this.longitude,
  });

  final String schoolName;
  final String type;
  final String address;
  final String district;
  final String phone;
  final String website;
  final double? latitude;
  final double? longitude;
  String get id =>
      '${_normalizeIdPart(schoolName)}|${_normalizeIdPart(address)}|${_normalizeIdPart(phone)}';

  factory School.fromJson(Map<String, dynamic> json) {
    final attributes = json['attributes'] is Map<String, dynamic>
        ? json['attributes'] as Map<String, dynamic>
        : json;

    final geometry = json['geometry'] is Map<String, dynamic>
        ? json['geometry'] as Map<String, dynamic>
        : const <String, dynamic>{};

    return School(
      schoolName: _readSchoolName(attributes),
      type: _readSchoolType(attributes),
      address: _readAddress(attributes),
      district: _readDistrict(attributes),
      phone: _readPhone(attributes),
      website: _readWebsite(attributes),
      latitude: _readDouble(attributes, const ['LATITUDE', 'latitude']) ??
          _readDouble(geometry, const ['y', 'latitude']),
      longitude: _readDouble(attributes, const ['LONGITUDE', 'longitude']) ??
          _readDouble(geometry, const ['x', 'longitude']),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'ENGLISH_NAME': schoolName,
      'SCHOOL_LEVEL': type,
      'ENGLISH_ADDRESS': address,
      'DISTRICT': district,
      'TELEPHONE': phone,
      'WEBSITE': website,
      'LATITUDE': latitude,
      'LONGITUDE': longitude,
    };
  }

  static String _readString(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key] ?? _readByKeyIgnoreCase(source, key);
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _readSchoolName(Map<String, dynamic> source) {
    final exact = _readString(source, const [
      'ENGLISH_NAME',
      'SCHOOL_NAME',
      'SCHOOL_NAME_EN',
      'SCH_NAME_EN',
      'ENG_NAME',
      'NAME_EN',
      'NAME_ENG',
      'schoolName',
      'name',
    ]);
    if (exact.isNotEmpty) return exact;

    final byPattern = _readByPattern(
      source,
      include: const ['name'],
      exclude: const ['district', 'address', 'website', 'type', 'level'],
    );
    if (byPattern.isNotEmpty) return byPattern;

    return _readByPattern(
      source,
      include: const ['school'],
      exclude: const ['district', 'address'],
    );
  }

  static String _readSchoolType(Map<String, dynamic> source) {
    final exact = _readString(source, const [
      'SCHOOL_LEVEL',
      'ENGLISH_CATEGORY',
      'CATEGORY',
      'SCHOOL_TYPE',
      'TYPE',
      'type',
      'LEVEL',
    ]);
    if (exact.isNotEmpty) return exact;

    return _readByPattern(
      source,
      include: const ['type', 'level', 'category'],
      exclude: const ['district'],
    );
  }

  static String _readAddress(Map<String, dynamic> source) {
    final exact = _readString(source, const [
      'ENGLISH_ADDRESS',
      'ADDRESS',
      'address',
    ]);
    if (exact.isNotEmpty) return exact;
    return _readByPattern(source, include: const ['address']);
  }

  static String _readDistrict(Map<String, dynamic> source) {
    final exact = _readString(source, const ['DISTRICT', 'district']);
    if (exact.isNotEmpty) return exact;
    return _readByPattern(source, include: const ['district']);
  }

  static String _readPhone(Map<String, dynamic> source) {
    final exact = _readString(source, const ['TELEPHONE', 'PHONE', 'phone']);
    if (exact.isNotEmpty) return exact;
    return _readByPattern(source, include: const ['phone', 'tel']);
  }

  static String _readWebsite(Map<String, dynamic> source) {
    final exact = _readString(source, const ['WEBSITE', 'website', 'URL', 'url']);
    if (exact.isNotEmpty) return exact;
    return _readByPattern(source, include: const ['website', 'web', 'url']);
  }

  static String _readByPattern(
    Map<String, dynamic> source, {
    required List<String> include,
    List<String> exclude = const [],
  }) {
    for (final entry in source.entries) {
      final key = entry.key.toString().toLowerCase();
      final value = entry.value;
      if (value == null) continue;
      if (value is! String && value is! num) continue;

      final shouldInclude = include.any(key.contains);
      final shouldExclude = exclude.any(key.contains);
      if (!shouldInclude || shouldExclude) continue;

      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static double? _readDouble(Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key] ?? _readByKeyIgnoreCase(source, key);
      if (value == null) continue;
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  static dynamic _readByKeyIgnoreCase(Map<String, dynamic> source, String key) {
    final target = key.toLowerCase();
    for (final entry in source.entries) {
      if (entry.key.toLowerCase() == target) {
        return entry.value;
      }
    }
    return null;
  }

  static String _normalizeIdPart(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
