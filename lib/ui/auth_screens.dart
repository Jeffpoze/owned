import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../domain/models.dart';
import '../state/auth_store.dart';
import '../theme.dart';
import 'widgets.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
const minPasswordLength = 8;

/// Shared frame: icon, wordmark, tagline, then the form.
class _AuthFrame extends StatelessWidget {
  const _AuthFrame({
    required this.title,
    required this.children,
    this.subtitle,
  });
  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        'assets/icon/icon.png',
                        width: 52,
                        height: 52,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Owned',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 34,
                        letterSpacing: -1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  "Know what you own. Know what's covered. Keep the proof.",
                  style: mutedStyle(context),
                ),
                const SizedBox(height: 32),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 24,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    subtitle!,
                    style: mutedStyle(context).copyWith(fontSize: 15),
                  ),
                ],
                const SizedBox(height: 20),
                ...children,
              ],
            ),
          ),
        ),
      ),
      backgroundColor: p.paper,
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hints = const [],
    this.obscure = false,
    this.email = false,
    this.action = TextInputAction.next,
    this.onSubmitted,
  });
  final String label;
  final TextEditingController controller;
  final List<String> hints;
  final bool obscure;
  final bool email;
  final TextInputAction action;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(label, style: labelStyle(context)),
        ),
        TextField(
          controller: controller,
          obscureText: obscure,
          autofillHints: hints,
          keyboardType: email
              ? TextInputType.emailAddress
              : TextInputType.visiblePassword,
          autocorrect: false,
          enableSuggestions: !obscure && !email,
          textCapitalization: TextCapitalization.none,
          textInputAction: action,
          onSubmitted: onSubmitted,
          style: const TextStyle(fontSize: 16),
        ),
      ],
    ),
  );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);
  final String? message;

  @override
  Widget build(BuildContext context) => message == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            message!,
            style: TextStyle(
              color: context.palette.status[WarrantyState.expired],
              fontSize: 14,
              height: 1.35,
            ),
          ),
        );
}

class _LinkButton extends StatelessWidget {
  const _LinkButton(this.label, this.onPressed);
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      foregroundColor: context.palette.status[WarrantyState.documented],
    ),
    child: Text(
      label,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
    ),
  );
}

/// The first screen on a new install: an account is required to use the app.
class CreateAccountScreen extends StatefulWidget {
  const CreateAccountScreen({super.key});

  @override
  State<CreateAccountScreen> createState() => _CreateAccountScreenState();
}

