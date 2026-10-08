import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../security/admin_auth.dart';
import '../../security/native_bridge.dart';
import '../../theme/tokens.dart';
import 'admin_screen.dart';

/// Passcode screen in front of the admin panel. Sets a passcode on first use.
class AdminGate extends StatefulWidget {
  const AdminGate({super.key});

  @override
  State<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends State<AdminGate> {
  final _pass = TextEditingController();
  final _confirm = TextEditingController();
  bool? _configured;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    NativeBridge.acquireSecure();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final admin = AppScope.of(context).admin;
      if (admin.isUnlocked) return _enter();
      final configured = await admin.isConfigured;
      if (mounted) setState(() => _configured = configured);
    });
  }

  @override
  void dispose() {
    NativeBridge.releaseSecure();
    _pass.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _enter() {
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => const AdminScreen()));
  }

  Future<void> _submit() async {
    if (_busy) return;
    final admin = AppScope.of(context).admin;
    final pass = _pass.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? err;
    if (_configured == false) {
      err = AdminAuth.validateNew(pass) ?? (pass != _confirm.text ? 'Passcodes don\'t match.' : null);
      if (err == null) await admin.setPasscode(pass);
    } else {
      err = await admin.verify(pass);
    }
    if (!mounted) return;
    _pass.clear();
    _confirm.clear();
    setState(() {
      _busy = false;
      _error = err;
    });
    if (err == null) _enter();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final creating = _configured == false;
    return Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(),
        body: _configured == null
            ? const Center(child: CircularProgressIndicator())
            : SafeArea(
                child: ListView(
                  padding: const EdgeInsets.all(Space.xl),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(color: c.primarySoft, borderRadius: BorderRadius.circular(Radii.md)),
                        child: Icon(Icons.admin_panel_settings_outlined, color: c.primary),
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    Text(creating ? 'Set an admin passcode' : 'Admin access', style: context.t.titleLarge),
                    const SizedBox(height: Space.xs),
                    Text(
                      creating
                          ? 'Choose at least ${AdminAuth.minLength} characters. It\'s stored only as a salted hash on this device.'
                          : 'Enter your admin passcode.',
                      style: context.t.bodySmall,
                    ),
                    const SizedBox(height: Space.xl),
                    TextField(
                      controller: _pass,
                      autofocus: true,
                      obscureText: _obscure,
                      enableSuggestions: false,
                      autocorrect: false,
                      maxLength: 64,
                      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                      keyboardType: TextInputType.visiblePassword,
                      onSubmitted: (_) => creating ? null : _submit(),
                      decoration: InputDecoration(
                        hintText: 'Passcode',
                        suffixIcon: IconButton(
                          tooltip: _obscure ? 'Show' : 'Hide',
                          icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                          onPressed: () => setState(() => _obscure = !_obscure),
                        ),
                      ),
                    ),
                    if (creating) ...[
                      const SizedBox(height: Space.md),
                      TextField(
                        controller: _confirm,
                        obscureText: _obscure,
                        enableSuggestions: false,
                        autocorrect: false,
                        maxLength: 64,
                        buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                        keyboardType: TextInputType.visiblePassword,
                        onSubmitted: (_) => _submit(),
                        decoration: const InputDecoration(hintText: 'Confirm passcode'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: Space.md),
                      Text(_error!, style: context.t.bodySmall!.copyWith(color: c.danger)),
                    ],
                    const SizedBox(height: Space.xl),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: c.onPrimary),
                            )
                          : Text(creating ? 'Set passcode' : 'Unlock'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
