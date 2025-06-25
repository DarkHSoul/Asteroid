import 'package:flutter/material.dart';

class AlbumArt extends StatelessWidget {
  final String? imageUrl;

  const AlbumArt({
    super.key,
    required this.imageUrl,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: imageUrl != null
            ? Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              )
            : Container(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                child: const Icon(
                  Icons.music_note,
                  size: 64,
                ),
              ),
      ),
    );
  }
}
