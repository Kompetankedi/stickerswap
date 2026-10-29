import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'package:video_player/video_player.dart';
import '../models/telegram_sticker.dart';
import '../services/telegram_service.dart';
import '../theme/app_theme.dart';

/// Plays animated Telegram stickers:
/// - Video stickers (.webm): decoded and played using video_player
/// - Lottie stickers (.tgs): ungzipped and played using lottie
/// - Static stickers (.webp): rendered crisply
class AnimatedStickerPlayer extends StatefulWidget {
  final TelegramSticker sticker;
  final String packName;
  final Uint8List? thumbnailBytes;
  final double size;
  final bool autoPlay;

  const AnimatedStickerPlayer({
    super.key,
    required this.sticker,
    required this.packName,
    this.thumbnailBytes,
    this.size = 200,
    this.autoPlay = true,
  });

  @override
  State<AnimatedStickerPlayer> createState() => _AnimatedStickerPlayerState();
}

class _AnimatedStickerPlayerState extends State<AnimatedStickerPlayer> {
  final _telegramService = TelegramService();

  VideoPlayerController? _videoController;
  Uint8List? _lottieJsonBytes;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadAnimation();
  }

  @override
  void didUpdateWidget(covariant AnimatedStickerPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sticker.fileId != widget.sticker.fileId) {
      _cleanup();
      _loadAnimation();
    }
  }

  void _cleanup() {
    _videoController?.pause();
    _videoController?.dispose();
    _videoController = null;
    _lottieJsonBytes = null;
    _isLoading = true;
    _errorMessage = null;
  }

  @override
  void dispose() {
    _videoController?.pause();
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _loadAnimation() async {
    final sticker = widget.sticker;

    try {
      if (sticker.isVideo) {
        // Video sticker (.webm)
        final filePath = await _telegramService.downloadSticker(
          sticker,
          widget.packName,
        );

        final file = File(filePath);
        if (await file.exists()) {
          final controller = VideoPlayerController.file(file);
          await controller.initialize();
          controller.setLooping(true);
          controller.setVolume(0.0);
          if (widget.autoPlay) {
            controller.play();
          }

          if (mounted) {
            setState(() {
              _videoController = controller;
              _isLoading = false;
            });
          }
        } else {
          throw Exception('Video dosyası bulunamadı');
        }
      } else if (sticker.isAnimated) {
        // Vector animated sticker (.tgs - gzipped Lottie)
        final filePath = await _telegramService.downloadSticker(
          sticker,
          widget.packName,
        );

        final file = File(filePath);
        if (await file.exists()) {
          final compressedBytes = await file.readAsBytes();
          // Ungzip .tgs file to obtain raw Lottie JSON bytes
          final unzippedBytes = Uint8List.fromList(gzip.decode(compressedBytes));

          if (mounted) {
            setState(() {
              _lottieJsonBytes = unzippedBytes;
              _isLoading = false;
            });
          }
        } else {
          throw Exception('Animasyon dosyası bulunamadı');
        }
      } else {
        // Static sticker
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sticker = widget.sticker;

    Widget content;

    if (sticker.isVideo && _videoController != null && _videoController!.value.isInitialized) {
      // Loop Video
      content = ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio > 0
              ? _videoController!.value.aspectRatio
              : 1.0,
          child: VideoPlayer(_videoController!),
        ),
      );
    } else if (sticker.isAnimated && _lottieJsonBytes != null) {
      // Vector Lottie Animation
      content = Lottie.memory(
        _lottieJsonBytes!,
        fit: BoxFit.contain,
        repeat: true,
        animate: true,
        errorBuilder: (_, error, stack) => _buildFallbackThumbnail(),
      );
    } else {
      // Static or loading thumbnail
      content = _buildFallbackThumbnail();
    }

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          content,
          if (_isLoading)
            Positioned(
              bottom: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(140),
                  shape: BoxShape.circle,
                ),
                child: const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppTheme.accentPrimary,
                  ),
                ),
              ),
            ),
          if (_errorMessage != null && widget.thumbnailBytes == null)
            Positioned(
              bottom: 4,
              child: Text(
                sticker.emoji,
                style: const TextStyle(fontSize: 32),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFallbackThumbnail() {
    if (widget.thumbnailBytes != null) {
      return Image.memory(
        widget.thumbnailBytes!,
        fit: BoxFit.contain,
        errorBuilder: (_, error, stack) => _placeholderEmoji(),
      );
    }
    return _placeholderEmoji();
  }

  Widget _placeholderEmoji() {
    return Center(
      child: Text(
        widget.sticker.emoji,
        style: TextStyle(fontSize: widget.size * 0.4),
      ),
    );
  }
}
