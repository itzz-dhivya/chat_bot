import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AiService {
  // ============================================================
  // SINGLETON
  // ============================================================

  static final AiService _instance = AiService._internal();

  factory AiService() {
    return _instance;
  }

  AiService._internal();

  // ============================================================
  // GEMINI API KEY
  // ============================================================
  //
  // IMPORTANT:
  // Use a NEW API key here.
  // Do NOT share your API key in chat, GitHub, screenshots, etc.
  //
  String geminiApiKey = '';

  // ============================================================
  // GEMINI MODEL
  // ============================================================

  static const String model = 'gemini-3.5-flash';

  // ============================================================
  // SEND MESSAGE
  // ============================================================

  Future<String> sendMessage({
    required String prompt,
    required List<Map<String, String>> conversationHistory,
  }) async {
    try {
      debugPrint('======================================');
      debugPrint('AI: Sending message to Gemini...');
      debugPrint('AI: Prompt length: ${prompt.length}');
      debugPrint('AI: History count: ${conversationHistory.length}');
      debugPrint('======================================');

      final response = await _callGeminiApi(
        prompt,
        conversationHistory,
      );

      debugPrint('AI: Gemini response received successfully');

      return response;
    } catch (e) {
      debugPrint('======================================');
      debugPrint('AI ERROR: $e');
      debugPrint('======================================');

      return _getUserFriendlyError(e);
    }
  }

  // ============================================================
  // GEMINI API CALL
  // ============================================================

  Future<String> _callGeminiApi(
      String prompt,
      List<Map<String, String>> history,
      ) async {
    final key = geminiApiKey.trim();

    // ----------------------------------------------------------
    // CHECK API KEY
    // ----------------------------------------------------------

    if (key.isEmpty || key == 'YOUR_NEW_GEMINI_API_KEY') {
      throw Exception('Gemini API key is empty');
    }

    // ----------------------------------------------------------
    // BUILD CONTENTS
    // ----------------------------------------------------------

    final List<Map<String, dynamic>> contents = [];

    /*
      Keep only recent messages.

      Example:

      user  -> Hello
      model -> Hi!
      user  -> How are you?
      model -> I am fine

      This reduces request size and improves response speed.
    */

    final List<Map<String, String>> recentHistory =
    history.length > 6
        ? history.sublist(history.length - 6)
        : history;

    for (final msg in recentHistory) {
      final String text = (msg['message'] ?? '').trim();

      if (text.isEmpty) {
        continue;
      }

      final String sender = msg['sender'] ?? 'user';

      contents.add({
        'role': sender == 'user' ? 'user' : 'model',
        'parts': [
          {
            'text': text,
          },
        ],
      });
    }

    // ----------------------------------------------------------
    // SAFETY CHECK
    // ----------------------------------------------------------

    if (contents.isEmpty) {
      final String cleanPrompt = prompt.trim();

      if (cleanPrompt.isEmpty) {
        throw Exception('Message is empty');
      }

      contents.add({
        'role': 'user',
        'parts': [
          {
            'text': cleanPrompt,
          },
        ],
      });
    }

    // ----------------------------------------------------------
    // REQUEST BODY
    // ----------------------------------------------------------

    final Map<String, dynamic> requestBody = {
      'contents': contents,

      'systemInstruction': {
        'parts': [
          {
            'text':
            'You are a friendly and intelligent AI assistant '
                'inside a mobile communication application. '
                'Give clear, concise and useful answers. '
                'Reply in the same language used by the user. '
                'If the user uses Tanglish, reply in Tanglish. '
                'Avoid unnecessary long explanations unless the user '
                'asks for detailed information.',
          },
        ],
      },

      'generationConfig': {
        'maxOutputTokens': 300,
      },
    };

    // ----------------------------------------------------------
    // GEMINI URL
    // ----------------------------------------------------------

    final Uri url = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/'
          'models/$model:generateContent',
    );

    debugPrint('Gemini model: $model');
    debugPrint('Sending request to Gemini...');

    final Stopwatch stopwatch = Stopwatch()..start();

    // ----------------------------------------------------------
    // HTTP REQUEST
    // ----------------------------------------------------------

    try {
      final http.Response response = await http
          .post(
        url,
        headers: {
          'Content-Type': 'application/json',

          // API key is sent through header
          'x-goog-api-key': key,
        },
        body: jsonEncode(requestBody),
      )
          .timeout(
        const Duration(seconds: 30),
      );

      stopwatch.stop();

      debugPrint(
        'Gemini response time: '
            '${stopwatch.elapsedMilliseconds} ms',
      );

      debugPrint(
        'Gemini status: ${response.statusCode}',
      );

      // --------------------------------------------------------
      // SUCCESS
      // --------------------------------------------------------

      if (response.statusCode == 200) {
        return _parseGeminiResponse(response);
      }

      // --------------------------------------------------------
      // ERROR RESPONSE
      // --------------------------------------------------------

      debugPrint('Gemini error response:');
      debugPrint(response.body);

      if (response.statusCode == 400) {
        throw Exception(
          'Gemini request is invalid (400)',
        );
      }

      if (response.statusCode == 401) {
        throw Exception(
          'Gemini API key is invalid (401)',
        );
      }

      if (response.statusCode == 403) {
        throw Exception(
          'Gemini API access denied (403)',
        );
      }

      if (response.statusCode == 404) {
        throw Exception(
          'Gemini model not found (404)',
        );
      }

      if (response.statusCode == 429) {
        throw Exception(
          'Gemini rate limit exceeded (429)',
        );
      }

      if (response.statusCode >= 500) {
        throw Exception(
          'Gemini server error (${response.statusCode})',
        );
      }

      throw Exception(
        'Gemini API failed: ${response.statusCode}',
      );
    } catch (e) {
      stopwatch.stop();

      debugPrint(
        'Gemini request error: $e',
      );

      rethrow;
    }
  }

  // ============================================================
  // PARSE GEMINI RESPONSE
  // ============================================================

  String _parseGeminiResponse(
      http.Response response,
      ) {
    try {
      final Map<String, dynamic> data =
      jsonDecode(
        utf8.decode(response.bodyBytes),
      );

      // --------------------------------------------------------
      // CANDIDATES
      // --------------------------------------------------------

      final dynamic candidates = data['candidates'];

      if (candidates == null ||
          candidates is! List ||
          candidates.isEmpty) {
        throw Exception(
          'Gemini returned no candidates',
        );
      }

      // --------------------------------------------------------
      // CONTENT
      // --------------------------------------------------------

      final dynamic content =
      candidates[0]['content'];

      if (content == null ||
          content is! Map) {
        throw Exception(
          'Gemini response content is empty',
        );
      }

      // --------------------------------------------------------
      // PARTS
      // --------------------------------------------------------

      final dynamic parts =
      content['parts'];

      if (parts == null ||
          parts is! List ||
          parts.isEmpty) {
        throw Exception(
          'Gemini response parts are empty',
        );
      }

      // --------------------------------------------------------
      // FIND TEXT
      // --------------------------------------------------------

      String? responseText;

      for (final part in parts) {
        if (part is Map &&
            part['text'] != null) {
          final String text =
          part['text'].toString().trim();

          if (text.isNotEmpty) {
            responseText = text;
            break;
          }
        }
      }

      // --------------------------------------------------------
      // EMPTY RESPONSE
      // --------------------------------------------------------

      if (responseText == null ||
          responseText.isEmpty) {
        throw Exception(
          'Gemini returned an empty response',
        );
      }

      debugPrint(
        'Gemini response received successfully',
      );

      return responseText;
    } catch (e) {
      debugPrint(
        'Gemini response parsing error: $e',
      );

      throw Exception(
        'Unable to read Gemini response',
      );
    }
  }

  // ============================================================
  // USER FRIENDLY ERROR
  // ============================================================

  String _getUserFriendlyError(
      Object error,
      ) {
    final String message =
    error.toString().toLowerCase();

    if (message.contains('api key') ||
        message.contains('401')) {
      return 'Gemini API key is invalid. Please check your API key.';
    }

    if (message.contains('403')) {
      return 'Gemini API access was denied. Please check your API key and API access.';
    }

    if (message.contains('404')) {
      return 'Gemini model was not found. Please check the model configuration.';
    }

    if (message.contains('429')) {
      return 'Gemini request limit reached. Please try again later.';
    }

    if (message.contains('timeout')) {
      return 'Gemini is taking too long to respond. Please check your internet connection and try again.';
    }

    if (message.contains('network')) {
      return 'Network error. Please check your internet connection.';
    }

    return 'Sorry, I could not process your request right now. Please try again.';
  }

  // ============================================================
  // CLEAR API KEY
  // ============================================================

  void clearApiKey() {
    geminiApiKey = '';
  }
}