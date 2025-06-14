import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';

class SongCard extends StatelessWidget {
  final MediaItem song;
  final bool isPlaying;
  final VoidCallback onTap;

  const SongCard({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  song.artUri != null
                      ? Image.network(
                          song.artUri.toString(),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            color: Theme.of(context).primaryColor.withOpacity(0.1),
                            child: const Icon(Icons.music_note, size: 48),
                          ),
                        )
                      : Container(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          child: const Icon(Icons.music_note, size: 48),
                        ),
                  if (isPlaying)
                    Container(
                      color: Colors.black38,
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          size: 48,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (song.artist != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      song.artist!,
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
