import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;

void main() async {
  print('═' * 60);
  print('   BINANCE API TEST - Standalone');
  print('═' * 60);

  // ============================================
  // PRUEBA 1: Ping a Binance
  // ============================================
  print('\n📡 Test 1: Ping a Binance API');
  try {
    final response = await http
        .get(Uri.parse('https://api.binance.com/api/v3/ping'))
        .timeout(Duration(seconds: 10));

    if (response.statusCode == 200) {
      print('✅ Binance API respondió: ${response.body}');
    } else {
      print('❌ Error ${response.statusCode}: ${response.body}');
    }
  } catch (e) {
    print('❌ Error de conexión: $e');
  }

  // ============================================
  // PRUEBA 2: Obtener precio actual de BTCUSDT
  // ============================================
  print('\n💰 Test 2: Precio actual BTC/USDT');
  try {
    final response = await http
        .get(
          Uri.parse(
            'https://api.binance.com/api/v3/ticker/price?symbol=BTCUSDT',
          ),
        )
        .timeout(Duration(seconds: 10));

    if (response.statusCode == 200) {
      Map<String, dynamic> data = jsonDecode(response.body);
      double price = double.parse(data['price']);
      print('✅ Precio actual: \$${price.toStringAsFixed(2)}');
      print('   Timestamp: ${DateTime.now()}');
    } else {
      print('❌ Error ${response.statusCode}: ${response.body}');
    }
  } catch (e) {
    print('❌ Error: $e');
  }

  // ============================================
  // PRUEBA 3: Obtener velas OHLCV (klines)
  // ============================================
  print('\n📊 Test 3: Velas OHLCV de BTCUSDT (1h, límite 100)');
  try {
    final uri = Uri.parse(
      'https://api.binance.com/api/v3/klines'
      '?symbol=BTCUSDT'
      '&interval=1h'
      '&limit=100',
    );

    final response = await http.get(uri).timeout(Duration(seconds: 10));

    if (response.statusCode == 200) {
      List<dynamic> data = jsonDecode(response.body);
      print('✅ Velas obtenidas: ${data.length}');

      // Mostrar la primera y última vela
      if (data.isNotEmpty) {
        List<dynamic> first = data[0];
        List<dynamic> last = data[data.length - 1];

        print('\n   Primera vela:');
        print('     Tiempo: ${DateTime.fromMillisecondsSinceEpoch(first[0])}');
        print(
          '     Open: \$${first[1]}, High: \$${first[2]}, Low: \$${first[3]}, Close: \$${first[4]}',
        );
        print('     Volume: ${first[5]}');

        print('\n   Última vela:');
        print('     Tiempo: ${DateTime.fromMillisecondsSinceEpoch(last[0])}');
        print(
          '     Open: \$${last[1]}, High: \$${last[2]}, Low: \$${last[3]}, Close: \$${last[4]}',
        );
        print('     Volume: ${last[5]}');
      }

      // Calcular indicadores básicos en memoria
      print('\n   Cálculo rápido de EMA (9 periodos):');
      List<double> closes = data.map((v) => double.parse(v[4])).toList();
      if (closes.length >= 9) {
        double ema9 = calculateEMA(closes, 9);
        print('     EMA(9) actual: \$${ema9.toStringAsFixed(2)}');
        print('     Precio actual: \$${closes.last.toStringAsFixed(2)}');
        print('     Precio > EMA9? ${closes.last > ema9}');
      }
    } else {
      print('❌ Error ${response.statusCode}: ${response.body}');
    }
  } catch (e) {
    print('❌ Error: $e');
  }

  // ============================================
  // PRUEBA 4: Obtener datos de 24h
  // ============================================
  print('\n📈 Test 4: Estadísticas 24h BTCUSDT');
  try {
    final response = await http
        .get(
          Uri.parse(
            'https://api.binance.com/api/v3/ticker/24hr?symbol=BTCUSDT',
          ),
        )
        .timeout(Duration(seconds: 10));

    if (response.statusCode == 200) {
      Map<String, dynamic> data = jsonDecode(response.body);
      print('✅ Estadísticas 24h:');
      print('   Precio actual: \$${double.parse(data['lastPrice'])}');
      print('   Cambio 24h: ${data['priceChange']}%');
      print(
        '   Volumen 24h: ${double.parse(data['volume']).toStringAsFixed(2)} BTC',
      );
      print(
        '   Volumen USDT: \$${double.parse(data['quoteVolume']).toStringAsFixed(0)}',
      );
    } else {
      print('❌ Error ${response.statusCode}');
    }
  } catch (e) {
    print('❌ Error: $e');
  }

  // ============================================
  // PRUEBA 5: Límites de rate (X-MBX-USED-WEIGHT)
  // ============================================
  print('\n⚡ Test 5: Verificar rate limits');
  try {
    final response = await http
        .get(
          Uri.parse(
            'https://api.binance.com/api/v3/klines?symbol=BTCUSDT&interval=1h&limit=1',
          ),
        )
        .timeout(Duration(seconds: 10));

    print('   Headers de respuesta:');
    response.headers.forEach((key, value) {
      if (key.toLowerCase().contains('weight') ||
          key.toLowerCase().contains('limit') ||
          key.toLowerCase().contains('rate')) {
        print('     $key: $value');
      }
    });

    if (response.statusCode == 200) {
      print('✅ Request exitoso');
    }
  } catch (e) {
    print('❌ Error: $e');
  }

  print('\n' + '═' * 60);
  print('   PRUEBAS BINANCE COMPLETADAS');
  print('═' * 60);
  print(
    '\n💡 Si todo está verde, puedes usar MarketDataService con confianza.',
  );
  print('   Nota: En producción agrega retry logic y manejo de rate limits.');
}

// ============================================
// FUNCIONES AUXILIARES PARA CÁLCULOS
// ============================================

/// Calcula EMA (Exponential Moving Average) de una lista de precios
double calculateEMA(List<double> prices, int period) {
  if (prices.length < period) {
    return prices.reduce((a, b) => a + b) / prices.length; // SMA fallback
  }

  double multiplier = 2 / (period + 1);

  // SMA inicial
  double sum = prices.sublist(0, period).reduce((a, b) => a + b);
  double sma = sum / period;

  // EMA recursiva
  double ema = sma;
  for (int i = period; i < prices.length; i++) {
    ema = (prices[i] - ema) * multiplier + ema;
  }

  return ema;
}
