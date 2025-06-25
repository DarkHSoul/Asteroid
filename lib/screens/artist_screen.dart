import 'package:flutter/material.dart';
import 'package:asteroid/api/youtube_api_service.dart';
import 'package:provider/provider.dart';
import 'package:asteroid/audio_handler.dart';

class ArtistScreen extends StatefulWidget {
  final String artistName;

  const ArtistScreen({super.key, required this.artistName});

  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  late Future<List<YoutubeMusicVideo>> _artistSongsFuture;

  @override
  void initState() {
    super.initState();
    _artistSongsFuture = YouTubeApiService().searchMusic(widget.artistName);
  }

  @override
  Widget build(BuildContext context) {
    final audioHandler = Provider.of<MyAudioHandler>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.artistName),
      ),
      body: FutureBuilder<List<YoutubeMusicVideo>>(
        future: _artistSongsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('No songs found for this artist.'));
          }

          final songs = snapshot.data!;
          return ListView.builder(
            itemCount: songs.length,
            itemBuilder: (context, index) {
              final song = songs[index];
              return ListTile(
                leading: Image.network(song.thumbnailUrl),
                title: Text(song.title),
                subtitle: Text(song.artist),
                onTap: () {
                  final mediaItem = YouTubeApiService().youtubeVideoToMediaItem(song);
                  audioHandler.playMediaItem(mediaItem, isFromSearch: true);
                },
              );
            },
          );
        },
      ),
    );
  }
}
