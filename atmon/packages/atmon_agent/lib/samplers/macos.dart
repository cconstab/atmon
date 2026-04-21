import 'dart:convert';
import 'dart:io';

import 'package:atmon_models/atmon_models.dart';

import 'sampler.dart';

/// macOS samplers — development convenience only. They shell out to standard
/// system tools (top, vm_stat, df, netstat, sysctl) and convert the output
/// into atmon model objects. Production targets Linux.

class MacCpuSampler implements Sampler<CpuStats> {
  @override
  Future<CpuStats?> sample() async {
    // top -l 1 -n 0 prints CPU usage line. Faster than top -l 2.
    final top = await runCmd('top', ['-l', '1', '-n', '0']);
    final loadCmd = await runCmd('sysctl', ['-n', 'vm.loadavg']);

    double mean = 0;
    final m =
        RegExp(r'CPU usage:\s+([\d.]+)% user,\s+([\d.]+)% sys').firstMatch(top);
    if (m != null) {
      final user = double.parse(m.group(1)!);
      final sys = double.parse(m.group(2)!);
      mean = Diff.round(user + sys);
    }

    final cores = await runCmd('sysctl', ['-n', 'hw.ncpu']);
    final n = int.tryParse(cores.trim()) ?? 1;
    // Without per-core stats from `top -l 1`, replicate the mean across cores.
    // It's not perfect — fine for a dev demo.
    final coreUsage = List<double>.filled(n, mean);

    final la = <double>[];
    final lm =
        RegExp(r'\{\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*\}').firstMatch(loadCmd);
    if (lm != null) {
      la.add(double.parse(lm.group(1)!));
      la.add(double.parse(lm.group(2)!));
      la.add(double.parse(lm.group(3)!));
    }

    return CpuStats(coreUsage: coreUsage, loadAvg: la, sampledAt: nowUtc());
  }
}

class MacMemSampler implements Sampler<MemStats> {
  @override
  Future<MemStats?> sample() async {
    final vm = await runCmd('vm_stat', const []);
    final hwMemRaw = await runCmd('sysctl', ['-n', 'hw.memsize']);
    final hwMemBytes = int.tryParse(hwMemRaw.trim()) ?? 0;
    final totalKb = hwMemBytes ~/ 1024;
    if (vm.isEmpty || totalKb == 0) return null;

    final pageSizeMatch = RegExp(r'page size of (\d+) bytes').firstMatch(vm);
    final pageSize = int.tryParse(pageSizeMatch?.group(1) ?? '4096') ?? 4096;
    int pages(String key) {
      final m = RegExp('$key:\\s+(\\d+)').firstMatch(vm);
      return m == null ? 0 : int.parse(m.group(1)!);
    }

    final free = pages('Pages free');
    final inactive = pages('Pages inactive');
    final speculative = pages('Pages speculative');
    final availPages = free + inactive + speculative;
    final availKb = (availPages * pageSize) ~/ 1024;

    // sysctl swap usage
    final swapRaw = await runCmd('sysctl', ['-n', 'vm.swapusage']);
    int swapTotalKb = 0, swapUsedKb = 0;
    final sm =
        RegExp(r'total = ([\d.]+)M.*used = ([\d.]+)M').firstMatch(swapRaw);
    if (sm != null) {
      swapTotalKb = (double.parse(sm.group(1)!) * 1024).toInt();
      swapUsedKb = (double.parse(sm.group(2)!) * 1024).toInt();
    }

    return MemStats(
      totalKb: totalKb,
      usedKb: totalKb - availKb,
      availKb: availKb,
      swapTotalKb: swapTotalKb,
      swapUsedKb: swapUsedKb,
      sampledAt: nowUtc(),
    );
  }
}

class MacDiskSampler implements Sampler<DiskStats> {
  @override
  Future<DiskStats?> sample() async {
    final out = await runCmd('df', ['-Pk']);
    if (out.isEmpty) return null;
    final lines = const LineSplitter().convert(out);
    final fs = <FilesystemStats>[];
    for (var i = 1; i < lines.length; i++) {
      final p = lines[i].split(RegExp(r'\s+'));
      if (p.length < 6) continue;
      // Skip system snapshots / /System volumes for clarity.
      if (p[5].startsWith('/System/Volumes')) continue;
      fs.add(FilesystemStats(
        mount: p[5],
        fsType: 'apfs',
        sizeKb: int.tryParse(p[1]) ?? 0,
        usedKb: int.tryParse(p[2]) ?? 0,
      ));
    }
    return DiskStats(filesystems: fs, sampledAt: nowUtc());
  }
}

