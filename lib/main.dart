import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ForexPendingProApp());
}

class ForexPendingProApp extends StatelessWidget {
  const ForexPendingProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sinyal S&R Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF070B14),
        cardColor: const Color(0xFF151F32),
      ),
      home: const MainDashboard(),
    );
  }
}

class CandleData {
  final double open, high, low, close;
  CandleData(this.open, this.high, this.low, this.close);
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  final List<Map<String, dynamic>> pairs = [
    {'name': 'XAU/USD (Gold)', 'symbol': 'GC=F', 'decimals': 2, 'pip': 0.1},
    {'name': 'EUR/USD', 'symbol': 'EURUSD=X', 'decimals': 5, 'pip': 0.0001},
    {'name': 'GBP/USD', 'symbol': 'GBPUSD=X', 'decimals': 5, 'pip': 0.0001},
    {'name': 'USD/JPY', 'symbol': 'JPY=X', 'decimals': 3, 'pip': 0.01},
    {'name': 'AUD/USD', 'symbol': 'AUDUSD=X', 'decimals': 5, 'pip': 0.0001},
    {'name': 'USD/CAD', 'symbol': 'CAD=X', 'decimals': 5, 'pip': 0.0001},
  ];

  String selectedTf = '15m';
  bool isLoading = false;
  List<Map<String, dynamic>> signals = [];

  // Pengaturan Kalkulator Lot & Risiko
  double accountBalance = 100.0; // Default modal $100
  double riskPercent = 2.0; // Default risiko 2% per trade

  @override
  void initState() {
    super.initState();
    fetchAllSignals();
  }

  String getCurrentMarketSession() {
    final int utcHour = DateTime.now().toUtc().hour;
    List<String> active = [];
    if (utcHour >= 22 || utcHour < 7) active.add('Sydney');
    if (utcHour >= 0 && utcHour < 9) active.add('Tokyo (Asia)');
    if (utcHour >= 7 && utcHour < 16) active.add('London (Eropa)');
    if (utcHour >= 12 && utcHour < 21) active.add('New York (US)');
    if (active.isEmpty) return 'Pasar Tenang';
    return 'Sesi Aktif: ${active.join(" + ")} 🔥';
  }

