import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' as v64;
import 'package:flame_audio/flame_audio.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GameScreen(),
    );
  }
}

// ==========================================
// GAME SCREEN & OVERLAY MANAGER
// ==========================================
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with SingleTickerProviderStateMixin {
  late GameEngine3D game;
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    game = GameEngine3D(onStateChanged: () => setState(() {}));
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat();

    _controller.addListener(_gameLoop);
  }

  DateTime _lastTime = DateTime.now();

  void _gameLoop() {
    final now = DateTime.now();
    final dt = now.difference(_lastTime).inMicroseconds / 1000000.0;
    _lastTime = now;

    if (!game.isPaused) {
      game.update(dt.clamp(0.001, 0.05));
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RawKeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKey: (event) => game.handleKeyEvent(event),
        child: GestureDetector(
          onTapDown: (details) => game.onTapDown(details.localPosition, context.size!),
          onPanUpdate: (details) => game.onTapDown(details.localPosition, context.size!),
          child: Stack(
            children: [
              // 3D CANVAS RENDERER
              CustomPaint(
                size: Size.infinite,
                painter: Game3DPainter(game: game),
              ),

              // FLUTTER OVERLAYS
              if (game.activeOverlays.contains('HUD')) HUDOverlay(game: game),
              if (game.activeOverlays.contains('Shop')) ShopOverlay(game: game),
              if (game.activeOverlays.contains('Pause')) PauseOverlay(game: game),
              if (game.activeOverlays.contains('Settings')) SettingsOverlay(game: game),
              if (game.activeOverlays.contains('StageClear')) StageClearOverlay(game: game),
              if (game.activeOverlays.contains('GameOver')) GameOverOverlay(game: game),
            ],
          ),
        ),
      ),
    );
  }
}

// ==========================================
// DRAGGABLE HUD HELPER WIDGET
// ==========================================
class DraggableHudItem extends StatefulWidget {
  final Offset initialOffset;
  final Widget child;

  const DraggableHudItem({
    super.key,
    required this.initialOffset,
    required this.child,
  });

  @override
  State<DraggableHudItem> createState() => _DraggableHudItemState();
}

class _DraggableHudItemState extends State<DraggableHudItem> {
  late Offset offset;

  @override
  void initState() {
    super.initState();
    offset = widget.initialOffset;
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            offset += details.delta;
          });
        },
        child: widget.child,
      ),
    );
  }
}

// ==========================================
// 3D GAME ENGINE & CORE LOGIC
// ==========================================
class GameEngine3D {
  final VoidCallback onStateChanged;

  v64.Vector3 playerPos = v64.Vector3(0, 0, 0);
  v64.Vector3 playerVelocity = v64.Vector3.zero();

  int coins = 0;
  int stage = 1;
  int playerDamageLevel = 1;
  int zombiesToSpawn = 5;
  int zombiesKilled = 0;
  bool isPaused = false;
  Set<String> activeOverlays = {'HUD'};

  double playerSpeed = 12.0;
  double zombieSpeed = 3.5;
  double playerHp = 100.0;

  // AUDIO POOLS
  AudioPool? pistolPool;
  AudioPool? riflePool;
  AudioPool? shotgunPool;
  AudioPool? sniperPool;
  AudioPool? reloadPool;

  // NOTIFIERS
  final ValueNotifier<int> currentAmmoNotifier = ValueNotifier<int>(12);
  final ValueNotifier<bool> isReloadingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<double> reloadTimerNotifier = ValueNotifier<double>(0.0);
  final ValueNotifier<String> weaponNotifier = ValueNotifier<String>('Pistol');
  final ValueNotifier<int> coinsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<double> hpNotifier = ValueNotifier<double>(100.0);
  final ValueNotifier<int> remainingZombiesNotifier = ValueNotifier<int>(5);
  final ValueNotifier<bool> compactHudNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<Color> hudColorNotifier = ValueNotifier<Color>(Colors.amber);

