// Pure logic around the default-SMS role. No Flutter or platform imports, so
// it is unit tested (test/role_state_test.dart).

/// What the phone reports about Sift and the SMS role.
class SmsRoleSnapshot {
  const SmsRoleSnapshot({
    this.sdk = 0,
    this.roleAvailable = true,
    this.roleHeld = false,
    this.defaultPackage,
    this.defaultLabel,
    this.smsPermission = true,
  });

  factory SmsRoleSnapshot.fromMap(Map<Object?, Object?>? map) => SmsRoleSnapshot(
    sdk: (map?['sdk'] as num?)?.toInt() ?? 0,
    roleAvailable: map?['roleAvailable'] as bool? ?? true,
    roleHeld: map?['roleHeld'] as bool? ?? false,
    defaultPackage: map?['package'] as String?,
    defaultLabel: map?['label'] as String?,
    smsPermission: map?['smsPermission'] as bool? ?? true,
  );

  /// Android API level (0 when unknown).
  final int sdk;

  /// False when the phone has no SMS role (tablets, some ROMs).
  final bool roleAvailable;

  /// True when Sift holds the SMS role / is the default SMS app.
  final bool roleHeld;
  final String? defaultPackage;
  final String? defaultLabel;
  final bool smsPermission;
}

/// What the UI shows for the SMS role.
enum SmsRoleUiState {
  /// This phone has no SMS role. Deleting is not possible.
  unavailable,

  /// Sift is not the default. It will ask for the role when deleting.
  notDefault,

  /// Sift is the default: it can delete, but the user should switch back after.
  defaultApp,
}

SmsRoleUiState roleUiState(SmsRoleSnapshot s) {
  if (s.roleHeld) return SmsRoleUiState.defaultApp;
  if (!s.roleAvailable) return SmsRoleUiState.unavailable;
  return SmsRoleUiState.notDefault;
}

extension SmsRoleUiStateText on SmsRoleUiState {
  String get title => switch (this) {
    SmsRoleUiState.unavailable => 'Not supported',
    SmsRoleUiState.notDefault => 'Not the default',
    SmsRoleUiState.defaultApp => 'Default SMS app',
  };
}

/// Android 13 (API 33) added "Restricted settings" for APKs installed outside a store.
const restrictedSettingsMinSdk = 33;

/// Result of asking Android for the SMS role (or a runtime permission).
class RequestOutcome {
  const RequestOutcome({required this.granted, this.elapsedMs = 1 << 30, this.failed = false});

  factory RequestOutcome.fromMap(Map<Object?, Object?>? map) => RequestOutcome(
    granted: map?['granted'] as bool? ?? false,
    elapsedMs: (map?['elapsedMs'] as num?)?.toInt() ?? 1 << 30,
    failed: map?['error'] != null,
  );

  final bool granted;

  /// How long the system took to answer. A real prompt takes a human a second or more.
  final int elapsedMs;

  /// The request could not even be started.
  final bool failed;
}

/// A prompt answered faster than a person can tap is the system refusing it.
const instantAnswerMs = 600;

/// True when a refused request looks like "Restricted settings" is blocking it:
/// Android 13+, not granted, and the system either failed to open the prompt or
/// answered at once.
bool looksRestricted({required int sdk, required RequestOutcome outcome}) {
  if (sdk < restrictedSettingsMinSdk || outcome.granted) return false;
  return outcome.failed || outcome.elapsedMs < instantAnswerMs;
}

/// Exact steps to allow restricted settings, by Android version.
class RestrictedStepsGuide {
  const RestrictedStepsGuide(this.heading, this.steps);
  final String heading;
  final List<String> steps;
}

const restrictedSettingsGuides = <RestrictedStepsGuide>[
  RestrictedStepsGuide('Android 13', [
    'Open Settings, then Apps (or Apps & notifications).',
    'Tap Sift. If it is not listed, tap See all apps first.',
    'Tap the three dots at the top right.',
    'Tap Allow restricted settings and confirm.',
  ]),
  RestrictedStepsGuide('Android 14', [
    'Open Settings, then Apps, then All apps.',
    'Tap Sift.',
    'Tap the three dots at the top right.',
    'Tap Allow restricted settings and confirm with your PIN or fingerprint.',
  ]),
  RestrictedStepsGuide('Android 15 and later', [
    'Open Settings, then Apps, then Sift (see all apps if needed).',
    'Tap the three dots at the top right. The item only appears after you have tried to grant a permission once.',
    'Tap Allow restricted settings and confirm with your PIN or fingerprint.',
    'Come back to Sift and tap Retry.',
  ]),
];

/// Short text used where space is tight (a banner).
const restrictedSettingsSummary =
    'Android blocks SMS access for apps installed from an APK. Open Settings, Apps, Sift, tap the three dots '
    'at the top right, then Allow restricted settings.';
