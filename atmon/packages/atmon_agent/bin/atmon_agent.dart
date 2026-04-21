import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:at_client/at_client.dart';
import 'package:atmon_models/atmon_models.dart';

import 'package:atmon_agent/publisher.dart';
import 'package:atmon_agent/rules.dart';
import 'package:atmon_agent/samplers/linux.dart';
import 'package:atmon_agent/samplers/macos.dart';
import 'package:atmon_agent/samplers/sampler.dart';

const String kAgentVersion = '0.1.0';
const int kMaxDevicesPerAgent = 25;

/// Wires up one set of samplers + publishers for a single `deviceId`. Usually
/// an agent process runs many of these in parallel when `--device-id` is
/// repeated.
class DeviceAgent {
  final AtClient atClient;
  final String deviceId;
  final List<String> monitors;

  late final Sampler<CpuStats> _cpu;
  late final Sampler<MemStats> _mem;
  late final Sampler<DiskStats> _disk;
  late final Sampler<NetStats> _net;
  late final Sampler<ProcSnapshot> _procs;
  late final Sampler<HostInfo> _host;

  late final Publisher<CpuStats> _cpuPub;
  late final Publisher<MemStats> _memPub;
  late final Publisher<DiskStats> _diskPub;
  late final Publisher<NetStats> _netPub;
  late final Publisher<ProcSnapshot> _procPub;
  late final Publisher<HostInfo> _hostPub;
  late final Publisher<AlertList> _alertPub;

  final AlertEngine _engine = AlertEngine();
  final MonitorConfig _config = MonitorConfig.defaults();
  AlertList? _lastAlerts;

  DeviceAgent({
    required this.atClient,
    required this.deviceId,
    required this.monitors,
  }) {
    _cpu = samplerFor(LinuxCpuSampler(), MacCpuSampler());
    _mem = samplerFor(LinuxMemSampler(), MacMemSampler());
    _disk = samplerFor(LinuxDiskSampler(), MacDiskSampler());
    _net = samplerFor(LinuxNetSampler(), MacNetSampler());
    _procs = samplerFor(LinuxProcSampler(), MacProcSampler());
    _host = samplerFor(
      LinuxHostSampler(agentVersion: kAgentVersion),
      MacHostSampler(agentVersion: kAgentVersion),
    );

    final ttl = Duration(seconds: _config.heartbeatSec * 3);
    AtCollection<X> col<X>(AtmonCategory c, [Duration? exp]) =>
        AtCollection<X>(atClient, c.namespace, exp ?? ttl);

    _cpuPub = Publisher<CpuStats>(
      collection: col<CpuStats>(AtmonCategory.cpu),
      typeName: AtmonCategory.cpu.typeName,
      itemId: deviceId,
      shareWith: monitors,
      heartbeatInterval: Duration(seconds: _config.heartbeatSec),
      shouldPublish: (prev, next) => next.changedFrom(prev),
    );
    _memPub = Publisher<MemStats>(
      collection: col<MemStats>(AtmonCategory.mem),
      typeName: AtmonCategory.mem.typeName,
      itemId: deviceId,
      shareWith: monitors,
      heartbeatInterval: Duration(seconds: _config.heartbeatSec),
      shouldPublish: (prev, next) => next.changedFrom(prev),
    );
    _diskPub = Publisher<DiskStats>(
      collection:
          col<DiskStats>(AtmonCategory.disk, const Duration(minutes: 15)),
      typeName: AtmonCategory.disk.typeName,
      itemId: deviceId,
      shareWith: monitors,
      heartbeatInterval: const Duration(minutes: 5),
      shouldPublish: (prev, next) => next.changedFrom(prev),
    );
    _netPub = Publisher<NetStats>(
      collection: col<NetStats>(AtmonCategory.net),
      typeName: AtmonCategory.net.typeName,
      itemId: deviceId,
      shareWith: monitors,
      heartbeatInterval: Duration(seconds: _config.heartbeatSec),
      shouldPublish: (prev, next) => next.changedFrom(prev),
    );
    _procPub = Publisher<ProcSnapshot>(
      collection: col<ProcSnapshot>(AtmonCategory.procs),
      typeName: AtmonCategory.procs.typeName,
      itemId: deviceId,
      shareWith: monitors,
      heartbeatInterval: Duration(seconds: _config.heartbeatSec * 2),
      shouldPublish: (prev, next) => next.changedFrom(prev),
    );
    _hostPub = Publisher<HostInfo>(
      collection:
          col<HostInfo>(AtmonCategory.host, const Duration(minutes: 15)),
      typeName: AtmonCategory.host.typeName,
      itemId: deviceId,
      shareWith: monitors,
      heartbeatInterval: const Duration(minutes: 5),
      shouldPublish: (prev, next) => next.changedFrom(prev),
    );
    _alertPub = Publisher<AlertList>(
      collection:
          col<AlertList>(AtmonCategory.alerts, const Duration(minutes: 15)),
      typeName: AtmonCategory.alerts.typeName,
      itemId: deviceId,
      shareWith: monitors,
      heartbeatInterval: const Duration(minutes: 5),
      shouldPublish: (prev, next) => next.changedFrom(prev),
    );
  }

