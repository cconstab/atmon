import '../diff.dart';

class ProcInfo {
  final int pid;
  final String name;
  final String user;
  final double cpuPct;
  final int memMb;

  ProcInfo({
    required this.pid,
    required this.name,
    required this.user,
    required this.cpuPct,
    required this.memMb,
  });

  Map<String, dynamic> toJson() => {
        'pid': pid,
        'name': name,
        'user': user,
        'cpuPct': cpuPct,
        'memMb': memMb,
      };

  factory ProcInfo.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return ProcInfo(
      pid: (j['pid'] as num).toInt(),
      name: j['name'] as String,
      user: j['user'] as String,
      cpuPct: (j['cpuPct'] as num).toDouble(),
      memMb: (j['memMb'] as num).toInt(),
    );
  }
}

class ProcSnapshot {
  final List<ProcInfo> topByCpu;
  final DateTime sampledAt;

  ProcSnapshot({required this.topByCpu, required this.sampledAt});

  Map<String, dynamic> toJson() => {
        'topByCpu': topByCpu.map((p) => p.toJson()).toList(),
        'sampledAt': sampledAt.toUtc().toIso8601String(),
      };

  factory ProcSnapshot.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return ProcSnapshot(
      topByCpu: (j['topByCpu'] as List)
          .map(ProcInfo.fromJson)
          .toList(growable: false),
      sampledAt: DateTime.parse(j['sampledAt'] as String),
    );
  }

  /// Significant change: top-N membership/order changed, or any process's
  /// CPU% moved >= [cpuEpsilon].
  bool changedFrom(ProcSnapshot? other, {double cpuEpsilon = 5.0}) {
    if (other == null) return true;
    if (other.topByCpu.length != topByCpu.length) return true;
    for (var i = 0; i < topByCpu.length; i++) {
      if (topByCpu[i].pid != other.topByCpu[i].pid) return true;
      if (Diff.numChanged(topByCpu[i].cpuPct, other.topByCpu[i].cpuPct,
          epsilon: cpuEpsilon)) {
        return true;
      }
    }
    return false;
  }
}
