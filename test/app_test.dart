import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frpc/controller.dart';
import 'package:frpc/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, dynamic> snapshot;
  late List<MethodCall> calls;
  setUp(() {
    snapshot = {
      'profiles': <Map<String, dynamic>>[
        {'id': 'home', 'name': '家庭服务器', 'content': 'serverPort = 7000'},
        {'id': 'office', 'name': '办公室', 'content': 'serverPort = 7001'},
      ],
      'selectedId': 'home',
      'runningId': 'home',
      'enabled': true,
      'phase': 'running',
      'status': 'frpc 进程运行中',
      'themeMode': 'system',
      'themeColor': 'teal',
      'systemBoot': false,
      'kernelVersion': '0.71.1',
      'runningVersion': '0.71.1',
      'legacyCleanupPending': false,
    };
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FrpcBridge.channel, (call) async {
          calls.add(call);
          final args = Map<String, dynamic>.from(call.arguments as Map? ?? {});
          switch (call.method) {
            case 'selectProfile':
              snapshot['selectedId'] = args['id'];
            case 'setSettings':
              snapshot.addAll(args);
            case 'saveProfile':
              final profiles = snapshot['profiles'] as List;
              final existing = profiles.indexWhere(
                (p) => p['id'] == args['id'],
              );
              if (existing < 0) {
                profiles.add({...args, 'id': 'created'});
              } else {
                profiles[existing] = args;
              }
            case 'installUpdate':
              throw PlatformException(code: 'CHECKSUM', message: 'SHA256 校验失败');
            case 'checkUpdate':
              return jsonEncode({'version': '0.72.0', 'notes': '修复连接'});
          }
          return jsonEncode(snapshot);
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FrpcBridge.channel, null);
  });

  testWidgets('selecting another profile does not restart the running tunnel', (
    tester,
  ) async {
    final c = FrpcController();
    await tester.pumpWidget(FrpcApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('办公室'));
    await tester.pumpAndSettle();
    expect(c.selectedId, 'office');
    expect(c.runningId, 'home');
    expect(calls.where((c) => c.method == 'start'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('creating a configuration saves a separate entry', (
    tester,
  ) async {
    final c = FrpcController();
    await tester.pumpWidget(FrpcApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('配置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建配置'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '备用服务器');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(c.profiles.length, 3);
    expect(c.profiles.last.name, '备用服务器');
    expect(c.runningId, 'home');
    expect(calls.where((c) => c.method == 'start'), isEmpty);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  testWidgets('theme settings apply dark mode and persist without root calls', (
    tester,
  ) async {
    final c = FrpcController();
    await tester.pumpWidget(FrpcApp(controller: c));
    await tester.pumpAndSettle();
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, '鸢紫'));
    await tester.pumpAndSettle();
    expect(c.data['themeColor'], 'violet');
    expect(snapshot['themeMode'], 'dark');
    expect(
      calls.where((c) => c.method == 'refresh' || c.method == 'start'),
      isEmpty,
    );
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });

  test('failed update preserves installed and running kernel state', () async {
    final c = FrpcController();
    await c.initialize();
    await c.checkUpdate();
    await expectLater(c.installUpdate(), throwsA(isA<PlatformException>()));
    expect(c.kernelVersion, '0.71.1');
    expect(c.data['runningVersion'], '0.71.1');
    expect(c.updateBusy, false);
    expect(c.enabled, true);
    c.dispose();
  });
}
