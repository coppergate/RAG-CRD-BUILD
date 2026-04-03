import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  final url = 'https://rag-admin-api.rag.hierocracy.home/api/health/all';
  print('Testing GET $url');
  try {
    final response = await dio.get(url);
    print('Response status: ${response.statusCode}');
    print('Response body: ${response.data}');
  } catch (e) {
    print('Error: $e');
    exit(1);
  }
}
