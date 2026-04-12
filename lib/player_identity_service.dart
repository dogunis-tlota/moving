import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'player_identity.dart';

/// 공인 IP 기반 국가코드 조회 후 `KR_1234` 형태 이름 생성.
class PlayerIdentityService {
  static final Random _rng = Random();

  static Future<PlayerIdentity> resolve() async {
    String country = 'KR';
    String ip = '';
    try {
      final res = await http.get(Uri.parse('https://ipapi.co/json/'));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final cc = (body['country_code'] ?? '').toString().trim();
        if (cc.isNotEmpty) {
          country = cc.toUpperCase();
        }
        ip = (body['ip'] ?? '').toString();
      }
    } catch (_) {
      // 네트워크 실패 시 KR 기본값 유지
    }

    final num = 1000 + _rng.nextInt(9000);
    final name = '${country}_$num';
    return PlayerIdentity(countryCode: country, displayName: name, ip: ip);
  }
}
