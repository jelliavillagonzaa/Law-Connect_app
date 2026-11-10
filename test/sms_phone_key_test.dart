import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/services/sms_service.dart';

void main() {
  test('09 and +63 for the same SIM are one SMS key', () {
    expect(
      SmsService.normalizePhoneE164Ph('09171234567'),
      SmsService.normalizePhoneE164Ph('+639171234567'),
    );
    expect(
      SmsService.normalizePhoneE164Ph('9171234567'),
      '+639171234567',
    );
  });
}
