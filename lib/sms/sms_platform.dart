import 'dart:isolate';

import 'package:flutter/services.dart';

import 'role_state.dart';
import 'sms_delete.dart';
import 'sms_message.dart';

/// The app that currently holds Android's default SMS role.
class DefaultSmsApp {
  const DefaultSmsApp({this.package, this.label, this.isSelf = false});

  factory DefaultSmsApp.fromMap(Map<Object?, Object?>? map) => DefaultSmsApp(
    package: map?['package'] as String?,
    label: map?['label'] as String?,
    isSelf: map?['isSelf'] as bool? ?? false,
  );

  final String? package;
  final String? label;
  final bool isSelf;
}

/// Thrown when Android refuses a delete because Sift is not the default SMS app.
class NotDefaultSmsAppException implements Exception {
  const NotDefaultSmsAppException();
}

/// Thrown when Android raises a SecurityException (role or permission missing).
class SmsSecurityException implements Exception {
  const SmsSecurityException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Dart side of MethodChannel "com.itsash.sift/sms" (MainActivity.kt).
/// Tests replace it with a fake that `implements SmsPlatform`.
class SmsPlatform implements SmsResolverBridge {
  const SmsPlatform();

  static const _channel = MethodChannel('com.itsash.sift/sms');

  Future<DefaultSmsApp> defaultSmsApp() async =>
      DefaultSmsApp.fromMap(await _channel.invokeMapMethod<Object?, Object?>('defaultSmsApp'));

  /// API level, role availability and whether Sift holds the role.
  Future<SmsRoleSnapshot> roleState() async =>
      SmsRoleSnapshot.fromMap(await _channel.invokeMapMethod<Object?, Object?>('roleState'));

  /// Shows Android's "set default SMS app" prompt (RoleManager on 10+).
  Future<RequestOutcome> requestDefaultSmsApp() async =>
      RequestOutcome.fromMap(await _channel.invokeMapMethod<Object?, Object?>('requestDefaultSmsApp'));

  /// Hands the role back: asks for [package] directly below Android 10, otherwise
  /// opens the default apps screen. Returns "requested" or "settings".
  Future<String> restoreDefaultSmsApp(String? package) async =>
      await _channel.invokeMethod<String>('restoreDefaultSmsApp', {'package': package}) ?? 'settings';

  /// Opens Sift's page in Android Settings (ACTION_APPLICATION_DETAILS_SETTINGS).
  Future<void> openAppDetails() => _channel.invokeMethod<void>('openAppDetails');

  Future<List<SmsMessage>> loadInbox() async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('loadInbox') ?? const [];
    // Sorting tens of thousands of messages takes a moment: keep it off the UI thread.
    return Isolate.run(() => [for (final r in rows) SmsMessage.fromMap(r)]);
  }

  @override
  Future<int> deleteByIds(List<int> ids) => _delete('deleteByIds', {'ids': ids});

  @override
  Future<int> deleteById(int id) => _delete('deleteById', {'id': id});

  /// Deletes whole conversations via `content://mms-sms/conversations/<threadId>`.
  Future<int> deleteThreads(List<int> threadIds) => _delete('deleteThreads', {'threadIds': threadIds});

  /// Deletes messages by id and returns how many Android removed.
  Future<DeleteResult> deleteMessages(Iterable<int> ids) => deleteSms(this, ids);

  Future<int> _delete(String method, Map<String, Object?> args) async {
    try {
      return await _channel.invokeMethod<int>(method, args) ?? 0;
    } on PlatformException catch (e) {
      if (e.code == 'not_default') throw const NotDefaultSmsAppException();
      if (e.code == 'security') throw SmsSecurityException(e.message ?? 'Permission denied');
      rethrow;
    }
  }
}
