import 'package:flutter_test/flutter_test.dart';
import 'package:law_connect4/utils/chat_push_title.dart';

void main() {
  test('chat push titles tag client, staff, and attorney', () {
    expect(
      ChatPushTitle.format(name: 'Ben Cruz', role: 'client'),
      'Ben Cruz · Client',
    );
    expect(
      ChatPushTitle.format(name: 'Mae Santos', role: 'staff'),
      'Mae Santos · Staff',
    );
    expect(
      ChatPushTitle.format(name: 'Mae Santos', role: 'paralegal'),
      'Mae Santos · Staff',
    );
    expect(
      ChatPushTitle.format(name: 'Juan Reyes', role: 'attorney'),
      'Juan Reyes · Attorney',
    );
    expect(ChatPushTitle.format(name: 'Admin User', role: 'admin'), 'Admin User');
    expect(ChatPushTitle.format(name: '', role: 'client'), 'Client');
  });
}
