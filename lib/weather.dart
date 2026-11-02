import 'dart:convert';

import 'package:http/http.dart' as http;

class Weather {
  Weather({required this.temperature, required this.code});

  final double temperature;
  final int code;

  factory Weather.fromJson(Map<String, dynamic> json) {
    return Weather(
      temperature: (json['temperature_2m'] as num).toDouble(),
      code: (json['weather_code'] as num).toInt(),
    );
  }
}

// Asks the weather server for the weather in Huye right now.
Future<Weather> fetchWeather() async {
  final url = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=-2.5967&longitude=29.7394'
    '&current=temperature_2m,weather_code'
    '&timezone=Africa%2FKigali',
  );
  final response = await http.get(url);
  if (response.statusCode != 200) {
    throw Exception('The weather server answered ${response.statusCode}');
  }
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  return Weather.fromJson(data['current'] as Map<String, dynamic>);
}

// Turns the weather code into words.
String describe(int code) {
  if (code == 0) return 'Clear sky';
  if (code <= 2) return 'Partly cloudy';
  if (code == 3) return 'Cloudy';
  if (code == 45 || code == 48) return 'Fog';
  if (code >= 51 && code <= 57) return 'Drizzle';
  if (code >= 61 && code <= 67) return 'Rain';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code >= 95) return 'Thunderstorm';
  return 'Unknown';
}
