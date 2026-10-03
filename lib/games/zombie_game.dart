import 'dart:math';
import 'package:flame/events.dart';
import 'package:flame/game.dart';
import 'package:flame/components.dart';
import 'package:flutter/material.dart';
import '../components/player.dart';
import '../components/zombie.dart';

class GameBackground extends RectangleComponent with HasGameReference<ZombieGame> {
  GameBackground() : super(priority: -100);

  @override
  Future<void> onLoad() async {
    super.onLoad();
    size = game.size;
  }

  @override
  void update(double dt) {
    super.update(dt);
    size = game.size;
    paint.color = game.gameThemeColor;
  }
}

class ZombieGame extends FlameGame
    with HasCollisionDetection, TapCallbacks, DragCallbacks, HasKeyboardHandlerComponents {
  
  late Player player;
  late GameBackground background;
  
  double zombieSpawnTimer = 0.0;
  double zombieSpawnInterval = 2.0; 
  
  ValueNotifier<int> currentStage = ValueNotifier(1);
  ValueNotifier<int> score = ValueNotifier(0);
  ValueNotifier<int> playerHp = ValueNotifier(100);
  
  ValueNotifier<bool> isPaused = ValueNotifier(false);
  ValueNotifier<bool> gameStarted = ValueNotifier(false);
  bool isGameOver = false;

  double bulletSpeed = 600.0;
  double bulletLifeTime = 1.2;
  double playerSpeed = 200.0;
  bool enableScreenWrap = true;
  
  Color gameThemeColor = const Color(0xFF1E1E1E);

  // --- Зэвсгүүд (Damage, Cooldown, Pierce) ---
  String selectedWeapon = 'Default Pistol';
  final List<Map<String, dynamic>> weapons = [
    {'name': 'Default Pistol', 'damage': 1, 'color': Colors.yellow, 'cooldown': 0.4, 'pierce': 0},
    {'name': 'AK-47', 'damage': 2, 'color': Colors.orange, 'cooldown': 0.12, 'pierce': 1}, 
    {'name': 'M4A1', 'damage': 3, 'color': Colors.cyan, 'cooldown': 0.22, 'pierce': 2}, 
    {'name': 'AWM', 'damage': 7, 'color': Colors.redAccent, 'cooldown': 0.9, 'pierce': 5}, 
  ];
  
  final Random _random = Random();

  @override
  Future<void> onLoad() async {
    super.onLoad();
    background = GameBackground();
    add(background);
    pauseEngine();
  }

  void startGame() {
    gameStarted.value = true;
    isPaused.value = false;
    resumeEngine();
    _resetGameKeepStats();
  }

  void _initGameObjects() {
    isGameOver = false;
    player = Player(
      position: Vector2(size.x / 2, size.y / 2),
    );
    add(player);
    _spawnZombie();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!gameStarted.value || isGameOver || isPaused.value) return;

    zombieSpawnTimer += dt;
    if (zombieSpawnTimer >= zombieSpawnInterval) {
      zombieSpawnTimer = 0.0;
      _spawnZombie();
    }
  }

  void _spawnZombie() {
    if (!gameStarted.value || isGameOver || isPaused.value) return;

    double spawnX = 0;
    double spawnY = 0;
    int side = _random.nextInt(4);

    switch (side) {
      case 0:
        spawnX = _random.nextDouble() * size.x;
        spawnY = -40.0;
        break;
      case 1:
        spawnX = _random.nextDouble() * size.x;
        spawnY = size.y + 40.0;
        break;
      case 2:
        spawnX = -40.0;
        spawnY = _random.nextDouble() * size.y;
        break;
      case 3:
        spawnX = size.x + 40.0;
        spawnY = _random.nextDouble() * size.y;
        break;
    }

    final zombie = Zombie(
      position: Vector2(spawnX, spawnY),
      initialHp: currentStage.value,
    );
    add(zombie);
  }

  // --- Touch болон Drag удирдах хэсэг ---
  @override
  void onTapDown(TapDownEvent event) {
    super.onTapDown(event);
    if (gameStarted.value && !isGameOver && !isPaused.value && children.contains(player)) {
      player.startFiring(event.canvasPosition);
    }
  }

  @override
  void onTapUp(TapUpEvent event) {
    super.onTapUp(event);
    if (children.contains(player)) {
      player.stopFiring();
    }
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    super.onTapCancel(event);
    if (children.contains(player)) {
      player.stopFiring();
    }
  }

  @override
  void onDragStart(DragStartEvent event) {
    super.onDragStart(event);
    if (gameStarted.value && !isGameOver && !isPaused.value && children.contains(player)) {
      player.startFiring(event.canvasPosition);
    }
  }

  @override
  void onDragUpdate(DragUpdateEvent event) {
    super.onDragUpdate(event);
    if (gameStarted.value && !isGameOver && !isPaused.value && children.contains(player)) {
      player.updateTargetDelta(event.canvasDelta);
    }
  }

  @override
  void onDragEnd(DragEndEvent event) {
    super.onDragEnd(event);
    if (children.contains(player)) {
      player.stopFiring();
    }
  }

  @override
  void onDragCancel(DragCancelEvent event) {
    super.onDragCancel(event);
    if (children.contains(player)) {
      player.stopFiring();
    }
  }

  void togglePause() {
    if (!gameStarted.value) return;
    isPaused.value = !isPaused.value;
    if (isPaused.value) {
      pauseEngine();
    } else {
      resumeEngine();
    }
  }

  void onZombieKilled() {
    score.value++;
    if (score.value % 5 == 0) {
      currentStage.value++;
    }
  }

  void triggerGameOver() {
    isGameOver = true;
    children.where((child) => child is Zombie).forEach((child) {
      child.removeFromParent();
    });
  }

  void nextStage() {
    currentStage.value++;
    playerHp.value += 50; 
    _resetGameKeepStats();
  }

  void restartGame() {
    score.value = 0;
    currentStage.value = 1;
    playerHp.value = 100;
    isPaused.value = false;
    gameStarted.value = true;
    resumeEngine();
    _resetGameKeepStats();
  }

  void _resetGameKeepStats() {
    children.where((child) => child is Zombie || child is Player).forEach((child) {
      child.removeFromParent();
    });
    zombieSpawnTimer = 0.0;
    _initGameObjects();
  }
}