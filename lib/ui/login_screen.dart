import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../core/address.dart';
import '../theme/tokens.dart';
import 'address_editor.dart';
import 'widgets/common.dart';

/// Sign-in. Demo only for now: any id and password are accepted, nothing
/// is sent anywhere and the password is never stored.
/// TODO(backend): call the real auth endpoint and keep a token in the
/// keystore (flutter_secure_storage), never the password.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.firstRun = false});

  /// Shown on first launch: offers "Continue as guest" and, after login,
  /// asks for a delivery address.
  final bool firstRun;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _id = TextEditingController();
  final _pass = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _id.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final s = AppScope.of(context).settings;
    final id = SavedAddress.cleanField(_id.text, max: 60)!;
    // Brief pause so the button state reads as a real sign-in.
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;
    s.logIn(id, name: _nameFrom(id));
    _pass.clear();
    if (widget.firstRun && s.addresses.isEmpty) {
      await editAddress(context);
    }
    if (mounted) _close();
  }

  void _guest() {
    AppScope.of(context).settings.markOnboarded();
    _close();
  }

  void _close() {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  /// "sambit.d@gmail.com" → "Sambit D".
  static String _nameFrom(String id) {
    final local = id.split('@').first;
    final words = local.split(RegExp(r'[._\-\s]+')).where((w) => w.isNotEmpty && !RegExp(r'^\d+$').hasMatch(w));
    final name = words.map((w) => '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}').join(' ');
    return name.isEmpty ? id : name;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: c.bg,
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.fromLTRB(Space.xl, MediaQuery.paddingOf(context).top + Space.lg, Space.xl, Space.xxl),
                decoration: BoxDecoration(
                  gradient: c.hero,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(Radii.xxl)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const SavrMark(size: 30),
                        const SizedBox(width: Space.sm),
                        Text('Savr', style: context.t.titleLarge!.copyWith(color: Colors.white)),
                        const Spacer(),
                        if (!widget.firstRun)
                          IconButton(
                            onPressed: _close,
                            icon: const Icon(Icons.close_rounded, color: Colors.white),
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.xxl),
                    Text(
                      'Pay less for\nthe same thing.',
                      style: context.t.headlineMedium!.copyWith(color: Colors.white, fontSize: 30),
                    ),
                    const SizedBox(height: Space.sm),
                    Text(
                      'Live prices from Blinkit, Zepto, Instamart and more, for your exact address.',
                      style: context.t.bodyMedium!.copyWith(color: Colors.white.withValues(alpha: 0.8)),
                    ),
                    const SizedBox(height: Space.lg),
                    const Wrap(
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: [
                        _Perk(icon: Icons.home_rounded, text: 'Saved addresses'),
                        _Perk(icon: Icons.bookmark_rounded, text: 'Saved searches'),
                        _Perk(icon: Icons.savings_rounded, text: 'Savings tracker'),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.xl),
                child: Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Log in', style: context.t.titleLarge),
                        const SizedBox(height: Space.lg),
                        TextFormField(
                          controller: _id,
                          autofillHints: const [AutofillHints.username, AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          maxLength: 60,
                          buildCounter: _noCounter,
                          decoration: const InputDecoration(
                            labelText: 'Email, phone or user ID',
                            prefixIcon: Icon(Icons.person_outline_rounded),
                          ),
                          validator: (v) => (v ?? '').trim().length < 3 ? 'Enter at least 3 characters' : null,
                        ),
                        const SizedBox(height: Space.md),
                        TextFormField(
                          controller: _pass,
                          obscureText: _obscure,
                          autofillHints: const [AutofillHints.password],
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _login(),
                          maxLength: 64,
                          buildCounter: _noCounter,
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _obscure ? 'Show password' : 'Hide password',
                              icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                              onPressed: () => setState(() => _obscure = !_obscure),
                            ),
                          ),
                          validator: (v) => (v ?? '').length < 4 ? 'Use at least 4 characters' : null,
                        ),
                        const SizedBox(height: Space.xl),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _busy ? null : _login,
                            child: _busy
                                ? SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: c.onPrimary),
                                  )
                                : const Text('Log in'),
                          ),
                        ),
                        if (widget.firstRun) ...[
                          const SizedBox(height: Space.sm),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton(onPressed: _guest, child: const Text('Continue as guest')),
                          ),
                        ],
                        const SizedBox(height: Space.lg),
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded, size: 16, color: c.inkMuted),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: Text(
                                'Preview: any ID and password work. Your account lives only on this phone for now; '
                                'the password is never stored.',
                                style: context.t.bodySmall!.copyWith(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget? _noCounter(BuildContext _, {required int currentLength, required bool isFocused, int? maxLength}) =>
      null;
}

class _Perk extends StatelessWidget {
  const _Perk({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: ShapeDecoration(
      color: Colors.white.withValues(alpha: 0.12),
      shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: const Color(0xFFF5C065)),
        const SizedBox(width: 6),
        Text(text, style: context.t.labelMedium!.copyWith(color: Colors.white)),
      ],
    ),
  );
}
