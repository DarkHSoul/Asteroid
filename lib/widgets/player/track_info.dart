import 'package:flutter/material.dart';

class TrackInfo extends StatelessWidget {
  final String title;
  final String? artist;
  final VoidCallback? onArtistTap;

  const TrackInfo({
    super.key,
    required this.title,
    this.artist,
    this.onArtistTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        if (artist != null)
          InkWell(
            onTap: onArtistTap,
            child: Text(
              artist!,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}
