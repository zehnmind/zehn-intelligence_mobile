import 'dart:typed_data';

import 'package:dio/dio.dart';
import '../core/log.dart';
import '../core/transport/zehn.dart';

/// Speech-to-text and text-to-speech through the Zehn gateway.
///
/// Used rather than the phone's own engines for one decisive reason: Apple
/// ships no Uzbek speech recognition and no Uzbek voice (checked against
/// `SFSpeechRecognizer.supportedLocales()` and the installed voices), so an
/// on-device path could never serve the app's primary language on an iPhone.
/// Zehn takes `language: uz` for both directions — and `ru` and `en`.
///
/// Both calls are OpenAI-compatible: `/audio/transcriptions` (multipart) and
/// `/audio/speech` (JSON in, audio bytes out).
///
/// Same two security notes as the chat transport: its own bare [Dio], so the
/// user's app token never reaches this server; and a key compiled into an app
/// can be extracted, so for real users point [baseUrl] at a backend that
/// holds it and pass an empty `apiKey` — no `Authorization` header is sent.
class ZehnSpeechClient {
  ZehnSpeechClient({
    required String apiKey,
    String baseUrl = Zehn.baseUrl,
    this.sttModel,
    this.ttsModel,
    this.ttsVoice,
    Dio? httpClient,
    this.log = silentAgentLog,
  }) : _dio =
           httpClient ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl,
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 60),
               headers: {
                 if (apiKey.trim().isNotEmpty)
                   'Authorization': 'Bearer $apiKey',
               },
             ),
           );

  final Dio _dio;
  final AgentLog log;
  final String? sttModel;
  final String? ttsModel;
  final String? ttsVoice;

  bool get enabled => true;

  /// Longest text sent for speech. A reply is one or two sentences; anything
  /// past this is a runaway model, and speaking it would take a minute.
  static const int maxSpeechLength = 600;

  /// Transcribes a WAV recording. Null on any failure — the caller treats it
  /// as "didn't catch that".
  ///
  /// [language] is passed through when known. Whisper's language detection is
  /// weakest on Uzbek, which it tends to hear as Turkish or Russian, so naming
  /// the language matters most for exactly the case Uzbek apps care about.
  Future<String?> transcribe(String wavPath, {String? language}) async {
    if (!enabled) return null;
    try {
      final form = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          wavPath,
          filename: 'speech.wav',
          contentType: DioMediaType('audio', 'wav'),
        ),
        if (sttModel != null && sttModel!.isNotEmpty) 'model': sttModel,
        'language': ?language,
        'response_format': 'verbose_json',
      });

      final response = await _dio.post<Object?>(
        'audio/transcriptions',
        data: form,
      );
      final data = response.data;
      final text = data is Map ? data['text'] : data;
      return text is String && text.trim().isNotEmpty ? text.trim() : null;
    } on DioException catch (e) {
      log(
        'zehn stt: ${e.response?.statusCode ?? e.type} — '
        '${_detail(e.response?.data)}',
      );
      return null;
    } catch (e) {
      log('zehn stt: unexpected failure: $e');
      return null;
    }
  }

  /// Synthesizes speech as WAV bytes. Null on any failure — the caller simply
  /// stays silent rather than surfacing an error for audio nobody asked for.
  Future<Uint8List?> synthesize(
    String text, {
    required String language,
    double speed = 1,
  }) async {
    final input = text.trim();
    if (input.isEmpty || !enabled) return null;

    try {
      final response = await _dio.post<List<int>>(
        'audio/speech',
        data: {
          if (ttsModel != null && ttsModel!.isNotEmpty) 'model': ttsModel,
          'input': input.length > maxSpeechLength
              ? input.substring(0, maxSpeechLength)
              : input,
          if (ttsVoice != null && ttsVoice!.isNotEmpty) 'voice': ttsVoice,
          'response_format': 'wav',
          'speed': speed,
          'language': language,
        },
        options: Options(
          responseType: ResponseType.bytes,
          contentType: Headers.jsonContentType,
        ),
      );
      final bytes = response.data;
      return bytes == null || bytes.isEmpty ? null : Uint8List.fromList(bytes);
    } on DioException catch (e) {
      log('zehn tts: ${e.response?.statusCode ?? e.type}');
      return null;
    } catch (e) {
      log('zehn tts: unexpected failure: $e');
      return null;
    }
  }

  static String _detail(Object? data) {
    if (data is Map) {
      final error = data['error'];
      if (error is Map && error['message'] is String) {
        return error['message'] as String;
      }
      if (data['detail'] is String) return data['detail'] as String;
    }
    return 'no detail';
  }
}
