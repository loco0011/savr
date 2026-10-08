import 'dart:async';

import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'core/app_launcher.dart';
import 'security/native_bridge.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';
import 'ui/compare_screen.dart';
import 'ui/rides_screen.dart';
import 'ui/login_screen.dart';
import 'ui/profile_screen.dart';

class SavrApp extends StatelessWidget {
  const SavrApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = AppScope.of(context).settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => MaterialApp(
        title: 'Savr',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        themeMode: settings.themeMode,
        home: const _Shell(),
      ),
    );
  }
}

class _Shell extends StatefulWidget {
  const _Shell();

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> with WidgetsBindingObserver {
  int _tab = 0;

  /// Text shared into the app from another app's share sheet.
  final _incoming = ValueNotifier<String?>(null);
  StreamSubscription<String>? _shareSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NativeBridge.initialSharedText().then(_onShared);
    _shareSub = NativeBridge.sharedText.listen(_onShared);
    AppLauncher.refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) => _welcome());
  }

  /// First launch: log in (or continue as guest) and add an address.
  Future<void> _welcome() async {
    final s = AppScope.of(context).settings;
    if (s.onboarded || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => const LoginScreen(firstRun: true)),
    );
    s.markOnboarded();
  }

  void _onShared(String? text) {
    if (text == null || text.trim().isEmpty || !mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    setState(() => _tab = 0);
    _incoming.value = text;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Apps may have been installed or removed while away.
    if (state == AppLifecycleState.resumed) AppLauncher.refresh();
    // Leaving the app always ends an admin session.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      AppScope.of(context).admin.lock();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shareSub?.cancel();
    _incoming.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: IndexedStack(
          index: _tab,
          children: [
            CompareScreen(incoming: _incoming),
            const RidesScreen(),
            const ProfileScreen(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.local_offer_outlined),
              selectedIcon: Icon(Icons.local_offer_rounded),
              label: 'Compare',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_taxi_outlined),
              selectedIcon: Icon(Icons.local_taxi_rounded),
              label: 'Rides',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline_rounded),
              selectedIcon: Icon(Icons.person_rounded),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}
