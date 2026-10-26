import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(FrpcApp(controller: FrpcController()));
}

const themeColors = <String, Color>{
  'teal': Color(0xFF008977),
  'blue': Color(0xFF2563EB),
  'violet': Color(0xFF7950C8),
  'orange': Color(0xFFC76626),
};
const colorNames = {'teal': '青绿', 'blue': '海蓝', 'violet': '鸢紫', 'orange': '暖橙'};

class FrpcApp extends StatelessWidget {
  const FrpcApp({super.key, required this.controller});
  final FrpcController controller;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final seed =
          themeColors[controller.data['themeColor']] ?? themeColors['teal']!;
      ThemeData theme(Brightness brightness) {
        final scheme = ColorScheme.fromSeed(
          seedColor: seed,
          brightness: brightness,
        );
        return ThemeData(
          useMaterial3: true,
          colorScheme: scheme,
          scaffoldBackgroundColor: scheme.surface,
          appBarTheme: AppBarTheme(
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            centerTitle: false,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
          cardTheme: const CardThemeData(
            elevation: 0,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(24)),
            ),
          ),
        );
      }

      final mode = switch (controller.data['themeMode']) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      return MaterialApp(
        title: 'Frpc',
        debugShowCheckedModeBanner: false,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        themeMode: mode,
        home: FrpcHome(controller: controller),
      );
    },
  );
}

Future<bool> perform(
  BuildContext context,
  Future<void> Function() operation, [
  String? success,
]) async {
  try {
    await operation();
    if (context.mounted && success != null)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(success)));
    return true;
  } catch (e) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('操作未完成'),
          content: SingleChildScrollView(
            child: SelectableText(FrpcController.message(e)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
    return false;
  }
}

class FrpcHome extends StatefulWidget {
  const FrpcHome({super.key, required this.controller});
  final FrpcController controller;
  @override
  State<FrpcHome> createState() => _FrpcHomeState();
}

