// devicelab probe: shows what flutter-aera passes from AERA's saved settings
// (tw_military_time -> alwaysUse24HourFormat, aera_theme_accent -> stock
// dynamic_color's getAccentColor). Big text so a capture is easy to read.
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';

void main() => runApp(const Probe());

class Probe extends StatefulWidget {
  const Probe({super.key});
  @override
  State<Probe> createState() => _ProbeState();
}

class _ProbeState extends State<Probe> {
  Color? accent;
  String error = '';

  @override
  void initState() {
    super.initState();
    DynamicColorPlugin.getAccentColor().then(
      (c) => setState(() => accent = c),
      onError: (Object e) => setState(() => error = '$e'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final seed = accent ?? Colors.grey;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
      home: Builder(builder: (context) {
        final h24 = MediaQuery.alwaysUse24HourFormatOf(context);
        final time = MaterialLocalizations.of(context).formatTimeOfDay(
            const TimeOfDay(hour: 15, minute: 7),
            alwaysUse24HourFormat: h24);
        final hex = accent == null
            ? 'none'
            : (accent!.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0');
        const big = TextStyle(fontSize: 40, fontWeight: FontWeight.bold);
        return Scaffold(
          body: SafeArea(
            child: Column(children: [
              Expanded(child: Container(color: accent ?? Colors.black12)),
              Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Text('24h: $h24', style: big),
                  Text('15:07 -> $time', style: big),
                  Text('accent: $hex', style: big),
                  if (error.isNotEmpty) Text(error),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }
}