  // WEAPONS DATA
  final Map<String, Map<String, dynamic>> weapons = {
    'Pistol': {'maxAmmo': 12, 'reloadTime': 2.0, 'price': 0, 'damage': 15.0, 'cooldown': 0.25, 'speed': 40.0},
    'Shotgun': {'maxAmmo': 6, 'reloadTime': 2.0, 'price': 150, 'damage': 18.0, 'cooldown': 0.65, 'speed': 35.0},
    'Rifle': {'maxAmmo': 35, 'reloadTime': 2.0, 'price': 300, 'damage': 8.0, 'cooldown': 0.08, 'speed': 50.0},
    'Sniper': {'maxAmmo': 5, 'reloadTime': 2.0, 'price': 500, 'damage': 120.0, 'cooldown': 0.9, 'speed': 80.0},
  };

  Map<String, bool> unlockedWeapons = {'Pistol': true, 'Shotgun': false, 'Rifle': false, 'Sniper': false};
  String currentWeapon = 'Pistol';
  int currentAmmo = 12;
  bool isReloading = false;
  double reloadTimer = 0.0;
  double fireCooldown = 0.0;

  List<Zombie3D> zombies = [];
  List<Bullet3D> bullets = [];
  List<Particle3D> particles = [];

  final Set<LogicalKeyboardKey> _pressedKeys = {};

  GameEngine3D({required this.onStateChanged}) {
    _initAudio();
    spawnStageZombies();
  }

  Future<void> _initAudio() async {
    try {
      pistolPool = await FlameAudio.createPool('pistol.mp3', maxPlayers: 10);
      riflePool = await FlameAudio.createPool('rifle.mp3', maxPlayers: 10);
      shotgunPool = await FlameAudio.createPool('shotgun.mp3', maxPlayers: 10);
      sniperPool = await FlameAudio.createPool('sniper.mp3', maxPlayers: 10);
      reloadPool = await FlameAudio.createPool('reload.mp3', maxPlayers: 5);
    } catch (_) {}
  }

  void safePlayAudio(String key) {
    try {
      switch (key) {
        case 'Pistol': pistolPool?.start(); break;
        case 'Rifle': riflePool?.start(); break;
        case 'Shotgun': shotgunPool?.start(); break;
        case 'Sniper': sniperPool?.start(); break;
        case 'Reload': reloadPool?.start(); break;
      }
    } catch (_) {}
  }

  void handleKeyEvent(RawKeyEvent event) {
    if (event is RawKeyDownEvent) {
      _pressedKeys.add(event.logicalKey);

      if (event.logicalKey == LogicalKeyboardKey.keyR) startReload();
      if (event.logicalKey == LogicalKeyboardKey.digit1) switchWeapon('Pistol');
      if (event.logicalKey == LogicalKeyboardKey.digit2) switchWeapon('Shotgun');
      if (event.logicalKey == LogicalKeyboardKey.digit3) switchWeapon('Rifle');
      if (event.logicalKey == LogicalKeyboardKey.digit4) switchWeapon('Sniper');
    } else if (event is RawKeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
    }
  }

