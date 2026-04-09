import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'boss_game.dart';
import 'game_session.dart';

/// 보스 방 — [BossGame] 전체 화면.
class BossScreen extends StatefulWidget {
  const BossScreen({super.key, required this.session});

  final GameSession session;

  @override
  State<BossScreen> createState() => _BossScreenState();
}

class _BossScreenState extends State<BossScreen> {
  late final BossGame game;

  @override
  void initState() {
    super.initState();
    game = BossGame(
      session: widget.session,
      onBossDefeated: () {
        if (mounted) Navigator.pop(context, true);
      },
      onPlayerDied: () {
        if (mounted) Navigator.pop(context, false);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GameWidget(game: game),
    );
  }
}
