import 'package:flutter/foundation.dart';
import 'package:shared_preferences.dart';
import 'dart:convert';

enum AudioQuality {
  auto,
  low,
  medium,
  high,
}

enum DownloadQuality {
  medium,
  high,
}

class EqualizerPreset {
  final String name;
  final List<double> bands;

  const EqualizerPreset({
    required this.name,
    required this.bands,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'bands': bands,
  };

  factory EqualizerPreset.fromJson(Map<String, dynamic> json) {
    return EqualizerPreset(
      name: json['name'] as String,
      bands: (json['bands'] as List).cast<double>(),
    );
  }

  static const List<EqualizerPreset> defaults = [
    EqualizerPreset(
      name: 'Flat',
      bands: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    ),
    EqualizerPreset(
      name: 'Bass Boost',
      bands: [6, 4, 2, 0, 0, 0, 0, 0, 0, 0],
    ),
    EqualizerPreset(
      name: 'Treble Boost',
      bands: [0, 0, 0, 0, 0, 0, 2, 4, 6, 8],
    ),
    EqualizerPreset(
      name: 'Electronic',
      bands: [4, 3, 0, -2, -3, -2, 0, 2, 4, 5],
    ),
    EqualizerPreset(
      name: 'Rock',
      bands: [4, 3, 2, 0, -1, -1, 0, 2, 3, 4],
    ),
    EqualizerPreset(
      name: 'Classical',
      bands: [0, 0, 0, 0, 0, 0, -2, -3, -3, -4],
    ),
  ];
}

class SettingsProvider with ChangeNotifier {
  late SharedPreferences _prefs;
  
  // Audio settings
  AudioQuality _streamingQuality = AudioQuality.auto;
  bool _autoAdjustQuality = true;
  double _volume = 1.0;
  bool _normalizeVolume = true;

  // Download settings
  DownloadQuality _downloadQuality = DownloadQuality.high;
  bool _downloadOverWifiOnly = true;
  String _downloadLocation = 'Music/Asteroid';

  // Cache settings
  int _maxCacheSize = 1024; // MB
  bool _autoClearCache = true;
  int _cacheDuration = 7; // days

  // Equalizer settings
  bool _equalizerEnabled = false;
  EqualizerPreset _currentPreset = EqualizerPreset.defaults.first;
  List<EqualizerPreset> _customPresets = [];

  // Getters
  AudioQuality get streamingQuality => _streamingQuality;
  bool get autoAdjustQuality => _autoAdjustQuality;
  double get volume => _volume;
  bool get normalizeVolume => _normalizeVolume;
  DownloadQuality get downloadQuality => _downloadQuality;
  bool get downloadOverWifiOnly => _downloadOverWifiOnly;
  String get downloadLocation => _downloadLocation;
  int get maxCacheSize => _maxCacheSize;
  bool get autoClearCache => _autoClearCache;
  int get cacheDuration => _cacheDuration;
  bool get equalizerEnabled => _equalizerEnabled;
  EqualizerPreset get currentPreset => _currentPreset;
  List<EqualizerPreset> get customPresets => _customPresets;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    _prefs = await SharedPreferences.getInstance();
    
    // Load audio settings
    _streamingQuality = AudioQuality.values[_prefs.getInt('streamingQuality') ?? 0];
    _autoAdjustQuality = _prefs.getBool('autoAdjustQuality') ?? true;
    _volume = _prefs.getDouble('volume') ?? 1.0;
    _normalizeVolume = _prefs.getBool('normalizeVolume') ?? true;

    // Load download settings
    _downloadQuality = DownloadQuality.values[_prefs.getInt('downloadQuality') ?? 1];
    _downloadOverWifiOnly = _prefs.getBool('downloadOverWifiOnly') ?? true;
    _downloadLocation = _prefs.getString('downloadLocation') ?? 'Music/Asteroid';

    // Load cache settings
    _maxCacheSize = _prefs.getInt('maxCacheSize') ?? 1024;
    _autoClearCache = _prefs.getBool('autoClearCache') ?? true;
    _cacheDuration = _prefs.getInt('cacheDuration') ?? 7;

