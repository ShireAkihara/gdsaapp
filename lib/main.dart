import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Server yang sama dengan setting "server-url" di mod.json
const kServer = 'https://gdsa.marvelanggara1209.workers.dev';

const bg = Color(0xFF15131F);
const panel = Color(0xFF1F1B2E);
const gold = Color(0xFFF2B84B);
const mute = Color(0xFF9A93B5);

class Session {
  final String token, username;
  final int accountId;
  Session(this.token, this.username, this.accountId);
}

class Api {
  static Future<Session> login(String code) async {
    final r = await http.post(Uri.parse('$kServer/app/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code.trim()}));
    final j = jsonDecode(r.body);
    if (r.statusCode != 200) throw j['error'] ?? 'Login gagal (${r.statusCode})';
    return Session(j['token'], j['username'], j['accountID']);
  }

  static Future<List<dynamic>> board(String region, String mode) async {
    final r = await http.get(Uri.parse(
        '$kServer/leaderboard?region=$region&mode=$mode&limit=100'));
    if (r.statusCode != 200) throw 'Gagal memuat leaderboard (${r.statusCode})';
    return jsonDecode(r.body)['entries'];
  }

  static Future<Map<String, dynamic>> me(String token) async {
    final r = await http.get(Uri.parse('$kServer/me'),
        headers: {'Authorization': 'Bearer $token'});
    if (r.statusCode == 401) throw 'expired';
    if (r.statusCode != 200) throw 'Gagal memuat profil';
    return jsonDecode(r.body);
  }
}

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'GDSA Ranked',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: const ColorScheme.dark(primary: gold, surface: panel),
          useMaterial3: true,
        ),
        home: const Gate(),
      );
}

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> {
  Session? s;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      final t = p.getString('token');
      if (t != null) {
        s = Session(t, p.getString('username') ?? '', p.getInt('aid') ?? 0);
      }
      setState(() => loading = false);
    });
  }

  Future<void> setSession(Session? n) async {
    final p = await SharedPreferences.getInstance();
    if (n == null) {
      await p.clear();
    } else {
      await p.setString('token', n.token);
      await p.setString('username', n.username);
      await p.setInt('aid', n.accountId);
    }
    setState(() => s = n);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return s == null
        ? LoginPage(onDone: setSession)
        : Home(session: s!, onLogout: () => setSession(null));
  }
}

class LoginPage extends StatefulWidget {
  final Future<void> Function(Session) onDone;
  const LoginPage({super.key, required this.onDone});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final c = TextEditingController();
  bool busy = false;
  String? err;

  Future<void> go() async {
    setState(() { busy = true; err = null; });
    try {
      await widget.onDone(await Api.login(c.text));
    } catch (e) {
      setState(() => err = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('GDSA Ranked',
                    style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: gold)),
                const SizedBox(height: 8),
                const Text('Masuk dengan akun Geometry Dash kamu.',
                    style: TextStyle(color: mute, fontSize: 15)),
                const SizedBox(height: 24),
                const Text(
                    '1. Buka GD, lalu buka pengaturan mod GDSA Ranked\n'
                    '2. Tekan "Link App" dan salin kode 6 karakter\n'
                    '3. Tempel kodenya di bawah',
                    style: TextStyle(height: 1.6)),
                const SizedBox(height: 20),
                TextField(
                  controller: c,
                  maxLength: 6,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(fontSize: 26, letterSpacing: 8),
                  decoration: InputDecoration(
                    hintText: 'ABC123',
                    filled: true,
                    fillColor: panel,
                    counterText: '',
                    errorText: err,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  onSubmitted: (_) => go(),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: gold, foregroundColor: Colors.black),
                    onPressed: busy ? null : go,
                    child: busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Masuk', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      );
}

class Home extends StatefulWidget {
  final Session session;
  final VoidCallback onLogout;
  const Home({super.key, required this.session, required this.onLogout});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  String region = 'global', mode = 'basic';
  late Future<List<dynamic>> f;
  late Future<Map<String, dynamic>> mine;

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    f = Api.board(region, mode);
    mine = Api.me(widget.session.token);
    mine.catchError((e) {
      if ('$e' == 'expired') widget.onLogout();
      return <String, dynamic>{};
    });
  }

  Widget seg(String a, String b, String v, void Function(String) on, String la, String lb) =>
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: [ButtonSegment(value: a, label: Text(la)), ButtonSegment(value: b, label: Text(lb))],
        selected: {v},
        onSelectionChanged: (x) => setState(() { on(x.first); reload(); }),
      );

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: bg,
          title: Text(widget.session.username, style: const TextStyle(fontWeight: FontWeight.w700)),
          actions: [
            IconButton(onPressed: () => setState(reload), icon: const Icon(Icons.refresh)),
            IconButton(onPressed: widget.onLogout, icon: const Icon(Icons.logout)),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(children: [
              FutureBuilder<Map<String, dynamic>>(
                future: mine,
                builder: (_, s) {
                  final d = s.data ?? {};
                  if (d.isEmpty) return const SizedBox(height: 8);
                  return Container(
                    margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(12)),
                    child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                      stat('Rank', '#${d['rank'] ?? '-'}'),
                      stat('MMR', '${d['mmr'] ?? '-'}'),
                      stat('Tier', '${d['tier'] ?? '-'}'),
                      stat('W/L', '${d['wins'] ?? 0}/${d['losses'] ?? 0}'),
                    ]),
                  );
                },
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(children: [
                  seg('global', 'id', region, (v) => region = v, 'Global', 'Indonesia'),
                  const Spacer(),
                  seg('basic', 'demon', mode, (v) => mode = v, 'Basic', 'Demon'),
                ]),
              ),
              Expanded(
                child: FutureBuilder<List<dynamic>>(
                  future: f,
                  builder: (_, s) {
                    if (s.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (s.hasError) {
                      return Center(child: Text('${s.error}\nTarik refresh untuk coba lagi.', textAlign: TextAlign.center));
                    }
                    final e = s.data!;
                    if (e.isEmpty) return const Center(child: Text('Belum ada pemain di leaderboard ini.'));
                    return RefreshIndicator(
                      onRefresh: () async { setState(reload); await f; },
                      child: ListView.builder(
                        itemCount: e.length,
                        itemBuilder: (_, i) {
                          final p = e[i];
                          final me = p['accountID'] == widget.session.accountId;
                          return Container(
                            color: me ? gold.withOpacity(0.12) : null,
                            child: ListTile(
                              leading: SizedBox(
                                width: 44,
                                child: Text('#${p['rank']}',
                                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16,
                                        color: i < 3 ? gold : mute)),
                              ),
                              title: Text('${p['username']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              subtitle: Text('${p['tier'] ?? ''}', style: const TextStyle(color: mute)),
                              trailing: Text('${p['mmr']}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      );

  Widget stat(String l, String v) => Column(children: [
        Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: gold)),
        Text(l, style: const TextStyle(color: mute, fontSize: 12)),
      ]);
}
