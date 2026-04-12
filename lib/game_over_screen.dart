import 'package:flutter/material.dart';

import 'leaderboard_service.dart';

/// 싱글 플레이 종료 — 기록 제출, 랭킹 목록, 다시하기 / 타이틀.
class GameOverScreen extends StatefulWidget {
  const GameOverScreen({
    super.key,
    required this.playerTag,
    required this.maxFloor,
    required this.elapsedSeconds,
  });

  final String playerTag;
  final int maxFloor;
  final int elapsedSeconds;

  @override
  State<GameOverScreen> createState() => _GameOverScreenState();
}

class _GameOverScreenState extends State<GameOverScreen> {
  final LeaderboardService _svc = LeaderboardService();
  List<LeaderboardEntry>? _rows;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _svc.submitRun(
      playerTag: widget.playerTag,
      maxFloor: widget.maxFloor,
      elapsedSeconds: widget.elapsedSeconds,
    );
    final list = await _svc.fetchTop();
    if (mounted) {
      setState(() {
        _rows = list;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '게임 오버',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '도달 층: ${widget.maxFloor}층\n경과 시간: ${widget.elapsedSeconds}초',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.amber.shade200,
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '랭킹',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _rows == null || _rows!.isEmpty
                    ? const Center(
                        child: Text(
                          '랭킹을 불러올 수 없습니다.',
                          style: TextStyle(color: Colors.white54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _rows!.length,
                        itemBuilder: (context, i) {
                          final e = _rows![i];
                          return ListTile(
                            dense: true,
                            leading: Text(
                              '${i + 1}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            title: Text(
                              e.playerTag.isEmpty ? '(이름 없음)' : e.playerTag,
                              style: const TextStyle(color: Colors.white),
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Text(
                              '${e.maxFloor}F / ${e.elapsedSeconds}s',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          );
                        },
                      ),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop('retry'),
                child: const Text('다시하기 (광고)'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop('title'),
                child: const Text('타이틀로 돌아가기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
