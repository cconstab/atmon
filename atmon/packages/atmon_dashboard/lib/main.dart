import 'dart:async';
import 'dart:io';

import 'package:at_cli_commons/at_cli_commons.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'services/atmon_client.dart';
import 'services/fleet_store.dart';
import 'ui/fleet_grid.dart';

void main(List<String> args) {
  runApp(AtmonApp(args: args));
}

class AtmonApp extends StatelessWidget {
  final List<String> args;
  const AtmonApp({super.key, required this.args});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'atmon',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0E1117),
        colorScheme: ColorScheme.dark(
          surface: const Color(0xFF161B22),
          primary: const Color(0xFF58A6FF),
        ),
      ),
      home: AtmonShell(args: args),
    );
  }
}

/// Top-level widget that manages onboarding → live dashboard state machine.
class AtmonShell extends StatefulWidget {
  final List<String> args;
  const AtmonShell({super.key, required this.args});
  @override
  State<AtmonShell> createState() => _AtmonShellState();
}

enum _Phase { configuring, connecting, running, error }

class _AtmonShellState extends State<AtmonShell> {
  _Phase _phase = _Phase.configuring;
  String _errorMsg = '';
  FleetStore? _store;
  AtmonClient? _client;
  StreamSubscription? _sub;
  final _atSignCtrl = TextEditingController();
  final _keysCtrl = TextEditingController();

  /// Returns the real user home directory. On macOS sandboxed apps, HOME is
  /// redirected to the container; we strip the sandbox suffix to recover the
  /// real home so ~/.atsign/keys/ can be found.
  String? _realHomeDir() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home == null) return null;
    // macOS sandbox path pattern: <realHome>/Library/Containers/<bundle>/Data
    final sandboxIdx = home.indexOf('/Library/Containers/');
    if (sandboxIdx > 0) return home.substring(0, sandboxIdx);
    return home;
  }

  @override
  void dispose() {
    _sub?.cancel();
    _client?.dispose();
    _atSignCtrl.dispose();
    _keysCtrl.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    setState(() => _phase = _Phase.connecting);
    try {
      final atsign = _atSignCtrl.text.trim();
      final keysFile = _keysCtrl.text.trim();
      if (atsign.isEmpty) {
        throw Exception('atSign is required.');
      }
      // CLIBase.fromCommandLineArgs hardcodes getHomeDirectory() and ignores
      // --home-dir, so on a sandboxed macOS app HOME points to the container.
      // We resolve the real home ourselves and always pass an explicit
      // --key-file path so CLIBase never has to guess.
      final resolvedKeyFile = keysFile.isNotEmpty
          ? keysFile
          : '${_realHomeDir()}/.atsign/keys/${atsign}_key.atKeys';
      final cliArgs = [
        '-a',
        atsign,
        '-n',
        'atmon.monitoring',
        '--never-sync',
        '--key-file',
        resolvedKeyFile,
      ];
      final cli = await CLIBase.fromCommandLineArgs(
        cliArgs,
        parser: CLIBase.createArgsParser(
          namespace: 'atmon.monitoring',
          addLegacyRootDomainArg: false,
        ),
      );
      final store = FleetStore();
      final client = AtmonClient(atClient: cli.atClient);
      await client.start();
      final sub = client.updates.listen((u) {
        store.apply(u);
      });
      if (!mounted) {
        sub.cancel();
        client.dispose();
        return;
      }
      setState(() {
        _store = store;
        _client = client;
        _sub = sub;
        _phase = _Phase.running;
      });
    } catch (e, st) {
      setState(() {
        _errorMsg = '$e\n$st';
        _phase = _Phase.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_phase) {
      _Phase.configuring || _Phase.error => _configScreen(),
      _Phase.connecting => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      _Phase.running => _dashboardScreen(),
    };
  }

  Widget _configScreen() {
    return Scaffold(
      body: Center(
        child: SizedBox(
          width: 400,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('atmon dashboard',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _atSignCtrl,
                    decoration: const InputDecoration(
                        labelText: 'atSign',
                        hintText: '@ops1',
                        border: OutlineInputBorder()),
                    onSubmitted: (_) => _connect(),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _keysCtrl,
                          decoration: const InputDecoration(
                              labelText: 'Keys file path (optional)',
                              hintText:
                                  'leave blank to use ~/.atsign/keys/ default',
                              border: OutlineInputBorder()),
                          onSubmitted: (_) => _connect(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Browse for .atKeys file',
                        child: IconButton.outlined(
                          icon: const Icon(Icons.folder_open),
                          onPressed: () async {
                            final result = await FilePicker.pickFiles(
                              type: FileType.any,
                              dialogTitle: 'Select your .atKeys file',
                            );
                            if (result != null &&
                                result.files.single.path != null) {
                              _keysCtrl.text = result.files.single.path!;
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _connect,
                    child: const Text('Connect'),
                  ),
                  if (_phase == _Phase.error) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.red.shade900,
                      child: SelectableText(
                        _errorMsg,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dashboardScreen() {
    final store = _store!;
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('atmon fleet'),
            actions: [
              Tooltip(
                message: 'Reconnect with a different atSign',
                child: IconButton(
                  icon: const Icon(Icons.logout),
                  onPressed: () {
                    _sub?.cancel();
                    _client?.dispose();
                    setState(() {
                      _store = null;
                      _client = null;
                      _sub = null;
                      _phase = _Phase.configuring;
                    });
                  },
                ),
              ),
            ],
          ),
          body: FleetGrid(store: store),
        );
      },
    );
  }
}