    // Load equalizer settings
    _equalizerEnabled = _prefs.getBool('equalizerEnabled') ?? false;
    final presetJson = _prefs.getString('currentPreset');
    if (presetJson != null) {
      _currentPreset = EqualizerPreset.fromJson(json.decode(presetJson));
    }

    final customPresetsJson = _prefs.getString('customPresets');
    if (customPresetsJson != null) {
      final List<dynamic> presets = json.decode(customPresetsJson);
      _customPresets = presets
          .map((preset) => EqualizerPreset.fromJson(preset))
          .toList();
    }

    notifyListeners();
  }

  Future<void> _saveSettings() async {
    // Save audio settings
    await _prefs.setInt('streamingQuality', _streamingQuality.index);
    await _prefs.setBool('autoAdjustQuality', _autoAdjustQuality);
    await _prefs.setDouble('volume', _volume);
    await _prefs.setBool('normalizeVolume', _normalizeVolume);

    // Save download settings
    await _prefs.setInt('downloadQuality', _downloadQuality.index);
    await _prefs.setBool('downloadOverWifiOnly', _downloadOverWifiOnly);
    await _prefs.setString('downloadLocation', _downloadLocation);

    // Save cache settings
    await _prefs.setInt('maxCacheSize', _maxCacheSize);
    await _prefs.setBool('autoClearCache', _autoClearCache);
    await _prefs.setInt('cacheDuration', _cacheDuration);

    // Save equalizer settings
    await _prefs.setBool('equalizerEnabled', _equalizerEnabled);
    await _prefs.setString('currentPreset', json.encode(_currentPreset.toJson()));
    await _prefs.setString('customPresets', 
      json.encode(_customPresets.map((preset) => preset.toJson()).toList()));
  }

  // Audio settings methods
  void setStreamingQuality(AudioQuality quality) {
    _streamingQuality = quality;
    _saveSettings();
    notifyListeners();
  }

  void setAutoAdjustQuality(bool value) {
    _autoAdjustQuality = value;
    _saveSettings();
    notifyListeners();
  }

  void setVolume(double value) {
    _volume = value.clamp(0.0, 1.0);
    _saveSettings();
    notifyListeners();
  }

  void setNormalizeVolume(bool value) {
    _normalizeVolume = value;
    _saveSettings();
    notifyListeners();
  }

  // Download settings methods
  void setDownloadQuality(DownloadQuality quality) {
    _downloadQuality = quality;
    _saveSettings();
    notifyListeners();
  }

  void setDownloadOverWifiOnly(bool value) {
    _downloadOverWifiOnly = value;
    _saveSettings();
    notifyListeners();
  }

  void setDownloadLocation(String path) {
    _downloadLocation = path;
    _saveSettings();
    notifyListeners();
  }

  // Cache settings methods
  void setMaxCacheSize(int sizeMB) {
    _maxCacheSize = sizeMB;
    _saveSettings();
    notifyListeners();
  }

  void setAutoClearCache(bool value) {
    _autoClearCache = value;
    _saveSettings();
    notifyListeners();
  }

  void setCacheDuration(int days) {
    _cacheDuration = days;
    _saveSettings();
    notifyListeners();
  }

  Future<void> clearCache() async {
    // TODO: Implement actual cache clearing logic
    notifyListeners();
  }

  // Equalizer settings methods
  void setEqualizerEnabled(bool value) {
    _equalizerEnabled = value;
    _saveSettings();
    notifyListeners();
  }

  void setCurrentPreset(EqualizerPreset preset) {
    _currentPreset = preset;
    _saveSettings();
    notifyListeners();
  }

  void addCustomPreset(EqualizerPreset preset) {
    _customPresets.add(preset);
    _saveSettings();
    notifyListeners();
  }

  void removeCustomPreset(EqualizerPreset preset) {
    _customPresets.remove(preset);
    _saveSettings();
    notifyListeners();
  }

  void updateCustomPreset(int index, EqualizerPreset preset) {
    if (index >= 0 && index < _customPresets.length) {
      _customPresets[index] = preset;
      _saveSettings();
      notifyListeners();
    }
  }
}
