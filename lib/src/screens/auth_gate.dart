import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.hasAccount,
    required this.onSubmit,
  });

  final bool hasAccount;
  final Future<String?> Function(String name, String password) onSubmit;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _nameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _passwordCtrl.dispose();
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
    setState(() {
      _loading = true;
      _error = null;
    });
    final error = await widget.onSubmit(name, password);
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
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              Text(
                                widget.hasAccount
                                    ? 'Sign in to continue'
                                    : 'Create a local account',
                                style: Theme.of(context).textTheme.bodySmall,
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
                    TextField(
                      controller: _nameCtrl,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'User name'),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                        ),
                      ),
                    ),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.login_outlined),
                      label: Text(
                        widget.hasAccount ? 'Sign in' : 'Create and sign in',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppPickerScreen extends StatelessWidget {
  const AppPickerScreen({
    super.key,
    required this.userName,
    required this.onOpenApp,
    required this.onLogout,
  });

  final String userName;
  final VoidCallback onOpenApp;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [colors.bg, colors.bg2],
          ),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Choose an app',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            Text(
                              'Hello $userName, choose a workspace to continue.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: AppTheme.toggleTheme,
                        icon: const Icon(Icons.brightness_6_outlined),
                        tooltip: 'Toggle theme',
                      ),
                      TextButton(
                        onPressed: onLogout,
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: onOpenApp,
                    child: Ink(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        color: colors.panel,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: colors.line),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(18),
                            child: Image.asset(
                              'assets/App_VietNamMap_Logo_no_background.png',
                              width: 58,
                              height: 58,
                              fit: BoxFit.contain,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'VietNam Map Checkin',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                Text(
                                  'Province map, check-in history, and backend sync.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: colors.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
