// devicelab probe for AERA's file picker (flutter-aera 0018/0019): four
// big buttons calling stock file_selector, and what each call returned.
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: Probe()));

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  final results = <String, String>{};

  Future<void> run(String name, Future<Object?> Function() call) async {
    setState(() => results[name] = '...');
    String text;
    try {
      final r = await call();
      text = switch (r) {
        null => 'null',
        XFile f => f.path,
        List<XFile> fs => fs.isEmpty ? '[]' : fs.map((f) => f.path).join(', '),
        FileSaveLocation l => l.path,
        _ => '$r',
      };
    } catch (e) {
      text = 'ERROR $e';
    }
    debugPrint('PICKER $name -> $text');
    setState(() => results[name] = text);
  }

  @override
  Widget build(BuildContext context) {
    final calls = <String, Future<Object?> Function()>{
      'openFile': () => openFile(),
      'openFiles': () => openFiles(),
      'getDirectoryPath': () => getDirectoryPath(),
      'getSaveLocation': () => getSaveLocation(suggestedName: 'lab-save.txt'),
    };
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          for (final e in calls.entries)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(80, 6, 80, 6),
                child: FilledButton(
                  onPressed: () => run(e.key, e.value),
                  child: Text(e.key, style: const TextStyle(fontSize: 26)),
                ),
              ),
            ),
          Expanded(
            flex: 2,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              for (final e in results.entries)
                Text('${e.key}: ${e.value}', style: const TextStyle(fontSize: 18)),
            ]),
          ),
        ]),
      ),
    );
  }
}
