import 'dart:convert';

import 'package:coil/src/services/wikimedia_feed_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('WikimediaFeedService', () {
    final mockFeed = {
      'tfa': {
        'title': 'Canary_Islands',
        'titles': {'normalized': 'Canary Islands'},
        'extract': 'The Canary Islands are an archipelago in the Atlantic Ocean.',
        'originalimage': {
          'source': 'https://upload.wikimedia.org/canary.jpg',
        },
      },
      'onthisday': [
        {
          'year': 1492,
          'text': 'Christopher Columbus sets sail from Palos de la Frontera.',
          'pages': [
            {
              'title': 'Christopher_Columbus',
              'originalimage': {
                'source': 'https://upload.wikimedia.org/columbus.jpg',
              },
            },
          ],
        },
        {
          'year': 1900,
          'text': 'Galveston Hurricane makes landfall in Texas without photographs available.',
          'pages': [],
        },
      ],
      'dyk': [
        {
          'text': '... that Zofia Rabcewicz gave more than 60 underground concerts in Warsaw during the Nazi occupation of Poland?',
        },
      ],
      'mostread': {
        'articles': [
          {
            'title': 'Quantum_computing',
            'titles': {'normalized': 'Quantum Computing'},
            'extract': 'Quantum computing is a rapidly-emerging technology.',
            'views': 85000,
            'thumbnail': {
              'source': 'https://upload.wikimedia.org/quantum.png',
            },
          },
        ],
      },
    };

    test('parses Wikimedia feed into featured, history, trivia, and trending posts', () {
      final service = WikimediaFeedService();
      final posts = service.parseFeedJson(mockFeed);

      expect(posts.length, 5);

      // 1. TFA
      final tfa = posts.firstWhere((p) => p.authorUsername.contains('Featured'));
      expect(tfa.caption, contains('Canary Islands'));
      expect(tfa.imageUrls, isNotEmpty);
      expect(tfa.discussKind, isNull);

      // 2. On this day (with image)
      final otdWithImg = posts.firstWhere((p) => p.caption.contains('Christopher Columbus'));
      expect(otdWithImg.imageUrls, isNotEmpty);
      expect(otdWithImg.discussKind, isNull);

      // 3. On this day (without image -> Discuss card)
      final otdNoImg = posts.firstWhere((p) => p.caption.contains('Galveston Hurricane'));
      expect(otdNoImg.imageUrls, isEmpty);
      expect(otdNoImg.discussKind, 'discussion');

      // 4. Did you know (without image -> Discuss card)
      final dyk = posts.firstWhere((p) => p.authorUsername.contains('Trivia'));
      expect(dyk.imageUrls, isEmpty);
      expect(dyk.discussKind, 'discussion');

      // 5. Trending
      final trending = posts.firstWhere((p) => p.authorUsername.contains('Trending'));
      expect(trending.caption, contains('Quantum Computing'));
      expect(trending.imageUrls, isNotEmpty);
    });

    test('falls back to thumbnail PNG when originalimage is SVG', () {
      final svgFeed = {
        'tfa': {
          'title': 'Flight_11',
          'titles': {'normalized': 'Flight 11'},
          'extract': 'American Airlines Flight 11 was a hijacked flight.',
          'originalimage': {
            'source': 'https://upload.wikimedia.org/path.svg?utm_source=orig',
          },
          'thumbnail': {
            'source': 'https://thumb.wikimedia.org/path.svg/960px-path.svg.png?utm_source=thumb',
          },
        },
      };

      final service = WikimediaFeedService();
      final posts = service.parseFeedJson(svgFeed);

      expect(posts.length, 1);
      expect(posts.first.imageUrls.length, 1);
      expect(posts.first.imageUrls.first, contains('960px-path.svg.png'));
    });
  });
}
