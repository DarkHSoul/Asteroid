import 'package:flutter/foundation.dart';
import 'package:audio_service/audio_service.dart';
import 'package:shared_preferences.dart';
import 'dart:math';

enum RepeatMode {
  off,
  all,
  one,
}

class QueueProvider with ChangeNotifier {
  final AudioHandler audioHandler;
  List<MediaItem> _queue = [];
  bool _shuffleMode = false;
  RepeatMode _repeatMode = RepeatMode.off;
  List<MediaItem> _originalQueue = [];

  QueueProvider(this.audioHandler) {
    _loadPreferences();
    _initializeQueueListener();
  }

  List<MediaItem> get queue => _queue;
  bool get shuffleMode => _shuffleMode;
  RepeatMode get repeatMode => _repeatMode;
  List<MediaItem> get originalQueue => _originalQueue;

  void _initializeQueueListener() {
    audioHandler.queue.listen((queue) {
      _queue = queue;
      notifyListeners();
    });
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    _shuffleMode = prefs.getBool('shuffleMode') ?? false;
    _repeatMode = RepeatMode.values[prefs.getInt('repeatMode') ?? 0];
    notifyListeners();
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('shuffleMode', _shuffleMode);
    await prefs.setInt('repeatMode', _repeatMode.index);
  }

  Future<void> toggleShuffle() async {
    _shuffleMode = !_shuffleMode;
    if (_shuffleMode) {
      _originalQueue = List.from(_queue);
      await _shuffleQueue();
    } else {
      await _restoreOriginalQueue();
    }
    await _savePreferences();
    notifyListeners();
  }

  Future<void> _shuffleQueue() async {
    if (_queue.isEmpty) return;

    final currentItem = await audioHandler.mediaItem.first;
    if (currentItem == null) return;

    final currentIndex = _queue.indexWhere((item) => item.id == currentItem.id);
    if (currentIndex == -1) return;

    // Remove current item
    final current = _queue.removeAt(currentIndex);
    
    // Shuffle remaining items
    final random = Random();
    for (var i = _queue.length - 1; i > 0; i--) {
      final j = random.nextInt(i + 1);
      final temp = _queue[i];
      _queue[i] = _queue[j];
      _queue[j] = temp;
    }

    // Put current item back at the start
    _queue.insert(0, current);

    // Update audio handler queue
    await _updateAudioHandlerQueue();
  }

  Future<void> _restoreOriginalQueue() async {
    if (_originalQueue.isEmpty) return;

    final currentItem = await audioHandler.mediaItem.first;
    if (currentItem == null) return;

    _queue = List.from(_originalQueue);
    await _updateAudioHandlerQueue();
  }

  Future<void> cycleRepeatMode() async {
    final values = RepeatMode.values;
    final currentIndex = values.indexOf(_repeatMode);
    _repeatMode = values[(currentIndex + 1) % values.length];
    await _savePreferences();
    notifyListeners();
  }

  Future<void> removeItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _queue.removeAt(index);
    await _updateAudioHandlerQueue();
    notifyListeners();
  }

  Future<void> moveItem(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0 || newIndex >= _queue.length) return;

    final item = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, item);
    await _updateAudioHandlerQueue();
    notifyListeners();
  }

  Future<void> addItems(List<MediaItem> items) async {
    _queue.addAll(items);
    if (_shuffleMode) {
      _originalQueue.addAll(items);
    }
    await _updateAudioHandlerQueue();
    notifyListeners();
  }

  Future<void> clearQueue() async {
    _queue.clear();
    _originalQueue.clear();
    await _updateAudioHandlerQueue();
    notifyListeners();
  }

  Future<void> _updateAudioHandlerQueue() async {
    // Update the audio handler's queue
    await audioHandler.updateQueue(_queue);
  }

  Future<void> skipToNext() async {
    if (_repeatMode == RepeatMode.one) {
      // Restart current song
      await audioHandler.seek(Duration.zero);
      await audioHandler.play();
      return;
    }

    final currentItem = await audioHandler.mediaItem.first;
    if (currentItem == null) return;

    final currentIndex = _queue.indexWhere((item) => item.id == currentItem.id);
    if (currentIndex == -1) return;

    if (currentIndex < _queue.length - 1) {
      await audioHandler.skipToNext();
    } else if (_repeatMode == RepeatMode.all) {
      // Skip to first song if repeat all is enabled
      await audioHandler.skipToQueueItem(0);
    }
  }

  Future<void> skipToPrevious() async {
    if (_repeatMode == RepeatMode.one) {
      // Restart current song
      await audioHandler.seek(Duration.zero);
      await audioHandler.play();
      return;
    }

    final position = await audioHandler.position.first;
    if (position > const Duration(seconds: 3)) {
      // If more than 3 seconds into song, restart it
      await audioHandler.seek(Duration.zero);
    } else {
      await audioHandler.skipToPrevious();
    }
  }
}
