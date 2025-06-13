import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asteroid/providers/settings_provider.dart';
import 'package:asteroid/providers/search_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            children: [
              // Audio Settings Section
              _SettingsSection(
                title: 'Audio',
                children: [
                  ListTile(
                    title: const Text('Streaming Quality'),
                    subtitle: Text(settings.streamingQuality.toString().split('.').last),
                    onTap: () => _showQualityDialog(context, settings),
                  ),
                  SwitchListTile(
                    title: const Text('Auto-adjust Quality'),
                    subtitle: const Text('Automatically adjust quality based on network'),
                    value: settings.autoAdjustQuality,
                    onChanged: settings.setAutoAdjustQuality,
                  ),
                  ListTile(
                    title: const Text('Volume'),
                    subtitle: Slider(
                      value: settings.volume,
                      onChanged: settings.setVolume,
                      divisions: 20,
                      label: '${(settings.volume * 100).round()}%',
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('Normalize Volume'),
                    subtitle: const Text('Maintain consistent volume across tracks'),
                    value: settings.normalizeVolume,
                    onChanged: settings.setNormalizeVolume,
                  ),
                ],
              ),

              // Download Settings Section
              _SettingsSection(
                title: 'Downloads',
                children: [
                  ListTile(
                    title: const Text('Download Quality'),
                    subtitle: Text(settings.downloadQuality.toString().split('.').last),
                    onTap: () => _showDownloadQualityDialog(context, settings),
                  ),
                  SwitchListTile(
                    title: const Text('Download over Wi-Fi only'),
                    value: settings.downloadOverWifiOnly,
                    onChanged: settings.setDownloadOverWifiOnly,
                  ),
                  ListTile(
                    title: const Text('Download Location'),
                    subtitle: Text(settings.downloadLocation),
                    onTap: () => _showDownloadLocationDialog(context, settings),
                  ),
                ],
              ),

              // Cache Settings Section
              _SettingsSection(
                title: 'Cache',
                children: [
                  ListTile(
                    title: const Text('Maximum Cache Size'),
                    subtitle: Text('${settings.maxCacheSize} MB'),
                    onTap: () => _showCacheSizeDialog(context, settings),
                  ),
                  SwitchListTile(
                    title: const Text('Auto-clear Cache'),
                    subtitle: Text('Clear cache older than ${settings.cacheDuration} days'),
                    value: settings.autoClearCache,
                    onChanged: settings.setAutoClearCache,
                  ),
                  ListTile(
                    title: const Text('Cache Duration'),
                    subtitle: Text('${settings.cacheDuration} days'),
                    onTap: () => _showCacheDurationDialog(context, settings),
                  ),
                  ListTile(
                    title: const Text('Clear Cache'),
                    subtitle: const Text('Free up storage space'),
                    onTap: () => _showClearCacheDialog(context, settings),
                  ),
                  Consumer<SearchProvider>(
                    builder: (context, searchProvider, child) {
                      return ListTile(
                        title: const Text('Clear Search History'),
                        subtitle: const Text('Clear search cache and history'),
                        onTap: () => _showClearSearchDialog(context, searchProvider),
                      );
                    },
                  ),
                ],
              ),

              // Equalizer Settings Section
              _SettingsSection(
                title: 'Equalizer',
                children: [
                  SwitchListTile(
                    title: const Text('Enable Equalizer'),
                    value: settings.equalizerEnabled,
                    onChanged: settings.setEqualizerEnabled,
                  ),
                  if (settings.equalizerEnabled) ...[
                    ListTile(
                      title: const Text('Preset'),
                      subtitle: Text(settings.currentPreset.name),
                      onTap: () => _showEqualizerPresetDialog(context, settings),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _EqualizerBands(
                        preset: settings.currentPreset,
                        onChanged: (preset) => settings.setCurrentPreset(preset),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  void _showQualityDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Streaming Quality'),
        children: AudioQuality.values.map((quality) {
          return SimpleDialogOption(
            onPressed: () {
              settings.setStreamingQuality(quality);
              Navigator.pop(context);
            },
            child: Text(quality.toString().split('.').last),
          );
        }).toList(),
      ),
    );
  }

  void _showDownloadQualityDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Download Quality'),
        children: DownloadQuality.values.map((quality) {
          return SimpleDialogOption(
            onPressed: () {
              settings.setDownloadQuality(quality);
              Navigator.pop(context);
            },
            child: Text(quality.toString().split('.').last),
          );
        }).toList(),
      ),
    );
  }

  void _showDownloadLocationDialog(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController(text: settings.downloadLocation);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Download Location'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter download path',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settings.setDownloadLocation(controller.text);
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showCacheSizeDialog(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController(
      text: settings.maxCacheSize.toString(),
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Maximum Cache Size'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            suffixText: 'MB',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final size = int.tryParse(controller.text);
              if (size != null && size > 0) {
                settings.setMaxCacheSize(size);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showCacheDurationDialog(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController(
      text: settings.cacheDuration.toString(),
    );
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cache Duration'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            suffixText: 'days',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final days = int.tryParse(controller.text);
              if (days != null && days > 0) {
                settings.setCacheDuration(days);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showClearCacheDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Cache'),
        content: const Text('Are you sure you want to clear the cache?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              settings.clearCache();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Cache cleared')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showClearSearchDialog(BuildContext context, SearchProvider searchProvider) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Search History'),
        content: const Text('Are you sure you want to clear your search history?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              searchProvider.clearCache();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Search history cleared')),
              );
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _showEqualizerPresetDialog(BuildContext context, SettingsProvider settings) {
    showDialog(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Equalizer Preset'),
        children: [
          ...EqualizerPreset.defaults.map((preset) {
            return SimpleDialogOption(
              onPressed: () {
                settings.setCurrentPreset(preset);
                Navigator.pop(context);
              },
              child: Text(preset.name),
            );
          }),
          if (settings.customPresets.isNotEmpty) const Divider(),
          ...settings.customPresets.map((preset) {
            return SimpleDialogOption(
              onPressed: () {
                settings.setCurrentPreset(preset);
                Navigator.pop(context);
              },
              child: Text(preset.name),
            );
          }),
          const Divider(),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(context);
              _showSavePresetDialog(context, settings);
            },
            child: const Text('Save Current as Preset...'),
          ),
        ],
      ),
    );
  }

  void _showSavePresetDialog(BuildContext context, SettingsProvider settings) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Save Preset'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Preset name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                settings.addCustomPreset(EqualizerPreset(
                  name: controller.text,
                  bands: settings.currentPreset.bands,
                ));
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsSection({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
      ],
    );
  }
}

