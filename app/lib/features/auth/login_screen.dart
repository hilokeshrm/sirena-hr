import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Session.instance.login(_email.text, _password.text);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _brand({required bool wide}) => Container(
        color: C.ink,
        padding: EdgeInsets.fromLTRB(28, wide ? 56 : 48, 28, wide ? 48 : 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: wide ? MainAxisAlignment.spaceBetween : MainAxisAlignment.start,
          children: [
            Image.asset('assets/sirena-logo.png', width: wide ? 170 : 140),
            SizedBox(height: wide ? 0 : 28),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('HR · PEOPLE · PROJECTS', style: TextStyle(color: C.grey, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Text('Work stuff,\nminus the fuss.', style: display(wide ? 46 : 30, color: Colors.white)),
            ]),
            if (wide) const Text('© Sirena Technologies · Built in India', style: TextStyle(color: C.grey, fontSize: 12)),
          ],
        ),
      );

  Widget _form() => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AutofillGroup(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Text('Welcome back', style: display(28)),
            const SizedBox(height: 6),
            const Text('Sign in with your Sirena work account.'),
            const SizedBox(height: 24),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: inputDeco('Work email'),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _password,
              obscureText: _hide,
              autofillHints: const [AutofillHints.password],
              onSubmitted: (_) => _submit(),
              decoration: inputDeco('Password',
                  suffix: IconButton(
                    tooltip: _hide ? 'Show password' : 'Hide password',
                    icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    onPressed: () => setState(() => _hide = !_hide),
                  )),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _submit,
              child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Sign in'),
            ),
            const SizedBox(height: 16),
            const Text('New here? Use the invite link HR sent you.\nForgot your password? Ask HR to reset it.', textAlign: TextAlign.center, style: TextStyle(fontSize: 13)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        if (wide) {
          return Row(children: [
            Expanded(child: _brand(wide: true)),
            Expanded(child: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(32), child: _form()))),
          ]);
        }
        return SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _brand(wide: false),
            Padding(padding: const EdgeInsets.fromLTRB(24, 28, 24, 32), child: _form()),
          ]),
        );
      }),
    );
  }
}
