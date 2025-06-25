import 'package:flutter/material.dart';

class SimilarSongsView extends StatelessWidget {
  const SimilarSongsView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Text(
          'Similar songs feature coming soon!',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}
