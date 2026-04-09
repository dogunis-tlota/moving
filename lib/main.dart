import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import 'boss_screen.dart';
import 'field_game.dart';
import 'game_session.dart';
import 'revive_dialog.dart';
import 'shop_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Moving Man Game', home: const GameHost());
  }
}

class GameHost extends StatefulWidget {
  const GameHost({super.key});

  @override
  State<GameHost> createState() => _GameHostState();
}

class _GameHostState extends State<GameHost> {
  final GameSession _session = GameSession();
  late FieldGame _field;

  @override
  void initState() {
    super.initState();
    _field = FieldGame(
      session: _session,
      onOpenShop: _openShop,
      onOpenBoss: _openBoss,
      onRequestRevive: _requestRevive,
    );
  }

  Future<void> _openShop() async {
    _field.pauseEngine();
    try {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => ShopScreen(session: _session)),
      );
    } finally {
      _field.resumeEngine();
    }
  }

  Future<void> _openBoss() async {
    _field.pauseEngine();
    try {
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => BossScreen(session: _session)),
      );
    } finally {
      _field.resumeEngine();
    }
  }

  Future<bool> _requestRevive() async {
    if (!mounted) return false;
    return showReviveDialog(context, _session.revive);
  }

  @override
  Widget build(BuildContext context) {
    return GameWidget(game: _field);
  }
}