class _CreateAccountScreenState extends State<CreateAccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    final error = !_emailPattern.hasMatch(email)
        ? 'Enter a valid email address.'
        : _password.text.length < minPasswordLength
        ? 'Use at least $minPasswordLength characters for your password.'
        : _password.text != _confirm.text
        ? "The passwords don't match."
        : null;
    setState(() => _error = error);
    if (error != null) return;
    setState(() => _busy = true);
    final result = await context.read<AuthStore>().signUp(
      email,
      _password.text,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result;
    });
    // Offer to save the new password to the phone's password manager.
    if (result == null) TextInput.finishAutofillContext();
  }

  @override
  Widget build(BuildContext context) {
    return _AuthFrame(
      title: 'Create your account',
      subtitle:
          'Your inventory, receipts and warranties are saved to your account, so they are there on any phone '
          'you sign in on.',
      children: [
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(
                label: 'Email',
                controller: _email,
                email: true,
                hints: const [AutofillHints.email, AutofillHints.username],
              ),
              _Field(
                label: 'Password',
                controller: _password,
                obscure: true,
                hints: const [AutofillHints.newPassword],
              ),
              _Field(
                label: 'Confirm password',
                controller: _confirm,
                obscure: true,
                hints: const [AutofillHints.newPassword],
                action: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        Text(
          'At least $minPasswordLength characters.',
          style: labelStyle(context),
        ),
        const SizedBox(height: 16),
        _ErrorText(_error),
        AppButton(
          _busy ? 'Creating account…' : 'Create account',
          onPressed: _busy ? null : _submit,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Already have an account?', style: mutedStyle(context)),
            _LinkButton('Sign in', () => context.go('/sign-in')),
          ],
        ),
      ],
    );
  }
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  late final _auth = context.read<AuthStore>();
  late final _email = TextEditingController(text: _auth.lastEmail);
  final _password = TextEditingController();
  late bool _keep = _auth.keepSignedIn;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!_emailPattern.hasMatch(email) || _password.text.isEmpty) {
      setState(() => _error = 'Enter your email and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await _auth.signIn(email, _password.text, keep: _keep);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = result;
    });
    if (result == null) TextInput.finishAutofillContext();
  }

  Future<void> _forgot() async {
    final email = _email.text.trim();
    if (!_emailPattern.hasMatch(email)) {
      setState(
        () => _error =
            'Enter your email above, then tap “Forgot password?” again.',
      );
      return;
    }
    final result = await _auth.sendPasswordReset(email);
    if (!mounted) return;
    if (result != null) {
      setState(() => _error = result);
    } else {
      toast(context, 'Password reset email sent to $email');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return _AuthFrame(
      title: 'Sign in',
      children: [
        AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Field(
                label: 'Email',
                controller: _email,
                email: true,
                hints: const [AutofillHints.email, AutofillHints.username],
              ),
              _Field(
                label: 'Password',
                controller: _password,
                obscure: true,
                hints: const [AutofillHints.password],
                action: TextInputAction.done,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => setState(() => _keep = !_keep),
                child: Row(
                  children: [
                    Checkbox.adaptive(
                      value: _keep,
                      onChanged: (v) => setState(() => _keep = v ?? true),
                      activeColor: p.ink,
                      checkColor: p.paper,
                    ),
                    const Text(
                      'Keep me signed in',
                      style: TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
            _LinkButton('Forgot password?', _busy ? null : _forgot),
          ],
        ),
        const SizedBox(height: 12),
        _ErrorText(_error),
        AppButton(
          _busy ? 'Signing in…' : 'Sign in',
          onPressed: _busy ? null : _submit,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('New to Owned?', style: mutedStyle(context)),
            _LinkButton('Create an account', () => context.go('/welcome')),
          ],
        ),
      ],
    );
  }
}

class VerifyEmailScreen extends StatefulWidget {
  const VerifyEmailScreen({super.key});

  @override
  State<VerifyEmailScreen> createState() => _VerifyEmailScreenState();
}

class _VerifyEmailScreenState extends State<VerifyEmailScreen> {
  bool _sending = false;

  Future<void> _resend() async {
    setState(() => _sending = true);
    final result = await context.read<AuthStore>().resendVerification();
    if (!mounted) return;
    setState(() => _sending = false);
    toast(context, result ?? 'Verification email sent again');
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthStore>();
    return _AuthFrame(
      title: 'Check your email',
      subtitle:
          'We sent a verification link to ${auth.pendingEmail}. Open it on this phone to sign in straight away, '
          'or verify on any device and then sign in here.',
      children: [
        CardBox(
          child: Row(
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                color: context.palette.ink2,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Can't find it? Check your spam folder. The link works once.",
                  style: mutedStyle(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        AppButton(
          'I’ve verified, sign in',
          onPressed: () async {
            await context.read<AuthStore>().backToSignIn();
            if (context.mounted) context.go('/sign-in');
          },
        ),
        const SizedBox(height: 8),
        AppButton(
          _sending ? 'Sending…' : 'Resend the email',
          kind: ButtonKind.ghost,
          onPressed: _sending ? null : _resend,
        ),
        const SizedBox(height: 8),
        Center(
          child: _LinkButton('Use a different email', () async {
            await context.read<AuthStore>().backToSignIn();
            if (context.mounted) context.go('/welcome');
          }),
        ),
      ],
    );
  }
}
