import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class FrpcBridge {
  const FrpcBridge();
  static const channel = MethodChannel('dev.kuugo.frpc/control');
  Future<dynamic> call(String method, [Map<String, dynamic>? args]) =>
      channel.invokeMethod<dynamic>(method, args);
  Future<Map<String, dynamic>> state(
    String method, [
    Map<String, dynamic>? args,
  ]) async => Map<String, dynamic>.from(
    jsonDecode(await call(method, args) as String) as Map,
  );
}

class Profile {
  const Profile(this.id, this.name, this.content);
  final String id, name, content;
  factory Profile.fromJson(Map<String, dynamic> value) => Profile(
    value['id'] as String,
    value['name'] as String,
    value['content'] as String,
  );
}

class FrpcController extends ChangeNotifier {
  FrpcController({this.bridge = const FrpcBridge()});
  final FrpcBridge bridge;
  Map<String, dynamic> data = {};
  bool ready = false, busy = false, updateBusy = false;
  String? loadError;
  Map<String, dynamic>? release;
  List<Profile> get profiles => (data['profiles'] as List? ?? [])
      .map((p) => Profile.fromJson(Map<String, dynamic>.from(p as Map)))
      .toList();
  String get selectedId => data['selectedId'] as String? ?? '';
  String get runningId => data['runningId'] as String? ?? '';
  bool get enabled => data['enabled'] == true;
  String get phase => data['phase'] as String? ?? 'stopped';
  String get kernelVersion => data['kernelVersion'] as String? ?? '0.71.1';
  Profile? profile(String id) {
    for (final p in profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> initialize() async {
    loadError = null;
    notifyListeners();
    try {
      data = await bridge.state('initialize');
      ready = true;
    } catch (e) {
      loadError = message(e);
    }
    notifyListeners();
  }

  Future<void> refresh() async {
    if (!ready || busy) return;
    try {
      data = await bridge.state('snapshot');
      notifyListeners();
    } catch (_) {
      /* Keep the last snapshot if the activity is transitioning. */
    }
  }

  Future<void> action(String method, [Map<String, dynamic>? args]) async {
    if (busy) throw StateError('正在处理其他操作，请稍候');
    busy = true;
    notifyListeners();
    try {
      data = await bridge.state(method, args);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> checkUpdate() async {
    if (updateBusy) return;
    updateBusy = true;
    notifyListeners();
    try {
      release = await bridge.state('checkUpdate');
    } finally {
      updateBusy = false;
      notifyListeners();
    }
  }

  Future<void> installUpdate() async {
    if (updateBusy || release == null) return;
    updateBusy = true;
    notifyListeners();
    try {
      await bridge.state('installUpdate', {'version': release!['version']});
      await refresh();
    } finally {
      updateBusy = false;
      notifyListeners();
    }
  }

  static String message(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : e.toString();
}
