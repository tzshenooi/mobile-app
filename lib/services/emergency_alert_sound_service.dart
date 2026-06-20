import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays a loud looping emergency siren on the alarm audio stream.
class EmergencyAlertSoundService {
  EmergencyAlertSoundService._();

  static final EmergencyAlertSoundService instance =
      EmergencyAlertSoundService._();

  final AudioPlayer _player = AudioPlayer();
  Timer? _stopTimer;
  bool _playing = false;

  static const _defaultDuration = Duration(seconds: 20);

  Future<void> play({Duration duration = _defaultDuration}) async {
    try {
      await stop();
      await _player.setAudioContext(
        AudioContext(
          android: AudioContextAndroid(
            usageType: AndroidUsageType.alarm,
            contentType: AndroidContentType.sonification,
            audioFocus: AndroidAudioFocus.gain,
            isSpeakerphoneOn: true,
          ),
          iOS: AudioContextIOS(
            category: AVAudioSessionCategory.playback,
            options: {AVAudioSessionOptions.duckOthers},
          ),
        ),
      );
      await _player.setVolume(1.0);
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/dispatch_alert.mp3'));
      _playing = true;
      _stopTimer = Timer(duration, () => unawaited(stop()));
    } catch (e, st) {
      debugPrint('EmergencyAlertSoundService.play failed: $e\n$st');
    }
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    if (!_playing) return;
    try {
      await _player.stop();
    } catch (e) {
      debugPrint('EmergencyAlertSoundService.stop failed: $e');
    } finally {
      _playing = false;
    }
  }
}
