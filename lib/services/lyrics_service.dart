import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:asteroid/models/lyric_line.dart';

class LyricsService {
  final String _baseUrl = 'https://lrclib.net/api';

  Future<List<LyricLine>> getLyricsForSong(String trackName, String artistName) async {
    print('[LyricsService] Fetching lyrics for: Track="$trackName", Artist="$artistName"');

    if (trackName.isEmpty) {
      print('[LyricsService] Error: Track name is empty. Aborting.');
      return [];
    }

    final Uri searchUrl = Uri.parse('$_baseUrl/search?track_name=${Uri.encodeComponent(trackName)}&artist_name=${Uri.encodeComponent(artistName)}');
    print('[LyricsService] Requesting URL: $searchUrl');

    try {
      final response = await http.get(searchUrl).timeout(const Duration(seconds: 15));

      print('[LyricsService] Response Status Code: ${response.statusCode}');
      // Only print the body if it's not too long to avoid cluttering logs
      if (response.body.length < 500) {
        print('[LyricsService] Response Body: ${response.body}');
      } else {
        print('[LyricsService] Response Body (truncated): ${response.body.substring(0, 500)}');
      }

      if (response.statusCode == 200) {
        final List<dynamic> searchResults = json.decode(response.body);

        if (searchResults.isNotEmpty) {
          final firstResult = searchResults[0];
          final String? syncedLyrics = firstResult['syncedLyrics'];

          if (syncedLyrics != null && syncedLyrics.isNotEmpty) {
            print('[LyricsService] Found synced lyrics. Parsing...');
            final parsedLyrics = _parseLrc(syncedLyrics);
            print('[LyricsService] Successfully parsed ${parsedLyrics.length} lines.');
            return parsedLyrics;
          } else {
            print('[LyricsService] No synced lyrics found in the first result.');
          }
        } else {
          print('[LyricsService] Search returned no results.');
        }
      } else {
        print('[LyricsService] API request failed with status code ${response.statusCode}.');
      }
    } catch (e) {
      print('[LyricsService] An exception occurred while fetching lyrics: $e');
    }

    print('[LyricsService] Returning empty list.');
    return []; // Return empty list if no lyrics are found or an error occurs
  }

  List<LyricLine> _parseLrc(String lrc) {
    final List<LyricLine> lines = [];
    final lrcRegex = RegExp(r'^\[(\d{2}):(\d{2})\.(\d{2,3})\](.*)$');

    for (final line in lrc.split('\n')) {
      final match = lrcRegex.firstMatch(line);
      if (match != null) {
        final min = int.parse(match.group(1)!);
        final sec = int.parse(match.group(2)!);
        final msText = match.group(3)!.padRight(3, '0');
        final ms = int.parse(msText);
        final text = match.group(4)!.trim();

        lines.add(LyricLine(Duration(minutes: min, seconds: sec, milliseconds: ms), text));
      }
    }
    lines.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return lines;
  }
}