class _FrpcHomeState extends State<FrpcHome> with WidgetsBindingObserver {
  int index = 0;
  Timer? timer;
  FrpcController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) c.initialize();
    });
    timer = Timer.periodic(const Duration(seconds: 5), (_) => c.refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      c.refresh();
      timer ??= Timer.periodic(const Duration(seconds: 5), (_) => c.refresh());
    } else if (state == AppLifecycleState.paused) {
      timer?.cancel();
      timer = null;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!c.ready)
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: c.loadError == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.loadError!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: c.initialize,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
          ),
        ),
      );
    final pages = [dashboard(context), profiles(context), settings(context)];
    return Scaffold(
      appBar: AppBar(
        title: Text(
          index == 0
              ? 'Frpc'
              : index == 1
              ? '配置'
              : '设置',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (index == 0)
            IconButton(
              tooltip: '运行日志',
              icon: const Icon(Icons.terminal_rounded),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => LogsPage(controller: c)),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (c.busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(child: pages[index]),
          ],
        ),
      ),
      floatingActionButton: index == 1
          ? FloatingActionButton.extended(
              onPressed: c.busy ? null : () => edit(context),
              icon: const Icon(Icons.add),
              label: const Text('新建配置'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard_rounded),
            label: '概览',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            selectedIcon: Icon(Icons.folder_rounded),
            label: '配置',
          ),
          NavigationDestination(icon: Icon(Icons.tune_rounded), label: '设置'),
        ],
      ),
    );
  }

  Widget dashboard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = c.phase == 'running', error = c.phase == 'error';
    final title = c.busy
        ? '正在处理…'
        : running
        ? '隧道进程运行中'
        : c.phase == 'retrying'
        ? '正在尝试恢复'
        : error
        ? '需要检查连接'
        : '准备连接';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        Card(
          color: scheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      running ? Icons.hub_rounded : Icons.hub_outlined,
                      size: 36,
                      color: scheme.onPrimaryContainer,
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Text(
                        running
                            ? 'RUNNING'
                            : error
                            ? 'ATTENTION'
                            : 'READY',
                        style: TextStyle(
                          color: scheme.onPrimaryContainer,
                          fontSize: 11,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  c.enabled
                      ? '当前运行：${c.profile(c.runningId)?.name ?? '未知配置'}'
                      : '选择一个配置，开始建立你的连接。',
                  style: TextStyle(color: scheme.onPrimaryContainer),
                ),
                const SizedBox(height: 20),
                Text(
                  c.data['status'] as String? ?? '尚未启动',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        sectionTitle(context, '启动配置'),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey(c.selectedId),
          initialValue: c.selectedId,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.description_outlined),
            labelText: '下次启动使用',
          ),
          items: c.profiles
              .map(
                (p) => DropdownMenuItem(
                  value: p.id,
                  child: Text(p.name, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: c.busy
              ? null
              : (id) {
                  if (id != null)
                    perform(
                      context,
                      () => c.action('selectProfile', {'id': id}),
                    );
                },
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: c.busy
                    ? null
                    : () => perform(
                        context,
                        () => c.action('start', {'id': c.selectedId}),
                      ),
                icon: Icon(
                  c.enabled ? Icons.restart_alt : Icons.play_arrow_rounded,
                ),
                label: Text(c.enabled ? '应用并重启' : '启动'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed:
                    c.busy ||
                        (!c.enabled &&
                            c.phase != 'running' &&
                            c.phase != 'retrying')
                    ? null
                    : () => perform(context, () => c.action('stop')),
                icon: const Icon(Icons.stop_rounded),
                label: const Text('停止'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Card(
          color: scheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                infoRow(
                  context,
                  Icons.shield_outlined,
                  '后台守护',
                  'Root 独立守护 · 异常退出自动拉起',
                ),
                const SizedBox(height: 18),
                infoRow(
                  context,
                  Icons.memory_rounded,
                  'frpc 内核',
                  '${c.data['runningVersion'] != '' && c.enabled ? '运行 ${c.data['runningVersion']} · ' : ''}已安装 ${c.kernelVersion}',
                ),
                const SizedBox(height: 18),
                infoRow(
                  context,
                  Icons.power_settings_new_rounded,
                  '开机恢复',
                  c.data['systemBoot'] == true ? '已开启 · 受系统自启动管理控制' : '未开启',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '进程运行不代表服务器已连接。请在日志中确认登录和代理启动结果。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: c.busy
              ? null
              : () => perform(context, () => c.action('refresh')),
          icon: const Icon(Icons.refresh),
          label: const Text('检查 Root 与运行状态'),
        ),
      ],
    );
  }

  Widget profiles(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
    children: [
      Text(
        '为不同服务器或网络保存独立配置。选择配置不会中断正在运行的隧道。',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      const SizedBox(height: 20),
      for (final p in c.profiles)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Card(
            color: p.id == c.selectedId
                ? Theme.of(context).colorScheme.secondaryContainer
                : Theme.of(context).colorScheme.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  ListTile(
                    onTap: c.busy
                        ? null
                        : () => perform(
                            context,
                            () => c.action('selectProfile', {'id': p.id}),
                          ),
                    leading: Icon(
                      p.id == c.selectedId
                          ? Icons.check_circle_rounded
                          : Icons.description_outlined,
                    ),
                    title: Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      c.enabled && p.id == c.runningId
                          ? '正在运行${p.id == c.selectedId ? ' · 已选择' : ''}'
                          : p.id == c.selectedId
                          ? '已选择 · 下次启动使用'
                          : 'TOML 配置',
                    ),
                    trailing: PopupMenuButton<String>(
                      enabled: !c.busy,
                      onSelected: (action) async {
                        if (action == 'edit')
                          edit(context, profile: p);
                        else if (action == 'copy')
                          edit(context, profile: p, duplicate: true);
                        else if (action == 'delete') {
                          final yes = await showDialog<bool>(
                            context: context,
                            builder: (d) => AlertDialog(
                              title: const Text('删除配置？'),
                              content: Text('“${p.name}”将从本机移除。'),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(d, false),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(d, true),
                                  child: const Text('删除'),
                                ),
                              ],
                            ),
                          );
                          if (yes == true && context.mounted)
                            await perform(
                              context,
                              () => c.action('deleteProfile', {'id': p.id}),
                            );
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('编辑 / 重命名')),
                        PopupMenuItem(value: 'copy', child: Text('复制配置')),
                        PopupMenuItem(value: 'delete', child: Text('删除')),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: c.busy
                            ? null
                            : () => edit(context, profile: p),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('编辑'),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
    ],
  );
  void edit(BuildContext context, {Profile? profile, bool duplicate = false}) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileEditor(
            controller: c,
            profile: profile,
            duplicate: duplicate,
          ),
        ),
      );
  Widget settings(BuildContext context) {
    final mode = c.data['themeMode'] as String? ?? 'system';
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        sectionTitle(context, '外观'),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'system',
              icon: Icon(Icons.brightness_auto),
              label: Text('系统'),
            ),
            ButtonSegment(
              value: 'light',
              icon: Icon(Icons.light_mode_outlined),
              label: Text('浅色'),
            ),
            ButtonSegment(
              value: 'dark',
              icon: Icon(Icons.dark_mode_outlined),
              label: Text('深色'),
            ),
          ],
          selected: {mode},
          onSelectionChanged: c.busy
              ? null
              : (set) => perform(
                  context,
                  () => c.action('setSettings', {'themeMode': set.first}),
                ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: themeColors.entries
              .map(
                (entry) => ChoiceChip(
                  label: Text(colorNames[entry.key]!),
                  avatar: CircleAvatar(backgroundColor: entry.value, radius: 9),
                  selected: (c.data['themeColor'] ?? 'teal') == entry.key,
                  onSelected: c.busy
                      ? null
                      : (_) => perform(
                          context,
                          () => c.action('setSettings', {
                            'themeColor': entry.key,
                          }),
                        ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 32),
        sectionTitle(context, '后台与启动'),
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('开机恢复隧道'),
                subtitle: const Text('由系统自启动管理恢复上次运行配置；手动停止后不恢复。'),
                value: c.data['systemBoot'] == true,
                onChanged: c.busy
                    ? null
                    : (v) => perform(
                        context,
                        () => c.action('setSettings', {'systemBoot': v}),
                      ),
              ),
              ListTile(
                leading: const Icon(Icons.launch_rounded),
                title: const Text('系统自启动管理'),
                subtitle: const Text('在系统设置中允许 Frpc 自启动'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => perform(context, () async {
                  await c.bridge.call('openAutostartSettings');
                }),
              ),
              ListTile(
                leading: const Icon(Icons.battery_saver_outlined),
                title: const Text('电池与后台运行'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => perform(context, () async {
                  await c.bridge.call('openBatterySettings');
                }),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Root 只负责后台守护，不安装开机脚本。自启动由系统管理；不同品牌的设置入口可能不同。',
          style: TextStyle(fontSize: 12),
        ),
        if (c.data['legacyCleanupPending'] == true) ...[
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('旧版 Root 开机脚本尚未清理。请授权清理，避免沿用旧版启动方式。'),
                  TextButton(
                    onPressed: c.busy
                        ? null
                        : () =>
                              perform(context, () => c.action('cleanupLegacy')),
                    child: const Text('清理旧版开机脚本'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 32),
        sectionTitle(context, 'frpc 内核'),
        const SizedBox(height: 12),
        Card(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.memory_rounded),
                    const SizedBox(width: 12),
                    Text(
                      '已安装 ${c.kernelVersion}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  '官方 Android ARM64 版本 · 下载后校验 SHA256',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 16),
                if (c.updateBusy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text(
                    '正在连接官方发布并处理更新，请稍候…',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
                if (!c.updateBusy)
                  OutlinedButton.icon(
                    onPressed: () => perform(context, c.checkUpdate),
                    icon: const Icon(Icons.refresh),
                    label: const Text('检查内核更新'),
                  ),
                if (c.release != null) ...[
                  const SizedBox(height: 12),
                  Text('官方最新版本：${c.release!['version']}'),
                  const SizedBox(height: 8),
                  if (c.release!['version'] != c.kernelVersion)
                    FilledButton.icon(
                      onPressed: c.updateBusy
                          ? null
                          : () => perform(
                              context,
                              c.installUpdate,
                              '内核已安装，下次启动或重启隧道时生效',
                            ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('下载并安装'),
                    )
                  else
                    const Text('已安装此版本', style: TextStyle(fontSize: 12)),
                  if ((c.release!['notes'] as String? ?? '').isNotEmpty)
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      title: const Text('更新说明'),
                      children: [SelectableText(c.release!['notes'] as String)],
                    ),
                ],
                if (c.enabled &&
                    c.data['runningVersion'] != c.kernelVersion) ...[
                  const SizedBox(height: 12),
                  const Text(
                    '新内核已准备好。回到概览点击“应用并重启”后生效。',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Frpc 2.0.0\n配置仅保存在本机。卸载前请先停止隧道。',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }
}

Widget sectionTitle(BuildContext context, String title) => Text(
  title,
  style: Theme.of(
    context,
  ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
);
Widget infoRow(
  BuildContext context,
  IconData icon,
  String title,
  String detail,
) => Row(
  children: [
    Icon(icon, color: Theme.of(context).colorScheme.primary),
    const SizedBox(width: 14),
    Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(detail, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    ),
  ],
);

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
    super.key,
    required this.controller,
    this.profile,
    this.duplicate = false,
  });
  final FrpcController controller;
  final Profile? profile;
  final bool duplicate;
  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late final TextEditingController name, content;
  late String initialName, initialContent;
  bool saving = false, allowPop = false;
  bool get dirty => name.text != initialName || content.text != initialContent;
  @override
  void initState() {
    super.initState();
    initialName = widget.profile == null
        ? ''
        : '${widget.profile!.name}${widget.duplicate ? ' 副本' : ''}';
    initialContent = widget.profile?.content ?? defaultConfig;
    name = TextEditingController(text: initialName);
    content = TextEditingController(text: initialContent);
  }

  @override
  void dispose() {
    name.dispose();
    content.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (saving) return;
    if (dirty) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('放弃未保存的修改？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('放弃'),
            ),
          ],
        ),
      );
      if (leave != true) return;
    }
    if (mounted) {
      setState(() => allowPop = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
    }
  }

  Future<void> save() async {
    if (saving) return;
    if (name.text.trim().isEmpty || content.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入配置名称和内容')));
      return;
    }
    setState(() => saving = true);
    final ok = await perform(
      context,
      () => widget.controller.action('saveProfile', {
        'id': widget.duplicate ? '' : widget.profile?.id ?? '',
        'name': name.text,
        'content': content.text,
      }),
      '配置已保存，启动或重启后生效',
    );
    if (!mounted) return;
    setState(() {
      saving = false;
      if (ok) allowPop = true;
    });
    if (ok)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.pop(context);
      });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: allowPop,
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) close();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: saving ? null : close,
          icon: const Icon(Icons.arrow_back),
        ),
        title: Text(
          widget.profile == null || widget.duplicate ? '新建配置' : '编辑配置',
        ),
        actions: [
          TextButton(onPressed: saving ? null : save, child: const Text('保存')),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            children: [
              TextField(
                controller: name,
                enabled: !saving,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: '配置名称',
                  hintText: '例如：家庭服务器',
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text(
                    'TOML',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: saving
                        ? null
                        : () async {
                            await perform(context, () async {
                              final text =
                                  await widget.controller.bridge.call(
                                        'importConfig',
                                      )
                                      as String?;
                              if (text != null && mounted) content.text = text;
                            });
                          },
                    icon: const Icon(Icons.file_open_outlined, size: 18),
                    label: const Text('导入文件'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: TextField(
                  controller: content,
                  enabled: !saving,
                  expands: true,
                  minLines: null,
                  maxLines: null,
                  keyboardType: TextInputType.multiline,
                  autocorrect: false,
                  enableSuggestions: false,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    height: 1.6,
                  ),
                  decoration: const InputDecoration(
                    hintText: '输入 frpc TOML 配置…',
                    contentPadding: EdgeInsets.all(16),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '保存不影响运行中的隧道。启动时会先校验配置，校验失败保留当前连接。',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class LogsPage extends StatefulWidget {
  const LogsPage({super.key, required this.controller});
  final FrpcController controller;
  @override
  State<LogsPage> createState() => _LogsPageState();
}

class _LogsPageState extends State<LogsPage> {
  String logs = '正在读取日志…';
  bool loading = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    load();
    timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => load(quiet: true),
    );
  }

  Future<void> load({bool quiet = false}) async {
    if (loading) return;
    loading = true;
    try {
      final result = await widget.controller.bridge.call('logs') as String;
      if (mounted)
        setState(() => logs = result.isEmpty ? '暂无日志，启动后可查看连接记录。' : result);
    } catch (e) {
      if (mounted && !quiet) setState(() => logs = FrpcController.message(e));
    } finally {
      loading = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('运行日志'),
      actions: [
        IconButton(
          tooltip: '复制日志',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: logs));
            if (context.mounted)
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('日志已复制，分享前请检查敏感信息')));
          },
          icon: const Icon(Icons.copy_outlined),
        ),
        IconButton(
          tooltip: '刷新',
          onPressed: load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '最近 120 行 · 每 5 秒刷新\n建议保持 log.to = "console"',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 16),
          SelectableText(
            logs,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    ),
  );
}

const defaultConfig = '''serverAddr = "your.server.com"
serverPort = 7000
auth.method = "token"
auth.token = "replace-me"

loginFailExit = false
transport.tls.enable = true
log.to = "console"
log.level = "info"

[[proxies]]
name = "android-ssh"
type = "tcp"
localIP = "127.0.0.1"
localPort = 8022
remotePort = 6000
''';
