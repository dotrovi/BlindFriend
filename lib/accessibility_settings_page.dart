import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'services/accessibility_settings.dart';
import 'theme/app_palette.dart';

class AccessibilitySettingsPage extends StatefulWidget {
  const AccessibilitySettingsPage({super.key});

  @override
  State<AccessibilitySettingsPage> createState() =>
      _AccessibilitySettingsPageState();
}

class _AccessibilitySettingsPageState extends State<AccessibilitySettingsPage> {
  final AccessibilitySettings _settings = AccessibilitySettings.instance;
  final FlutterTts _tts = FlutterTts();
  final SpeechToText _stt = SpeechToText();

  bool _sttAvailable = false;
  bool _isListening = false;

  static const String _voiceInstruction =
      'Say small, medium, large, or extra large to change font size. '
      'Say enable contrast or disable contrast for high contrast mode. '
      'Say reset to restore defaults, or back to home page to return.';

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
    _initVoice();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _stt.stop();
    _tts.stop();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initVoice() async {
    final micStatus = await Permission.microphone.request();
    if (!mounted) return;

    if (micStatus.isGranted) {
      _sttAvailable = await _stt.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'listening') {
            setState(() => _isListening = true);
          } else if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (error) {
          debugPrint('STT error: ${error.errorMsg}');
          if (mounted) setState(() => _isListening = false);
        },
      );
    }

    if (mounted) {
      await _speak('This is accessibility settings. $_voiceInstruction');
    }
  }

  Future<void> _pressMic() async {
    if (!_sttAvailable || _isListening) return;
    setState(() => _isListening = true);
    await _stt.listen(
      onResult: (result) {
        if (!mounted || !result.finalResult) return;
        _handleVoiceCommand(result.recognizedWords.toLowerCase());
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 10),
      localeId: 'en_US',
    );
  }

  void _handleVoiceCommand(String command) {
    if (command.contains('back') && command.contains('home')) {
      _speak('Returning to home page.');
      Navigator.of(context).popUntil((route) => route.isFirst);
    } else if (command.contains('extra large')) {
      _selectFontSize(FontSizeOption.extraLarge);
    } else if (command.contains('large')) {
      _selectFontSize(FontSizeOption.large);
    } else if (command.contains('medium')) {
      _selectFontSize(FontSizeOption.medium);
    } else if (command.contains('small')) {
      _selectFontSize(FontSizeOption.small);
    } else if (command.contains('disable contrast') ||
        command.contains('turn off contrast') ||
        command.contains('contrast off')) {
      _toggleHighContrast(false);
    } else if (command.contains('contrast')) {
      _toggleHighContrast(true);
    } else if (command.contains('reset')) {
      _resetToDefault();
    } else {
      _speak('I did not catch that. $_voiceInstruction');
    }
  }

  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  Future<void> _selectFontSize(FontSizeOption option) async {
    await _settings.setFontSizeOption(option);
    await _speak('Font size set to ${option.label}.');
  }

  Future<void> _toggleHighContrast(bool enabled) async {
    await _settings.setHighContrast(enabled);
    await _speak(
        enabled ? 'High contrast enabled.' : 'High contrast disabled.');
  }

  Future<void> _resetToDefault() async {
    await _settings.reset();
    await _speak('Accessibility settings reset to default.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kNavyDeep,
      appBar: AppBar(
        backgroundColor: kNavyMid,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Accessibility Settings',
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Voice Command Card
            GestureDetector(
              onTap: _pressMic,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: kCardFill.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (_isListening ? Colors.greenAccent : kPinkBright)
                        .withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _isListening
                            ? const LinearGradient(
                                colors: [Colors.green, Colors.lightGreen],
                              )
                            : kAccentGradient,
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening ? Colors.green : kPinkBright)
                                .withValues(alpha: 0.5),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isListening ? 'Listening...' : 'Voice Command',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _voiceInstruction,
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildSectionCard(
              title: 'Font Size',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: FontSizeOption.values
                        .map((option) => _buildFontSizeChip(option))
                        .toList(),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Aa Sample text',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18 * _settings.fontScale,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: 'Contrast',
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'High Contrast Mode',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                subtitle: const Text(
                  'Increases contrast between text, icons, and backgrounds '
                  'throughout the app to make content easier to see.',
                  style: TextStyle(color: Colors.white60),
                ),
                activeThumbColor: kPinkBright,
                value: _settings.highContrastEnabled,
                onChanged: _toggleHighContrast,
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: TextButton(
                onPressed: _resetToDefault,
                child: const Text(
                  'Reset to Default',
                  style: TextStyle(color: kBlueAccent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCardFill.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildFontSizeChip(FontSizeOption option) {
    final bool selected = _settings.fontSizeOption == option;
    return InkWell(
      onTap: () => _selectFontSize(option),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          gradient: selected ? kAccentGradient : null,
          color: selected ? null : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? Colors.transparent
                : Colors.white.withValues(alpha: 0.15),
          ),
        ),
        child: Text(
          option.label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
