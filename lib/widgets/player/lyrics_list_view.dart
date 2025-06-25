import 'package:flutter/material.dart';

class LyricsListView extends StatelessWidget {
  const LyricsListView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32.0),
        child: Text(
          'No lyrics found',
          style: TextStyle(fontStyle: FontStyle.italic),
        ),
      ),
    );
  }
}