class MacNetSampler implements Sampler<NetStats> {
  Map<String, _IfaceTick> _last = {};
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<NetStats?> sample() async {
    final out = await runCmd('netstat', ['-ibn']);
    if (out.isEmpty) return null;
    final now = nowUtc();
    final dtSec = _lastAt.millisecondsSinceEpoch == 0
        ? 1.0
        : (now.difference(_lastAt).inMilliseconds / 1000).clamp(0.001, 60);

    final ticks = <String, _IfaceTick>{};
    final lines = const LineSplitter().convert(out);
    for (var i = 1; i < lines.length; i++) {
      final p = lines[i].trim().split(RegExp(r'\s+'));
      // We only want one row per interface (the link rows show <Link#N>).
      if (p.length < 10) continue;
      if (!p[2].startsWith('<Link')) continue;
      final name = p[0];
      if (name == 'lo0') continue;
      final ipkts = int.tryParse(p[4]) ?? 0;
      final ibytes = int.tryParse(p[6]) ?? 0;
      final opkts = int.tryParse(p[7]) ?? 0;
      final obytes = int.tryParse(p[9]) ?? 0;
      final ierrs = int.tryParse(p[5]) ?? 0;
      ticks[name] = _IfaceTick(
        rxBytes: ibytes,
        txBytes: obytes,
        errors: ierrs,
        // ignore: unused_field
        ipkts: ipkts,
        opkts: opkts,
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
  // ignore: unused_field
  final int ipkts;
  // ignore: unused_field
  final int opkts;
  _IfaceTick({
    required this.rxBytes,
    required this.txBytes,
    required this.errors,
    required this.ipkts,
    required this.opkts,
  });
}

class MacProcSampler implements Sampler<ProcSnapshot> {
  final int topN;
  MacProcSampler({this.topN = 10});

  @override
  Future<ProcSnapshot?> sample() async {
    final out = await runCmd('ps', ['-Ao', 'pid,user,pcpu,rss,comm', '-r']);
    if (out.isEmpty) return null;
    final lines = const LineSplitter().convert(out).skip(1);
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

class MacHostSampler implements Sampler<HostInfo> {
  final String agentVersion;
  MacHostSampler({required this.agentVersion});

  @override
  Future<HostInfo?> sample() async {
    final hostname = Platform.localHostname;
    final uname = await runCmd('uname', ['-sr']);
    final cpuModel =
        (await runCmd('sysctl', ['-n', 'machdep.cpu.brand_string'])).trim();
    final cpuCount =
        int.tryParse((await runCmd('sysctl', ['-n', 'hw.ncpu'])).trim()) ?? 1;
    final memBytes =
        int.tryParse((await runCmd('sysctl', ['-n', 'hw.memsize'])).trim()) ??
            0;
    final boottimeRaw =
        (await runCmd('sysctl', ['-n', 'kern.boottime'])).trim();
    final btMatch = RegExp(r'sec = (\d+)').firstMatch(boottimeRaw);
    final bootEpoch = int.tryParse(btMatch?.group(1) ?? '0') ?? 0;
    final boot =
        DateTime.fromMillisecondsSinceEpoch(bootEpoch * 1000, isUtc: true);
    final uptimeSec = nowUtc().difference(boot).inSeconds;
    final unameParts = uname.trim().split(RegExp(r'\s+'));
    return HostInfo(
      hostname: hostname,
      os: unameParts.isNotEmpty ? unameParts[0] : 'Darwin',
      kernel: unameParts.length > 1 ? unameParts[1] : '',
      cpuCount: cpuCount,
      cpuModel: cpuModel,
      totalMemKb: memBytes ~/ 1024,
      uptimeSec: uptimeSec,
      bootTime: boot,
      agentVersion: agentVersion,
      sampledAt: nowUtc(),
    );
  }
}