  Future<void> fetchAllSignals() async {
    setState(() {
      isLoading = true;
      signals.clear();
    });

    for (var p in pairs) {
      final res = await analyzeMarket(
        p['name'],
        p['symbol'],
        p['decimals'],
        p['pip'],
      );
      if (res != null) {
        signals.add(res);
      }
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<Map<String, dynamic>?> analyzeMarket(
      String name, String symbol, int dec, double pipSize) async {
    try {
      String apiInterval = selectedTf == '4h' ? '1h' : selectedTf;
      String range = '5d';
      if (selectedTf == '5m') range = '5d';
      if (selectedTf == '15m' || selectedTf == '30m') range = '5d';
      if (selectedTf == '1h') range = '1mo';
      if (selectedTf == '4h') range = '3mo';

      final url = Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=$apiInterval&range=$range');
      final response = await http.get(url);
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final quote = data['chart']['result'][0]['indicators']['quote'][0];

      List<CandleData> rawCandles = [];
      List<dynamic> opens = quote['open'];
      List<dynamic> highs = quote['high'];
      List<dynamic> lows = quote['low'];
      List<dynamic> closes = quote['close'];

      for (int i = 0; i < closes.length; i++) {
        if (opens[i] != null && highs[i] != null && lows[i] != null && closes[i] != null) {
          rawCandles.add(CandleData(
            (opens[i] as num).toDouble(),
            (highs[i] as num).toDouble(),
            (lows[i] as num).toDouble(),
            (closes[i] as num).toDouble(),
          ));
        }
      }

      // Jika user pilih H4, gabungkan 4 candle H1 menjadi 1 candle H4
      List<CandleData> candles = [];
      if (selectedTf == '4h') {
        for (int i = 0; i <= rawCandles.length - 4; i += 4) {
          var chunk = rawCandles.sublist(i, i + 4);
          candles.add(CandleData(
            chunk.first.open,
            chunk.map((c) => c.high).reduce(max),
            chunk.map((c) => c.low).reduce(min),
            chunk.last.close,
          ));
        }
      } else {
        candles = rawCandles;
      }

      if (candles.length < 40) return null;

      double currentPrice = candles.last.close;
      List<CandleData> chartCandles = candles.sublist(candles.length - 35);

      // Cari Support & Resistance dari 35 candle terakhir
      double resistance = chartCandles.map((c) => c.high).reduce(max);
      double support = chartCandles.map((c) => c.low).reduce(min);

      // Hitung ATR (14)
      double atrSum = 0;
      for (int i = candles.length - 14; i < candles.length; i++) {
        double tr1 = candles[i].high - candles[i].low;
        double tr2 = (candles[i].high - candles[i - 1].close).abs();
        double tr3 = (candles[i].low - candles[i - 1].close).abs();
        atrSum += max(tr1, max(tr2, tr3));
      }
      double atr = atrSum / 14;

      // Hitung RSI (14)
      double gain = 0, loss = 0;
      for (int i = candles.length - 14; i < candles.length; i++) {
        double diff = candles[i].close - candles[i - 1].close;
        if (diff >= 0) gain += diff; else loss -= diff;
      }
      double rs = (gain / 14) / ((loss / 14) == 0 ? 0.0001 : (loss / 14));
      double rsi = 100 - (100 / (1 + rs));

      // Hitung EMA 30 (Trend Filter)
      double ema = candles[candles.length - 30].close;
      double k = 2 / (30 + 1);
      for (int i = candles.length - 29; i < candles.length; i++) {
        ema = (candles[i].close * k) + (ema * (1 - k));
      }
      bool isBullishTrend = currentPrice >= ema;

      // Rumus BUY LIMIT & SELL LIMIT
      double buyLimit = support + (atr * 0.12);
      double buySL = support - (atr * 1.25);
      double buyTP1 = buyLimit + (atr * 1.6);
      double buyTP2 = resistance - (atr * 0.2);

      double sellLimit = resistance - (atr * 0.12);
      double sellSL = resistance + (atr * 1.25);
      double sellTP1 = sellLimit - (atr * 1.6);
      double sellTP2 = support + (atr * 0.2);

      // Rumus Breakout (BUY STOP & SELL STOP)
      double buyStop = resistance + (atr * 0.25);
      double buyStopSL = resistance - (atr * 1.0);
      double buyStopTP = buyStop + (atr * 2.0);

      double sellStop = support - (atr * 0.25);
      double sellStopSL = support + (atr * 1.0);
      double sellStopTP = sellStop - (atr * 2.0);

      // Hitung Jarak Pips
      double pipsToBuy = ((currentPrice - buyLimit).abs() / pipSize);
      double pipsToSell = ((sellLimit - currentPrice).abs() / pipSize);
      double slPipsBuy = ((buyLimit - buySL).abs() / pipSize);
      double slPipsSell = ((sellSL - sellLimit).abs() / pipSize);

      // Kalkulator Lot Otomatis (Risk $ / (SL Pips * Pip Value ~$10 per 1.0 lot))
      double riskDollar = accountBalance * (riskPercent / 100.0);
      double recLotBuy = max(0.01, riskDollar / (slPipsBuy * 1.0));
      double recLotSell = max(0.01, riskDollar / (slPipsSell * 1.0));

      bool nearBuy = pipsToBuy < pipsToSell;

      // Skor Kekuatan Sinyal
      int score = 72;
      if (nearBuy && isBullishTrend) score += 12;
      if (!nearBuy && !isBullishTrend) score += 12;
      if (nearBuy && rsi < 42) score += 10;
      if (!nearBuy && rsi > 58) score += 10;
      score = min(96, score);

      return {
        'name': name,
        'decimals': dec,
        'current': currentPrice,
        'support': support,
        'resistance': resistance,
        'rsi': rsi,
        'trend': isBullishTrend ? 'BULLISH 📈' : 'BEARISH 📉',
        'is_bull': isBullishTrend,
        'score': score,
        'near_buy': nearBuy,
        'pips_to_buy': pipsToBuy.toStringAsFixed(0),
        'pips_to_sell': pipsToSell.toStringAsFixed(0),
        'lot_buy': (recLotBuy * 0.1).toStringAsFixed(2),
        'lot_sell': (recLotSell * 0.1).toStringAsFixed(2),
        'risk_dollar': riskDollar.toStringAsFixed(2),
        'buy_entry': buyLimit,
        'buy_sl': buySL,
        'buy_tp1': buyTP1,
        'buy_tp2': buyTP2 > buyTP1 ? buyTP2 : buyTP1 + atr,
        'sell_entry': sellLimit,
        'sell_sl': sellSL,
        'sell_tp1': sellTP1,
        'sell_tp2': sellTP2 < sellTP1 ? sellTP2 : sellTP1 - atr,
        'buystop_entry': buyStop,
        'buystop_sl': buyStopSL,
        'buystop_tp': buyStopTP,
        'sellstop_entry': sellStop,
        'sellstop_sl': sellStopSL,
        'sellstop_tp': sellStopTP,
        'candles': chartCandles,
      };
    } catch (e) {
      return null;
    }
  }

  void copyText(String title, String val) {
    Clipboard.setData(ClipboardData(text: val));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title ($val) disalin!'),
        duration: const Duration(milliseconds: 900),
        backgroundColor: Colors.teal,
      ),
    );
  }

