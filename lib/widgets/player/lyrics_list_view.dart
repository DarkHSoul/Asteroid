import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:asteroid/audio_handler.dart';
import 'package:asteroid/widgets/lyrics_view.dart';

class LyricsListView extends StatelessWidget {
  const LyricsListView({super.key});

  @override
  Widget build(BuildContext context) {
    final audioHandler = Provider.of<MyAudioHandler>(context);
    final mediaItem = audioHandler.mediaItem.value;

    if (mediaItem == null) {
      return const Center(
        child: Text('No song selected.'),
      );
    }

    return LyricsView(
      trackName: mediaItem.title,
      artistName: mediaItem.artist ?? '',
      audioPlayer: audioHandler.player,
    );
  }
}
