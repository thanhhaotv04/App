import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/checkin.dart';
import '../repositories/local_image_storage.dart';
import '../repositories/credential_store.dart';
import '../repositories/backend_config.dart';
import '../repositories/private_photo.dart';
import '../theme/app_colors.dart';

class CheckInPhoto extends StatefulWidget {
  const CheckInPhoto({
    super.key,
    required this.item,
    required this.remoteUrl,
    this.fit = BoxFit.cover,
    this.emptyIconSize = 20,
    this.errorText,
  });

  final CheckIn item;
  final String Function(String path) remoteUrl;
  final BoxFit fit;
  final double emptyIconSize;
  final String? errorText;

  @override
  State<CheckInPhoto> createState() => _CheckInPhotoState();
}

class _CheckInPhotoState extends State<CheckInPhoto> {
  Future<Uint8List?>? _localFuture;

  @override
  void initState() {
    super.initState();
    _prepareLocal();
  }

  @override
  void didUpdateWidget(covariant CheckInPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.primaryPhoto?.localPhoto !=
        widget.item.primaryPhoto?.localPhoto) {
      _prepareLocal();
    }
  }

  void _prepareLocal() {
    final ref = widget.item.primaryPhoto?.localPhoto ?? '';
    _localFuture = ref.isEmpty ? null : LocalImageStorage.readImage(ref);
  }

  @override
  Widget build(BuildContext context) {
    final asset = widget.item.primaryPhoto;
    if (asset?.localPhoto.isNotEmpty == true) {
      return FutureBuilder<Uint8List?>(
        future: _localFuture,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          if (bytes != null && bytes.isNotEmpty) {
            return Image.memory(bytes, fit: widget.fit);
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Icon(
              Icons.image_outlined,
              size: widget.emptyIconSize,
              color: AppColors.of(context).muted,
            );
          }
          return _RemoteOrFallback(
            item: widget.item,
            remoteUrl: widget.remoteUrl,
            fit: widget.fit,
            emptyIconSize: widget.emptyIconSize,
            errorText: widget.errorText,
          );
        },
      );
    }
    return _RemoteOrFallback(
      item: widget.item,
      remoteUrl: widget.remoteUrl,
      fit: widget.fit,
      emptyIconSize: widget.emptyIconSize,
      errorText: widget.errorText,
    );
  }
}

class _RemoteOrFallback extends StatelessWidget {
  const _RemoteOrFallback({
    required this.item,
    required this.remoteUrl,
    required this.fit,
    required this.emptyIconSize,
    required this.errorText,
  });

  final CheckIn item;
  final String Function(String path) remoteUrl;
  final BoxFit fit;
  final double emptyIconSize;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final asset = item.primaryPhoto;
    if (asset == null || asset.photo.isEmpty) {
      return Icon(
        Icons.image_outlined,
        size: emptyIconSize,
        color: colors.muted,
      );
    }
    return _AuthenticatedNetworkImage(
      url: remoteUrl(asset.photo),
      fit: fit,
      semanticLabel: asset.name.isEmpty ? 'Travel photo' : asset.name,
      emptyIconSize: emptyIconSize,
      errorText: errorText,
    );
  }
}

class _AuthenticatedNetworkImage extends StatefulWidget {
  const _AuthenticatedNetworkImage({
    required this.url,
    required this.fit,
    required this.semanticLabel,
    required this.emptyIconSize,
    required this.errorText,
  });

  final String url;
  final BoxFit fit;
  final String semanticLabel;
  final double emptyIconSize;
  final String? errorText;

  @override
  State<_AuthenticatedNetworkImage> createState() =>
      _AuthenticatedNetworkImageState();
}

class _AuthenticatedNetworkImageState
    extends State<_AuthenticatedNetworkImage> {
  late Future<Uint8List?> _photo = _load();

  Future<Uint8List?> _load() async => PrivatePhoto.read(
    baseUrl: await BackendConfig.loadUrl(),
    photo: widget.url,
    headers: await const CredentialStore().authHeaders(),
  );

  @override
  void didUpdateWidget(covariant _AuthenticatedNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _photo = _load();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FutureBuilder<Uint8List?>(
      future: _photo,
      builder: (context, snapshot) {
        if (snapshot.hasError ||
            (snapshot.connectionState == ConnectionState.done &&
                (snapshot.data == null || snapshot.data!.isEmpty))) {
          return Icon(
            Icons.broken_image_outlined,
            size: widget.emptyIconSize,
            color: colors.muted,
          );
        }
        if (!snapshot.hasData) {
          return Icon(
            Icons.image_outlined,
            size: widget.emptyIconSize,
            color: colors.muted,
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: widget.fit,
          semanticLabel: widget.semanticLabel,
          errorBuilder: (context, error, stackTrace) {
            if (widget.errorText != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    widget.errorText!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colors.muted),
                  ),
                ),
              );
            }
            return Icon(
              Icons.broken_image_outlined,
              size: widget.emptyIconSize,
              color: colors.muted,
            );
          },
        );
      },
    );
  }
}
