// devicelab probe for AERA's pixel plugin lifecycle (flutter-aera 0021/0022):
// a counter that lists every app lifecycle state it sees and shows
// AERA_PLUGIN_DATA_VOLATILE. The lower half of the surface is the + button.
import 'dart:io';

import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Probe()));

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  int count = 0;
  final states = <String>[];
  late final AppLifecycleListener listener;
  final volatile = Platform.environment['AERA_PLUGIN_DATA_VOLATILE'] ?? 'unset';
  final data = Platform.environment['AERA_PLUGIN_DATA'] ?? 'unset';

  @override
  void initState() {
    super.initState();
    debugPrint('LIFECYCLE start pid=$pid VOLATILE=$volatile DATA=$data');
    listener = AppLifecycleListener(onStateChange: (s) {
      debugPrint('LIFECYCLE ${s.name} count=$count');
      setState(() => states.add(s.name));
    });
  }

  @override
  void dispose() {
    listener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('count: $count', style: const TextStyle(fontSize: 48)),
                Text('pid: $pid'),
                Text('VOLATILE: $volatile'),
                Text('DATA: $data'),
                Text('states: ${states.join(' > ')}'),
              ]),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 48),
              child: SizedBox.expand(
                child: FilledButton(
                  onPressed: () {
                    setState(() => count++);
                    debugPrint('LIFECYCLE tap count=$count');
                  },
                  child: const Text('+', style: TextStyle(fontSize: 64)),
                ),
              ),
            ),
          ),
        ]),
      );
}
