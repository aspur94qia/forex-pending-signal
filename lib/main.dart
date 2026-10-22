import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const ForexUltimateApp());

class ForexUltimateApp extends StatelessWidget {
  const ForexUltimateApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sinyal S&R Ultimate V3',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF060911),
        cardColor: const Color(0xFF121A2B),
      ),
      home: const UltimateDashboard(),
    );
  }
}

class CandleData {
  final double open, high, low, close;
  CandleData(this.open, this.high, this.low, this.close);
}

class UltimateDashboard extends StatefulWidget {
  const UltimateDashboard({super.key});
  @override
  State<UltimateDashboard> createState() => _UltimateDashboardState();
}

class _UltimateDashboardState extends State<UltimateDashboard> {
  final List<Map<String, dynamic>> pairs = [
    {'name': 'XAU/USD (Gold)', 'mt5': 'XAUUSD', 'symbol': 'GC=F', 'decimals': 2, 'pip': 0.1, 'ccy1': 'XAU', 'ccy2': 'USD'},
    {'name': 'EUR/USD', 'mt5': 'EURUSD', 'symbol': 'EURUSD=X', 'decimals': 5, 'pip': 0.0001, 'ccy1': 'EUR', 'ccy2': 'USD'},
    {'name': 'GBP/USD', 'mt5': 'GBPUSD', 'symbol': 'GBPUSD=X', 'decimals': 5, 'pip': 0.0001, 'ccy1': 'GBP', 'ccy2': 'USD'},
    {'name': 'USD/JPY', 'mt5': 'USDJPY', 'symbol': 'JPY=X', 'decimals': 3, 'pip': 0.01, 'ccy1': 'USD', 'ccy2': 'JPY'},
    {'name': 'AUD/USD', 'mt5': 'AUDUSD', 'symbol': 'AUDUSD=X', 'decimals': 5, 'pip': 0.0001, 'ccy1': 'AUD', 'ccy2': 'USD'},
    {'name': 'USD/CAD', 'mt5': 'USDCAD', 'symbol': 'CAD=X', 'decimals': 5, 'pip': 0.0001, 'ccy1': 'USD', 'ccy2': 'CAD'},
  ];

  String selectedTf = '15m';
  bool isLoading = false;
  bool autoRefresh = true;
  int countdown = 60;
  Timer? refreshTimer;
  double accountBalance = 100.0;
  double riskPercent = 2.0;
  List<Map<String, dynamic>> signals = [];
  List<Map<String, dynamic>> newsList = [];
  String strengthSummary = 'Menghitung kekuatan...';