  void update(double dt) {
    // Player Movement Logic
    v64.Vector3 moveDir = v64.Vector3.zero();
    if (_pressedKeys.contains(LogicalKeyboardKey.keyW) || _pressedKeys.contains(LogicalKeyboardKey.arrowUp)) moveDir.z -= 1;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyS) || _pressedKeys.contains(LogicalKeyboardKey.arrowDown)) moveDir.z += 1;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyA) || _pressedKeys.contains(LogicalKeyboardKey.arrowLeft)) moveDir.x -= 1;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyD) || _pressedKeys.contains(LogicalKeyboardKey.arrowRight)) moveDir.x += 1;

    if (moveDir.length > 0) moveDir.normalize();
    playerPos += moveDir * playerSpeed * dt;

    // Map Boundaries (-35 to 35)
    playerPos.x = playerPos.x.clamp(-35.0, 35.0);
    playerPos.z = playerPos.z.clamp(-35.0, 35.0);

    // Weapon Cooldown & Reloading
    if (fireCooldown > 0) fireCooldown -= dt;

    if (isReloading) {
      reloadTimer -= dt;
      reloadTimerNotifier.value = reloadTimer;
      if (reloadTimer <= 0) {
        isReloading = false;
        isReloadingNotifier.value = false;
        currentAmmo = weapons[currentWeapon]!['maxAmmo'] as int;
        currentAmmoNotifier.value = currentAmmo;
      }
    }

    // Update Zombies
    for (var z in zombies) {
      v64.Vector3 dir = (playerPos - z.pos);
      dir.y = 0;
      if (dir.length > 0) dir.normalize();
      z.pos += dir * zombieSpeed * dt;

      if ((z.pos - playerPos).length < 1.5) {
        takeDamage(12 * dt);
      }
    }

    // Update Bullets
    for (int i = bullets.length - 1; i >= 0; i--) {
      var b = bullets[i];
      b.pos += b.dir * b.speed * dt;

      // Check Collision with Zombies
      for (var z in zombies) {
        if ((z.pos - b.pos).length < 1.2) {
          z.hp -= b.damage;
          addBloodParticles(b.pos.clone());
          bullets.removeAt(i);
          if (z.hp <= 0) {
            zombies.remove(z);
            onZombieKilled();
          }
          break;
        }
      }

      if (b.pos.length > 80) bullets.remove(b);
    }

    // Update Particles
    for (int i = particles.length - 1; i >= 0; i--) {
      var p = particles[i];
      p.update(dt);
      if (p.life <= 0) particles.removeAt(i);
    }
  }

  void onTapDown(Offset tapPos, Size screenSize) {
    if (fireCooldown > 0 || isReloading) return;

    // Simple 3D Screen Raycast to Floor Plane
    double normalizedX = (tapPos.dx / screenSize.width) * 2 - 1;
    double normalizedZ = (tapPos.dy / screenSize.height) * 2 - 1;

    v64.Vector3 target3D = playerPos + v64.Vector3(normalizedX * 25, 0, normalizedZ * 25);
    shoot(target3D);
  }

  void shoot(v64.Vector3 target) {
    if (currentAmmo <= 0) {
      startReload();
      return;
    }

    v64.Vector3 dir = (target - playerPos);
    dir.y = 0;
    dir.normalize();

    final wData = weapons[currentWeapon]!;
    final double baseDamage = (wData['damage'] as double) * playerDamageLevel;
    final double speed = wData['speed'] as double;

    currentAmmo--;
    currentAmmoNotifier.value = currentAmmo;
    fireCooldown = wData['cooldown'] as double;

    safePlayAudio(currentWeapon);

    if (currentWeapon == 'Shotgun') {
      for (int i = -2; i <= 2; i++) {
        double spread = i * 0.15;
        v64.Vector3 spreadDir = v64.Vector3(
          dir.x * cos(spread) - dir.z * sin(spread),
          0,
          dir.x * sin(spread) + dir.z * cos(spread),
        );
        bullets.add(Bullet3D(pos: playerPos.clone() + v64.Vector3(0, 1.2, 0), dir: spreadDir, damage: baseDamage, speed: speed));
      }
    } else {
      bullets.add(Bullet3D(pos: playerPos.clone() + v64.Vector3(0, 1.2, 0), dir: dir, damage: baseDamage, speed: speed));
    }

    if (currentAmmo <= 0) startReload();
  }

  void startReload() {
    final maxAmmo = weapons[currentWeapon]!['maxAmmo'] as int;
    if (isReloading || currentAmmo == maxAmmo) return;
    isReloading = true;
    isReloadingNotifier.value = true;
    reloadTimer = weapons[currentWeapon]!['reloadTime'] as double;
    reloadTimerNotifier.value = reloadTimer;
    safePlayAudio('Reload');
  }

  void switchWeapon(String weapon) {
    if (unlockedWeapons[weapon] == true && currentWeapon != weapon) {
      currentWeapon = weapon;
      weaponNotifier.value = weapon;
      isReloading = false;
      isReloadingNotifier.value = false;
      currentAmmo = weapons[currentWeapon]!['maxAmmo'] as int;
      currentAmmoNotifier.value = currentAmmo;
    }
  }

  void spawnStageZombies() {
    zombiesToSpawn = stage * 5;
    zombiesKilled = 0;
    remainingZombiesNotifier.value = zombiesToSpawn - zombiesKilled;
    zombies.clear();

    final random = Random();
    for (int i = 0; i < zombiesToSpawn; i++) {
      double angle = random.nextDouble() * pi * 2;
      double dist = 20 + random.nextDouble() * 20;
      zombies.add(Zombie3D(pos: v64.Vector3(playerPos.x + cos(angle) * dist, 0, playerPos.z + sin(angle) * dist)));
    }
  }

  void onZombieKilled() {
    zombiesKilled++;
    remainingZombiesNotifier.value = max(0, zombiesToSpawn - zombiesKilled);
    coins += 10;
    coinsNotifier.value = coins;

    if (zombiesKilled >= zombiesToSpawn) {
      pauseEngine();
      activeOverlays.add('StageClear');
      onStateChanged();
    }
  }

  void nextStage() {
    stage++;
    coins += 50 + (stage * 20);
    coinsNotifier.value = coins;
    playerHp = (playerHp + 50).clamp(0.0, 100.0);
    hpNotifier.value = playerHp;

    activeOverlays.remove('StageClear');
    spawnStageZombies();
    resumeEngine();
  }

  void restart() {
    stage = 1;
    coins = 0;
    coinsNotifier.value = 0;
    playerDamageLevel = 1;
    unlockedWeapons = {'Pistol': true, 'Shotgun': false, 'Rifle': false, 'Sniper': false};
    currentWeapon = 'Pistol';
    weaponNotifier.value = 'Pistol';
    currentAmmo = weapons['Pistol']!['maxAmmo'] as int;
    currentAmmoNotifier.value = currentAmmo;
    isReloading = false;
    isReloadingNotifier.value = false;
    playerHp = 100;
    hpNotifier.value = 100;
    playerPos = v64.Vector3.zero();

    activeOverlays.remove('GameOver');
    spawnStageZombies();
    resumeEngine();
  }

  void takeDamage(double amount) {
    playerHp -= amount;
    hpNotifier.value = playerHp;
    if (playerHp <= 0) {
      playerHp = 0;
      hpNotifier.value = 0;
      pauseEngine();
      activeOverlays.add('GameOver');
      onStateChanged();
    }
  }

  void addBloodParticles(v64.Vector3 pos) {
    final rand = Random();
    for (int i = 0; i < 10; i++) {
      particles.add(Particle3D(
        pos: pos.clone(),
        vel: v64.Vector3((rand.nextDouble() - 0.5) * 8, rand.nextDouble() * 6 + 2, (rand.nextDouble() - 0.5) * 8),
        color: Colors.redAccent,
      ));
    }
  }

  void pauseEngine() {
    isPaused = true;
    onStateChanged();
  }

  void resumeEngine() {
    isPaused = false;
    onStateChanged();
  }
}

