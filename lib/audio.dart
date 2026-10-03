import 'package:audioplayers/audioplayers.dart';

class AudioService {
  static bool isSoundOn = true;
  static bool _isUnlocked = false;

  /// Вэб/утасны браузерын аудио хоригийг анхны даралтаар нээх
  static Future<void> unlockAudio() async {
    if (_isUnlocked) return;
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('audio/shoot.mp3'), volume: 0.0);
      _isUnlocked = true;
    } catch (_) {}
  }

  /// Эффект дуу тоглуулах
  static Future<void> playSfx(String fileName) async {
    if (!isSoundOn) return;
    try {
      final player = AudioPlayer();
      await player.play(AssetSource('audio/$fileName'));
    } catch (e) {
      print("Audio Error ($fileName): $e");
    }
  }
}