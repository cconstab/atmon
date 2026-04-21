import 'dart:convert';
import 'dart:io';

import 'package:atmon_models/atmon_models.dart';

import 'sampler.dart';

/// Linux CPU sampler that parses `/proc/stat` between two ticks for
/// per-core usage and reads `/proc/loadavg` for load averages.
class LinuxCpuSampler implements Sampler<CpuStats> {
  Map<int, _CpuTick> _last = {};

  @override
  Future<CpuStats?> sample() async {
    final stat = await readFileSafe('/proc/stat');
    final loadAvg = await readFileSafe('/proc/loadavg');
    if (stat.isEmpty) return null;

    final ticks = <int, _CpuTick>{};
    for (final line in const LineSplitter().convert(stat)) {
      if (!line.startsWith('cpu')) break; // cpu lines are first
      if (line.startsWith('cpu ')) continue; // aggregate
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 8) continue;
      final id = int.tryParse(parts[0].substring(3));
      if (id == null) continue;
      final user = int.parse(parts[1]);
      final nice = int.parse(parts[2]);
      final system = int.parse(parts[3]);
      final idle = int.parse(parts[4]);
      final iowait = int.parse(parts[5]);
      final irq = int.parse(parts[6]);
      final softirq = int.parse(parts[7]);
      final steal = parts.length > 8 ? int.parse(parts[8]) : 0;
      final total =
          user + nice + system + idle + iowait + irq + softirq + steal;
      final idleAll = idle + iowait;
      ticks[id] = _CpuTick(total: total, idle: idleAll);
    }

    final cores = <double>[];
    for (final id in ticks.keys.toList()..sort()) {
      final cur = ticks[id]!;
      final prev = _last[id];
      if (prev == null) {
        cores.add(0);
      } else {
        final dt = cur.total - prev.total;
        final di = cur.idle - prev.idle;
        if (dt <= 0) {
          cores.add(0);
        } else {
          cores.add(Diff.round(((dt - di) / dt) * 100));
        }
      }
    }
    _last = ticks;

    final la = <double>[];
    if (loadAvg.isNotEmpty) {
      final p = loadAvg.split(RegExp(r'\s+'));
      for (var i = 0; i < 3 && i < p.length; i++) {
        final v = double.tryParse(p[i]);
        if (v != null) la.add(v);
      }
    }

    return CpuStats(
      coreUsage: cores,
      loadAvg: la,
      sampledAt: nowUtc(),
    );
  }
}

class _CpuTick {
  final int total;
  final int idle;
  _CpuTick({required this.total, required this.idle});
}

class LinuxMemSampler implements Sampler<MemStats> {
  @override
  Future<MemStats?> sample() async {
    final s = await readFileSafe('/proc/meminfo');
    if (s.isEmpty) return null;
    int parse(String key) {
      final m = RegExp('^$key:\\s+(\\d+)', multiLine: true).firstMatch(s);
      return m == null ? 0 : int.parse(m.group(1)!);
    }

    final total = parse('MemTotal');
    final avail = parse('MemAvailable');
    final swapTotal = parse('SwapTotal');
    final swapFree = parse('SwapFree');
    return MemStats(
      totalKb: total,
      usedKb: total - avail,
      availKb: avail,
      swapTotalKb: swapTotal,
      swapUsedKb: swapTotal - swapFree,
      sampledAt: nowUtc(),
    );
  }
}

class LinuxDiskSampler implements Sampler<DiskStats> {
  @override
  Future<DiskStats?> sample() async {
    final out = await runCmd('df', ['-PkT']);
    if (out.isEmpty) return null;
    final lines = const LineSplitter().convert(out);
    final fs = <FilesystemStats>[];
    for (var i = 1; i < lines.length; i++) {
      final p = lines[i].split(RegExp(r'\s+'));
      if (p.length < 7) continue;
      // Skip pseudo / overlay file systems for clarity.
      const skip = {
        'tmpfs',
        'devtmpfs',
        'overlay',
        'squashfs',
        'proc',
        'sysfs'
      };
      if (skip.contains(p[1])) continue;
      fs.add(FilesystemStats(
        mount: p[6],
        fsType: p[1],
        sizeKb: int.tryParse(p[2]) ?? 0,
        usedKb: int.tryParse(p[3]) ?? 0,
      ));
    }
    return DiskStats(filesystems: fs, sampledAt: nowUtc());
  }
}

