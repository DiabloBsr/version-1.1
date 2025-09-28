import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class DashboardService {
  final String baseUrl = "http://127.0.0.1:8000/api/v1/dashboard/summary/";
  final storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>> fetchDashboardSummary() async {
    final token = await storage.read(key: "access_token");

    final response = await http.get(
      Uri.parse(baseUrl),
      headers: {
        "Authorization": "Bearer $token",
        "Content-Type": "application/json",
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Erreur API: ${response.statusCode}");
    }
  }
}