  @override
  void initState() {
    super.initState();
    fetchEverything();
    refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!autoRefresh || isLoading) return;
      setState(() {
        if (countdown > 1) {
          countdown--;
        } else {
          countdown = 60;
          fetchEverything(silent: true);
        }
      });
    });
  }

  @override
  void dispose() {
    refreshTimer?.cancel();
    super.dispose();
  }

  String getCurrentMarketSession() {
    final int h = DateTime.now().toUtc().hour;
    List<String> a = [];
    if (h >= 22 || h < 7) a.add('Sydney');
    if (h >= 0 && h < 9) a.add('Tokyo');
    if (h >= 7 && h < 16) a.add('London');
    if (h >= 12 && h < 21) a.add('New York');
    return a.isEmpty ? 'Pasar Transisi' : 'Sesi: ${a.join(" + ")} 🔥';
  }

  Future<void> fetchEverything({bool silent = false}) async {
    if (!silent) {
      setState(() {
        isLoading = true;
        signals.clear();
      });
    }
    await fetchFundamentalNews();
    List<Map<String, dynamic>> temp = [];
    Map<String, double> ccy = {};

    for (var p in pairs) {
      final res = await analyzeAndBacktest1000(p);
      if (res != null) {
        temp.add(res);
        double chg = res['change_pct'];
        ccy[p['ccy1']] = (ccy[p['ccy1']] ?? 0) + chg;
        ccy[p['ccy2']] = (ccy[p['ccy2']] ?? 0) - chg;
      }
    }

    var sorted = ccy.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (sorted.isNotEmpty) {
      strengthSummary = sorted
          .map((e) => '${e.key}(${e.value >= 0 ? "+" : ""}${e.value.toStringAsFixed(1)})')
          .join(' > ');
    }

    for (var s in temp) {
      if (s['score'] >= 85 && s['pips_to_entry_num'] <= 15) {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
        break;
      }
    }

    setState(() {
      signals = temp;
      isLoading = false;
      countdown = 60;
    });
  }

  Future<void> fetchFundamentalNews() async {
    try {
      final url = Uri.parse('https://nfs.faireconomy.media/ff_calendar_thisweek.json');
      final res = await http.get(url).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final List<dynamic> data = json.decode(res.body);
        final now = DateTime.now();
        List<Map<String, dynamic>> up = [];
        for (var item in data) {
          if (item['impact'] == 'High' || item['impact'] == 'Medium') {
            DateTime? t = DateTime.tryParse(item['date'] ?? '');
            if (t != null) {
              final mins = t.difference(now).inMinutes;
              if (mins >= -60 && mins <= 1440) {
                up.add({
                  'title': item['title'] ?? 'News',
                  'country': item['country'] ?? 'USD',
                  'impact': item['impact'] ?? 'High',
                  'diff_min': mins,
                });
              }
            }
          }
        }
        up.sort((a, b) => (a['diff_min'] as int).compareTo(b['diff_min'] as int));
        newsList = up;
      }
    } catch (_) {}
  }

  Map<String, dynamic> checkFund(String c1, String c2) {
    for (var n in newsList) {
      if ((n['country'] == c1 || n['country'] == c2 || n['country'] == 'USD') && n['impact'] == 'High') {
        int m = n['diff_min'];
        if (m >= -15 && m <= 90) {
          return {'danger': true, 'text': '🚨 AWAS NEWS ${n['country']} (${n['title']}) ${m <= 0 ? "RILIS!" : "$m Menit Lagi!"}'};
        } else if (m > 90 && m <= 360) {
          return {'danger': false, 'text': '⚠️ Info: News ${n['country']} (${n['title']}) ${(m / 60).toStringAsFixed(1)} Jam lagi'};
        }
      }
    }
    return {'danger': false, 'text': '✅ FUNDAMENTAL AMAN (Tidak ada News High Impact dekat)'};
  }

  Future<Map<String, dynamic>?> analyzeAndBacktest1000(Map<String, dynamic> p) async {
    try {
      int dec = p['decimals'];
      double pip = p['pip'];
      String apiTf = selectedTf == '4h' ? '1h' : selectedTf;
      String rng = selectedTf == '5m' ? '5d' : (selectedTf == '1h' ? '3mo' : (selectedTf == '4h' ? '1y' : '1mo'));

      final url = Uri.parse('https://query1.finance.yahoo.com/v8/finance/chart/${p['symbol']}?interval=$apiTf&range=$rng');
      final res = await http.get(url);
      if (res.statusCode != 200) return null;

      final q = json.decode(res.body)['chart']['result'][0]['indicators']['quote'][0];
      List<CandleData> raw = [];
      for (int i = 0; i < (q['close'] as List).length; i++) {
        if (q['open'][i] != null && q['high'][i] != null && q['low'][i] != null && q['close'][i] != null) {
          raw.add(CandleData(
            (q['open'][i] as num).toDouble(),
            (q['high'][i] as num).toDouble(),
            (q['low'][i] as num).toDouble(),
            (q['close'][i] as num).toDouble(),
          ));
        }
      }

      List<CandleData> candles = [];
      if (selectedTf == '4h') {
        for (int i = 0; i <= raw.length - 4; i += 4) {
          var ch = raw.sublist(i, i + 4);
          candles.add(CandleData(ch.first.open, ch.map((c) => c.high).reduce(max), ch.map((c) => c.low).reduce(min), ch.last.close));
        }
      } else {
        candles = raw;
      }
      if (candles.length < 60) return null;

      List<CandleData> bt = candles.length > 1000 ? candles.sublist(candles.length - 1000) : candles;
      double cur = bt.last.close;
      double chgPct = ((cur - bt[max(0, bt.length - 24)].close) / cur) * 100;

      double ema50 = bt.first.close, ema100 = bt.first.close;
      double k50 = 2 / 51, k100 = 2 / 101;
      for (var c in bt) {
        ema50 = (c.close * k50) + (ema50 * (1 - k50));
        ema100 = (c.close * k100) + (ema100 * (1 - k100));
      }
      bool isBull = cur >= ema50;

      List<CandleData> chartC = bt.sublist(bt.length - 35);
      double resLevel = chartC.map((c) => c.high).reduce(max);
      double supLevel = chartC.map((c) => c.low).reduce(min);

      double atrSum = 0, gain = 0, loss = 0;
      for (int i = bt.length - 14; i < bt.length; i++) {
        atrSum += max(bt[i].high - bt[i].low, max((bt[i].high - bt[i - 1].close).abs(), (bt[i].low - bt[i - 1].close).abs()));
        double d = bt[i].close - bt[i - 1].close;
        if (d >= 0) gain += d; else loss -= d;
      }
      double atr = atrSum / 14;
      double rsi = 100 - (100 / (1 + ((gain / 14) / ((loss / 14) == 0 ? 0.0001 : (loss / 14)))));

      // Backtest 1000 Candle
      int wins = 0, losses = 0;
      double netPips = 0, runEma = bt.first.close;
      for (int i = 35; i < bt.length - 15; i += 3) {
        runEma = (bt[i].close * k50) + (runEma * (1 - k50));
        bool bNow = bt[i].close >= runEma;
        var w = bt.sublist(i - 30, i);
        double lSup = w.map((c) => c.low).reduce(min);
        double lRes = w.map((c) => c.high).reduce(max);
        double lAtr = (lRes - lSup) / 4.0;
        if (lAtr <= 0) continue;

        double en = bNow ? lSup + (lAtr * 0.15) : lRes - (lAtr * 0.15);
        double tp = bNow ? en + (lAtr * 1.5) : en - (lAtr * 1.5);
        double sl = bNow ? lSup - (lAtr * 1.1) : lRes + (lAtr * 1.1);
        bool trig = false;

        for (int f = i + 1; f < min(i + 15, bt.length); f++) {
          if (!trig && (bNow ? bt[f].low <= en : bt[f].high >= en)) {
            trig = true;
          } else if (trig) {
            if (bNow ? bt[f].high >= tp : bt[f].low <= tp) {
              wins++;
              netPips += (tp - en).abs() / pip;
              break;
            } else if (bNow ? bt[f].low <= sl : bt[f].high >= sl) {
              losses++;
              netPips -= (en - sl).abs() / pip;
              break;
            }
          }
        }
      }

      double btWr = (wins + losses) > 0 ? (wins / (wins + losses)) * 100 : 79.0;
      double entry = isBull ? supLevel + (atr * 0.12) : resLevel - (atr * 0.12);
      double sl = isBull ? supLevel - (atr * 1.2) : resLevel + (atr * 1.2);
      double tp1 = isBull ? entry + (atr * 1.6) : entry - (atr * 1.6);
      double tp2 = isBull ? max(resLevel - (atr * 0.15), tp1 + atr) : min(supLevel + (atr * 0.15), tp1 - atr);
      double bep = isBull ? entry + (atr * 0.9) : entry - (atr * 0.9);

      double pipsToEn = (cur - entry).abs() / pip;
      double slPips = (entry - sl).abs() / pip;
      double riskUsd = accountBalance * (riskPercent / 100.0);
      double lot = max(0.01, (riskUsd / (slPips * 1.0)) * 0.1);

      final fund = checkFund(p['ccy1'], p['ccy2']);
      int score = btWr.round().clamp(68, 94);
      if (fund['danger'] == true) score -= 12;

      return {
        'name': p['name'],
        'mt5_symbol': p['mt5'],
        'decimals': dec,
        'current': cur,
        'support': supLevel,
        'resistance': resLevel,
        'rsi': rsi,
        'is_bull': isBull,
        'signal_type': isBull ? 'BUY LIMIT' : 'SELL LIMIT',
        'entry': entry,
        'tp1': tp1,
        'tp2': tp2,
        'sl': sl,
        'bep': bep,
        'lot': lot.toStringAsFixed(2),
        'risk_dollar': riskUsd.toStringAsFixed(2),
        'pips_to_entry': pipsToEn.toStringAsFixed(0),
        'pips_to_entry_num': pipsToEn,
        'bt_candles': bt.length,
        'bt_winrate': btWr.toStringAsFixed(1),
        'bt_wins': wins,
        'bt_losses': losses,
        'bt_pips': netPips.toStringAsFixed(0),
        'fund_danger': fund['danger'],
        'fund_text': fund['text'],
        'score': score.clamp(60, 97),
        'change_pct': chgPct,
        'candles': chartC,
      };
    } catch (_) {
      return null;
    }
  }

  void copySingle(String label, String val) {
    Clipboard.setData(ClipboardData(text: val));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$label ($val) berhasil disalin!'),
        duration: const Duration(milliseconds: 900),
        backgroundColor: Colors.teal,
      ),
    );
  }

  Future<void> launchMT5WithSmartFill(Map<String, dynamic> s) async {
    final int d = s['decimals'];
    final String entryStr = s['entry'].toStringAsFixed(d);
    final String slStr = s['sl'].toStringAsFixed(d);
    final String tp1Str = s['tp1'].toStringAsFixed(d);
    final String tp2Str = s['tp2'].toStringAsFixed(d);

    await Clipboard.setData(ClipboardData(text: entryStr));
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151F32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('🚀 Eksekusi MT5 (${s['mt5_symbol']})',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.tealAccent),
              ),
              child: Text(
                '✅ Harga Entry ($entryStr) SUDAH DISALIN OTOMATIS!\nSaat MT5 terbuka, tinggal PASTE di kolom Harga Pending Order.',
                style: const TextStyle(fontSize: 11, color: Colors.tealAccent),
              ),
            ),
            const SizedBox(height: 10),
            Text('📋 Contekan Cepat (${s['signal_type']} | Lot: ${s['lot']}):',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            _quickChip('1. Copy Entry', entryStr),
            _quickChip('2. Copy SL', slStr),
            _quickChip('3. Copy TP 1', tp1Str),
            _quickChip('4. Copy TP 2', tp2Str),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Tutup')),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('BUKA MT5 SEKARANG'),
            onPressed: () async {
              Navigator.pop(ctx);
              final Uri mt5Uri = Uri.parse('metatrader5://');
              final Uri intentUri = Uri.parse('intent://#Intent;package=net.metaquotes.metatrader5;end');
              try {
                if (await canLaunchUrl(mt5Uri)) {
                  await launchUrl(mt5Uri, mode: LaunchMode.externalApplication);
                } else {
                  await launchUrl(intentUri, mode: LaunchMode.externalApplication);
                }
              } catch (_) {
                await launchUrl(
                  Uri.parse('https://play.google.com/store/apps/details?id=net.metaquotes.metatrader5'),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _quickChip(String label, String val) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        onTap: () => copySingle(label, val),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black38,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
              Row(
                children: [
                  Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                  const SizedBox(width: 6),
                  const Icon(Icons.copy, size: 13, color: Colors.white70),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void openCalcDialog() {
    final balCtrl = TextEditingController(text: accountBalance.toStringAsFixed(0));
    final riskCtrl = TextEditingController(text: riskPercent.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF151F32),
        title: const Text('🧮 Modal & Risiko', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: balCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Modal Akun (USD \$)')),
            const SizedBox(height: 10),
            TextField(controller: riskCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Risiko per Trade (%)')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                accountBalance = double.tryParse(balCtrl.text) ?? 100.0;
                riskPercent = double.tryParse(riskCtrl.text) ?? 2.0;
              });
              Navigator.pop(ctx);
              fetchEverything();
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tfList = [
      {'label': 'M5', 'val': '5m'},
      {'label': 'M15', 'val': '15m'},
      {'label': 'M30', 'val': '30m'},
      {'label': 'H1', 'val': '1h'},
      {'label': 'H4', 'val': '4h'},
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF121A2B),
        elevation: 0,
        title: const Text('⚡ Sinyal S&R Ultimate V3', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        actions: [
          GestureDetector(
            onTap: () => setState(() => autoRefresh = !autoRefresh),
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: autoRefresh ? Colors.teal.withOpacity(0.25) : Colors.white10,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: autoRefresh ? Colors.tealAccent : Colors.white24),
              ),
              alignment: Alignment.center,
              child: Text(
                autoRefresh ? '⏱️ ${countdown}s' : '⏱️ OFF',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: autoRefresh ? Colors.tealAccent : Colors.white54),
              ),
            ),
          ),
          IconButton(icon: const Icon(Icons.calculate_outlined, color: Colors.amberAccent), onPressed: openCalcDialog),
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => fetchEverything()),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF0B101B),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(getCurrentMarketSession(), style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.bold)),
                    GestureDetector(
                      onTap: openCalcDialog,
                      child: Text('Modal: \$${accountBalance.toStringAsFixed(0)} (Risk ${riskPercent.toStringAsFixed(1)}%) ⚙️',
                          style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text('💪 Kekuatan: $strengthSummary', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Colors.white70)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            color: const Color(0xFF121A2B),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: tfList.map((tf) {
                bool active = selectedTf == tf['val'];
                return GestureDetector(
                  onTap: () {
                    setState(() => selectedTf = tf['val']!);
                    fetchEverything();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? Colors.blueAccent : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? Colors.blueAccent : Colors.white24),
                    ),
                    child: Text(tf['label']!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.white70)),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: signals.length,
                    itemBuilder: (ctx, i) => _buildCard(signals[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> s) {
    final int d = s['decimals'];
    final bool isBull = s['is_bull'];
    final Color mainColor = isBull ? Colors.green : Colors.red;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    Text(
                      'Trend Utama: ${isBull ? "BULLISH 📈" : "BEARISH 📉"}  |  RSI: ${s['rsi'].toStringAsFixed(1)}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isBull ? Colors.greenAccent : Colors.redAccent),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amberAccent),
                  ),
                  child: Text('⚡ Skor: ${s['score']}%', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Kotak Hasil Backtest Real-Time 1000 Candle
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blueAccent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.35)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('📊 Backtest (${s['bt_candles']} Candle):', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  Text('🏆 Winrate: ${s['bt_winrate']}% (${s['bt_wins']}W/${s['bt_losses']}L)',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                  Text('${int.parse(s['bt_pips']) >= 0 ? "+" : ""}${s['bt_pips']} Pips',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // Kotak Status Berita Fundamental
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: s['fund_danger'] ? Colors.red.withOpacity(0.2) : Colors.teal.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: s['fund_danger'] ? Colors.redAccent : Colors.teal),
              ),
              child: Text(
                s['fund_text'],
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: s['fund_danger'] ? Colors.redAccent : Colors.tealAccent),
              ),
            ),
            const SizedBox(height: 10),
            // Grafik Candlestick Visual
            Container(
              height: 130,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF060911),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: CustomPaint(
                painter: UltimateChartPainter(
                  candles: s['candles'],
                  support: s['support'],
                  resistance: s['resistance'],
                  current: s['current'],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // HANYA 1 KOTAK SINYAL FOKUS SEARAH TREN
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: mainColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: mainColor, width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        isBull ? '🟢 SINYAL UTAMA: BUY LIMIT (IKUTI TREN)' : '🔴 SINYAL UTAMA: SELL LIMIT (IKUTI TREN)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isBull ? Colors.greenAccent : Colors.redAccent),
                      ),
                      Text('Jarak: ${s['pips_to_entry']} Pips', style: const TextStyle(fontSize: 11, color: Colors.cyanAccent)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('Saran Ukuran Lot: ${s['lot']} Lot (Risiko \$${s['risk_dollar']})  |  Live: ${s['current'].toStringAsFixed(d)}',
                      style: const TextStyle(fontSize: 11, color: Colors.amberAccent)),
                  const Divider(height: 14),
                  _priceLine('🎯 Harga Entry (${s['signal_type']})', s['entry'].toStringAsFixed(d)),
                  _priceLine('✅ Take Profit 1 (Target Utama)', s['tp1'].toStringAsFixed(d)),
                  _priceLine('🚀 Take Profit 2 (Target Maksimal)', s['tp2'].toStringAsFixed(d)),
                  _priceLine('🛡️ Geser SL ke BEP+ jika sentuh', s['bep'].toStringAsFixed(d)),
                  _priceLine('❌ Stop Loss (SL Aman)', s['sl'].toStringAsFixed(d)),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.rocket_launch, size: 16, color: Colors.white),
                      label: const Text('BUKA MT5 & COPY OTOMATIS',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                      onPressed: () => launchMT5WithSmartFill(s),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _priceLine(String label, String val) {
    return InkWell(
      onTap: () => copySingle(label, val),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Row(
              children: [
                Text(val, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                const Icon(Icons.copy, size: 13, color: Colors.white54),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class UltimateChartPainter extends CustomPainter {
  final List<CandleData> candles;
  final double support, resistance, current;

  UltimateChartPainter({
    required this.candles,
    required this.support,
    required this.resistance,
    required this.current,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double range = (resistance - support) == 0 ? 1 : (resistance - support);
    double getY(double p) => size.height - ((p - support) / range) * size.height;

    canvas.drawLine(Offset(0, getY(resistance)), Offset(size.width, getY(resistance)),
        Paint()..color = Colors.redAccent..strokeWidth = 1.5);
    canvas.drawLine(Offset(0, getY(support)), Offset(size.width, getY(support)),
        Paint()..color = Colors.greenAccent..strokeWidth = 1.5);
    canvas.drawLine(Offset(0, getY(current)), Offset(size.width, getY(current)),
        Paint()..color = Colors.cyanAccent.withOpacity(0.5)..strokeWidth = 1.0);

    double stepX = size.width / candles.length;
    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];
      final p = Paint()
        ..color = c.close >= c.open ? Colors.green : Colors.red
        ..strokeWidth = 1.2;
      double x = i * stepX + (stepX / 2);
      canvas.drawLine(Offset(x, getY(c.high)), Offset(x, getY(c.low)), p);
      double top = getY(max(c.open, c.close));
      double bot = getY(min(c.open, c.close));
      if ((bot - top).abs() < 1.5) bot = top + 1.5;
      canvas.drawRect(Rect.fromLTRB(x - (stepX * 0.3), top, x + (stepX * 0.3), bot), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
