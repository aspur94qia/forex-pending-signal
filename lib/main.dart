import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ForexPendingApp());
}

class ForexPendingApp extends StatelessWidget {
  const ForexPendingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sinyal Pending S&R',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0B1120),
        cardColor: const Color(0xFF1E293B),
      ),
      home: const PendingSignalScreen(),
    );
  }
}

class CandleData {
  final double open, high, low, close;
  CandleData(this.open, this.high, this.low, this.close);
}

class PendingSignalScreen extends StatefulWidget {
  const PendingSignalScreen({super.key});

  @override
  State<PendingSignalScreen> createState() => _PendingSignalScreenState();
}

class _PendingSignalScreenState extends State<PendingSignalScreen> {
  final List<Map<String, String>> pairs = [
    {'name': 'XAU/USD (Gold)', 'symbol': 'GC=F', 'decimals': '2'},
    {'name': 'EUR/USD', 'symbol': 'EURUSD=X', 'decimals': '5'},
    {'name': 'GBP/USD', 'symbol': 'GBPUSD=X', 'decimals': '5'},
    {'name': 'USD/JPY', 'symbol': 'JPY=X', 'decimals': '3'},
    {'name': 'AUD/USD', 'symbol': 'AUDUSD=X', 'decimals': '5'},
  ];

  String selectedTf = '1h';
  bool isLoading = false;
  List<Map<String, dynamic>> signals = [];

  @override
  void initState() {
    super.initState();
    fetchAllSignals();
  }

