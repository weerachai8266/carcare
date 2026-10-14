import 'package:carcare/services/donate_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('product ids สำหรับ Donate ต้องตรงกับที่ต้องสร้างใน Play Console', () {
    expect(
      DonateCatalog.ids,
      containsAll(<String>{
        'carcare_support_small',
        'carcare_support_medium',
        'carcare_support_large',
      }),
    );
    expect(DonateCatalog.all, hasLength(3));
  });

  test('เรียงรายการสนับสนุนจากเล็กไปใหญ่', () {
    expect(DonateCatalog.all.map((option) => option.id), <String>[
      'carcare_support_small',
      'carcare_support_medium',
      'carcare_support_large',
    ]);
  });
}
