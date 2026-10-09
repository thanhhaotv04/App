import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_version.dart';
import '../repositories/app_update_service.dart';
import '../repositories/album_repository.dart';
import '../repositories/auth_service.dart';
import '../repositories/backend_config.dart';
import '../repositories/backup_service.dart';
import '../repositories/checkin_repository.dart';
import '../repositories/credential_store.dart';
import '../repositories/local_image_storage.dart';
import '../repositories/privacy_settings.dart';
import '../repositories/sync_queue_repository.dart';
import '../repositories/sync_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onSignOut});

  final VoidCallback? onSignOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _userKey = 'vmc-auth-user';

  final _repo = CheckInRepository();
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
  bool _savingPrivacy = false;
  bool _localOnly = false;
  bool _hideLocation = false;
  int _autoBackupDays = 7;
  int _lastBackupAt = 0;
  int _localBytes = 0;
  int _serverBytes = 0;
  int _serverLimit = 0;

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
    final privacy = await PrivacySettings.load();
    var localBytes = 0;
    try {
      localBytes = await LocalImageStorage.usageBytes();
    } catch (_) {}
    final lastBackup = await const AutoBackupService().lastBackupAt();
    if (!mounted) return;
    setState(() {
      _localOnly = privacy.localOnly;
      _hideLocation = privacy.hideLocation;
      _autoBackupDays = prefs.getInt(AutoBackupService.intervalKey) ?? 7;
      _lastBackupAt = lastBackup;
      _localBytes = localBytes;
    });
    try {
      final usage = await SyncService(baseUrl: backendUrl).storageUsage();
      if (mounted) {
        setState(() {
          _serverBytes = usage.usedBytes;
          _serverLimit = usage.limitBytes;
        });
      }
    } catch (_) {}
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

    if (name.isEmpty) {
      _showMessage('User name cannot be empty.');
      return;
    }
    if (!await const CredentialStore().matchesOffline(
      prefs.getString(_userKey) ?? name,
      currentPassword,
    )) {
      _showMessage('Current password is incorrect.');
      return;
    }
    if (newPassword.isNotEmpty &&
        (newPassword.length < 8 || newPassword.length > 128)) {
      _showMessage('Use a new password with 8-128 characters.');
      return;
    }
    if (newPassword.isNotEmpty && newPassword != confirmation) {
      _showMessage('New passwords do not match.');
      return;
    }

    setState(() => _savingAccount = true);
    try {
      final oldName = prefs.getString(_userKey)?.trim() ?? '';
      final credentials = const CredentialStore();
      final session = await AuthService(baseUrl: await BackendConfig.loadUrl())
          .updateAccountSession(
            name: prefs.getString(_userKey) ?? name,
            currentPassword: currentPassword,
            newName: name,
            newPassword: newPassword.isEmpty ? null : newPassword,
            token: await credentials.readToken(),
          );
      final savedName = session.name;
      await prefs.setString(_userKey, savedName);
      if (oldName.isNotEmpty && oldName != savedName) {
        await LocalImageStorage.moveUserData(oldName, savedName);
        await CheckInRepository.moveUserData(oldName, savedName);
        await AlbumRepository.moveUserData(oldName, savedName);
      }
      await credentials.saveSession(
        userName: savedName,
        password: newPassword.isEmpty ? currentPassword : newPassword,
        token: session.token,
      );
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
    try {
      await BackendConfig.saveUrl(_backendCtrl.text);
      _showMessage(
        'Backend URL saved. If the server changed, sign out and sign in to reconnect.',
      );
    } catch (error) {
      _showMessage(error.toString().replaceFirst('FormatException: ', ''));
    }
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await BackendConfig.saveUrl(_backendCtrl.text);
      final sync = SyncService(baseUrl: await BackendConfig.loadUrl());
      final merged = await sync.syncTwoWay(await _repo.load());
      await _repo.save(merged);
      final albums = await AlbumRepository().syncTwoWay(
        baseUrl: await BackendConfig.loadUrl(),
      );
      await const AutoBackupService().runIfDue(merged, albums);
      _showMessage(
        'Synced ${merged.length} check-in(s) and ${albums.where((album) => !album.isDeleted).length} album(s).',
      );
    } catch (err) {
      _showMessage('Sync failed: $err');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<String?> _askBackupPassword(String title) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Backup password',
            helperText: 'At least 8 characters. Keep it safe.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _exportBackup() async {
    final password = await _askBackupPassword('Export encrypted backup');
    if (password == null) return;
    if (password.length < 8) {
      _showMessage('Backup password must have at least 8 characters.');
      return;
    }
    try {
      final bytes = await const BackupService().encode(
        checkIns: await _repo.load(),
        albums: await AlbumRepository().load(),
        password: password,
      );
      await SharePlus.instance.share(
        ShareParams(
          text: 'Encrypted VietNam Map Checkin backup',
          files: [
            XFile.fromData(
              bytes,
              name: 'vietnam-map-checkin.vmcbackup',
              mimeType: 'application/octet-stream',
            ),
          ],
        ),
      );
    } catch (error) {
      _showMessage('Backup export failed: $error');
    }
  }

  Future<void> _importBackup() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'VMC backup', extensions: ['vmcbackup', 'json']),
      ],
    );
    if (file == null || !mounted) return;
    final fileSize = await file.length();
    if (fileSize > 100 * 1024 * 1024) {
      _showMessage('Backup is too large (maximum 100 MB).');
      return;
    }
    final password = await _askBackupPassword('Import encrypted backup');
    if (password == null) return;
    if (password.length < 8) {
      _showMessage('Backup password must have at least 8 characters.');
      return;
    }
    try {
      final service = const BackupService();
      final payload = await service.decode(
        Uint8List.fromList(await file.readAsBytes()),
        password,
      );
      await _repo.save(
        service.mergeCheckIns(await _repo.load(), payload.checkIns),
      );
      final albums = AlbumRepository();
      await albums.save(
        service.mergeAlbums(await albums.load(), payload.albums),
      );
      _showMessage('Backup imported successfully.');
    } catch (error) {
      _showMessage('Backup import failed: $error');
    }
  }

  Future<void> _setPrivacy({bool? localOnly, bool? hideLocation}) async {
    final previous = PrivacySettings(
      localOnly: _localOnly,
      hideLocation: _hideLocation,
    );
    final next = previous.copyWith(
      localOnly: localOnly,
      hideLocation: hideLocation,
    );
    setState(() {
      _localOnly = next.localOnly;
      _hideLocation = next.hideLocation;
      _savingPrivacy = true;
    });
    try {
      await next.save();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _localOnly = previous.localOnly;
        _hideLocation = previous.hideLocation;
      });
      _showMessage('Could not save privacy settings. Please try again.');
    } finally {
      if (mounted) setState(() => _savingPrivacy = false);
    }
  }

  Future<void> _setBackupInterval(int? days) async {
    if (days == null) return;
    await (await SharedPreferences.getInstance()).setInt(
      AutoBackupService.intervalKey,
      days,
    );
    setState(() => _autoBackupDays = days);
    if (days > 0) {
      await const AutoBackupService().runIfDue(
        await _repo.load(),
        await AlbumRepository().load(),
        force: true,
      );
      _lastBackupAt = await const AutoBackupService().lastBackupAt();
      if (mounted) setState(() {});
    }
  }

  Future<void> _deleteAccount() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account and all data?'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: 'Type ${_userCtrl.text} to confirm',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    final confirmation = controller.text.trim();
    controller.dispose();
    if (confirmed != true || confirmation != _userCtrl.text.trim()) {
      if (confirmed == true) _showMessage('Confirmation did not match.');
      return;
    }
    try {
      await SyncService(
        baseUrl: await BackendConfig.loadUrl(),
      ).deleteAccount(confirmation);
      await LocalImageStorage.deleteAllImages();
      await CheckInRepository.clearCurrentData();
      await AlbumRepository.clearCurrentData();
      await const SyncQueueRepository().clear();
      await const CredentialStore().clearAll();
      widget.onSignOut?.call();
    } catch (error) {
      _showMessage('Account deletion failed: $error');
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
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
          'v${AppVersion.versionName} (build ${AppVersion.versionCode}).',
        );
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(
            'Install update v${info.versionName} (build ${info.versionCode})?',
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
                'Account',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 18),
              _SettingsCard(
                title: 'Account',
                subtitle: 'Manage your user name and password',
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
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: const EdgeInsets.only(bottom: 8),
                      title: const Text('Change password'),
                      subtitle: const Text(
                        'Optional when changing your user name',
                      ),
                      children: [
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
                          onToggle: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                        ),
                      ],
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
                    if (widget.onSignOut != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: widget.onSignOut,
                          icon: const Icon(Icons.logout_outlined),
                          label: const Text('Sign out'),
                        ),
                      ),
                    ],
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
                      decoration: InputDecoration(
                        labelText: 'Backend URL',
                        hintText: BackendConfig.defaultUrl,
                        helperText:
                            'HTTPS keeps your data encrypted. HTTP is for trusted LAN only.',
                        helperMaxLines: 3,
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
                        OutlinedButton.icon(
                          onPressed: () => context.push('/sync'),
                          icon: const Icon(Icons.sync_problem_outlined),
                          label: const Text('Sync center'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: 'Encrypted backup',
                subtitle: _lastBackupAt == 0
                    ? 'Export or restore check-ins, albums, and photos'
                    : 'Last automatic backup: ${DateTime.fromMillisecondsSinceEpoch(_lastBackupAt)}',
                icon: Icons.backup_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: _autoBackupDays,
                      decoration: const InputDecoration(
                        labelText: 'Automatic backup',
                      ),
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Off')),
                        DropdownMenuItem(value: 1, child: Text('Daily')),
                        DropdownMenuItem(value: 7, child: Text('Weekly')),
                      ],
                      onChanged: _setBackupInterval,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        FilledButton.icon(
                          onPressed: _exportBackup,
                          icon: const Icon(Icons.ios_share_outlined),
                          label: const Text('Export'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _importBackup,
                          icon: const Icon(Icons.restore_outlined),
                          label: const Text('Import'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: 'Privacy',
                subtitle: 'Defaults applied to newly created memories',
                icon: Icons.privacy_tip_outlined,
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _localOnly,
                      onChanged: _savingPrivacy
                          ? null
                          : (value) => _setPrivacy(localOnly: value),
                      title: const Text('Local only'),
                      subtitle: const Text(
                        'Do not upload new check-ins to the server',
                      ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _hideLocation,
                      onChanged: _savingPrivacy
                          ? null
                          : (value) => _setPrivacy(hideLocation: value),
                      title: const Text('Hide exact coordinates'),
                      subtitle: const Text(
                        'Hide coordinates in new uploads and all shared albums',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: 'Storage quota',
                subtitle: 'Images are automatically validated and compressed',
                icon: Icons.storage_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('On this device: ${_formatBytes(_localBytes)}'),
                    const SizedBox(height: 6),
                    Text(
                      _serverLimit > 0
                          ? 'On server: ${_formatBytes(_serverBytes)} / ${_formatBytes(_serverLimit)}'
                          : 'Server quota unavailable while offline',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SettingsCard(
                title: 'App update',
                subtitle:
                    'Current version v${AppVersion.versionName} '
                    '(build ${AppVersion.versionCode})',
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
                title: 'Danger zone',
                subtitle:
                    'Delete the server account and this device’s local copy',
                icon: Icons.delete_forever_outlined,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _deleteAccount,
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Delete account'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
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
      autocorrect: false,
      enableSuggestions: false,
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
    return Material(
      color: colors.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: colors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
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
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
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
