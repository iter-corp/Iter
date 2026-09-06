import 'dart:convert';
import 'package:coil/src/services/nasa_apod_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('NasaApodService', () {
    test('fetches and converts APOD JSON array to Post objects with caption and image', () async {
      final mockResponse = [
        {
          'date': '2026-09-06',
          'title': 'Pluto in Enhanced Color',
          'explanation': 'Pluto is more colorful than we can see.',
          'hdurl': 'https://apod.nasa.gov/apod/image/2609/Pluto_hd.jpg',
          'url': 'https://apod.nasa.gov/apod/image/2609/Pluto_std.jpg',
          'media_type': 'image',
          'copyright': 'NASA / JHUAPL / SwRI',
        },
      ];

      final client = MockClient((request) async {
        expect(request.url.host, 'api.nasa.gov');
        expect(request.url.path, '/planetary/apod');
        return http.Response(jsonEncode(mockResponse), 200);
      });

      final service = NasaApodService(client: client);
      final posts = await service.fetchApodPosts(count: 1);

      expect(posts.length, 1);
      final post = posts.first;
      expect(post.authorUsername, 'NASA APOD');
      expect(post.imageUrls, ['https://apod.nasa.gov/apod/image/2609/Pluto_hd.jpg']);
      expect(post.caption, contains('Pluto in Enhanced Color'));
      expect(post.caption, contains('Date: 2026-09-06'));
      expect(post.caption, contains('Pluto is more colorful than we can see.'));
      expect(post.caption, contains('Credit: NASA / JHUAPL / SwRI'));
    });

    test('handles single-object APOD response gracefully', () async {
      final mockSingle = {
        'date': '2026-09-05',
        'title': 'Supernova Remnant',
        'explanation': 'Expanding cloud of interstellar gas.',
        'url': 'https://apod.nasa.gov/apod/image/2609/sn_std.jpg',
        'media_type': 'image',
      };

      final client = MockClient((request) async {
        return http.Response(jsonEncode(mockSingle), 200);
      });

      final service = NasaApodService(client: client);
      final posts = await service.fetchApodPosts();

      expect(posts.length, 1);
      final post = posts.first;
      expect(post.imageUrls, ['https://apod.nasa.gov/apod/image/2609/sn_std.jpg']);
      expect(post.caption, contains('Date: 2026-09-05'));
      expect(post.caption, contains('Expanding cloud of interstellar gas.'));
    });
  });
}
