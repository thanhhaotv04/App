import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/checkin.dart';
import '../repositories/backend_config.dart';
import '../repositories/app_update_service.dart';
import '../repositories/checkin_repository.dart';
import '../repositories/local_image_storage.dart';
import '../repositories/sync_service.dart';
import '../app_version.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _repo = CheckInRepository();
  final _backendCtrl = TextEditingController(text: BackendConfig.defaultUrl);
  String _status = 'Local settings are ready.';
  String _exportText = '';
  String _localImageFolder = '';
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _loadBackendUrl();
    _loadLocalImageFolder();
  }

  @override
  void dispose() {
    _backendCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBackendUrl() async {
    final url = await BackendConfig.loadUrl();
    if (!mounted) return;
    setState(() => _backendCtrl.text = url);
  }

  Future<void> _loadLocalImageFolder() async {
    final folder = await LocalImageStorage.folderPath();
    if (!mounted) return;
    setState(() => _localImageFolder = folder);
  }

  Future<void> _saveBackendUrl() async {
    await BackendConfig.saveUrl(_backendCtrl.text);
    if (!mounted) return;
    setState(() => _status = 'Backend URL saved.');
  }

  Future<void> _loadSample() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    const hcm = 'TP.H\u1ed3 Ch\u00ed Minh';
    const binhDinh = 'B\u00ecnh \u0110\u1ecbnh';
    await _repo.save([
      CheckIn(
        id: 'sample-hcm',
        city: hcm,
        place: hcm,
        notes: 'Sample check-in',
        source: 'manual',
        synced: false,
        createdAt: now,
        lat: 10.8231,
        lng: 106.6297,
        photo: 'user/Picture/thanhhao/$hcm/1780386908045-Screenshot 2025-12-01 182729.png',
      ),
      CheckIn(
        id: 'sample-binh-dinh',
        city: binhDinh,
        place: binhDinh,
        notes: 'Sample check-in',
        source: 'manual',
        synced: false,
        createdAt: now - 86400000,
        lat: 13.782,
        lng: 109.219,
        photo: 'user/Picture/thanhhao/$binhDinh/1780299398898-Screenshot 2025-12-01 134518.png',
      ),
    ]);
    setState(() => _status = 'Sample data loaded.');
  }
  Future<void> _exportJson() async {
    final items = await _repo.load();
    setState(() {
      _exportText = const JsonEncoder.withIndent('  ').convert(items.map((e) => e.toJson()).toList());
      _status = 'Export JSON generated below.';
    });
  }

  Future<void> _importJson() async {
    const jsonGroup = XTypeGroup(label: 'JSON', extensions: ['json'], mimeTypes: ['application/json']);
    final file = await openFile(acceptedTypeGroups: const [jsonGroup]);
    if (file == null) return;
    try {
      final raw = await file.readAsString();
      final decoded = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      final items = decoded.map(CheckIn.fromJson).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      await _repo.save(items);
      if (!mounted) return;
      setState(() {
        _exportText = '';
        _status = 'Imported ${items.length} check-in(s) from ${file.name}.';
      });
    } catch (err) {
      if (!mounted) return;
      setState(() => _status = 'Import failed: $err');
    }
  }

  Future<void> _syncNow() async {
    try {
      await BackendConfig.saveUrl(_backendCtrl.text);
      final sync = SyncService(baseUrl: await BackendConfig.loadUrl());
      final merged = await sync.syncTwoWay(await _repo.load());
      await _repo.save(merged);
      if (!mounted) return;
      setState(() => _status = 'Synced ${merged.length} check-in(s).');
    } catch (err) {
      if (!mounted) return;
      setState(() => _status = 'Sync failed: $err');
    }
  }

  Future<void> _checkAndInstallUpdate() async {
    setState(() {
      _updating = true;
      _status = 'Checking for updates...';
    });
    try {
      await BackendConfig.saveUrl(_backendCtrl.text);
      final service = AppUpdateService(baseUrl: await BackendConfig.loadUrl());
      final info = await service.checkLatest();
      if (!info.available) {
        if (!mounted) return;
        setState(() => _status = 'Already up to date: ${AppVersion.versionName}+${AppVersion.versionCode}.');
        return;
      }
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Install update ${info.versionName}+${info.versionCode}?'),
          content: Text(info.notes.isEmpty ? 'A newer APK is available on the backend.' : info.notes),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Download')),
          ],
        ),
      );
      if (confirmed != true) {
        setState(() => _status = 'Update cancelled.');
        return;
      }
      setState(() => _status = 'Downloading APK...');
      final path = await service.downloadApk(info);
      setState(() => _status = 'Opening Android installer...');
      await service.installApk(path);
    } catch (err) {
      if (!mounted) return;
      setState(() => _status = 'Update failed: $err');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _resetData() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all data?'),
        content: const Text('This clears local check-ins stored on this device.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.save([]);
    setState(() {
      _exportText = '';
      _status = 'Local data deleted.';
    });
  }

  Future<String> _accountSummary() async {
    final prefs = await SharedPreferences.getInstance();
    final user = prefs.getString('vmc-auth-user');
    return user == null || user.isEmpty ? 'No local account stored.' : 'Signed in as $user. Account data is stored locally on this device.';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [colors.bg, colors.bg2]),
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Settings', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          _SettingsCard(
            title: 'Account',
            subtitle: 'Local sign-in state',
            icon: Icons.person_outline,
            child: FutureBuilder<String>(
              future: _accountSummary(),
              builder: (context, snapshot) => Text(snapshot.data ?? 'Loading...', style: Theme.of(context).textTheme.bodyMedium),
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: 'Theme and data',
            subtitle: 'Mirror the controls from the original web app',
            icon: Icons.tune_outlined,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(onPressed: AppTheme.toggleTheme, icon: const Icon(Icons.brightness_6_outlined), label: const Text('Toggle theme')),
                OutlinedButton.icon(onPressed: _exportJson, icon: const Icon(Icons.download_outlined), label: const Text('Export JSON')),
                OutlinedButton.icon(onPressed: _importJson, icon: const Icon(Icons.upload_file_outlined), label: const Text('Import JSON')),
                OutlinedButton.icon(onPressed: _loadSample, icon: const Icon(Icons.dataset_outlined), label: const Text('Load sample')),
                OutlinedButton.icon(onPressed: _resetData, icon: const Icon(Icons.delete_outline), label: const Text('Delete all data')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: 'Backend',
            subtitle: 'Used by uploads, photo previews, and two-way sync',
            icon: Icons.cloud_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _backendCtrl,
                  decoration: const InputDecoration(labelText: 'Backend URL', hintText: BackendConfig.defaultUrl),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(onPressed: _saveBackendUrl, icon: const Icon(Icons.save_outlined), label: const Text('Save URL')),
                    OutlinedButton.icon(onPressed: _syncNow, icon: const Icon(Icons.sync_alt_outlined), label: const Text('Sync now')),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: 'LAN app update',
            subtitle: 'Current version ${AppVersion.versionName}+${AppVersion.versionCode}',
            icon: Icons.system_update_alt_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'The phone downloads a newer APK from the backend over the same Wi-Fi, then Android asks you to confirm installation.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _updating ? null : _checkAndInstallUpdate,
                  icon: _updating
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.system_update_alt_outlined),
                  label: const Text('Check for update'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: 'Private image storage',
            subtitle: 'Images selected in the app are copied here first',
            icon: Icons.folder_copy_outlined,
            child: SelectableText(
              _localImageFolder.isEmpty ? 'Loading...' : _localImageFolder,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          _SettingsCard(
            title: 'Status',
            subtitle: _status,
            icon: Icons.info_outline,
            child: _exportText.isEmpty
                ? Text('JSON import/export, backend URL persistence, and two-way sync are available here.', style: Theme.of(context).textTheme.bodySmall)
                : SelectableText(_exportText, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.title, required this.subtitle, required this.icon, required this.child});

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: colors.panel, borderRadius: BorderRadius.circular(16), border: Border.all(color: colors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