  Future<void> fetchAllSignals() async {
    setState(() {
      isLoading = true;
      signals.clear();
    });

    for (var p in pairs) {
      final res = await analyzeMarket(
        p['name']!,
        p['symbol']!,
        int.parse(p['decimals']!),
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
      String name, String symbol, int dec) async {
    try {
      String range = selectedTf == '15m' ? '5d' : (selectedTf == '1h' ? '10d' : '1mo');
      final url = Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=$selectedTf&range=$range');
      final response = await http.get(url);
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final quote = data['chart']['result'][0]['indicators']['quote'][0];

      List<CandleData> candles = [];
      List<dynamic> opens = quote['open'];
      List<dynamic> highs = quote['high'];
      List<dynamic> lows = quote['low'];
      List<dynamic> closes = quote['close'];

      for (int i = 0; i < closes.length; i++) {
        if (opens[i] != null && highs[i] != null && lows[i] != null && closes[i] != null) {
          candles.add(CandleData(
            (opens[i] as num).toDouble(),
            (highs[i] as num).toDouble(),
            (lows[i] as num).toDouble(),
            (closes[i] as num).toDouble(),
          ));
        }
      }

      if (candles.length < 35) return null;

      double currentPrice = candles.last.close;
      List<CandleData> chartCandles = candles.sublist(candles.length - 30);

      double resistance = chartCandles.map((c) => c.high).reduce(max);
      double support = chartCandles.map((c) => c.low).reduce(min);

      double atrSum = 0;
      for (int i = candles.length - 14; i < candles.length; i++) {
        double tr1 = candles[i].high - candles[i].low;
        double tr2 = (candles[i].high - candles[i - 1].close).abs();
        double tr3 = (candles[i].low - candles[i - 1].close).abs();
        atrSum += max(tr1, max(tr2, tr3));
      }
      double atr = atrSum / 14;

      double buyLimitEntry = support + (atr * 0.15);
      double buyLimitSL = support - (atr * 1.3);
      double buyLimitTP1 = buyLimitEntry + (atr * 1.8);
      double buyLimitTP2 = resistance - (atr * 0.2);

      double sellLimitEntry = resistance - (atr * 0.15);
      double sellLimitSL = resistance + (atr * 1.3);
      double sellLimitTP1 = sellLimitEntry - (atr * 1.8);
      double sellLimitTP2 = support + (atr * 0.2);

      double distToBuy = (currentPrice - support).abs();
      double distToSell = (resistance - currentPrice).abs();
      bool isNearBuy = distToBuy < distToSell;

      return {
        'name': name,
        'decimals': dec,
        'current': currentPrice,
        'support': support,
        'resistance': resistance,
        'is_near_buy': isNearBuy,
        'buy_entry': buyLimitEntry,
        'buy_sl': buyLimitSL,
        'buy_tp1': buyLimitTP1,
        'buy_tp2': buyLimitTP2 > buyLimitTP1 ? buyLimitTP2 : buyLimitTP1 + atr,
        'sell_entry': sellLimitEntry,
        'sell_sl': sellLimitSL,
        'sell_tp1': sellLimitTP1,
        'sell_tp2': sellLimitTP2 < sellLimitTP1 ? sellLimitTP2 : sellLimitTP1 - atr,
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
        content: Text('$title ($val) disalin ke clipboard!'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.teal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('📊 Sinyal Pending Order S&R',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          DropdownButton<String>(
            value: selectedTf,
            dropdownColor: const Color(0xFF1E293B),
            underline: const SizedBox(),
            items: const [
              DropdownMenuItem(value: '15m', child: Text('M15')),
              DropdownMenuItem(value: '1h', child: Text('H1')),
              DropdownMenuItem(value: '1d', child: Text('D1')),
            ],
            onChanged: (v) {
              if (v != null) {
                setState(() => selectedTf = v);
                fetchAllSignals();
              }
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: fetchAllSignals),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: signals.length,
              itemBuilder: (ctx, i) {
                final s = signals[i];
                final int d = s['decimals'];
                final bool nearBuy = s['is_near_buy'];
                return Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(s['name'],
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: nearBuy ? Colors.green.withOpacity(0.2) : Colors.red.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: nearBuy ? Colors.green : Colors.red),
                              ),
                              child: Text(
                                nearBuy ? 'FOKUS BUY LIMIT 🟢' : 'FOKUS SELL LIMIT 🔴',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: nearBuy ? Colors.greenAccent : Colors.redAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Harga Sekarang: ${s['current'].toStringAsFixed(d)}  |  Support: ${s['support'].toStringAsFixed(d)}  |  Resist: ${s['resistance'].toStringAsFixed(d)}',
                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          height: 130,
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF090D16),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: CustomPaint(
                            painter: MiniChartPainter(
                              candles: s['candles'],
                              support: s['support'],
                              resistance: s['resistance'],
                              current: s['current'],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _buildOrderBox(
                                title: '🟢 BUY LIMIT (Area Support)',
                                color: Colors.green,
                                entry: s['buy_entry'].toStringAsFixed(d),
                                tp1: s['buy_tp1'].toStringAsFixed(d),
                                tp2: s['buy_tp2'].toStringAsFixed(d),
                                sl: s['buy_sl'].toStringAsFixed(d),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildOrderBox(
                                title: '🔴 SELL LIMIT (Area Resist)',
                                color: Colors.red,
                                entry: s['sell_entry'].toStringAsFixed(d),
                                tp1: s['sell_tp1'].toStringAsFixed(d),
                                tp2: s['sell_tp2'].toStringAsFixed(d),
                                sl: s['sell_sl'].toStringAsFixed(d),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildOrderBox({
    required String title,
    required Color color,
    required String entry,
    required String tp1,
    required String tp2,
    required String sl,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color)),
          const Divider(height: 12),
          _priceRow('Entry', entry),
          _priceRow('TP 1', tp1),
          _priceRow('TP 2', tp2),
          _priceRow('SL', sl),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String val) {
    return InkWell(
      onTap: () => copyText(label, val),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
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

class MiniChartPainter extends CustomPainter {
  final List<CandleData> candles;
  final double support, resistance, current;

  MiniChartPainter({
    required this.candles,
    required this.support,
    required this.resistance,
    required this.current,
  });

  @override
  void paint(Canvas canvas, Size size) {
    double maxPrice = resistance;
    double minPrice = support;
    double range = (maxPrice - minPrice) == 0 ? 1 : (maxPrice - minPrice);

    double getY(double price) {
      return size.height - ((price - minPrice) / range) * size.height;
    }

    final resPaint = Paint()..color = Colors.redAccent..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, getY(resistance)), Offset(size.width, getY(resistance)), resPaint);

    final supPaint = Paint()..color = Colors.greenAccent..strokeWidth = 1.5;
    canvas.drawLine(Offset(0, getY(support)), Offset(size.width, getY(support)), supPaint);

    double stepX = size.width / candles.length;
    for (int i = 0; i < candles.length; i++) {
      final c = candles[i];
      bool isBull = c.close >= c.open;
      final paint = Paint()
        ..color = isBull ? Colors.green : Colors.red
        ..strokeWidth = 1.2;

      double x = i * stepX + (stepX / 2);
      canvas.drawLine(Offset(x, getY(c.high)), Offset(x, getY(c.low)), paint);

      double top = getY(max(c.open, c.close));
      double bottom = getY(min(c.open, c.close));
      if ((bottom - top).abs() < 1.5) bottom = top + 1.5;

      canvas.drawRect(
        Rect.fromLTRB(x - (stepX * 0.3), top, x + (stepX * 0.3), bottom),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
