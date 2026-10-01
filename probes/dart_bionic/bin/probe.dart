// Prints one JSON object describing the process: who it runs as, what
// libc-dependent features work (DNS, temp dir, processes, isolates) and
// whether a loopback WebSocket round trip works. No dependencies, so the
// same file compiles with any Dart SDK, glibc or bionic.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

Future<Object?> attempt(Future<Object?> Function() f) async {
  final sw = Stopwatch()..start();
  try {
    final v = await f().timeout(const Duration(seconds: 10));
    return {'ok': true, 'value': v, 'ms': sw.elapsedMilliseconds};
  } catch (e) {
    return {'ok': false, 'error': '$e', 'ms': sw.elapsedMilliseconds};
  }
}

Future<void> main(List<String> args) async {
  final out = <String, Object?>{
    'os': Platform.operatingSystem,
    'osVersion': Platform.operatingSystemVersion,
    'dart': Platform.version,
    'executable': Platform.resolvedExecutable,
    'pid': pid,
    'env': {
      for (final k in ['PATH', 'TMPDIR', 'LD_LIBRARY_PATH', 'ANDROID_ROOT', 'HOME'])
        k: Platform.environment[k],
    },
  };
  out['selinux'] = await attempt(
      () async => File('/proc/self/attr/current').readAsStringSync().trim());
  out['status'] = await attempt(() async => File('/proc/self/status')
      .readAsLinesSync()
      .where((l) => l.startsWith('Uid') || l.startsWith('Gid'))
      .toList());
  out['tempDir'] = await attempt(() async {
    final d = Directory.systemTemp.createTempSync('probe');
    d.deleteSync();
    return d.path;
  });
  out['processRun'] = await attempt(() async {
    final r = await Process.run('/system/bin/sh', ['-c', 'id; getprop ro.build.fingerprint']);
    return {'exit': r.exitCode, 'stdout': '${r.stdout}'.trim(), 'stderr': '${r.stderr}'.trim()};
  });
  out['isolate'] = await attempt(() => Isolate.run(() => List.generate(1000, (i) => i).fold<int>(0, (a, b) => a + b)));
  out['dnsLocalhost'] = await attempt(() async =>
      (await InternetAddress.lookup('localhost')).map((a) => a.address).toList());
  out['dnsRemote'] = await attempt(() async =>
      (await InternetAddress.lookup('dart.dev')).map((a) => a.address).toList());
  out['loopbackWebSocket'] = await attempt(() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final ws = await WebSocketTransformer.upgrade(req);
      ws.listen(ws.add);
    });
    final sw = Stopwatch()..start();
    final ws = await WebSocket.connect('ws://127.0.0.1:${server.port}');
    final connectMs = sw.elapsedMilliseconds;
    final replies = StreamIterator(ws);
    final rtt = <int>[];
    for (var i = 0; i < 100; i++) {
      final t = sw.elapsedMicroseconds;
      ws.add('ping $i');
      if (!await replies.moveNext()) throw StateError('closed at $i');
      rtt.add(sw.elapsedMicroseconds - t);
    }
    rtt.sort();
    await ws.close();
    await server.close(force: true);
    return {'roundTrips': rtt.length, 'p50Us': rtt[50], 'maxUs': rtt.last, 'connectMs': connectMs};
  });
  // Termux:API listens on abstract-namespace sockets ('@' prefix in Dart).
  for (final name in ['@devicelab-probe-$pid', '${Directory.systemTemp.path}/devicelab-probe-$pid.sock']) {
    out[name.startsWith('@') ? 'unixAbstract' : 'unixPath'] = await attempt(() async {
      final addr = InternetAddress(name, type: InternetAddressType.unix);
      final server = await ServerSocket.bind(addr, 0);
      server.listen((c) => c.listen(c.add));
      final c = await Socket.connect(addr, 0);
      final replies = StreamIterator(c);
      c.add(utf8.encode('hello'));
      await replies.moveNext();
      final got = utf8.decode(replies.current);
      await c.close();
      await server.close();
      return got;
    });
  }
  stdout.writeln(jsonEncode(out));
  await stdout.flush();
  exit(0); // timed-out lookups would otherwise keep the VM alive
}
