import 'package:flutter/material.dart';

import 'revive_manager.dart';

/// '부활하겠습니까?' (무료 부활이 있을 때만 예/아니오).
Future<bool> showReviveDialog(BuildContext context, ReviveManager revive) async {
  if (!revive.canReviveFree) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('부활'),
        content: const Text('남은 무료 부활이 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
    return false;
  }
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('부활'),
        content: Text(
          '부활하겠습니까?\n남은 무료 부활: ${revive.freeRevivesLeft}회',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('아니오'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('예'),
          ),
        ],
      );
    },
  );
  return ok == true;
}
