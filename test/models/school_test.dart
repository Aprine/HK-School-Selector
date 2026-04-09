import 'package:flutter_test/flutter_test.dart';
import 'package:hk_school_selector/models/school.dart';

void main() {
  group('School.fromJson', () {
    test('parses direct EDB-like fields', () {
      final school = School.fromJson(<String, dynamic>{
        'ENGLISH_NAME': 'ABC School',
        'SCHOOL_LEVEL': 'Primary',
        'ENGLISH_ADDRESS': '1 Main Street',
        'DISTRICT': 'TAI PO',
        'TELEPHONE': '12345678',
        'WEBSITE': 'abc.edu.hk',
        'LATITUDE': '22.123',
        'LONGITUDE': '114.123',
      });

      expect(school.schoolName, 'ABC School');
      expect(school.type, 'Primary');
      expect(school.address, '1 Main Street');
      expect(school.district, 'TAI PO');
      expect(school.phone, '12345678');
      expect(school.website, 'abc.edu.hk');
      expect(school.latitude, closeTo(22.123, 0.00001));
      expect(school.longitude, closeTo(114.123, 0.00001));
    });

    test('parses wrapped attributes + geometry fields', () {
      final school = School.fromJson(<String, dynamic>{
        'attributes': <String, dynamic>{
          'school_name_en': 'Wrapped School',
          'category': 'Secondary',
          'district': 'SHA TIN',
        },
        'geometry': <String, dynamic>{
          'y': 22.44,
          'x': 114.22,
        },
      });

      expect(school.schoolName, 'Wrapped School');
      expect(school.type, 'Secondary');
      expect(school.district, 'SHA TIN');
      expect(school.latitude, closeTo(22.44, 0.00001));
      expect(school.longitude, closeTo(114.22, 0.00001));
    });
  });
}
