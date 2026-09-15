class MentionUtils {
  /// Regex to extract usernames starting with `@` (e.g., @john_doe)
  /// Matches a sequence of word characters (a-zA-Z0-9_), dots, or dashes.
  static final RegExp mentionRegex = RegExp(r'@([\w.-]+)');

  /// Extracts unique usernames (without the `@` symbol) from the given text.
  static List<String> extractMentions(String text) {
    if (text.trim().isEmpty) return [];

    final matches = mentionRegex.allMatches(text);
    final Set<String> usernames = {};

    for (final match in matches) {
      if (match.groupCount >= 1) {
        final username = match.group(1);
        if (username != null && username.isNotEmpty) {
          usernames.add(username);
        }
      }
    }

    return usernames.toList();
  }
}
