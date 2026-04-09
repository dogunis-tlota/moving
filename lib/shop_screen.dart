import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_session.dart';
import 'player_stats.dart';

/// 사방 나무벽 방 — 아이템 3종 중 1개만 선택 (탭 또는 1·2·3).
class ShopScreen extends StatefulWidget {
  const ShopScreen({super.key, required this.session});

  final GameSession session;

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  ShopItem? chosen;
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const wall = Color(0xFF6B4F3A);
    const floor = Color(0xFF4A3728);

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (chosen != null || event is! KeyDownEvent) {
          return KeyEventResult.ignored;
        }
        final k = event.logicalKey;
        if (k == LogicalKeyboardKey.digit1 || k == LogicalKeyboardKey.numpad1) {
          _pick(ShopItem.powerUp);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.digit2 || k == LogicalKeyboardKey.numpad2) {
          _pick(ShopItem.speedUp);
          return KeyEventResult.handled;
        }
        if (k == LogicalKeyboardKey.digit3 || k == LogicalKeyboardKey.numpad3) {
          _pick(ShopItem.heal);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        body: ColoredBox(
          color: floor,
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: wall, width: 24),
                  ),
                ),
              ),
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      '상점 — 하나만 선택 (1 · 2 · 3)',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 32),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      alignment: WrapAlignment.center,
                      children: [
                        _itemCard('1 · 파워업', '공격력 증가', ShopItem.powerUp),
                        _itemCard('2 · 이동속도업', '이동 빨라짐', ShopItem.speedUp),
                        _itemCard('3 · 체력회복', 'HP 가득', ShopItem.heal),
                      ],
                    ),
                    const SizedBox(height: 40),
                    TextButton(
                      onPressed: chosen == null ? () => Navigator.pop(context) : null,
                      child: const Text('나가기 (선택 없음)'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemCard(String label, String detail, ShopItem item) {
    final sel = chosen == item;
    return Material(
      color: sel ? Colors.amber.shade900 : Colors.brown.shade800,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: chosen == null ? () => _pick(item) : null,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 180,
          height: 120,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(detail, style: TextStyle(color: Colors.white.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _pick(ShopItem item) {
    if (chosen != null) return;
    setState(() => chosen = item);
    if (item == ShopItem.heal) {
      widget.session.pendingFullHeal = true;
    } else {
      widget.session.stats.applyShopItem(item);
    }
    Navigator.pop(context, item);
  }
}
