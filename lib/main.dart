import 'package:flame/game.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:async' show Timer, unawaited;

import 'firebase_init.dart';
import 'field_game.dart';
import 'game_session.dart';
import 'game_over_screen.dart';
import 'game_constants.dart';
import 'ranking_screen.dart';
import 'revive_dialog.dart';
import 'splash_screen.dart';
import 'victory_dialog.dart';
import 'multiplayer/network_session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS)) {
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }
  try {
    await ensureFirebaseInitialized();
  } catch (_) {
    // Firebase 설정이 없으면 멀티 기능만 제한될 수 있음
  }
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Moving Man Game',
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}

class GameHost extends StatefulWidget {
  const GameHost({super.key, this.network, this.session});

  final NetworkSession? network;
  final GameSession? session;

  @override
  State<GameHost> createState() => _GameHostState();
}

class _GameHostState extends State<GameHost> {
  late final GameSession _session;
  late final ValueNotifier<FieldOverlayHudData> _overlayHud;
  late final ValueNotifier<String?> _bossBanner;
  late FieldGame _field;
  Timer? _runTimer;
  int _runSeconds = 0;
  int _prevRemotePlayerCount = 0;

  @override
  void initState() {
    super.initState();
    _session = widget.session ?? GameSession();
    _overlayHud = ValueNotifier<FieldOverlayHudData>(
      const FieldOverlayHudData(
        floor: 1,
        hp: kDefaultMaxHp,
        hpMax: kDefaultMaxHp,
        npcAlive: 0,
        npcTotal: 0,
        roomNumber: 5,
      ),
    );
    _bossBanner = ValueNotifier<String?>(null);
    _field = FieldGame(
      session: _session,
      onRequestRevive: _requestRevive,
      onVictory: _onVictory,
      network: widget.network,
      overlayHud: _overlayHud,
      bossBanner: _bossBanner,
      getRunElapsedSeconds: () => _runSeconds,
      onSinglePlayerRunEnded:
          widget.network == null ? _onSinglePlayerGameOver : null,
    );
    widget.network?.allPlayers.addListener(_onRemotePlayerChanged);
    _runTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _runSeconds++);
    });
    if (widget.network != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog<void>(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            title: const Text('멀티플레이 PvP'),
            content: const Text(
              'PvP 모드에 입장했습니다.\n\n'
              '· 보스 몬스터만 등장합니다 (boss1).\n'
              '· 보스를 처치하면 파워업·이동속도 아이템이 나타납니다.\n'
              '· 상대를 격파하면 체력이 일부 회복됩니다.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _runTimer?.cancel();
    _overlayHud.dispose();
    _bossBanner.dispose();
    widget.network?.allPlayers.removeListener(_onRemotePlayerChanged);
    final net = widget.network;
    if (net != null) {
      unawaited(net.leave());
    }
    super.dispose();
  }

  void _onSinglePlayerGameOver(int floor, int elapsedSec) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      _runTimer?.cancel();
      final result = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          fullscreenDialog: true,
          builder: (_) => GameOverScreen(
            playerTag: _session.playerTag,
            maxFloor: floor,
            elapsedSeconds: elapsedSec,
          ),
        ),
      );
      if (!mounted) return;
      if (result == 'retry') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('광고 로드 자리')),
        );
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => GameHost(
              session: GameSession()..playerTag = _session.playerTag,
            ),
          ),
        );
      } else if (result == 'title') {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
  }

  void _onRemotePlayerChanged() {
    if (!mounted) return;
    final net = widget.network;
    if (net == null) return;
    final n = net.allPlayers.value.length;
    final others = n > 1 ? n - 1 : 0;
    if (others > _prevRemotePlayerCount && others >= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('플레이어 입장 (상대 $others명)')),
      );
    }
    _prevRemotePlayerCount = others;
  }

  Future<void> _onVictory() async {
    if (!mounted) return;
    if (widget.network != null) {
      return;
    }
    await showVictoryDialog(context);
  }

  Future<bool> _requestRevive() async {
    if (!mounted) return false;
    return showReviveDialog(context, _session.revive);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GameWidget(game: _field),
                  Positioned(
                    left: 0,
                    bottom: 0,
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 10),
                        child: _CircularJoystick(field: _field),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: ColoredBox(
                      color: Colors.transparent,
                      child: SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 8, 10, 10),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _GameActionChip(
                                label: 'PUNCH',
                                color: const Color(0xFFE53935),
                                onTap: _field.triggerPunch,
                              ),
                              const SizedBox(height: 8),
                              _GameActionChip(
                                label: 'KICK',
                                color: const Color(0xFFFB8C00),
                                onTap: _field.triggerKick,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              top: 6,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: Text(
                    '$_runSeconds초',
                    style: TextStyle(
                      color: Colors.amber.shade200,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.88),
                          blurRadius: 7,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ValueListenableBuilder<String?>(
              valueListenable: _bossBanner,
              builder: (context, msg, _) {
                if (msg == null || msg.isEmpty) return const SizedBox.shrink();
                return Positioned(
                  top: 40,
                  left: 12,
                  right: 12,
                  child: SafeArea(
                    bottom: false,
                    child: Material(
                      color: Colors.transparent,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFE53935)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withValues(alpha: 0.35),
                                blurRadius: 18,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: Text(
                            msg,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 4,
              left: 4,
              child: SafeArea(
                child: Material(
                  color: Colors.transparent,
                  child: PopupMenuButton<String>(
                    icon: Icon(Icons.menu, color: Colors.white.withValues(alpha: 0.92)),
                    tooltip: '메뉴',
                    onSelected: (v) {
                      if (v == 'title') {
                        Navigator.of(context).pop();
                      } else if (v == 'rank') {
                        Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => const RankingScreen(),
                          ),
                        );
                      }
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'rank', child: Text('랭킹')),
                      PopupMenuItem(value: 'title', child: Text('타이틀 화면으로')),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 6,
              child: ValueListenableBuilder<FieldOverlayHudData>(
                valueListenable: _overlayHud,
                builder: (context, h, _) {
                  final multi = h.remoteShort.isNotEmpty;
                  final buff = <String>[
                    if (h.powerBuffSecRemain > 0)
                      'PWR×2 ${h.powerBuffSecRemain}s',
                    if (h.speedBuffSecRemain > 0)
                      'SPD×2 ${h.speedBuffSecRemain}s',
                  ].join(' ');
                  final base = multi
                      ? (h.hideFloorInHud
                          ? '방${h.roomNumber} · HP${h.hp}/${h.hpMax} · ${h.remoteShort}'
                          : '방${h.roomNumber} · F${h.floor} HP${h.hp}/${h.hpMax} · ${h.remoteShort}')
                      : '방${h.roomNumber} · F${h.floor} HP${h.hp}/${h.hpMax} N${h.npcAlive}/${h.npcTotal}';
                  final mid = buff.isEmpty ? '' : ' · $buff';
                  return Material(
                    color: Colors.transparent,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 320),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.42),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        '$base$mid',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.2,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 왼쪽 하단 원형 가상 조이스틱.
class _CircularJoystick extends StatefulWidget {
  const _CircularJoystick({required this.field});

  final FieldGame field;

  static const double _outerR = 62;
  static const double _knobR = 22;

  @override
  State<_CircularJoystick> createState() => _CircularJoystickState();
}

class _CircularJoystickState extends State<_CircularJoystick> {
  /// 노브가 중심에서 벗어난 오프셋(픽셀).
  Offset _knob = Offset.zero;

  double get _outerR => _CircularJoystick._outerR;
  double get _knobR => _CircularJoystick._knobR;

  /// 노브 중심이 움직일 수 있는 최대 반경.
  double get _maxTravel => _outerR - _knobR - 4;

  @override
  void dispose() {
    widget.field.clearTouchMove();
    super.dispose();
  }

  void _onPan(Offset local) {
    final center = Offset(_outerR, _outerR);
    var d = local - center;
    final len = d.distance;
    if (len < 6) {
      setState(() => _knob = Offset.zero);
      widget.field.clearTouchMove();
      return;
    }
    if (len > _maxTravel) {
      d = Offset.fromDirection(d.direction, _maxTravel);
    }
    setState(() => _knob = d);
    final nx = (d.dx / _maxTravel).clamp(-1.0, 1.0);
    final ny = (d.dy / _maxTravel).clamp(-1.0, 1.0);
    widget.field.setTouchMoveAnalog(nx, ny);
  }

  void _endPan() {
    setState(() => _knob = Offset.zero);
    widget.field.clearTouchMove();
  }

  @override
  Widget build(BuildContext context) {
    final size = _outerR * 2;
    return SizedBox(
      width: size,
      height: size,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanDown: (d) => _onPan(d.localPosition),
        onPanUpdate: (d) => _onPan(d.localPosition),
        onPanEnd: (_) => _endPan(),
        onPanCancel: _endPan,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.35),
                  border: Border.all(color: Colors.white24, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: _outerR - _knobR + _knob.dx,
              top: _outerR - _knobR + _knob.dy,
              child: Container(
                width: _knobR * 2,
                height: _knobR * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.82),
                  border: Border.all(color: Colors.white30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GameActionChip extends StatelessWidget {
  const _GameActionChip({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 88,
        height: 40,
        child: FilledButton(
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            backgroundColor: color.withValues(alpha: 0.88),
            foregroundColor: Colors.white,
            textStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          onPressed: onTap,
          child: Text(label),
        ),
      ),
    );
  }
}
