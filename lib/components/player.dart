import 'package:flame/collisions.dart';
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../games/zombie_game.dart';
import 'bullet.dart';
import 'zombie.dart';

class Player extends RectangleComponent
    with HasGameReference<ZombieGame>, KeyboardHandler, CollisionCallbacks {
  
  Vector2 velocity = Vector2.zero();
  double shootCooldown = 0.0;
  
  Vector2? targetPosition;
  bool isFiring = false;

  Player({super.position})
      : super(
          size: Vector2.all(50),
          anchor: Anchor.center,
          paint: Paint()..color = Colors.blue,
        );

  @override
  Future<void> onLoad() async {
    super.onLoad();
    add(RectangleHitbox());
  }

  void startFiring(Vector2 pos) {
    targetPosition = pos.clone();
    isFiring = true;
    if (shootCooldown <= 0) {
      _fireBullet();
    }
  }

  void updateTargetDelta(Vector2 delta) {
    if (targetPosition != null) {
      targetPosition!.add(delta);
    }
  }

  void stopFiring() {
    isFiring = false;
    targetPosition = null;
  }

  void _fireBullet() {
    if (targetPosition == null) return;

    final weapon = game.weapons.firstWhere(
      (w) => w['name'] == game.selectedWeapon,
      orElse: () => game.weapons.first,
    );
    
    int damage = weapon['damage'];
    Color color = weapon['color'];
    shootCooldown = weapon['cooldown'];
    int pierce = weapon['pierce'] ?? 0;

    final direction = (targetPosition! - position).normalized();
    final spawnPosition = position + direction * 45; 

    game.add(Bullet(
      position: spawnPosition, 
      direction: direction, 
      damage: damage, 
      color: color,
      speed: game.bulletSpeed,
      lifeTime: game.bulletLifeTime,
      pierceCount: pierce,
    ));
  }

  void takeDamage(int amount) {
    game.playerHp.value -= amount;
    if (game.playerHp.value <= 0) {
      game.playerHp.value = 0;
      removeFromParent();
      game.triggerGameOver();
    }
  }

  @override
  void onCollisionStart(Set<Vector2> intersectionPoints, PositionComponent other) {
    super.onCollisionStart(intersectionPoints, other);
    if (other is Zombie) {
      takeDamage(10);
    }
  }

  @override
  void update(double dt) {
    super.update(dt);

    if (shootCooldown > 0) {
      shootCooldown -= dt;
    }

    if (isFiring && targetPosition != null && game.gameStarted.value && !game.isPaused.value && !game.isGameOver) {
      if (shootCooldown <= 0) {
        _fireBullet();
      }
    }

    position += velocity * game.playerSpeed * dt;

    if (game.enableScreenWrap) {
      if (position.x < 0) {
        position.x = game.size.x;
      } else if (position.x > game.size.x) {
        position.x = 0;
      }

      if (position.y < 0) {
        position.y = game.size.y;
      } else if (position.y > game.size.y) {
        position.y = 0;
      }
    } else {
      position.x = position.x.clamp(25, game.size.x - 25);
      position.y = position.y.clamp(25, game.size.y - 25);
    }
  }

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    velocity = Vector2.zero();

    if (keysPressed.contains(LogicalKeyboardKey.keyW) ||
        keysPressed.contains(LogicalKeyboardKey.arrowUp)) {
      velocity.y -= 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.keyS) ||
        keysPressed.contains(LogicalKeyboardKey.arrowDown)) {
      velocity.y += 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.keyA) ||
        keysPressed.contains(LogicalKeyboardKey.arrowLeft)) {
      velocity.x -= 1;
    }
    if (keysPressed.contains(LogicalKeyboardKey.keyD) ||
        keysPressed.contains(LogicalKeyboardKey.arrowRight)) {
      velocity.x += 1;
    }

    return true;
  }
}