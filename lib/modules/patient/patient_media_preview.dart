import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import 'patient_ui.dart';

String attachmentKindFromName(String name, {String? mimeType}) {
  final m = (mimeType ?? '').toLowerCase();
  final n = name.toLowerCase();
  if (m.startsWith('video') || n.endsWith('.mp4') || n.endsWith('.mov') || n.endsWith('.mkv')) {
    return 'video';
  }
  if (m.startsWith('audio') ||
      n.endsWith('.m4a') ||
      n.endsWith('.mp3') ||
      n.endsWith('.wav') ||
      n.contains('voice')) {
    return 'audio';
  }
  if (n.endsWith('.webm')) return n.contains('voice') ? 'audio' : 'video';
  if (m.startsWith('image') ||
      n.endsWith('.jpg') ||
      n.endsWith('.jpeg') ||
      n.endsWith('.png') ||
      n.endsWith('.webp')) {
    return 'image';
  }
  return 'file';
}

String attachmentKindFromXFile(XFile file) =>
    attachmentKindFromName(file.name, mimeType: file.mimeType);

/// Full-screen pinch-zoom viewer for patient / mission photos.
Future<void> openAttachmentImageViewer(
  BuildContext context, {
  String? url,
  File? file,
  String title = 'Photo',
}) {
  if (url == null && file == null) return Future.value();
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (ctx) {
        final ImageProvider image =
            file != null ? FileImage(file) : NetworkImage(url!);
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(title),
          ),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Center(
              child: Image(
                image: image,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Could not load image',
                    style: TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Preview a local file before the report is submitted.
class LocalAttachmentPreview extends StatefulWidget {
  const LocalAttachmentPreview({
    super.key,
    required this.file,
    this.onRemove,
    this.compact = false,
  });

  final XFile file;
  final VoidCallback? onRemove;
  final bool compact;

  @override
  State<LocalAttachmentPreview> createState() => _LocalAttachmentPreviewState();
}

class _LocalAttachmentPreviewState extends State<LocalAttachmentPreview> {
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  bool _audioPlaying = false;

  @override
  void initState() {
    super.initState();
    _initPlayers();
  }

  Future<void> _initPlayers() async {
    final kind = attachmentKindFromXFile(widget.file);
    if (kind == 'video' && !kIsWeb) {
      final c = VideoPlayerController.file(File(widget.file.path));
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() => _video = c);
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio() async {
    if (kIsWeb) return;
    _audio ??= AudioPlayer();
    if (_audioPlaying) {
      await _audio!.pause();
      if (mounted) setState(() => _audioPlaying = false);
      return;
    }
    await _audio!.play(DeviceFileSource(widget.file.path));
    if (mounted) setState(() => _audioPlaying = true);
    _audio!.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _audioPlaying = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final kind = attachmentKindFromXFile(widget.file);
    final maxH = widget.compact ? 160.0 : 220.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                if (widget.onRemove != null)
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 22),
                    onPressed: widget.onRemove,
                  ),
              ],
            ),
          ),
          _previewBody(kind, maxH),
        ],
      ),
    );
  }

  Widget _previewBody(String kind, double maxH) {
    if (kind == 'image' && !kIsWeb) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
        child: Image.file(
          File(widget.file.path),
          height: maxH,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    }
    if (kind == 'video' && _video != null && _video!.value.isInitialized) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
        child: AspectRatio(
          aspectRatio: _video!.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(_video!),
              IconButton(
                icon: Icon(
                  _video!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  size: 48,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                onPressed: () {
                  setState(() {
                    _video!.value.isPlaying ? _video!.pause() : _video!.play();
                  });
                },
              ),
            ],
          ),
        ),
      );
    }
    if (kind == 'audio') {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        child: FilledButton.icon(
          onPressed: kIsWeb ? null : _toggleAudio,
          style: FilledButton.styleFrom(backgroundColor: PatientUi.accentRed),
          icon: Icon(_audioPlaying ? Icons.pause : Icons.play_arrow),
          label: Text(_audioPlaying ? 'Pause voice note' : 'Play voice note'),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text('Preview not available for this file type.', style: TextStyle(color: Colors.grey.shade600)),
    );
  }
}

/// Preview a remote attachment (signed URL) after submit.
class RemoteAttachmentPreview extends StatefulWidget {
  const RemoteAttachmentPreview({
    super.key,
    required this.name,
    required this.url,
    required this.kind,
    this.accentColor,
  });

  final String name;
  final String url;
  final String kind;
  final Color? accentColor;

  @override
  State<RemoteAttachmentPreview> createState() => _RemoteAttachmentPreviewState();
}

class _RemoteAttachmentPreviewState extends State<RemoteAttachmentPreview> {
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  bool _audioPlaying = false;
  bool _videoLoading = false;
  String? _videoError;

  Color get _accent => widget.accentColor ?? PatientUi.accentRed;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (widget.kind != 'video') return;
    setState(() {
      _videoLoading = true;
      _videoError = null;
    });
    try {
      final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _video = c;
        _videoLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _videoLoading = false;
        _videoError = 'Could not load video';
      });
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  Future<void> _toggleAudio() async {
    _audio ??= AudioPlayer();
    if (_audioPlaying) {
      await _audio!.pause();
      if (mounted) setState(() => _audioPlaying = false);
      return;
    }
    await _audio!.play(UrlSource(widget.url));
    if (mounted) setState(() => _audioPlaying = true);
    _audio!.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _audioPlaying = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.kind == 'image')
            GestureDetector(
              onTap: () => openAttachmentImageViewer(context, url: widget.url),
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.network(
                      widget.url,
                      height: 200,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Could not load image'),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.zoom_out_map, color: Colors.white, size: 16),
                            SizedBox(width: 4),
                            Text('View', style: TextStyle(color: Colors.white, fontSize: 12)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.kind == 'video' && _videoLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
          if (widget.kind == 'video' && _videoError != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Text(_videoError!, style: TextStyle(color: Colors.grey.shade600)),
            ),
          if (widget.kind == 'video' && _video != null && _video!.value.isInitialized)
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: AspectRatio(
                aspectRatio: _video!.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_video!),
                    IconButton(
                      icon: Icon(
                        _video!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                        size: 48,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                      onPressed: () {
                        setState(() {
                          _video!.value.isPlaying ? _video!.pause() : _video!.play();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          if (widget.kind == 'audio')
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: _toggleAudio,
                style: FilledButton.styleFrom(backgroundColor: _accent),
                icon: Icon(_audioPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(_audioPlaying ? 'Pause voice note' : 'Play voice note'),
              ),
            ),
        ],
      ),
    );
  }
}
