import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../app_scope.dart';
import '../../core/models.dart';
import '../../core/platforms.dart';
import '../../data/device/scrapers.dart';
import '../../data/price_source.dart';
import '../../data/remote_source.dart';
import '../../security/admin_auth.dart';
import '../../security/native_bridge.dart';
import '../../state/settings.dart';
import '../../theme/tokens.dart';
import '../widgets/common.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _url = TextEditingController();
  final _key = TextEditingController();
  String? _urlError;
  bool _hasKey = false;
  bool _testing = false;
  String? _testResult;
  Timer? _idle;
  late final AdminAuth _admin;

  @override
  void initState() {
    super.initState();
    NativeBridge.acquireSecure();
    final scope = context.getInheritedWidgetOfExactType<AppScope>()!;
    _admin = scope.admin..addListener(_onAuthChange);
    _url.text = scope.settings.backendUrl?.toString() ?? '';
    scope.settings.hasApiKey.then((v) => mounted ? setState(() => _hasKey = v) : null);
    // Re-check the idle timeout every few seconds; touches reset it.
    // Defence in depth: never render the panel without a live session.
    if (!_admin.isUnlocked) WidgetsBinding.instance.addPostFrameCallback((_) => _onAuthChange());
    _idle = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_admin.isUnlocked) _onAuthChange();
    });
  }

  @override
  void dispose() {
    _idle?.cancel();
    _admin.removeListener(_onAuthChange);
    NativeBridge.releaseSecure();
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  void _onAuthChange() {
    if (!_admin.isUnlocked && mounted) Navigator.of(context).maybePop();
  }

  Future<void> _saveSource(Settings s) async {
    final repo = AppScope.of(context).repo;
    final err = s.setBackendUrl(_url.text);
    setState(() => _urlError = err);
    if (err != null) return;
    if (_key.text.isNotEmpty) {
      await s.writeApiKey(_key.text.trim());
      _key.clear();
      _hasKey = true;
    }
    repo.clearCache();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Price source saved')));
    }
  }

  Future<void> _test(Settings s) async {
    final url = s.backendUrl;
    if (url == null) {
      setState(() => _testResult = 'Save a valid URL first.');
      return;
    }
    setState(() {
      _testing = true;
      _testResult = null;
    });
    try {
      final ms = await RemotePriceSource(baseUrl: url, apiKey: await s.readApiKey()).ping();
      _testResult = 'Connected · ${ms}ms';
    } on PriceSourceException catch (e) {
      _testResult = e.userMessage;
    } catch (_) {
      _testResult = 'Could not reach the server.';
    }
    if (mounted) setState(() => _testing = false);
  }

  Future<void> _changePasscode() async {
    final a = TextEditingController();
    final b = TextEditingController();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Change passcode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: a,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(hintText: 'New passcode'),
              ),
              const SizedBox(height: Space.md),
              TextField(
                controller: b,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(hintText: 'Confirm', errorText: err),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final e = AdminAuth.validateNew(a.text) ?? (a.text != b.text ? 'Passcodes don\'t match.' : null);
                if (e != null) return set(() => err = e);
                Navigator.pop(ctx, true);
              },
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _admin.changePasscode(a.text);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Passcode changed')));
    }
    a.dispose();
    b.dispose();
  }

  Future<void> _factoryReset() async {
    final scope = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Factory reset?'),
        content: const Text(
          'Clears all settings, the API key, search history and the admin passcode. This can\'t be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: context.c.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    scope.repo.clearCache();
    scope.repo.diagnostics.reset();
    await scope.settings.resetAll();
    await _admin.clear(); // triggers pop via listener
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final s = scope.settings;
    final d = scope.repo.diagnostics;
    final c = context.c;

    return Listener(
      onPointerDown: (_) => _admin.touch(),
      child: Backdrop(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            title: const Text('Admin'),
            actions: [
              TextButton.icon(
                onPressed: _admin.lock,
                icon: const Icon(Icons.lock_outline_rounded, size: 18),
                label: const Text('Lock'),
              ),
            ],
          ),
          body: ListenableBuilder(
            listenable: s,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxl),
              children: [
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: Space.sm,
                  crossAxisSpacing: Space.sm,
                  childAspectRatio: 2.1,
                  children: [
                    _Stat('Source', s.dataMode.label),
                    _Stat('Requests', '${d.requests}', sub: d.failures > 0 ? '${d.failures} failed' : 'no failures'),
                    _Stat(
                      'Last latency',
                      d.lastLatencyMs == null ? '—' : '${d.lastLatencyMs} ms',
                      sub: d.lastErrorCode,
                    ),
                    _Stat('Cache', '${scope.repo.cacheSize}', sub: 'entries · 5 min TTL'),
                  ],
                ),
                const SizedBox(height: Space.xl),
                const SectionLabel('Price source'),
                Surface(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RadioGroup<DataMode>(
                        groupValue: s.dataMode,
                        onChanged: (v) {
                          if (v == null || (v == DataMode.server && s.backendUrl == null)) return;
                          s.dataMode = v;
                          scope.repo.clearCache();
                        },
                        child: Column(
                          children: [
                            for (final m in DataMode.values)
                              RadioListTile<DataMode>(
                                contentPadding: EdgeInsets.zero,
                                value: m,
                                enabled: !(m == DataMode.server && s.backendUrl == null),
                                title: Text(m.label),
                                subtitle: Text(
                                  m == DataMode.server && s.backendUrl == null
                                      ? 'Add a server URL below first'
                                      : m.blurb,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const Divider(),
                      const SizedBox(height: Space.md),
                      Text('Price server', style: context.t.titleSmall),
                      const SizedBox(height: Space.sm),
                      TextField(
                        controller: _url,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Server URL',
                          hintText: 'https://api.example.com',
                          errorText: _urlError,
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      TextField(
                        controller: _key,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        decoration: InputDecoration(
                          labelText: 'API key',
                          hintText: _hasKey ? 'Saved — enter a new one to replace' : 'Optional bearer token',
                          suffixIcon: _hasKey
                              ? IconButton(
                                  tooltip: 'Remove saved key',
                                  icon: const Icon(Icons.delete_outline_rounded),
                                  onPressed: () async {
                                    await s.writeApiKey(null);
                                    if (mounted) setState(() => _hasKey = false);
                                  },
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(height: Space.md),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(onPressed: () => _saveSource(s), child: const Text('Save')),
                          ),
                          const SizedBox(width: Space.sm),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _testing ? null : () => _test(s),
                              child: Text(_testing ? 'Testing…' : 'Test'),
                            ),
                          ),
                        ],
                      ),
                      if (_testResult != null) ...[
                        const SizedBox(height: Space.sm),
                        Text(_testResult!, style: context.t.bodySmall),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Space.xl),
                for (final v in Vertical.values) ...[
                  SectionLabel(v.label),
                  Surface(
                    padding: const EdgeInsets.symmetric(vertical: Space.xs),
                    child: Column(
                      children: [
                        for (final p in platformsFor(v))
                          SwitchListTile(
                            dense: true,
                            secondary: PlatformDot(p, size: 12),
                            title: Text(p.name, style: context.t.bodyMedium),
                            value: s.isPlatformEnabled(p.id),
                            onChanged: (on) {
                              s.setPlatformEnabled(p.id, on);
                              scope.repo.clearCache();
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.lg),
                ],
                const SizedBox(height: Space.sm),
                const SectionLabel('Maintenance'),
                Surface(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.public_off_rounded),
                        title: const Text('Reset app sessions'),
                        subtitle: const Text('Clears cookies and saved addresses for Blinkit, Zepto, Instamart'),
                        onTap: () async {
                          await CookieManager.instance().deleteAllCookies();
                          await WebStorageManager.instance().deleteAllData();
                          for (final sc in deviceScrapers) {
                            s.markLocationSet(sc.platformId, false);
                          }
                          scope.repo.clearCache();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.cached_rounded),
                        title: const Text('Clear result cache'),
                        onTap: () => setState(scope.repo.clearCache),
                      ),
                      ListTile(
                        leading: const Icon(Icons.restart_alt_rounded),
                        title: const Text('Reset diagnostics'),
                        onTap: () => setState(d.reset),
                      ),
                      ListTile(
                        leading: const Icon(Icons.history_toggle_off_rounded),
                        title: const Text('Clear search history'),
                        onTap: s.clearRecent,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.xl),
                const SectionLabel('Security'),
                Surface(
                  padding: const EdgeInsets.symmetric(vertical: Space.xs),
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.password_rounded),
                        title: const Text('Change passcode'),
                        onTap: _changePasscode,
                      ),
                      ListTile(
                        leading: const Icon(Icons.timer_outlined),
                        title: const Text('Auto-lock'),
                        subtitle: Text('After ${AdminAuth.idleTimeout.inMinutes} min idle or when the app is closed'),
                      ),
                      ListTile(
                        leading: Icon(Icons.delete_forever_outlined, color: c.danger),
                        title: Text('Factory reset', style: TextStyle(color: c.danger)),
                        onTap: _factoryReset,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.sub});
  final String label;
  final String value;
  final String? sub;

  @override
  Widget build(BuildContext context) => Surface(
    padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(label.toUpperCase(), style: context.t.labelSmall),
        Text(value, style: context.t.titleMedium!.copyWith(fontFeatures: tabular), maxLines: 1),
        if (sub != null) Text(sub!, style: context.t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}
