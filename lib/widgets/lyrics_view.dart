import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:asteroid/models/lyric_line.dart';
import 'package:asteroid/services/lyrics_service.dart';

class LyricsView extends StatefulWidget {
  final String trackName;
  final String artistName;
  final AudioPlayer audioPlayer;

  const LyricsView({
    Key? key,
    required this.trackName,
    required this.artistName,
    required this.audioPlayer,
  }) : super(key: key);

  @override
  _LyricsViewState createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final LyricsService _lyricsService = LyricsService();
  Future<List<LyricLine>>? _lyricsFuture;
  final ScrollController _scrollController = ScrollController();
  int _currentLineIndex = -1;

  @override
  void initState() {
    super.initState();
    _lyricsFuture = _lyricsService.getLyricsForSong(widget.trackName, widget.artistName);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<LyricLine>>(
      future: _lyricsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return const Center(child: Text('No lyrics found.'));
        }

        final lyrics = snapshot.data!;

        return StreamBuilder<Duration>(
          stream: widget.audioPlayer.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;

            int newIndex = lyrics.lastIndexWhere((line) => line.timestamp <= position);
            if (newIndex < 0) newIndex = 0;

            if (newIndex != _currentLineIndex) {
              _currentLineIndex = newIndex;
              if (_scrollController.hasClients) {
                _scrollController.animateTo(
                  _currentLineIndex * 60.0, // Assuming a fixed line height
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                );
              }
            }

            return ListView.builder(
              controller: _scrollController,
              itemCount: lyrics.length,
              itemBuilder: (context, index) {
                final line = lyrics[index];
                final isCurrent = index == _currentLineIndex;

                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
                  child: Text(
                    line.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isCurrent ? 22 : 18,
                      color: isCurrent ? Colors.white : Colors.white.withOpacity(0.6),
                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
