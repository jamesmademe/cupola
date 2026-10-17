/// The native side of what Cupola shows outside itself, over one channel:
/// where the widgets read their file, and the widgets themselves. A build
/// without them (a test, a desktop) answers nothing, and the app goes
/// on as if there were no widget.
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'package:cupola/features/outside/data/outside_run.dart';

const _channel = MethodChannel('cupola/outside');

/// The widgets: asked to draw the snapshot again after a run, and whether
/// any is on a screen.
class ChannelOutsideWidgets implements OutsideWidgets {
  const ChannelOutsideWidgets();

  @override
  Future<void> reload() async {
    try {
      await _channel.invokeMethod<void>('reload');
    } on MissingPluginException {
      // No widget to draw.
    } on PlatformException {
      // The next run asks again.
    }
  }

  /// Whether the person has one of Cupola's widgets on a screen.
  Future<bool> installed() async {
    try {
      return await _channel.invokeMethod<bool>('installed') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}

/// The folder the widgets can read: the App Group's on iOS, which only the
/// native side can name, and `filesDir/outside` on Android, which the
/// `outside_channel` plugin names (the widgets run in the app's own process
/// and read its own folder, and that folder is the one
/// `getApplicationSupportDirectory()` points to, so the fallback below is the
/// same place). Where there is no native side at all, a desktop has no widget
/// and keeps the folder only for the notifications' memory.
Future<Directory> outsideFolder() async {
  try {
    final path = await _channel.invokeMethod<String>('sharedFolder');
    if (path != null && path.isNotEmpty) return Directory(path);
  } on MissingPluginException {
    // No native side: the folder below.
  } on PlatformException {
    // An App Group the build does not carry: the folder below.
  }
  final support = await getApplicationSupportDirectory();
  return Directory('${support.path}/outside');
}
