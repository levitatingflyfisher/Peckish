import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:peckish/features/recipes/import/recipe_fetcher.dart';

void main() {
  test('sends a browser UA and returns the page body', () async {
    late Map<String, String> seenHeaders;
    final fetcher = RecipeFetcher(
      client: MockClient((request) async {
        seenHeaders = request.headers;
        return http.Response('<html>recipe</html>', 200);
      }),
    );
    final body = await fetcher.fetch(Uri.parse('https://example.com/tacos'));
    expect(body, contains('recipe'));
    expect(seenHeaders['User-Agent'], contains('Firefox'));
  });

  test('a non-200 becomes a friendly error, not a silent empty parse',
      () async {
    final fetcher = RecipeFetcher(
      client: MockClient((_) async => http.Response('nope', 403)),
    );
    expect(
      () => fetcher.fetch(Uri.parse('https://example.com/blocked')),
      throwsA(isA<http.ClientException>()),
    );
  });

  test('refuses non-http schemes outright', () {
    final fetcher = RecipeFetcher(client: MockClient((_) async {
      fail('must not be called');
    }));
    expect(
      () => fetcher.fetch(Uri.parse('file:///etc/passwd')),
      throwsFormatException,
    );
  });
}
