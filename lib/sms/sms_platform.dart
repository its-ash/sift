import 'dart:isolate';

import 'package:flutter/services.dart';

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

/// Dart side of MethodChannel "com.itsash.sift/sms" (MainActivity.kt).
class SmsPlatform {
  const SmsPlatform();

  static const _channel = MethodChannel('com.itsash.sift/sms');

  Future<DefaultSmsApp> defaultSmsApp() async =>
      DefaultSmsApp.fromMap(await _channel.invokeMapMethod<Object?, Object?>('defaultSmsApp'));

  /// Shows Android's "set default SMS app" prompt. True when Sift is the default afterwards.
  Future<bool> requestDefaultSmsApp() async => await _channel.invokeMethod<bool>('requestDefaultSmsApp') ?? false;

  /// Hands the role back: asks for [package] directly below Android 10, otherwise
  /// opens the default apps screen. Returns "requested" or "settings".
  Future<String> restoreDefaultSmsApp(String? package) async =>
      await _channel.invokeMethod<String>('restoreDefaultSmsApp', {'package': package}) ?? 'settings';

  Future<List<SmsMessage>> loadInbox() async {
    final rows = await _channel.invokeListMethod<Map<Object?, Object?>>('loadInbox') ?? const [];
    // Sorting tens of thousands of messages takes a moment: keep it off the UI thread.
    return Isolate.run(() => [for (final r in rows) SmsMessage.fromMap(r)]);
  }

  /// Deletes messages by id and returns how many Android removed.
  Future<int> deleteMessages(Iterable<int> ids) async {
    try {
      return await _channel.invokeMethod<int>('deleteMessages', {'ids': ids.toList()}) ?? 0;
    } on PlatformException catch (e) {
      if (e.code == 'not_default') throw const NotDefaultSmsAppException();
      rethrow;
    }
  }
}
