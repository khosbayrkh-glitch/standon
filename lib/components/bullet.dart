import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../games/zombie_game.dart';
import 'zombie.dart';

class Bullet extends RectangleComponent
    with HasGameReference<ZombieGame>, CollisionCallbacks {
  
  final Vector2 direction;
  final int damage;
  final double speed;
  final double lifeTime;
  int pierceCount;
  
  double _timer = 0.0;
  final Set<Zombie> _hitZombies = {}; // Нэг зомбийг дахин дахин цохихоос сэргийлнэ

  Bullet({
    required Vector2 position,
    required this.direction,
    required this.damage,
    required Color color,
    required this.speed,
    required this.lifeTime,
    this.pierceCount = 0,
  }) : super(
          position: position,
          size: Vector2.all(8),
          anchor: Anchor.center,
          paint: Paint()..color = color,
        );

  @override
  Future<void> onLoad() async {
    super.onLoad();
    // Мөргөлдөөнийг бүртгэх хэсэг (Чухал)
    add(RectangleHitbox());
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (!game.gameStarted.value || game.isPaused.value || game.isGameOver) return;

    position += direction * speed * dt;

    _timer += dt;
    if (_timer >= lifeTime) {
      removeFromParent();
    }
  }

  @override
  void onCollisionStart(
    Set<Vector2> intersectionPoints,
    PositionComponent other,
  ) {
    super.onCollisionStart(intersectionPoints, other);

    // Зомбитой мөргөлдвөл HP-г нь багасгана
    if (other is Zombie && !_hitZombies.contains(other)) {
      _hitZombies.add(other);
      other.takeDamage(damage);

      // Pierce (нэвт гарах) тоо дууссан бол сумыг устгана
      if (pierceCount > 0) {
        pierceCount--;
      } else {
        removeFromParent();
      }
    }
  }
}