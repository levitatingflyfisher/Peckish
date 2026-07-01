import 'package:http/http.dart' as http;

/// Fetches exactly one user-pasted recipe page. This is one of the two
/// network flows the app has (the other is barcode lookup): user-initiated,
/// one URL, fetched, parsed, discarded.
class RecipeFetcher {
  RecipeFetcher({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// 3MB is generous for any real recipe page; the cap keeps a hostile URL
  /// from ballooning memory.
  static const maxBytes = 3 * 1024 * 1024;

  /// A mainstream browser UA: several large recipe sites 403 obviously
  /// non-browser agents (the Mealie lesson — their self-identifying UA got
  /// blocked wholesale).
  static const userAgent =
      'Mozilla/5.0 (X11; Linux x86_64; rv:128.0) Gecko/20100101 Firefox/128.0';

  Future<String> fetch(Uri url) async {
    if (url.scheme != 'https' && url.scheme != 'http') {
      throw const FormatException('Recipe links must start with http(s)://');
    }
    final response = await _client.get(url, headers: {
      'User-Agent': userAgent,
      'Accept': 'text/html,application/xhtml+xml',
    }).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw http.ClientException(
          'The site answered ${response.statusCode} — try copying the '
          'recipe text instead.',
          url);
    }
    if (response.bodyBytes.length > maxBytes) {
      throw http.ClientException('That page is too large to import.', url);
    }
    return response.body;
  }
}
