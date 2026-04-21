/// Threshold + cadence configuration for one monitor atSign. Owned and
/// published by the dashboard, shared down to each agent atSign.
class MonitorConfig {
  final double cpuPct;
  final double memPct;
  final double swapPct;
  final double diskPct;
  final double loadAvgPerCore;
  final int sampleIntervalSec;
  final int heartbeatSec;
  final DateTime updatedAt;

  MonitorConfig({
    this.cpuPct = 90,
    this.memPct = 85,
    this.swapPct = 50,
    this.diskPct = 85,
    this.loadAvgPerCore = 1.5,
    this.sampleIntervalSec = 2,
    this.heartbeatSec = 30,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
        'cpuPct': cpuPct,
        'memPct': memPct,
        'swapPct': swapPct,
        'diskPct': diskPct,
        'loadAvgPerCore': loadAvgPerCore,
        'sampleIntervalSec': sampleIntervalSec,
        'heartbeatSec': heartbeatSec,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory MonitorConfig.fromJson(dynamic raw) {
    final j = (raw as Map).cast<String, dynamic>();
    return MonitorConfig(
      cpuPct: (j['cpuPct'] as num?)?.toDouble() ?? 90,
      memPct: (j['memPct'] as num?)?.toDouble() ?? 85,
      swapPct: (j['swapPct'] as num?)?.toDouble() ?? 50,
      diskPct: (j['diskPct'] as num?)?.toDouble() ?? 85,
      loadAvgPerCore: (j['loadAvgPerCore'] as num?)?.toDouble() ?? 1.5,
      sampleIntervalSec: (j['sampleIntervalSec'] as num?)?.toInt() ?? 2,
      heartbeatSec: (j['heartbeatSec'] as num?)?.toInt() ?? 30,
      updatedAt: DateTime.parse(j['updatedAt'] as String),
    );
  }

  static MonitorConfig defaults() =>
      MonitorConfig(updatedAt: DateTime.now().toUtc());
}
