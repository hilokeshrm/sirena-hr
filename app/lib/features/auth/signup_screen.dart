import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/api.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../widgets/common.dart';

/// Accepting an HR invite: set a password and fill in personal details.
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key, required this.token});
  final String token;

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _preferred = TextEditingController();
  final _phone = TextEditingController();
  final _emName = TextEditingController();
  final _emRelation = TextEditingController();
  final _emPhone = TextEditingController();
  DateTime? _dob;
  String _food = 'VEG';
  bool _busy = false;
  bool _done = false;

  Future<void> _submit() async {
    if (_password.text.length < 10) {
      showSnack(context, 'Password needs at least 10 characters');
      return;
    }
    if (_password.text != _confirm.text) {
      showSnack(context, "Passwords don't match");
      return;
    }
    setState(() => _busy = true);
    final ok = await attempt(context, () => Api.instance.post('/auth/invites/${widget.token}/accept', {
          'password': _password.text,
          if (_preferred.text.isNotEmpty) 'preferredName': _preferred.text,
          if (_phone.text.isNotEmpty) 'phone': _phone.text,
          if (_dob != null) 'dateOfBirth': ymd(_dob!),
          'foodPref': _food,
          if (_emName.text.isNotEmpty) 'emergencyName': _emName.text,
          if (_emRelation.text.isNotEmpty) 'emergencyRelation': _emRelation.text,
          if (_emPhone.text.isNotEmpty) 'emergencyPhone': _emPhone.text,
        }));
    if (!mounted) return;
    setState(() {
      _busy = false;
      _done = ok != null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Fetch<Map<String, dynamic>>(
        load: () async => asMap(await Api.instance.get('/auth/invites/${widget.token}')),
        builder: (context, invite, _) => SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              color: C.ink,
              padding: const EdgeInsets.fromLTRB(28, 48, 28, 28),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Image.asset('assets/sirena-logo.png', width: 140),
                const SizedBox(height: 24),
                const Text("YOU'RE INVITED", style: TextStyle(color: C.grey, fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                const SizedBox(height: 6),
                Text('Welcome to Sirena, ${(invite['fullName'] as String).split(' ').first}.', style: display(30, color: Colors.white)),
                const SizedBox(height: 12),
                Text(
                  [invite['designation'], (invite['department'] as Map?)?['name'], (invite['location'] as Map?)?['name']].whereType<String>().join(' · '),
                  style: const TextStyle(color: C.grey),
                ),
                if (invite['invitedBy'] != null) Text('Invited by ${invite['invitedBy']}', style: const TextStyle(color: C.grey)),
              ]),
            ),
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                  child: _done
                      ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text("You're in.", style: display(28)),
                          gap8,
                          const Text('Your account is ready. Sign in with your work email and the password you just set.'),
                          gap16,
                          FilledButton(onPressed: () => context.go('/login'), child: const Text('Go to sign in')),
                        ])
                      : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text('Set up your account', style: display(26)),
                          gap8,
                          Text('Work email: ${invite['email']}'),
                          gap16,
                          TextField(controller: _password, obscureText: true, decoration: inputDeco('Password', hint: 'At least 10 characters')),
                          gap12,
                          TextField(controller: _confirm, obscureText: true, decoration: inputDeco('Confirm password')),
                          gap16,
                          Text('About you', style: display(18)),
                          gap8,
                          TextField(controller: _preferred, decoration: inputDeco('Preferred name (optional)')),
                          gap12,
                          TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: inputDeco('Mobile number')),
                          gap12,
                          OutlinedButton.icon(
                            icon: const Icon(Icons.cake_outlined),
                            label: Text(_dob == null ? 'Date of birth' : niceDay(ymd(_dob!))),
                            onPressed: () async {
                              final d = await showDatePicker(context: context, firstDate: DateTime(1950), lastDate: DateTime.now(), initialDate: DateTime(1995));
                              if (d != null) setState(() => _dob = d);
                            },
                          ),
                          gap12,
                          const Text('Lunch preference', style: TextStyle(fontWeight: FontWeight.w700)),
                          gap8,
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'VEG', label: Text('Veg'), icon: FoodMark(veg: true, size: 16)),
                              ButtonSegment(value: 'NON_VEG', label: Text('Non-veg'), icon: FoodMark(veg: false, size: 16)),
                            ],
                            selected: {_food},
                            onSelectionChanged: (v) => setState(() => _food = v.first),
                          ),
                          gap16,
                          Text('Emergency contact', style: display(18)),
                          gap8,
                          TextField(controller: _emName, decoration: inputDeco('Name')),
                          gap12,
                          TextField(controller: _emRelation, decoration: inputDeco('Relationship')),
                          gap12,
                          TextField(controller: _emPhone, keyboardType: TextInputType.phone, decoration: inputDeco('Phone')),
                          const SizedBox(height: 24),
                          FilledButton(onPressed: _busy ? null : _submit, child: const Text('Finish setup')),
                        ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
