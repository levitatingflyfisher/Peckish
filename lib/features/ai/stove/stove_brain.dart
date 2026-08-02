/// The seam between the guess pipeline and the household stove (domovoi's
/// encrypted home-server tier). Pure Dart, no domovoi import: [GuessService]
/// and every test compile against this, while the real `StoveClient` stays
/// behind the io-only factory file — domovoi's export manifest carries
/// `dart:io` (server, transfer engine) and must never reach a web compile.
abstract class StoveBrain {
  /// One prompt in, the stove's whole text answer out. Implementations
  /// throw `GuessException` for anything the user might need to read.
  Future<String> complete(String prompt);
}
