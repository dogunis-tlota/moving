class PlayerIdentity {
  PlayerIdentity({
    required this.countryCode,
    required this.displayName,
    required this.ip,
  });

  final String countryCode;
  final String displayName;
  final String ip;

  Map<String, dynamic> toMap() {
    return {
      'countryCode': countryCode,
      'displayName': displayName,
      'ip': ip,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
  }
}