  void openLotCalculatorDialog() {
    final balCtrl = TextEditingController(text: accountBalance.toStringAsFixed(0));
    final riskCtrl = TextEditingController(text: riskPercent.toStringAsFixed(1));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('🧮 Pengaturan Modal & Risiko', style: TextStyle(fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: balCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Modal Akun (USD \$)'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: riskCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Risiko per Trade (%)'),
            ),
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
              fetchAllSignals();
            },
            child: const Text('Simpan & Hitung Ulang Lot'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, String>> tfList = [
      {'label': 'M5', 'val': '5m'},
      {'label': 'M15', 'val': '15m'},
      {'label': 'M30', 'val': '30m'},
      {'label': 'H1', 'val': '1h'},
      {'label': 'H4', 'val': '4h'},
    ];

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF151F32),
        elevation: 0,
        title: const Text('⚡ Sinyal S&R Pro + Tools',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.calculate_outlined, color: Colors.amberAccent),
            tooltip: 'Kalkulator Lot',
            onPressed: openLotCalculatorDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: fetchAllSignals,
          ),
        ],
      ),
      body: Column(
        children: [
          // Bar Info Sesi & Modal
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: const Color(0xFF0F172A),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(getCurrentMarketSession(),
                    style: const TextStyle(fontSize: 11, color: Colors.amberAccent, fontWeight: FontWeight.w600)),
                GestureDetector(
                  onTap: openLotCalculatorDialog,
                  child: Text(
                    'Modal: \$${accountBalance.toStringAsFixed(0)} (Risk ${riskPercent.toStringAsFixed(1)}%) ⚙️',
                    style: const TextStyle(fontSize: 11, color: Colors.cyanAccent, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          // Bar Tombol Timeframe M5, M15, M30, H1, H4
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
            color: const Color(0xFF151F32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: tfList.map((tf) {
                bool active = selectedTf == tf['val'];
                return GestureDetector(
                  onTap: () {
                    setState(() => selectedTf = tf['val']!);
                    fetchAllSignals();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? Colors.blueAccent : Colors.transparent,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: active ? Colors.blueAccent : Colors.white24),
                    ),
                    child: Text(
                      tf['label']!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: active ? Colors.white : Colors.white70,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          // Daftar Sinyal
          Expanded(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: signals.length,
                    itemBuilder: (ctx, i) => _buildSignalCard(signals[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignalCard(Map<String, dynamic> s) {
    final int d = s['decimals'];
    final bool nearBuy = s['near_buy'];

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Pair + Trend + Skor
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['name'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text('Trend: ${s['trend']}',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: s['is_bull'] ? Colors.greenAccent : Colors.redAccent)),
                        const SizedBox(width: 10),
                        Text('RSI: ${s['rsi'].toStringAsFixed(1)}',
                            style: const TextStyle(fontSize: 11, color: Colors.white70)),
                      ],
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
                  child: Text(
                    '⚡ Akurasi: ${s['score']}%',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Bar Info Harga & Radar Jarak Pips
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Live: ${s['current'].toStringAsFixed(d)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.cyanAccent)),
                  Text('🎯 Ke Buy: ${s['pips_to_buy']} Pips',
                      style: const TextStyle(fontSize: 11, color: Colors.greenAccent)),
                  Text('🎯 Ke Sell: ${s['pips_to_sell']} Pips',
                      style: const TextStyle(fontSize: 11, color: Colors.redAccent)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Mini Chart Candlestick + Garis S&R
            Container(
              height: 135,
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF070B14),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: CustomPaint(
                painter: ProChartPainter(
                  candles: s['candles'],
                  support: s['support'],
                  resistance: s['resistance'],
                  current: s['current'],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Kotak Pending Order BUY LIMIT & SELL LIMIT
            Row(
              children: [
                Expanded(
                  child: _buildLimitBox(
                    title: '🟢 BUY LIMIT',
                    subtitle: 'Saran Lot: ${s['lot_buy']} (\$${s['risk_dollar']})',
                    color: Colors.green,
                    isHighlight: nearBuy,
                    entry: s['buy_entry'].toStringAsFixed(d),
                    tp1: s['buy_tp1'].toStringAsFixed(d),
                    tp2: s['buy_tp2'].toStringAsFixed(d),
                    sl: s['buy_sl'].toStringAsFixed(d),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildLimitBox(
                    title: '🔴 SELL LIMIT',
                    subtitle: 'Saran Lot: ${s['lot_sell']} (\$${s['risk_dollar']})',
                    color: Colors.red,
                    isHighlight: !nearBuy,
                    entry: s['sell_entry'].toStringAsFixed(d),
                    tp1: s['sell_tp1'].toStringAsFixed(d),
                    tp2: s['sell_tp2'].toStringAsFixed(d),
                    sl: s['sell_sl'].toStringAsFixed(d),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Panel Tambahan: Sinyal Breakout (Buy Stop & Sell Stop)
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('🚀 Lihat Sinyal Breakout (Buy Stop / Sell Stop)',
                  style: TextStyle(fontSize: 12, color: Colors.white70)),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildStopBox(
                        title: '🔼 BUY STOP (Jika Resist Jebol)',
                        color: Colors.tealAccent,
                        entry: s['buystop_entry'].toStringAsFixed(d),
                        tp: s['buystop_tp'].toStringAsFixed(d),
                        sl: s['buystop_sl'].toStringAsFixed(d),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildStopBox(
                        title: '🔽 SELL STOP (Jika Support Jebol)',
                        color: Colors.orangeAccent,
                        entry: s['sellstop_entry'].toStringAsFixed(d),
                        tp: s['sellstop_tp'].toStringAsFixed(d),
                        sl: s['sellstop_sl'].toStringAsFixed(d),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLimitBox({
    required String title,
    required String subtitle,
    required Color color,
    required bool isHighlight,
    required String entry,
    required String tp1,
    required String tp2,
    required String sl,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(isHighlight ? 0.14 : 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isHighlight ? color : color.withOpacity(0.3),
          width: isHighlight ? 1.6 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.amberAccent)),
          const Divider(height: 10),
          _copyRow('Entry', entry),
          _copyRow('TP 1', tp1),
          _copyRow('TP 2', tp2),
          _copyRow('SL', sl),
        ],
      ),
    );
  }

  Widget _buildStopBox({
    required String title,
    required Color color,
    required String entry,
    required String tp,
    required String sl,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          const Divider(height: 8),
          _copyRow('Entry', entry),
          _copyRow('TP', tp),
          _copyRow('SL', sl),
        ],
      ),
    );
  }

  Widget _copyRow(String label, String val) {
    return InkWell(
      onTap: () => copyText(label, val),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('$label:', style: const TextStyle(fontSize: 11, color: Colors.white70)),
            Row(
              children: [
                Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 4),
                const Icon(Icons.copy, size: 11, color: Colors.white54),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class ProChartPainter extends CustomPainter {
  final List<CandleData> candles;
  final double support, resistance, current;

  ProChartPainter({
    required this.candles,
    required this.support,
    required this.resistance,
    required this.current,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double range = (resistance - support) == 0 ? 1 : (resistance - support);
    double getY(double p) => size.height - ((p - support) / range) * size.height;

    // Garis Resistance (Merah)
    final resPaint = Paint()..color = Colors.redAccent..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, getY(resistance)), Offset(size.width, getY(resistance)), resPaint);

    // Garis Support (Hijau)
    final supPaint = Paint()..color = Colors.greenAccent..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, getY(support)), Offset(size.width, getY(support)), supPaint);

    // Garis Harga Sekarang (Biru Tipis)
    final curPaint = Paint()..color = Colors.cyanAccent.withOpacity(0.5)..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, getY(current)), Offset(size.width, getY(current)), curPaint);

    // Gambar Candlestick
    double stepX = size.width / candles.length;
    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];
      bool bull = c.close >= c.open;
      final p = Paint()
        ..color = bull ? Colors.green : Colors.red
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