class _EqualizerBands extends StatelessWidget {
  final EqualizerPreset preset;
  final ValueChanged<EqualizerPreset> onChanged;

  const _EqualizerBands({
    required this.preset,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(
        preset.bands.length,
        (index) => _EqualizerBand(
          frequency: _getFrequency(index),
          value: preset.bands[index],
          onChanged: (value) {
            final newBands = List<double>.from(preset.bands);
            newBands[index] = value;
            onChanged(EqualizerPreset(
              name: preset.name,
              bands: newBands,
            ));
          },
        ),
      ),
    );
  }

  String _getFrequency(int index) {
    final frequencies = [
      '32Hz',
      '64Hz',
      '125Hz',
      '250Hz',
      '500Hz',
      '1kHz',
      '2kHz',
      '4kHz',
      '8kHz',
      '16kHz'
    ];
    return frequencies[index];
  }
}

class _EqualizerBand extends StatelessWidget {
  final String frequency;
  final double value;
  final ValueChanged<double> onChanged;

  const _EqualizerBand({
    required this.frequency,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RotatedBox(
          quarterTurns: -1,
          child: SizedBox(
            height: 150,
            child: Slider(
              value: value,
              min: -12,
              max: 12,
              divisions: 48,
              onChanged: onChanged,
            ),
          ),
        ),
        Text(
          frequency,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
