import 'package:atmon_models/atmon_models.dart';

/// Pure alert engine. Given the most-recent set of model samples and the
/// active threshold [MonitorConfig], returns the current list of alerts with
/// stable `id`s so the dashboard can diff them. Alert `since` timestamps are
/// carried forward from a prior [AlertList] when the id is already active.
class AlertEngine {
  AlertList evaluate({
    required MonitorConfig config,
    required CpuStats? cpu,
    required MemStats? mem,
    required DiskStats? disk,
    AlertList? previous,
    required DateTime now,
  }) {
    final prevById = <String, Alert>{
      for (final a in (previous?.active ?? const <Alert>[])) a.id: a,
    };
    final out = <Alert>[];

    void add({
      required String id,
      required Severity sev,
      required String metric,
      required double value,
      required double threshold,
      required String message,
    }) {
      final since = prevById[id]?.since ?? now;
      out.add(Alert(
        id: id,
        severity: sev,
        metric: metric,
        value: value,
        threshold: threshold,
        message: message,
        since: since,
      ));
    }

    if (cpu != null) {
      if (cpu.maxCore >= config.cpuPct) {
        add(
          id: 'cpu.high',
          sev: cpu.maxCore >= (config.cpuPct + 5)
              ? Severity.crit
              : Severity.warn,
          metric: 'cpu.maxCore',
          value: cpu.maxCore,
          threshold: config.cpuPct,
          message: 'CPU usage ${cpu.maxCore.toStringAsFixed(1)}% '
              '>= ${config.cpuPct.toStringAsFixed(0)}%',
        );
      }
      if (cpu.loadAvg.isNotEmpty &&
          cpu.coreUsage.isNotEmpty &&
          cpu.loadAvg.first >= cpu.coreUsage.length * config.loadAvgPerCore) {
        add(
          id: 'load.high',
          sev: Severity.warn,
          metric: 'loadAvg.1m',
          value: cpu.loadAvg.first,
          threshold: cpu.coreUsage.length * config.loadAvgPerCore,
          message: '1-minute load average ${cpu.loadAvg.first} '
              '>= ${(cpu.coreUsage.length * config.loadAvgPerCore).toStringAsFixed(1)}',
        );
      }
    }

    if (mem != null) {
      if (mem.usedPct >= config.memPct) {
        add(
          id: 'mem.high',
          sev: mem.usedPct >= (config.memPct + 10)
              ? Severity.crit
              : Severity.warn,
          metric: 'mem.usedPct',
          value: mem.usedPct,
          threshold: config.memPct,
          message: 'Memory usage ${mem.usedPct.toStringAsFixed(1)}% '
              '>= ${config.memPct.toStringAsFixed(0)}%',
        );
      }
      if (mem.swapTotalKb > 0 && mem.swapUsedPct >= config.swapPct) {
        add(
          id: 'swap.high',
          sev: Severity.warn,
          metric: 'swap.usedPct',
          value: mem.swapUsedPct,
          threshold: config.swapPct,
          message: 'Swap usage ${mem.swapUsedPct.toStringAsFixed(1)}% '
              '>= ${config.swapPct.toStringAsFixed(0)}%',
        );
      }
    }

    if (disk != null) {
      for (final fs in disk.filesystems) {
        if (fs.usedPct >= config.diskPct) {
          add(
            id: 'disk.full.${fs.mount}',
            sev: fs.usedPct >= (config.diskPct + 5)
                ? Severity.crit
                : Severity.warn,
            metric: 'disk.usedPct',
            value: fs.usedPct,
            threshold: config.diskPct,
            message: '${fs.mount} is ${fs.usedPct.toStringAsFixed(1)}% full',
          );
        }
      }
    }

    return AlertList(active: out, sampledAt: now);
  }
}
