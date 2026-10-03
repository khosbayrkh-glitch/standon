import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../zombie_game.dart';

class Zombie extends RectangleComponent
    with HasGameReference<ZombieGame>, CollisionCallbacks {
  final double speed = 80.0;

  Zombie({required Vector2 position})
      : super(
          position: position,
          size: Vector2(30, 30),
          anchor: Anchor.center,
          paint: Paint()..color = Colors.green,
        );

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);
    
    // Тоглогчийн байршил руу зомби ойртох хөдөлгөөн
    final playerPosition = game.player.position;
    final direction = (playerPosition - position).normalized();
    position += direction * speed * dt;
  }
}
  void takeDamage(int amount) {
    hp -= amount;
    if (hp <= 0) {
      hp = 0;
      removeFromParent();
      game.onZombieKilled();
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (!game.gameStarted.value || game.isPaused.value || game.isGameOver) return;

    if (game.children.contains(game.player)) {
      final direction = (game.player.position - position).normalized();
      position += direction * speed * dt;
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas); // Зомбигийн ногоон дөрвөлжинг зурна

    // --- Цусны бар (HP Bar) зурах хэсэг ---
    double barWidth = size.x;
    double barHeight = 6.0;
    double barY = -12.0; // Дөрвөлжингөөс 12px дээш байрлана

    // 1. Арын суурь (Бараан улаан)
    final bgPaint = Paint()..color = const Color(0xFF550000);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, barY, barWidth, barHeight),
        const Radius.circular(3),
      ),
      bgPaint,
    );

    // 2. Үлдсэн цусны хэмжээ (Ногоон -> Шар -> Улаан)
    double hpPercent = (hp / maxHp).clamp(0.0, 1.0);
    if (hpPercent > 0) {
      final hpPaint = Paint()
        ..color = hpPercent > 0.5
            ? Colors.greenAccent
            : (hpPercent > 0.25 ? Colors.orangeAccent : Colors.redAccent);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(0, barY, barWidth * hpPercent, barHeight),
          const Radius.circular(3),
        ),
        hpPaint,
      );
    }

    // 3. Хар хүрээ
    final borderPaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, barY, barWidth, barHeight),
        const Radius.circular(3),
      ),
      borderPaint,
    );
  }

// Сананд заасан үндсэн замыг өөрчлөх
FlameAudio.audioCache.prefix = 'assets/';

// Тэгээд дуудахдаа:
FlameAudio.play('shoot.mp3');