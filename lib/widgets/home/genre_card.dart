import 'package:flutter/material.dart';

class Genre {
  final String name;
  final IconData icon;
  final Color color;

  const Genre({
    required this.name,
    required this.icon,
    required this.color,
  });

  static const List<Genre> predefinedGenres = [
    Genre(
      name: 'Pop',
      icon: Icons.music_note,
      color: Colors.pink,
    ),
    Genre(
      name: 'Rock',
      icon: Icons.electric_guitar,
      color: Colors.purple,
    ),
    Genre(
      name: 'Hip Hop',
      icon: Icons.mic,
      color: Colors.orange,
    ),
    Genre(
      name: 'Electronic',
      icon: Icons.electric_bolt,
      color: Colors.blue,
    ),
    Genre(
      name: 'Jazz',
      icon: Icons.piano,
      color: Colors.amber,
    ),
    Genre(
      name: 'Classical',
      icon: Icons.music_note,
      color: Colors.teal,
    ),
    Genre(
      name: 'R&B',
      icon: Icons.queue_music,
      color: Colors.red,
    ),
    Genre(
      name: 'Country',
      icon: Icons.music_note,
      color: Colors.brown,
    ),
  ];
}

class GenreCard extends StatelessWidget {
  final Genre genre;
  final VoidCallback onTap;

  const GenreCard({
    super.key,
    required this.genre,
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
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                genre.color,
                genre.color.withOpacity(0.7),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20,
                bottom: -20,
                child: Icon(
                  genre.icon,
                  size: 100,
                  color: Colors.white.withOpacity(0.2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      genre.icon,
                      color: Colors.white,
                      size: 32,
                    ),
                    const Spacer(),
                    Text(
                      genre.name,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