// ==========================================
// 3D ENTITY CLASSES
// ==========================================
class Zombie3D {
  v64.Vector3 pos;
  double hp = 40.0;
  Zombie3D({required this.pos});
}

class Bullet3D {
  v64.Vector3 pos;
  v64.Vector3 dir;
  double damage;
  double speed;
  Bullet3D({required this.pos, required this.dir, required this.damage, required this.speed});
}

class Particle3D {
  v64.Vector3 pos;
  v64.Vector3 vel;
  Color color;
  double life = 0.5;

  Particle3D({required this.pos, required this.vel, required this.color});

  void update(double dt) {
    pos += vel * dt;
    vel.y -= 15 * dt; // Gravity
    life -= dt;
  }
}

// ==========================================
// PURE FLUTTER 3D MATRIX RENDER PAINTER
// ==========================================
class Game3DPainter extends CustomPainter {
  final GameEngine3D game;

  Game3DPainter({required this.game});

  @override
  void paint(Canvas canvas, Size size) {
    final double fov = 45.0;
    final double aspect = size.width / size.height;

    // 3D Camera Matrix Setup (Behind & Above Player)
    v64.Vector3 camPos = game.playerPos + v64.Vector3(0, 22, 22);
    v64.Vector3 camTarget = game.playerPos + v64.Vector3(0, 0, -2);

    v64.Matrix4 viewMatrix = v64.makeViewMatrix(camPos, camTarget, v64.Vector3(0, 1, 0));
    v64.Matrix4 projMatrix = v64.makePerspectiveMatrix(fov * pi / 180, aspect, 0.1, 200.0);
    v64.Matrix4 vpMatrix = projMatrix * viewMatrix;

    Offset? project(v64.Vector3 worldPos) {
      v64.Vector4 p = vpMatrix.transform(v64.Vector4(worldPos.x, worldPos.y, worldPos.z, 1.0));
      if (p.w <= 0.1) return null;
      double screenX = (p.x / p.w + 1.0) * 0.5 * size.width;
      double screenY = (1.0 - p.y / p.w) * 0.5 * size.height;
      return Offset(screenX, screenY);
    }

    // 1. Clear Dark Sky / Background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = const Color(0xFF10121A));

    // 2. Draw 3D Ground Floor Grid
    final gridPaint = Paint()..color = Colors.cyan.withOpacity(0.15)..strokeWidth = 1.0;
    const double gridSize = 40.0;
    const double step = 4.0;

    for (double x = -gridSize; x <= gridSize; x += step) {
      var p1 = project(v64.Vector3(x, 0, -gridSize));
      var p2 = project(v64.Vector3(x, 0, gridSize));
      if (p1 != null && p2 != null) canvas.drawLine(p1, p2, gridPaint);
    }
    for (double z = -gridSize; z <= gridSize; z += step) {
      var p1 = project(v64.Vector3(-gridSize, 0, z));
      var p2 = project(v64.Vector3(gridSize, 0, z));
      if (p1 != null && p2 != null) canvas.drawLine(p1, p2, gridPaint);
    }

    // Render Helper for 3D Mesh Cylinders / Cubes
    void draw3DCylinder(v64.Vector3 pos, double radius, double height, Color color) {
      var shadowCenter = project(pos);
      if (shadowCenter != null) {
        canvas.drawOval(Rect.fromCenter(center: shadowCenter, width: radius * 35, height: radius * 18), Paint()..color = Colors.black45);
      }

      var bottom = project(pos);
      var top = project(pos + v64.Vector3(0, height, 0));
      if (bottom != null && top != null) {
        double currentRadius = (bottom - top).distance * (radius / height);
        canvas.drawLine(bottom, top, Paint()..color = color..strokeWidth = currentRadius * 2..strokeCap = StrokeCap.round);
        canvas.drawCircle(top, currentRadius * 1.1, Paint()..color = color.withOpacity(0.8));
      }
    }

    // 3. Render 3D Zombies
    for (var z in game.zombies) {
      draw3DCylinder(z.pos, 0.7, 2.2, Colors.green.shade600);
      var headPos = project(z.pos + v64.Vector3(0, 2.3, 0));
      if (headPos != null) {
        canvas.drawCircle(headPos, 4, Paint()..color = Colors.redAccent); // Eyes
      }
    }

    // 4. Render 3D Player
    draw3DCylinder(game.playerPos, 0.8, 2.5, Colors.blueAccent);
    var visorPos = project(game.playerPos + v64.Vector3(0, 2.4, -0.2));
    if (visorPos != null) {
      canvas.drawCircle(visorPos, 5, Paint()..color = Colors.cyanAccent);
    }

    // 5. Render 3D Bullets
    for (var b in game.bullets) {
      var p = project(b.pos);
      if (p != null) {
        canvas.drawCircle(p, 4, Paint()..color = Colors.yellowAccent);
        canvas.drawCircle(p, 8, Paint()..color = Colors.orangeAccent.withOpacity(0.4));
      }
    }

    // 6. Render 3D Blood & Particles
    for (var particle in game.particles) {
      var p = project(particle.pos);
      if (p != null) {
        canvas.drawCircle(p, 3, Paint()..color = particle.color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

// ==========================================
// FLUTTER OVERLAYS (UI)
// ==========================================
class HUDOverlay extends StatelessWidget {
  final GameEngine3D game;
  const HUDOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          DraggableHudItem(
            initialOffset: const Offset(16, 16),
            child: ValueListenableBuilder<bool>(
              valueListenable: game.compactHudNotifier,
              builder: (context, isCompact, _) {
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.65),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
                  ),
                  child: ValueListenableBuilder<Color>(
                    valueListenable: game.hudColorNotifier,
                    builder: (context, themeColor, _) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ValueListenableBuilder<double>(
                            valueListenable: game.hpNotifier,
                            builder: (context, hp, _) => Text(
                              'HP: ${hp.toInt()}',
                              style: TextStyle(color: Colors.redAccent, fontSize: isCompact ? 13 : 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          ValueListenableBuilder<int>(
                            valueListenable: game.coinsNotifier,
                            builder: (context, coins, _) => Text(
                              'Gold: \$$coins',
                              style: TextStyle(color: themeColor, fontSize: isCompact ? 13 : 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text('Stage: ${game.stage} (3D Engine)', style: TextStyle(color: Colors.lightBlueAccent, fontSize: isCompact ? 13 : 16, fontWeight: FontWeight.bold)),
                          ValueListenableBuilder<int>(
                            valueListenable: game.remainingZombiesNotifier,
                            builder: (context, remaining, _) => Text(
                              'Zombies Left: $remaining',
                              style: TextStyle(color: Colors.red, fontSize: isCompact ? 13 : 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (!isCompact) ...[
                            const SizedBox(height: 4),
                            ValueListenableBuilder<String>(
                              valueListenable: game.weaponNotifier,
                              builder: (context, weapon, _) => Text(
                                'Weapon: $weapon',
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ),
                          ],
                          AnimatedBuilder(
                            animation: Listenable.merge([
                              game.currentAmmoNotifier,
                              game.isReloadingNotifier,
                              game.reloadTimerNotifier,
                              game.weaponNotifier,
                            ]),
                            builder: (context, _) {
                              final maxAmmo = game.weapons[game.currentWeapon]!['maxAmmo'];
                              final isReloading = game.isReloadingNotifier.value;
                              final ammo = game.currentAmmoNotifier.value;
                              final timer = game.reloadTimerNotifier.value;

                              final ammoDisplay = isReloading ? 'RELOADING... (${timer.toStringAsFixed(1)}s)' : 'Ammo: $ammo / $maxAmmo';

                              return Text(
                                ammoDisplay,
                                style: TextStyle(
                                  color: isReloading ? Colors.orangeAccent : Colors.lightGreenAccent,
                                  fontSize: isCompact ? 12 : 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      );
                    },
                  ),
                );
              },
            ),
          ),

          DraggableHudItem(
            initialOffset: const Offset(240, 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.65),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                    onPressed: game.startReload,
                    icon: const Icon(Icons.refresh, size: 16, color: Colors.white),
                    label: const Text('RELOAD (R)', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.shopping_cart, color: Colors.amber, size: 26),
                    onPressed: () {
                      game.pauseEngine();
                      game.activeOverlays.add('Shop');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.pause, color: Colors.white, size: 26),
                    onPressed: () {
                      game.pauseEngine();
                      game.activeOverlays.add('Pause');
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PauseOverlay extends StatelessWidget {
  final GameEngine3D game;
  const PauseOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 260,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('PAUSED', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                onPressed: () {
                  game.activeOverlays.remove('Pause');
                  game.resumeEngine();
                },
                icon: const Icon(Icons.play_arrow, color: Colors.white),
                label: const Text('RESUME', style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[800]),
                onPressed: () {
                  game.activeOverlays.remove('Pause');
                  game.activeOverlays.add('Settings');
                },
                icon: const Icon(Icons.settings, color: Colors.white),
                label: const Text('SETTINGS', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsOverlay extends StatefulWidget {
  final GameEngine3D game;
  const SettingsOverlay({super.key, required this.game});

  @override
  State<SettingsOverlay> createState() => _SettingsOverlayState();
}

class _SettingsOverlayState extends State<SettingsOverlay> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 360,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.blueAccent, width: 2),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Center(child: Text('3D GAME SETTINGS', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold))),
              const Divider(color: Colors.white24, height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Compact HUD Mode', style: TextStyle(color: Colors.white)),
                  Switch(
                    value: widget.game.compactHudNotifier.value,
                    onChanged: (val) {
                      setState(() {
                        widget.game.compactHudNotifier.value = val;
                      });
                    },
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 24),
              Text('3D Player Speed: ${widget.game.playerSpeed.toInt()}', style: const TextStyle(color: Colors.white)),
              Slider(
                value: widget.game.playerSpeed,
                min: 5,
                max: 35,
                divisions: 6,
                activeColor: Colors.blue,
                onChanged: (val) {
                  setState(() {
                    widget.game.playerSpeed = val;
                  });
                },
              ),
              Text('3D Zombie Speed: ${widget.game.zombieSpeed.toInt()}', style: const TextStyle(color: Colors.white)),
              Slider(
                value: widget.game.zombieSpeed,
                min: 1,
                max: 12,
                divisions: 11,
                activeColor: Colors.red,
                onChanged: (val) {
                  setState(() {
                    widget.game.zombieSpeed = val;
                  });
                },
              ),
              const SizedBox(height: 16),
              Center(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                  onPressed: () {
                    widget.game.activeOverlays.remove('Settings');
                    widget.game.activeOverlays.add('Pause');
                  },
                  child: const Text('BACK TO PAUSE MENU', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ShopOverlay extends StatefulWidget {
  final GameEngine3D game;
  const ShopOverlay({super.key, required this.game});

  @override
  State<ShopOverlay> createState() => _ShopOverlayState();
}

class _ShopOverlayState extends State<ShopOverlay> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 350,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.amber, width: 2),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('3D WEAPON & UPGRADE SHOP', style: TextStyle(color: Colors.amber, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              Text('Gold: \$${widget.game.coins}', style: const TextStyle(color: Colors.white, fontSize: 16)),
              const Divider(color: Colors.white24),
              _shopItem(
                'Damage Multiplier (Lvl ${widget.game.playerDamageLevel})',
                50,
                () {
                  if (widget.game.coins >= 50) {
                    setState(() {
                      widget.game.coins -= 50;
                      widget.game.coinsNotifier.value = widget.game.coins;
                      widget.game.playerDamageLevel++;
                    });
                  }
                },
                isUnlocked: true,
                buttonText: 'UPGRADE (\$50)',
              ),
              const Divider(color: Colors.white24),
              ...widget.game.weapons.keys.map((weapon) => _buildWeaponTile(weapon)),
              const SizedBox(height: 15),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () {
                  widget.game.activeOverlays.remove('Shop');
                  widget.game.resumeEngine();
                },
                child: const Text('CLOSE SHOP', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeaponTile(String weapon) {
    final bool isUnlocked = widget.game.unlockedWeapons[weapon] ?? false;
    final bool isEquipped = widget.game.currentWeapon == weapon;
    final int price = widget.game.weapons[weapon]!['price'] as int;

    String btnText = 'BUY \$${price}';
    if (isUnlocked) {
      btnText = isEquipped ? 'EQUIPPED' : 'EQUIP';
    }

    return _shopItem(
      weapon,
      price,
      () {
        setState(() {
          if (isUnlocked) {
            widget.game.switchWeapon(weapon);
          } else if (widget.game.coins >= price) {
            widget.game.coins -= price;
            widget.game.coinsNotifier.value = widget.game.coins;
            widget.game.unlockedWeapons[weapon] = true;
            widget.game.switchWeapon(weapon);
          }
        });
      },
      isUnlocked: isUnlocked,
      isEquipped: isEquipped,
      buttonText: btnText,
    );
  }

  Widget _shopItem(
    String title,
    int cost,
    VoidCallback onTap, {
    bool isUnlocked = false,
    bool isEquipped = false,
    String buttonText = 'BUY',
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 14, color: isEquipped ? Colors.amber : Colors.white))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: isEquipped ? Colors.green : (isUnlocked ? Colors.blue : Colors.orange)),
            onPressed: isEquipped ? null : onTap,
            child: Text(buttonText, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class StageClearOverlay extends StatelessWidget {
  final GameEngine3D game;
  const StageClearOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.green),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('3D STAGE ${game.stage} CLEARED!', style: const TextStyle(fontSize: 24, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('Bonus Gold: \$${50 + (game.stage * 20)}', style: const TextStyle(fontSize: 16, color: Colors.amber)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                game.nextStage();
              },
              child: const Text('NEXT STAGE'),
            ),
          ],
        ),
      ),
    );
  }
}

class GameOverOverlay extends StatelessWidget {
  final GameEngine3D game;
  const GameOverOverlay({super.key, required this.game});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('GAME OVER', style: TextStyle(fontSize: 28, color: Colors.redAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('Reached 3D Stage: ${game.stage}', style: const TextStyle(fontSize: 18, color: Colors.white)),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                game.restart();
              },
              child: const Text('RESTART'),
            ),
          ],
        ),
      ),
    );
  }
}