  /// Run a single sampling tick: sample every metric, feed each publisher,
  /// evaluate alerts, and publish whatever changed.
  Future<void> tick() async {
    final results = await Future.wait<Object?>([
      _cpu.sample(),
      _mem.sample(),
      _disk.sample(),
      _net.sample(),
      _procs.sample(),
      _host.sample(),
    ]);
    final cpu = results[0] as CpuStats?;
    final mem = results[1] as MemStats?;
    final disk = results[2] as DiskStats?;
    final net = results[3] as NetStats?;
    final procs = results[4] as ProcSnapshot?;
    final host = results[5] as HostInfo?;

    await Future.wait<void>([
      if (cpu != null) _cpuPub.consider(cpu).then((_) {}),
      if (mem != null) _memPub.consider(mem).then((_) {}),
      if (disk != null) _diskPub.consider(disk).then((_) {}),
      if (net != null) _netPub.consider(net).then((_) {}),
      if (procs != null) _procPub.consider(procs).then((_) {}),
      if (host != null) _hostPub.consider(host).then((_) {}),
    ]);

    final alerts = _engine.evaluate(
      config: _config,
      cpu: cpu,
      mem: mem,
      disk: disk,
      previous: _lastAlerts,
      now: DateTime.now().toUtc(),
    );
    if (await _alertPub.consider(alerts)) {
      _lastAlerts = alerts;
    }
  }
}

Future<void> main(List<String> args) async {
  registerAtmonFactories();

  final parser = CLIBase.createArgsParser(
    namespace: kAtmonNamespace,
    hide: CLIBase.hideableArgs,
    addLegacyRootDomainArg: false,
  )
    ..addMultiOption('device-id',
        abbr: 'D',
        help: 'Device identifier (CItem.id). Repeat to run many devices '
            'behind this single agent atSign. Max $kMaxDevicesPerAgent.')
    ..addMultiOption('monitor',
        abbr: 'm',
        help: 'Dashboard atSign to share metrics with. Repeat for fan-out.',
        valueHelp: '@ops1')
    ..addOption('sample-sec',
        abbr: 'S', defaultsTo: '2', help: 'Seconds between samples.');

  try {
    final parsed = parser.parse(args);
    final deviceIds = (parsed['device-id'] as List<String>);
    final monitors = (parsed['monitor'] as List<String>);
    final sampleSec = int.parse(parsed['sample-sec'] as String);

    if (deviceIds.isEmpty) {
      stderr.writeln(
          'atmon_agent: at least one --device-id is required.\n\n${parser.usage}');
      exit(64);
    }
    if (deviceIds.length > kMaxDevicesPerAgent) {
      stderr.writeln('atmon_agent: too many --device-id values '
          '(${deviceIds.length} > max $kMaxDevicesPerAgent).');
      exit(64);
    }
    for (final id in deviceIds) {
      if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9_-]*$').hasMatch(id)) {
        stderr
            .writeln('atmon_agent: --device-id "$id" must match [a-zA-Z0-9_-]+ '
                '(no dots).');
        exit(64);
      }
    }
    if (monitors.isEmpty) {
      stderr.writeln(
          'atmon_agent: at least one --monitor is required.\n\n${parser.usage}');
      exit(64);
    }

    final cli = await CLIBase.fromCommandLineArgs(args, parser: parser);
    final atClient = cli.atClient;
    // The agent only writes; all get/scan calls inside AtCollection.put must
    // go to the remote server so they see keys written on previous runs.
    atClient.getPreferences()!.remoteLocalPref = RemoteLocalPref.remoteOnly;

    stdout.writeln('atmon_agent v$kAgentVersion');
    stdout.writeln(
        '  atsign=${atClient.getCurrentAtSign()} devices=$deviceIds monitors=$monitors');

    final devices = [
      for (final d in deviceIds)
        DeviceAgent(
          atClient: atClient,
          deviceId: d,
          monitors: monitors,
        )
    ];

    ProcessSignal.sigint.watch().listen((_) async {
      stdout.writeln('\natmon_agent: shutting down.');
      exit(0);
    });

    // Prime the sampler cache once, then start the periodic ticker. The first
    // tick has no delta so most samplers return zero for rates — that's fine;
    // the second tick lands within `sampleSec`.
    for (final d in devices) {
      await d.tick();
    }
    Timer.periodic(Duration(seconds: sampleSec), (_) async {
      for (final d in devices) {
        // ignore errors on a single tick — keep sampling.
        unawaited(d.tick());
      }
    });
  } on ArgParserException catch (e) {
    stderr.writeln(e.message);
    stderr.writeln(parser.usage);
    exit(64);
  }
}
