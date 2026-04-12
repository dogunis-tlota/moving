import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../game_session.dart';
import 'network_session.dart';

class MultiplayerLobbyScreen extends StatefulWidget {
  const MultiplayerLobbyScreen({super.key, required this.session});

  final GameSession session;

  @override
  State<MultiplayerLobbyScreen> createState() => _MultiplayerLobbyScreenState();
}

class _MultiplayerLobbyScreenState extends State<MultiplayerLobbyScreen> {
  final TextEditingController _codeController = TextEditingController();
  bool _busy = false;
  bool _loadingRooms = false;
  String? _error;
  String? _createdCode;
  NetworkSession? _createdNet;
  /// true면 게임 화면으로 `NetworkSession`을 넘기며 나가는 중(방 유지).
  bool _pushedGameWithNet = false;
  List<String> _openRooms = [];

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      await _tryRestoreHostRoom();
      if (mounted) await _refreshRooms();
    });
  }

  /// 방 생성 직후 새로고침해도 같은 계정으로 방 코드를 다시 불러옴.
  Future<void> _tryRestoreHostRoom() async {
    try {
      final code = await NetworkSession.tryRestoreHostRoomCode();
      if (!mounted || code == null || code.isEmpty) return;
      final net = NetworkSession();
      final ok = await net.attachAsHost(
        roomCode: code,
        playerTag: widget.session.playerTag,
      );
      if (!mounted || !ok) {
        await net.dispose();
        return;
      }
      setState(() {
        _createdCode = code;
        _createdNet = net;
        _error = null;
      });
      await _refreshRooms();
    } catch (_) {
      // Firebase 미설정 등은 조용히 무시
    }
  }

  @override
  void dispose() {
    if (!_pushedGameWithNet) {
      final net = _createdNet;
      if (net != null) {
        unawaited(net.leave());
      }
    }
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _refreshRooms() async {
    if (!mounted) return;
    setState(() => _loadingRooms = true);
    try {
      final list = await NetworkSession.listRoomCodesFromDatabase();
      if (mounted) {
        setState(() {
          _openRooms = list;
          _loadingRooms = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingRooms = false;
          _error = '목록 불러오기 실패: $e';
        });
      }
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final net = NetworkSession();
      await net.createRoom(playerTag: widget.session.playerTag);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _createdCode = net.roomCode;
        _createdNet = net;
      });
      await _refreshRooms();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '방 생성 실패: $e';
        });
      }
    }
  }

  void _startCreatedGame() {
    final net = _createdNet;
    if (net == null) return;
    _pushedGameWithNet = true;
    Navigator.pop(context, net);
  }

  Future<void> _join() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = '방 코드를 입력하세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final net = NetworkSession();
      final ok = await net.joinRoom(code: code, playerTag: widget.session.playerTag);
      if (!ok) {
        if (mounted) {
          setState(() => _error = '입장 실패: 방이 없거나 이미 가득 찼습니다.');
        }
        await net.dispose();
        return;
      }
      if (!mounted) return;
      _pushedGameWithNet = true;
      Navigator.pop(context, net);
    } catch (e) {
      if (mounted) {
        setState(() => _error = '입장 실패: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _applyRoomCode(String code) {
    _codeController.text = code;
    setState(() {});
  }

  Widget _smallButton(String label, VoidCallback? onPressed) {
    return FilledButton.tonal(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('멀티플레이'), toolbarHeight: 44),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '코드를 상대에게 알려주세요. 아래에서 방을 만들거나, 개방된 방 코드로 입장할 수 있습니다.',
                style: TextStyle(fontSize: 14, height: 1.4),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, c) {
                  final narrow = c.maxWidth < 520;
                  final field = TextField(
                    controller: _codeController,
                    style: const TextStyle(fontSize: 13),
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: '방 코드 입력',
                      hintText: '예: ABC123',
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(),
                    ),
                  );
                  if (narrow) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(child: _smallButton('방 만들기', _busy ? null : _create)),
                            const SizedBox(width: 8),
                            Expanded(child: _smallButton('코드로 입장', _busy ? null : _join)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        field,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _smallButton('방 만들기', _busy ? null : _create),
                      const SizedBox(width: 8),
                      Expanded(child: field),
                      const SizedBox(width: 8),
                      _smallButton('코드로 입장', _busy ? null : _join),
                    ],
                  );
                },
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _loadingRooms ? null : _refreshRooms,
                  icon: _loadingRooms
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text('새로고침'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '데이터베이스 방 코드 (${_openRooms.length})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              if (_loadingRooms)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '불러오는 중…',
                    style: TextStyle(fontSize: 12),
                  ),
                )
              else if (_openRooms.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    '등록된 방 코드가 없습니다. 방 만들기로 새 방을 만드세요.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).hintColor,
                    ),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _openRooms.map((code) {
                    return ActionChip(
                      label: Text(code),
                      onPressed: () => _applyRoomCode(code),
                      tooltip: '입력칸에 넣기',
                    );
                  }).toList(),
                ),
              if (_createdCode != null) ...[
                const SizedBox(height: 16),
                SelectableText(
                  '내가 만든 방 코드: $_createdCode',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _createdNet == null ? null : _startCreatedGame,
                  child: const Text('게임 시작'),
                ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
