import 'package:flutter/material.dart';

/// 10층 클리어 승리 팝업.
Future<void> showVictoryDialog(
  BuildContext context, {
  String? message,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => AlertDialog(
      title: const Text('승리'),
      content: Text(message ?? '10층을 모두 클리어했습니다!'),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('확인'),
        ),
      ],
    ),
  );
}
