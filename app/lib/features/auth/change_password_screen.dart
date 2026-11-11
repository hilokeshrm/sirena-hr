import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/session.dart';
import '../../core/theme.dart';

/// Shown right after sign-in when HR set a temporary password: the person picks their own before going on.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    String? problem;
    if (_next.text.length < 10) {
      problem = 'Use at least 10 characters';
    } else if (_next.text != _again.text) {
      problem = 'The two new passwords don’t match';
    }
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Session.instance.changePassword(_current.text, _next.text);
    } on ApiError catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: AutofillGroup(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                Text('Set your password', style: display(28)),
                const SizedBox(height: 6),
                Text('Hi ${Session.instance.firstName}, you signed in with a temporary password. Choose your own to continue.'),
                const SizedBox(height: 24),
                TextField(
                  controller: _current,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: inputDeco('Temporary password'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _next,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: inputDeco('New password (10+ characters)'),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _again,
                  obscureText: true,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _submit(),
                  decoration: inputDeco('New password again'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: C.red, fontWeight: FontWeight.w700)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('Save and continue'),
                ),
                const SizedBox(height: 12),
                TextButton(onPressed: Session.instance.logout, child: const Text('Sign out')),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
