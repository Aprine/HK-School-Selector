import 'dart:convert';

import 'package:http/http.dart' as http;

class QwenChatService {
  static const String _proxyUrl = String.fromEnvironment('AI_PROXY_URL');

  bool get isConfigured => _proxyUrl.trim().isNotEmpty;

  Future<String> reply({
    required List<ChatTurn> history,
    required String userMessage,
    required String appContext,
  }) async {
    if (!isConfigured) {
      throw Exception('AI_PROXY_URL is missing.');
    }

    final trimmedHistory = history.length <= 8
        ? history
        : history.sublist(history.length - 8);

    final response = await http.post(
      Uri.parse(_proxyUrl),
      headers: <String, String>{
        'Content-Type': 'application/json',
      },
      body: jsonEncode(<String, dynamic>{
        'history': trimmedHistory
            .map(
              (turn) => <String, String>{
                'role': turn.role,
                'content': turn.content,
              },
            )
            .toList(growable: false),
        'userMessage': userMessage,
        'appContext': appContext,
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('AI proxy error: HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw Exception('Unexpected AI proxy response format.');
    }

    final content = (decoded['reply'] ?? decoded['message'])?.toString().trim() ?? '';
    if (content.isEmpty) {
      throw Exception('AI proxy returned empty content.');
    }

    return content;
  }
}

class ChatTurn {
  const ChatTurn({required this.role, required this.content});

  final String role;
  final String content;
}
