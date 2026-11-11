import 'package:flutter_test/flutter_test.dart';
import 'package:sift/sms/role_state.dart';

void main() {
  group('roleUiState', () {
    test('held role is the default app', () {
      expect(roleUiState(const SmsRoleSnapshot(sdk: 34, roleHeld: true)), SmsRoleUiState.defaultApp);
    });
    test('available but not held', () {
      expect(roleUiState(const SmsRoleSnapshot(sdk: 34)), SmsRoleUiState.notDefault);
    });
    test('role missing on the phone', () {
      expect(roleUiState(const SmsRoleSnapshot(sdk: 34, roleAvailable: false)), SmsRoleUiState.unavailable);
    });
    test('parses the channel map', () {
      final s = SmsRoleSnapshot.fromMap({'sdk': 33, 'roleHeld': true, 'package': 'com.itsash.sift'});
      expect(s.sdk, 33);
      expect(roleUiState(s), SmsRoleUiState.defaultApp);
    });
  });

  group('looksRestricted', () {
    test('instant refusal on Android 13+', () {
      expect(looksRestricted(sdk: 34, outcome: const RequestOutcome(granted: false, elapsedMs: 120)), isTrue);
    });
    test('a request that could not start on Android 13+', () {
      expect(looksRestricted(sdk: 33, outcome: const RequestOutcome(granted: false, failed: true)), isTrue);
    });
    test('user took time and said no', () {
      expect(looksRestricted(sdk: 34, outcome: const RequestOutcome(granted: false, elapsedMs: 4000)), isFalse);
    });
    test('granted is never restricted', () {
      expect(looksRestricted(sdk: 34, outcome: const RequestOutcome(granted: true, elapsedMs: 5)), isFalse);
    });
    test('before Android 13 there is no restricted settings', () {
      expect(looksRestricted(sdk: 32, outcome: const RequestOutcome(granted: false, elapsedMs: 5)), isFalse);
    });
  });

  test('guide covers Android 13, 14 and 15', () {
    expect(restrictedSettingsGuides.map((g) => g.heading), containsAll(['Android 13', 'Android 14']));
    expect(restrictedSettingsGuides.last.heading, contains('15'));
    for (final g in restrictedSettingsGuides) {
      expect(g.steps.any((s) => s.contains('Allow restricted settings')), isTrue);
    }
  });
}
