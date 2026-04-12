import 'package:flutter/material.dart';

import 'leaderboard_service.dart';

/// 타이틀 등에서 열리는 랭킹 전용 화면.
class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  final LeaderboardService _svc = LeaderboardService();
  List<LeaderboardEntry>? _rows;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
      appBar: AppBar(title: const Text('랭킹')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _rows == null || _rows!.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('기록이 없거나 Firebase에 연결되지 않았습니다.')),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _rows!.length,
                      itemBuilder: (context, i) {
                        final e = _rows![i];
                        return Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Text('${i + 1}')),
                            title: Text(
                              e.playerTag.isEmpty ? '(이름 없음)' : e.playerTag,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${e.maxFloor}층 · ${e.elapsedSeconds}초',
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
