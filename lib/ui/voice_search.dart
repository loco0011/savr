import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../theme/tokens.dart';

/// Listens once and returns what the user said, or null if cancelled.
/// Uses the phone's own speech recogniser (Google on most Android phones);
/// Savr never records or stores audio.
Future<String?> listenForSpeech(BuildContext context, {String prompt = 'Say a product, e.g. "Amul butter"'}) =>
    showModalBottomSheet<String>(
      context: context,
      isDismissible: true,
      showDragHandle: false,
      builder: (_) => _VoiceSheet(prompt: prompt),
    );

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet({required this.prompt});
  final String prompt;

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> with SingleTickerProviderStateMixin {
  static final _stt = SpeechToText();
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  String _words = '';
  String? _error;
  bool _listening = false;
  double _level = 0;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _pulse.dispose();
    if (_stt.isListening) _stt.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _error = null;
      _words = '';
    });
    final ok = await _stt.initialize(onError: _onError, onStatus: _onStatus);
    if (!mounted) return;
    if (!ok) {
      setState(() => _error = 'Voice search isn\'t available. Allow microphone access, or type instead.');
      return;
    }
    setState(() => _listening = true);
    await _stt.listen(
      onResult: _onResult,
      onSoundLevelChange: (l) {
        if (mounted) setState(() => _level = l);
      },
      listenOptions: SpeechListenOptions(
        localeId: 'en_IN',
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        listenMode: ListenMode.search,
        cancelOnError: true,
      ),
    );
  }

  void _onResult(SpeechRecognitionResult r) {
    if (!mounted) return;
    setState(() => _words = r.recognizedWords);
    if (r.finalResult) _finish();
  }

  void _onStatus(String s) {
    if (!mounted) return;
    if (s == 'done' || s == 'notListening') {
      setState(() => _listening = false);
      if (_words.trim().isNotEmpty) _finish();
    }
  }

  void _onError(SpeechRecognitionError e) {
    if (!mounted) return;
    setState(() {
      _listening = false;
      _error = switch (e.errorMsg) {
        'error_no_match' || 'error_speech_timeout' => 'Didn\'t catch that. Tap the mic and try again.',
        'error_network' || 'error_network_timeout' => 'Voice search needs an internet connection.',
        'error_permission' || 'error_insufficient_permissions' => 'Allow microphone access to search by voice.',
        _ => 'Voice search stopped. Tap the mic to try again.',
      };
    });
  }

  void _finish() {
    if (_done) return;
    final w = _words.trim();
    if (w.isEmpty) return;
    _done = true;
    _stt.stop();
    Navigator.pop(context, w);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _error ?? (_words.isEmpty ? (_listening ? 'Listening…' : 'Starting…') : _words),
              textAlign: TextAlign.center,
              style: _words.isEmpty || _error != null
                  ? context.t.titleMedium!.copyWith(color: _error != null ? c.danger : c.ink)
                  : context.t.headlineMedium!.copyWith(fontSize: 24),
            ),
            const SizedBox(height: Space.xs),
            if (_error == null)
              Text(widget.prompt, textAlign: TextAlign.center, style: context.t.bodySmall),
            const SizedBox(height: Space.xl),
            GestureDetector(
              onTap: _listening ? _finish : _start,
              child: SizedBox(
                width: 132,
                height: 132,
                child: AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) {
                    // Rings breathe with time and swell with the voice level.
                    final lvl = (_level.clamp(-2, 10) + 2) / 12;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_listening)
                          for (var i = 0; i < 2; i++)
                            Builder(
                              builder: (_) {
                                final t = (_pulse.value + i * 0.5) % 1.0;
                                return Container(
                                  width: 76 + 56 * t + 16 * lvl,
                                  height: 76 + 56 * t + 16 * lvl,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: c.primary.withValues(alpha: 0.22 * (1 - t)),
                                  ),
                                );
                              },
                            ),
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: c.hero,
                            boxShadow: [
                              BoxShadow(
                                color: c.primary.withValues(alpha: 0.35),
                                blurRadius: 18 + 10 * math.max(0, lvl),
                              ),
                            ],
                          ),
                          child: Icon(_listening ? Icons.mic_rounded : Icons.mic_none_rounded, color: Colors.white, size: 34),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: Space.md),
            Text(
              _listening ? 'Tap to finish' : 'Tap the mic to speak',
              style: context.t.labelMedium!.copyWith(color: c.inkMuted),
            ),
          ],
        ),
      ),
    );
  }
}
