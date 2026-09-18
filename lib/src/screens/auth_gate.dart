import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

enum AuthMode { signIn, register }

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.hasAccount,
    required this.onSubmit,
  });

  final bool hasAccount;
  final Future<String?> Function(AuthMode mode, String name, String password)
  onSubmit;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  late AuthMode _mode;
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mode = widget.hasAccount ? AuthMode.signIn : AuthMode.register;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (name.isEmpty || password.length < 4) {
      setState(
        () =>
            _error = 'Enter a name and a password with at least 4 characters.',
      );
      return;
    }
    if (_mode == AuthMode.register && password != _confirmCtrl.text) {
      setState(() => _error = 'The passwords do not match.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.onSubmit(_mode, name, password);
    } catch (_) {
      error =
          'Could not connect to the backend. Check your connection and try again.';
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [colors.bg, colors.bg2],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Card(
                    margin: const EdgeInsets.all(20),
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(16),
                                child: Image.asset(
                                  'assets/App_VietNamMap_Logo_no_background.png',
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.contain,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'VietNam Map Checkin',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleLarge,
                                    ),
                                    Text(
                                      _mode == AuthMode.signIn
                                          ? 'Sign in to restore your memories'
                                          : 'Register to save your memories',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: AppTheme.toggleTheme,
                                icon: ValueListenableBuilder<ThemeMode>(
                                  valueListenable: AppTheme.themeMode,
                                  builder: (context, mode, _) {
                                    return Icon(
                                      mode == ThemeMode.dark
                                          ? Icons.light_mode_outlined
                                          : Icons.dark_mode_outlined,
                                    );
                                  },
                                ),
                                tooltip: 'Toggle theme',
                              ),
                            ],
                          ),
                          const SizedBox(height: 26),
                          SegmentedButton<AuthMode>(
                            segments: const [
                              ButtonSegment(
                                value: AuthMode.signIn,
                                label: Text('Sign in'),
                                icon: Icon(Icons.login_outlined),
                              ),
                              ButtonSegment(
                                value: AuthMode.register,
                                label: Text('Register'),
                                icon: Icon(Icons.person_add_alt_1_outlined),
                              ),
                            ],
                            selected: {_mode},
                            onSelectionChanged: _loading
                                ? null
                                : (selected) => setState(() {
                                    _mode = selected.first;
                                    _error = null;
                                  }),
                          ),
                          const SizedBox(height: 18),
                          TextField(
                            controller: _nameCtrl,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'User name',
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordCtrl,
                            obscureText: _obscure,
                            textInputAction: _mode == AuthMode.register
                                ? TextInputAction.next
                                : TextInputAction.done,
                            onSubmitted: (_) {
                              if (_mode == AuthMode.signIn) _submit();
                            },
                            decoration: InputDecoration(
                              labelText: 'Password',
                              suffixIcon: IconButton(
                                onPressed: () =>
                                    setState(() => _obscure = !_obscure),
                                icon: Icon(
                                  _obscure
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                tooltip: _obscure
                                    ? 'Show password'
                                    : 'Hide password',
                              ),
                            ),
                          ),
                          if (_mode == AuthMode.register) ...[
                            const SizedBox(height: 14),
                            TextField(
                              controller: _confirmCtrl,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _submit(),
                              decoration: const InputDecoration(
                                labelText: 'Confirm password',
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFFE85D5D),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          FilledButton.icon(
                            onPressed: _loading ? null : _submit,
                            icon: _loading
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    _mode == AuthMode.signIn
                                        ? Icons.login_outlined
                                        : Icons.person_add_alt_1_outlined,
                                  ),
                            label: Text(
                              _mode == AuthMode.signIn
                                  ? 'Sign in'
                                  : 'Create account',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
