import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frpc/controller.dart';
import 'package:frpc/main.dart';

void main() {
  testWidgets('phone layout renders light and dark pages without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Use an installed CJK font for local previews, without shipping it in the app.
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (font.existsSync()) {
      for (final family in ['Roboto', 'Ahem']) {
        await tester.runAsync(() async {
          final loader = FontLoader(family);
          loader.addFont(
            font.readAsBytes().then((b) => ByteData.sublistView(b)),
          );
          await loader.load();
        });
      }
    }
    final icons = File(
      '.downloads/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      await tester.runAsync(() async {
        final loader = FontLoader('MaterialIcons');
        loader.addFont(
          icons.readAsBytes().then((b) => ByteData.sublistView(b)),
        );
        await loader.load();
      });
    }
    final state = <String, dynamic>{
      'profiles': [
        {'id': 'home', 'name': '家庭服务器', 'content': defaultConfig},
        {'id': 'office', 'name': '办公室开发环境', 'content': defaultConfig},
      ],
      'selectedId': 'home',
      'runningId': 'home',
      'enabled': true,
      'phase': 'running',
      'status': 'frpc 进程运行中 · PID 12890',
      'themeMode': 'light',
      'themeColor': 'teal',
      'systemBoot': true,
      'kernelVersion': '0.71.1',
      'runningVersion': '0.71.1',
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(FrpcBridge.channel, (call) async {
          if (call.method == 'setSettings')
            state.addAll(Map<String, dynamic>.from(call.arguments as Map));
          return jsonEncode(state);
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(FrpcBridge.channel, null),
    );
    final c = FrpcController();
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: FrpcApp(controller: c),
      ),
    );
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull);
      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        final directory = Directory('.downloads/previews');
        await directory.create(recursive: true);
        await File(
          '${directory.path}/$name.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await capture('home-light');
    await tester.tap(find.text('配置').last);
    await tester.pumpAndSettle();
    await capture('profiles-light');
    await tester.tap(find.text('设置').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    await capture('settings-dark');
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
