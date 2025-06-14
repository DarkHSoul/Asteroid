import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:provider/provider.dart';
import 'package:asteroid/providers/library_provider.dart';

class SongListItem extends StatelessWidget {
  final MediaItem song;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback? onRemove;
  final bool showFavorite;

  const SongListItem({
    super.key,
    required this.song,
    required this.isPlaying,
    required this.onPlay,
    this.onRemove,
    this.showFavorite = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: song.artUri != null
            ? Image.network(
                song.artUri.toString(),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: 48,
                  height: 48,
                  color: Colors.grey[300],
                  child: const Icon(Icons.music_note),
                ),
              )
            : Container(
                width: 48,
                height: 48,
                color: Colors.grey[300],
                child: const Icon(Icons.music_note),
              ),
      ),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: isPlaying ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        song.artist ?? 'Unknown Artist',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showFavorite)
            Consumer<LibraryProvider>(
              builder: (context, library, child) {
                final isFavorite = library.isFavorite(song);
                return IconButton(
                  icon: Icon(
                    isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: isFavorite ? Colors.red : null,
                  ),
                  onPressed: () => library.toggleFavorite(song),
                );
              },
            ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: onRemove,
            ),
          IconButton(
            icon: Icon(isPlaying ? Icons.pause : Icons.play_arrow),
            onPressed: onPlay,
          ),
        ],
      ),
    );
  }
}
