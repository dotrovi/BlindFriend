import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
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

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    _tts.stop();
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
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