class LinuxNetSampler implements Sampler<NetStats> {
  Map<String, _IfaceTick> _last = {};
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<NetStats?> sample() async {
    final s = await readFileSafe('/proc/net/dev');
    if (s.isEmpty) return null;
    final now = nowUtc();
    final dtSec = _lastAt.millisecondsSinceEpoch == 0
        ? 1.0
        : (now.difference(_lastAt).inMilliseconds / 1000).clamp(0.001, 60);

    final ticks = <String, _IfaceTick>{};
    final lines = const LineSplitter().convert(s);
    for (var i = 2; i < lines.length; i++) {
      final m = RegExp(r'^\s*([^:]+):\s*(.*)$').firstMatch(lines[i]);
      if (m == null) continue;
      final name = m.group(1)!.trim();
      if (name == 'lo') continue;
      final p = m
          .group(2)!
          .trim()
          .split(RegExp(r'\s+'))
          .map((e) => int.tryParse(e) ?? 0)
          .toList();
      if (p.length < 16) continue;
      ticks[name] = _IfaceTick(
        rxBytes: p[0],
        txBytes: p[8],
        errors: p[2] + p[10],
      );
    }

    final ifaces = <IfaceStats>[];
    for (final e in ticks.entries) {
      final prev = _last[e.key];
      if (prev == null) {
        ifaces.add(IfaceStats(
            name: e.key, rxKbps: 0, txKbps: 0, errors: e.value.errors));
      } else {
        ifaces.add(IfaceStats(
          name: e.key,
          rxKbps: Diff.round((e.value.rxBytes - prev.rxBytes) / 1024 / dtSec),
          txKbps: Diff.round((e.value.txBytes - prev.txBytes) / 1024 / dtSec),
          errors: e.value.errors,
        ));
      }
    }
    _last = ticks;
    _lastAt = now;
    return NetStats(ifaces: ifaces, sampledAt: now);
  }
}

class _IfaceTick {
  final int rxBytes;
  final int txBytes;
  final int errors;
  _IfaceTick(
      {required this.rxBytes, required this.txBytes, required this.errors});
}

/// Read top-N processes via `ps`. Going via `/proc/<pid>/stat` would be more
/// efficient, but `ps` is universally available and a few hundred lines per
/// sample is fine for a demo agent.
class LinuxProcSampler implements Sampler<ProcSnapshot> {
  final int topN;
  LinuxProcSampler({this.topN = 10});

  @override
  Future<ProcSnapshot?> sample() async {
    final out = await runCmd('ps',
        ['-eo', 'pid,user,pcpu,rss,comm', '--sort=-pcpu', '--no-headers']);
    if (out.isEmpty) return null;
    final lines = const LineSplitter().convert(out);
    final procs = <ProcInfo>[];
    for (final line in lines.take(topN)) {
      final p = line.trim().split(RegExp(r'\s+'));
      if (p.length < 5) continue;
      procs.add(ProcInfo(
        pid: int.tryParse(p[0]) ?? 0,
        user: p[1],
        cpuPct: double.tryParse(p[2]) ?? 0,
        memMb: ((int.tryParse(p[3]) ?? 0) ~/ 1024),
        name: p.sublist(4).join(' '),
      ));
    }
    return ProcSnapshot(topByCpu: procs, sampledAt: nowUtc());
  }
}

class LinuxHostSampler implements Sampler<HostInfo> {
  final String agentVersion;
  LinuxHostSampler({required this.agentVersion});

  @override
  Future<HostInfo?> sample() async {
    final hostname = Platform.localHostname;
    final uname = await runCmd('uname', ['-sr']);
    final cpuInfo = await readFileSafe('/proc/cpuinfo');
    final mem = await readFileSafe('/proc/meminfo');
    final upStr = await readFileSafe('/proc/uptime');
    final uptimeSec =
        double.tryParse(upStr.split(RegExp(r'\s+')).first)?.toInt() ?? 0;
    final boot = nowUtc().subtract(Duration(seconds: uptimeSec));

    String cpuModel = '';
    int cpuCount = 0;
    final m = RegExp(r'model name\s*:\s*(.+)').firstMatch(cpuInfo);
    if (m != null) cpuModel = m.group(1)!.trim();
    cpuCount =
        RegExp(r'^processor\s*:', multiLine: true).allMatches(cpuInfo).length;

    int totalMemKb = 0;
    final mm = RegExp(r'MemTotal:\s+(\d+)').firstMatch(mem);
    if (mm != null) totalMemKb = int.parse(mm.group(1)!);

    final unameParts = uname.trim().split(RegExp(r'\s+'));
    return HostInfo(
      hostname: hostname,
      os: unameParts.isNotEmpty ? unameParts[0] : 'Linux',
      kernel: unameParts.length > 1 ? unameParts[1] : '',
      cpuCount: cpuCount,
      cpuModel: cpuModel,
      totalMemKb: totalMemKb,
      uptimeSec: uptimeSec,
      bootTime: boot,
      agentVersion: agentVersion,
      sampledAt: nowUtc(),
    );
  }
}
