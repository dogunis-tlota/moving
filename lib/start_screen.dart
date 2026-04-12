import 'package:flutter/material.dart';

import 'character_face_thumb.dart';
import 'game_session.dart';
import 'main.dart' show GameHost;
import 'multiplayer/multiplayer_lobby_screen.dart';
import 'multiplayer/network_session.dart';
import 'player_identity_service.dart';
import 'ranking_screen.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  int _selected = 0;
  bool _busy = false;

  Future<void> _startSingle() async {
    final session = GameSession()..selectedCharacterIndex = _selected;
    final identity = await PlayerIdentityService.resolve();
    session.playerTag = identity.displayName;
    if (!mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => GameHost(session: session)));
  }

  Future<void> _startMultiViaLobby() async {
    setState(() => _busy = true);
    try {
      final session = GameSession()..selectedCharacterIndex = _selected;
      final identity = await PlayerIdentityService.resolve();
      session.playerTag = identity.displayName;
      if (!mounted) return;
      final net = await Navigator.of(context).push<NetworkSession>(
        MaterialPageRoute<NetworkSession>(
          builder: (_) => MultiplayerLobbyScreen(session: session),
        ),
      );
      if (net == null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => GameHost(network: net, session: session),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('멀티 진입 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _characterRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List<Widget>.generate(4, (i) {
        final enabled = i == 0;
        final selected = _selected == i;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: GestureDetector(
            onTap: enabled ? () => setState(() => _selected = i) : null,
            child: enabled
                ? CharacterFaceThumbnail(selected: selected)
                : Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: const Color(0xFF3A3A3A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? Colors.amber : Colors.white24,
                        width: selected ? 2.5 : 1.2,
                      ),
                    ),
                    child: const Center(
                      child: Text(
                        'COMING\nSOON',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),
          ),
        );
      }),
    );
  }

  Widget _actionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton(
          onPressed: _busy ? null : _startSingle,
          child: const Text('싱글 플레이'),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _startMultiViaLobby,
          child: Text(
            _busy ? '로딩 중...' : '멀티 플레이 (방 만들기/코드 입장)',
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final landscapeUi = size.width >= size.height;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.28),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.leaderboard_outlined, color: Colors.white),
            tooltip: '랭킹',
            onPressed: () {
              Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => const RankingScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF141E30), Color(0xFF243B55), Color(0xFF0B5E2D)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: landscapeUi ? 920 : 460,
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: landscapeUi ? 28 : 24,
                  vertical: landscapeUi ? 16 : 24,
                ),
                child: landscapeUi
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 5,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.sports_martial_arts,
                                      size: 52,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 14),
                                    const Expanded(
                                      child: Text(
                                        'Maru Floor Up',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 32,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  'Fight and climb. Defeat enemies and move to higher floors.',
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: 0.88),
                                    fontSize: 14,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                _characterRow(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            flex: 4,
                            child: _actionButtons(),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.sports_martial_arts,
                            size: 68,
                            color: Colors.white,
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Maru Floor Up',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Fight and climb.\nDefeat enemies and move to higher floors.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 15,
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _characterRow(),
                          const SizedBox(height: 24),
                          _actionButtons(),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
