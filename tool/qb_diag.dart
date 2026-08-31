// qBittorrent connection diagnostic: walks the same path onboarding does,
// but prints the real error instead of the generic "unreachable".
//
//   dart run tool/qb_diag.dart <url> [username] [password]
import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:cupola/features/qbittorrent/data/qbittorrent_client.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/qb_diag.dart <url> [user] [pass]');
    exit(64);
  }
  final rawUrl = args[0];
  var user = args.length > 1 && args[1].isNotEmpty ? args[1] : null;
  var pass = args.length > 2 && args[2].isNotEmpty ? args[2] : null;

  // Credentials are asked for at runtime: they reach neither argv nor the
  // shell history.
  if (user == null) {
    stdout.write('username qBittorrent (invio = nessuna auth): ');
    final typed = stdin.readLineSync()?.trim() ?? '';
    user = typed.isEmpty ? null : typed;
  }
  if (user != null && pass == null) {
    stdout.write('password (non viene mostrata): ');
    stdin.echoMode = false;
    pass = stdin.readLineSync() ?? '';
    stdin.echoMode = true;
    stdout.writeln();
  }

  // 1. What the app's normaliser makes of the URL as typed.
  final client = QbittorrentClient(url: rawUrl, username: user, password: pass);
  stdout.writeln('input url        : $rawUrl');
  stdout.writeln('normalized base  : ${client.baseUrl}');
  stdout.writeln('has credentials  : ${client.hasCredentials}');
  if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
    stdout.writeln('!! nessuno schema nell\'URL -> l\'app ha assunto HTTPS');
  }
  stdout.writeln('');

  // 2. A raw login, no retry and no interceptor, to see status and body.
  final jar = CookieJar();
  final dio = Dio(
    BaseOptions(
      baseUrl: client.baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      validateStatus: (_) => true,
    ),
  )..interceptors.add(CookieManager(jar));

  Future<void> step(String label, Future<void> Function() body) async {
    final sw = Stopwatch()..start();
    try {
      await body();
    } on DioException catch (e) {
      stdout.writeln('$label -> DioException ${e.type}');
      stdout.writeln('  message: ${e.message}');
      stdout.writeln('  error  : ${e.error}');
    } catch (e) {
      stdout.writeln('$label -> ${e.runtimeType}: $e');
    } finally {
      stdout.writeln('  elapsed: ${sw.elapsedMilliseconds}ms\n');
    }
  }

  await step('GET /api/v2/app/version (senza login)', () async {
    final r = await dio.get('/api/v2/app/version');
    stdout.writeln('GET version (no auth) -> HTTP ${r.statusCode}: ${r.data}');
  });

  if (user != null) {
    await step('POST /api/v2/auth/login', () async {
      final r = await dio.post(
        '/api/v2/auth/login',
        data: {'username': user, 'password': pass},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'Referer': client.baseUrl, 'Origin': client.baseUrl},
        ),
      );
      stdout.writeln('POST login -> HTTP ${r.statusCode}: "${r.data}"');
      final setCookie = r.headers.map['set-cookie'] ?? const [];
      // The SID is a session token: log only its shape, never its value.
      stdout.writeln(
        '  set-cookie: ${setCookie.map((c) => c.split('=').first).toList()}'
        ' (${setCookie.length} cookie)',
      );
      final cookies = await jar.loadForRequest(Uri.parse(client.baseUrl));
      stdout.writeln('  cookie jar: ${cookies.map((c) => c.name).toList()}');
    });

    await step('GET /api/v2/app/version (dopo login)', () async {
      final r = await dio.get('/api/v2/app/version');
      stdout.writeln('GET version (auth) -> HTTP ${r.statusCode}: ${r.data}');
    });
  }

  // 3. The app's exact path: getVersion() on the onboarding timeout.
  await step(
    'QbittorrentClient.getVersion() [timeout 8s come onboarding]',
    () async {
      final v = await client.getVersion().timeout(const Duration(seconds: 8));
      stdout.writeln('app path -> versione: "$v"  => CONNECTED');
    },
  );

  client.close(force: true);
  dio.close(force: true);
  exit(0);
}
