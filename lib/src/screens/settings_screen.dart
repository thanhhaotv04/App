import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_version.dart';
import '../models/checkin.dart';
import '../repositories/app_data_reset.dart';
import '../repositories/app_update_service.dart';
import '../repositories/auth_service.dart';
import '../repositories/backup_service.dart';
import '../repositories/backend_config.dart';
import '../repositories/checkin_repository.dart';
import '../repositories/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _userKey = 'vmc-auth-user';
  static const _passwordKey = 'vmc-auth-password';

  final _repo = CheckInRepository();
  final _backup = const BackupService();
  final _backendCtrl = TextEditingController(text: BackendConfig.defaultUrl);
  final _userCtrl = TextEditingController();
  final _currentPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _savingAccount = false;
  bool _syncing = false;
  bool _updating = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _backendCtrl.dispose();
    _userCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final backendUrl = await BackendConfig.loadUrl();
    if (!mounted) return;
    setState(() {
      _backendCtrl.text = backendUrl;
      _userCtrl.text = prefs.getString(_userKey) ?? '';
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _saveAccount() async {
    final name = _userCtrl.text.trim();
    final currentPassword = _currentPasswordCtrl.text;
    final newPassword = _newPasswordCtrl.text;
    final confirmation = _confirmPasswordCtrl.text;
    final prefs = await SharedPreferences.getInstance();
    final storedPassword = prefs.getString(_passwordKey) ?? '';

    if (name.isEmpty) {
      _showMessage('User name cannot be empty.');
      return;
    }
    if (storedPassword.isNotEmpty && currentPassword != storedPassword) {
      _showMessage('Current password is incorrect.');
      return;
    }
    if (newPassword.isNotEmpty && newPassword != confirmation) {
      _showMessage('New passwords do not match.');
      return;
    }

    setState(() => _savingAccount = true);
    try {
      await BackendConfig.saveUrl(_backendCtrl.text);
      final savedName =
          await AuthService(
            baseUrl: await BackendConfig.loadUrl(),
          ).updateAccount(
            name: prefs.getString(_userKey) ?? name,
            currentPassword: currentPassword,
            newName: name,
            newPassword: newPassword.isEmpty ? null : newPassword,
          );
      await prefs.setString(_userKey, savedName);
      if (newPassword.isNotEmpty) {
        await prefs.setString(_passwordKey, newPassword);
      }
      if (!mounted) return;
      setState(() {
        _userCtrl.text = savedName;
        _currentPasswordCtrl.clear();
        _newPasswordCtrl.clear();
        _confirmPasswordCtrl.clear();
      });
      _showMessage('Account saved.');
    } catch (err) {
      _showMessage('Account update failed: $err');
    } finally {
      if (mounted) setState(() => _savingAccount = false);
    }
  }

  Future<void> _saveBackendUrl() async {
    await BackendConfig.saveUrl(_backendCtrl.text);
    _showMessage('Backend URL saved.');
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await BackendConfig.saveUrl(_backendCtrl.text);
      final sync = SyncService(baseUrl: await BackendConfig.loadUrl());
      final merged = await sync.syncTwoWay(await _repo.load());
      await _repo.save(merged);
      _showMessage('Synced ${merged.length} check-in(s).');
    } catch (err) {
      _showMessage('Sync failed: $err');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _checkAndInstallUpdate() async {
    setState(() => _updating = true);
    try {
      await BackendConfig.saveUrl(_backendCtrl.text);
      final service = AppUpdateService(baseUrl: await BackendConfig.loadUrl());
      final info = await service.checkLatest();
      if (!info.available) {
        _showMessage(
          'Already up to date: '
          '${AppVersion.versionName}+${AppVersion.versionCode}.',
        );
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Install update ${info.versionName}+${info.versionCode}?',
          ),
          content: Text(
            info.notes.isEmpty
                ? 'A newer APK is available on the backend.'
                : info.notes,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Download'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final path = await service.downloadApk(info);
      await service.installApk(path);
    } catch (err) {
      _showMessage('Update failed: $err');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _resetData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all check-ins?'),
        content: const Text(
          'This clears local check-ins and photos stored on this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AppDataReset.clearCheckInsAndPhotos();
    await _repo.save([]);
    _showMessage('Local check-ins deleted.');
  }

  Future<void> _restoreFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text?.trim() ?? '';
    if (raw.isEmpty) {
      _showMessage('Clipboard does not contain a backup.');
      return;
    }
    List<CheckIn> imported;
    try {
      imported = _backup.decode(raw);
    } catch (err) {
      _showMessage('Backup import failed: $err');
      return;
    }
    if (imported.isEmpty) {
      _showMessage('Backup has no valid check-ins.');
      return;
    }
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup?'),
        content: Text(
          'Merge ${imported.length} check-in(s) from clipboard with local data. Existing newer items are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final merged = _backup.merge(await _repo.load(), imported);
    await _repo.save(merged);
    _showMessage('Restored ${imported.length} check-in(s).');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.bg, colors.bg2],
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontal = constraints.maxWidth > 960
              ? (constraints.maxWidth - 900) / 2
              : 18.0;
          return ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 32),
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 18),
              _SettingsCard(
                title: 'Account',
                subtitle: 'Change local sign-in name and password',
                icon: Icons.person_outline,
                child: Column(
                  children: [
                    TextField(
                      controller: _userCtrl,
                      decoration: const InputDecoration(labelText: 'User name'),
                    ),
                    const SizedBox(height: 12),
                    _PasswordField(
                      controller: _currentPasswordCtrl,
                      label: 'Current password',
                      obscureText: _obscureCurrent,
                      onToggle: () =>
                          setState(() => _obscureCurrent = !_obscureCurrent),
                    ),
                    const SizedBox(height: 12),
                    _PasswordField(
                      controller: _newPasswordCtrl,
                      label: 'New password',
                      obscureText: _obscureNew,
                      onToggle: () =>
                          setState(() => _obscureNew = !_obscureNew),
                    ),
                    const SizedBox(height: 12),
                    _PasswordField(
                      controller: _confirmPasswordCtrl,
                      label: 'Confirm new password',
                      obscureText: _obscureConfirm,
                      onToggle: () =>
                          setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                    const SizedBox(height: 18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: _savingAccount ? null : _saveAccount,
                        icon: _savingAccount
                            ? const _ButtonSpinner()
                            : const Icon(Icons.save_outlined),
                        label: const Text('Save account'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: 'Theme',
                subtitle: 'Switch light or dark mode',
                icon: Icons.brightness_6_outlined,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: AppTheme.toggleTheme,
                    icon: const Icon(Icons.brightness_6_outlined),
                    label: const Text('Toggle theme'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: 'Backend and sync',
                subtitle: 'Used by uploads, photo previews, and two-way sync',
                icon: Icons.cloud_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _backendCtrl,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'Backend URL',
                        hintText: BackendConfig.defaultUrl,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: _saveBackendUrl,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save URL'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _syncing ? null : _syncNow,
                          icon: _syncing
                              ? const _ButtonSpinner()
                              : const Icon(Icons.sync_alt_outlined),
                          label: const Text('Sync now'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: 'App update',
                subtitle:
                    'Current version ${AppVersion.versionName}+${AppVersion.versionCode}',
                icon: Icons.system_update_alt_outlined,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _updating ? null : _checkAndInstallUpdate,
                    icon: _updating
                        ? const _ButtonSpinner()
                        : const Icon(Icons.system_update_alt_outlined),
                    label: const Text('Check for update'),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: 'Data',
                subtitle: 'Restore backups or clear local check-ins',
                icon: Icons.delete_outline,
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _restoreFromClipboard,
                      icon: const Icon(Icons.restore_page_outlined),
                      label: const Text('Restore JSON'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _resetData,
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete all check-ins'),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscureText,
    required this.onToggle,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          onPressed: onToggle,
          tooltip: obscureText ? 'Show password' : 'Hide password',
          icon: Icon(
            obscureText
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(icon, color: colors.accent, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
