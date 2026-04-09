import 'package:flutter_test/flutter_test.dart';
import 'package:hk_school_selector/models/school.dart';
import 'package:hk_school_selector/services/school_image_service.dart';

void main() {
  group('SchoolImageService.imagePathForSchool', () {
    test('matches by normalized school name', () {
      final service = SchoolImageService();
      final school = School(
        schoolName: 'A-ONE KINDERGARTEN',
        type: 'Kindergarten',
        address: 'Address',
        district: 'WONG TAI SIN',
        phone: '1234',
        website: '',
      );

      final map = <String, String>{
        service.normalizeForMapping('a-one kindergarten'):
            'assets/schools/a_one.jpg',
      };

      final result = service.imagePathForSchool(school, map);
      expect(result, 'assets/schools/a_one.jpg');
    });

    test('returns null when no mapping exists', () {
      final service = SchoolImageService();
      final school = School(
        schoolName: 'No Image School',
        type: 'Primary',
        address: '',
        district: 'TAI PO',
        phone: '',
        website: '',
      );

      final result = service.imagePathForSchool(school, const <String, String>{});
      expect(result, isNull);
    });
  });
}
