/// Mostly-static host info: hostname, OS, kernel, CPU model, agent version.
/// Re-published only when something changes (or once per heartbeat to keep
/// liveness via [sampledAt]).
class HostInfo {
  final String hostname;
  final String os;
  final String kernel;
  final int cpuCount;
  final String cpuModel;
  final int totalMemKb;
  final int uptimeSec;
  final DateTime bootTime;
  final String agentVersion;
  final DateTime sampledAt;

  HostInfo({
    required this.hostname,
    required this.os,
    required this.kernel,
    required this.cpuCount,
    required this.cpuModel,
    required this.totalMemKb,
    required this.uptimeSec,
    required this.bootTime,
    required this.agentVersion,
    required this.sampledAt,
  });

  Map<String, dynamic> toJson() => {
        'hostname': hostname,
        'os': os,
        'kernel': kernel,
        'cpuCount': cpuCount,
        'cpuModel': cpuModel,
        'totalMemKb': totalMemKb,
        'uptimeSec': uptimeSec,
        'bootTime': bootTime.toUtc().toIso8601String(),
        'agentVersion': agentVersion,
        'sampledAt': sampledAt.toUtc().toIso8601String(),
      };

  factory HostInfo.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return HostInfo(
      hostname: j['hostname'] as String,
      os: j['os'] as String,
      kernel: j['kernel'] as String,
      cpuCount: (j['cpuCount'] as num).toInt(),
      cpuModel: j['cpuModel'] as String,
      totalMemKb: (j['totalMemKb'] as num).toInt(),
      uptimeSec: (j['uptimeSec'] as num).toInt(),
      bootTime: DateTime.parse(j['bootTime'] as String),
      agentVersion: j['agentVersion'] as String,
      sampledAt: DateTime.parse(j['sampledAt'] as String),
    );
  }

  /// Significant change: anything except [uptimeSec] / [sampledAt] differs.
  bool changedFrom(HostInfo? other) {
    if (other == null) return true;
    return hostname != other.hostname ||
        os != other.os ||
        kernel != other.kernel ||
        cpuCount != other.cpuCount ||
        cpuModel != other.cpuModel ||
        totalMemKb != other.totalMemKb ||
        bootTime != other.bootTime ||
        agentVersion != other.agentVersion;
  }
}
