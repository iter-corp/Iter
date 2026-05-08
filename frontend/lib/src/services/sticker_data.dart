// Built-in sticker packs shipped with the app.
//
// Each sticker is represented as an emoji string rendered at large size
// inside the chat bubble. For production, these would be replaced with
// actual PNG/WebP assets, but emoji stickers are instantly usable,
// require zero network, and cover the most popular reaction categories
// identified in community research (cute, meme reactions, celebrations,
// love, greetings, emotions, cool, kawaii).

class StickerPack {
  final String id;
  final String name;
  final String icon; // emoji shown on the tab
  final List<Sticker> stickers;
  final bool isCustom;

  const StickerPack({
    required this.id,
    required this.name,
    required this.icon,
    required this.stickers,
    this.isCustom = false,
  });
}

class Sticker {
  /// For built-in packs: an emoji string rendered at large size.
  /// For custom packs: 'asset:...' path or Firebase Storage URL.
  final String url;

  /// The pack this sticker belongs to.
  final String packId;

  /// Emoji keywords for search matching.
  final List<String> keywords;

  const Sticker({
    required this.url,
    required this.packId,
    this.keywords = const [],
  });
}

// ─────────────────────────────────────────────
// Built-in sticker packs
// ─────────────────────────────────────────────

const kBuiltInStickerPacks = <StickerPack>[
  // ── 1. Cute Animals ──
  StickerPack(
    id: 'cute_animals',
    name: 'Cute Animals',
    icon: '🐱',
    stickers: [
      Sticker(url: '🐱', packId: 'cute_animals', keywords: ['cat', 'cute', 'kitty']),
      Sticker(url: '🐶', packId: 'cute_animals', keywords: ['dog', 'puppy', 'cute']),
      Sticker(url: '🐰', packId: 'cute_animals', keywords: ['bunny', 'rabbit', 'cute']),
      Sticker(url: '🦊', packId: 'cute_animals', keywords: ['fox', 'cute', 'clever']),
      Sticker(url: '🐼', packId: 'cute_animals', keywords: ['panda', 'bear', 'cute']),
      Sticker(url: '🐨', packId: 'cute_animals', keywords: ['koala', 'cute', 'sleep']),
      Sticker(url: '🦁', packId: 'cute_animals', keywords: ['lion', 'king', 'roar']),
      Sticker(url: '🐸', packId: 'cute_animals', keywords: ['frog', 'cute', 'meme']),
      Sticker(url: '🦋', packId: 'cute_animals', keywords: ['butterfly', 'pretty']),
      Sticker(url: '🐥', packId: 'cute_animals', keywords: ['chick', 'baby', 'cute']),
      Sticker(url: '🦉', packId: 'cute_animals', keywords: ['owl', 'wise', 'night']),
      Sticker(url: '🐧', packId: 'cute_animals', keywords: ['penguin', 'cute', 'cold']),
    ],
  ),

  // ── 2. Reactions & Memes ──
  StickerPack(
    id: 'reactions',
    name: 'Reactions',
    icon: '😂',
    stickers: [
      Sticker(url: '😂', packId: 'reactions', keywords: ['laugh', 'funny', 'lol']),
      Sticker(url: '🤣', packId: 'reactions', keywords: ['rofl', 'laugh', 'crying']),
      Sticker(url: '😭', packId: 'reactions', keywords: ['cry', 'sad', 'tears']),
      Sticker(url: '🤯', packId: 'reactions', keywords: ['mind blown', 'shocked', 'explode']),
      Sticker(url: '🙄', packId: 'reactions', keywords: ['eye roll', 'annoyed', 'whatever']),
      Sticker(url: '😤', packId: 'reactions', keywords: ['angry', 'frustrated', 'mad']),
      Sticker(url: '🤡', packId: 'reactions', keywords: ['clown', 'joke', 'fool']),
      Sticker(url: '💀', packId: 'reactions', keywords: ['dead', 'skull', 'dying', 'lol']),
      Sticker(url: '👀', packId: 'reactions', keywords: ['eyes', 'look', 'watching']),
      Sticker(url: '🤔', packId: 'reactions', keywords: ['thinking', 'hmm', 'wonder']),
      Sticker(url: '😏', packId: 'reactions', keywords: ['smirk', 'sly', 'heh']),
      Sticker(url: '🫠', packId: 'reactions', keywords: ['melting', 'overwhelmed', 'done']),
    ],
  ),

  // ── 3. Celebrations ──
  StickerPack(
    id: 'celebrations',
    name: 'Celebrations',
    icon: '🎉',
    stickers: [
      Sticker(url: '🎉', packId: 'celebrations', keywords: ['party', 'celebrate', 'congrats']),
      Sticker(url: '🎊', packId: 'celebrations', keywords: ['confetti', 'party', 'yay']),
      Sticker(url: '🥳', packId: 'celebrations', keywords: ['party', 'birthday', 'celebrate']),
      Sticker(url: '🎂', packId: 'celebrations', keywords: ['cake', 'birthday', 'sweet']),
      Sticker(url: '🍾', packId: 'celebrations', keywords: ['champagne', 'cheers', 'new year']),
      Sticker(url: '🏆', packId: 'celebrations', keywords: ['trophy', 'winner', 'champion']),
      Sticker(url: '🎆', packId: 'celebrations', keywords: ['fireworks', 'new year', 'wow']),
      Sticker(url: '🌟', packId: 'celebrations', keywords: ['star', 'amazing', 'shine']),
      Sticker(url: '👑', packId: 'celebrations', keywords: ['crown', 'king', 'queen', 'royal']),
      Sticker(url: '💯', packId: 'celebrations', keywords: ['hundred', 'perfect', 'score']),
      Sticker(url: '🔥', packId: 'celebrations', keywords: ['fire', 'hot', 'lit', 'amazing']),
      Sticker(url: '⭐', packId: 'celebrations', keywords: ['star', 'good', 'great']),
    ],
  ),

  // ── 4. Love & Hearts ──
  StickerPack(
    id: 'love',
    name: 'Love & Hearts',
    icon: '💕',
    stickers: [
      Sticker(url: '❤', packId: 'love', keywords: ['heart', 'love', 'red']),
      Sticker(url: '💕', packId: 'love', keywords: ['hearts', 'love', 'double']),
      Sticker(url: '💖', packId: 'love', keywords: ['sparkle heart', 'love', 'cute']),
      Sticker(url: '😍', packId: 'love', keywords: ['heart eyes', 'love', 'crush']),
      Sticker(url: '🥰', packId: 'love', keywords: ['love', 'adore', 'hearts']),
      Sticker(url: '😘', packId: 'love', keywords: ['kiss', 'love', 'blow kiss']),
      Sticker(url: '💋', packId: 'love', keywords: ['lips', 'kiss', 'love']),
      Sticker(url: '🤗', packId: 'love', keywords: ['hug', 'warm', 'love']),
      Sticker(url: '💝', packId: 'love', keywords: ['gift heart', 'love', 'present']),
      Sticker(url: '💌', packId: 'love', keywords: ['love letter', 'mail', 'valentine']),
      Sticker(url: '🌹', packId: 'love', keywords: ['rose', 'flower', 'love', 'romantic']),
      Sticker(url: '💍', packId: 'love', keywords: ['ring', 'proposal', 'wedding']),
    ],
  ),

  // ── 5. Cool & Chill ──
  StickerPack(
    id: 'cool',
    name: 'Cool & Chill',
    icon: '😎',
    stickers: [
      Sticker(url: '😎', packId: 'cool', keywords: ['cool', 'sunglasses', 'chill']),
      Sticker(url: '🤙', packId: 'cool', keywords: ['hang loose', 'chill', 'surf']),
      Sticker(url: '✌', packId: 'cool', keywords: ['peace', 'victory', 'chill']),
      Sticker(url: '🫰', packId: 'cool', keywords: ['snap', 'money', 'got it']),
      Sticker(url: '💅', packId: 'cool', keywords: ['nails', 'sassy', 'fabulous']),
      Sticker(url: '🕶', packId: 'cool', keywords: ['sunglasses', 'cool', 'shady']),
      Sticker(url: '🛹', packId: 'cool', keywords: ['skateboard', 'cool', 'rad']),
      Sticker(url: '🎸', packId: 'cool', keywords: ['guitar', 'rock', 'music']),
      Sticker(url: '🎧', packId: 'cool', keywords: ['headphones', 'music', 'vibes']),
      Sticker(url: '☕', packId: 'cool', keywords: ['coffee', 'chill', 'relax']),
      Sticker(url: '🧊', packId: 'cool', keywords: ['ice', 'cold', 'cool']),
      Sticker(url: '🌊', packId: 'cool', keywords: ['wave', 'ocean', 'surf', 'chill']),
    ],
  ),

  // ── 6. Greetings ──
  StickerPack(
    id: 'greetings',
    name: 'Greetings',
    icon: '👋',
    stickers: [
      Sticker(url: '👋', packId: 'greetings', keywords: ['wave', 'hello', 'hi', 'hey']),
      Sticker(url: '🤝', packId: 'greetings', keywords: ['handshake', 'deal', 'agree']),
      Sticker(url: '🙏', packId: 'greetings', keywords: ['pray', 'thanks', 'please']),
      Sticker(url: '👍', packId: 'greetings', keywords: ['thumbs up', 'good', 'ok', 'yes']),
      Sticker(url: '👎', packId: 'greetings', keywords: ['thumbs down', 'bad', 'no']),
      Sticker(url: '👏', packId: 'greetings', keywords: ['clap', 'bravo', 'well done']),
      Sticker(url: '🫡', packId: 'greetings', keywords: ['salute', 'respect', 'yes sir']),
      Sticker(url: '🌞', packId: 'greetings', keywords: ['sun', 'good morning', 'bright']),
      Sticker(url: '🌙', packId: 'greetings', keywords: ['moon', 'good night', 'sleep']),
      Sticker(url: '💪', packId: 'greetings', keywords: ['strong', 'flex', 'power', 'lets go']),
      Sticker(url: '🤞', packId: 'greetings', keywords: ['fingers crossed', 'hope', 'wish']),
      Sticker(url: '✨', packId: 'greetings', keywords: ['sparkle', 'magic', 'special']),
    ],
  ),

  // ── 7. Emotions ──
  StickerPack(
    id: 'emotions',
    name: 'Emotions',
    icon: '🥺',
    stickers: [
      Sticker(url: '🥺', packId: 'emotions', keywords: ['pleading', 'cute', 'please']),
      Sticker(url: '😢', packId: 'emotions', keywords: ['cry', 'sad', 'tear']),
      Sticker(url: '😡', packId: 'emotions', keywords: ['angry', 'mad', 'rage']),
      Sticker(url: '😱', packId: 'emotions', keywords: ['scream', 'scared', 'shocked']),
      Sticker(url: '🤢', packId: 'emotions', keywords: ['nausea', 'sick', 'gross']),
      Sticker(url: '😴', packId: 'emotions', keywords: ['sleep', 'tired', 'bored']),
      Sticker(url: '🫣', packId: 'emotions', keywords: ['peek', 'shy', 'embarrassed']),
      Sticker(url: '🫥', packId: 'emotions', keywords: ['invisible', 'empty', 'numb']),
      Sticker(url: '😇', packId: 'emotions', keywords: ['angel', 'innocent', 'good']),
      Sticker(url: '🤩', packId: 'emotions', keywords: ['starstruck', 'wow', 'amazing']),
      Sticker(url: '😌', packId: 'emotions', keywords: ['relieved', 'calm', 'peace']),
      Sticker(url: '🫶', packId: 'emotions', keywords: ['heart hands', 'love', 'appreciate']),
    ],
  ),

  // ── 8. Food & Drinks ──
  StickerPack(
    id: 'food',
    name: 'Food & Drinks',
    icon: '🍕',
    stickers: [
      Sticker(url: '🍕', packId: 'food', keywords: ['pizza', 'food', 'yum']),
      Sticker(url: '🍔', packId: 'food', keywords: ['burger', 'food', 'hungry']),
      Sticker(url: '🍟', packId: 'food', keywords: ['fries', 'food', 'snack']),
      Sticker(url: '🍩', packId: 'food', keywords: ['donut', 'sweet', 'dessert']),
      Sticker(url: '🍦', packId: 'food', keywords: ['ice cream', 'sweet', 'treat']),
      Sticker(url: '🧋', packId: 'food', keywords: ['boba', 'tea', 'drink']),
      Sticker(url: '🍜', packId: 'food', keywords: ['noodles', 'ramen', 'food']),
      Sticker(url: '🍣', packId: 'food', keywords: ['sushi', 'japanese', 'food']),
      Sticker(url: '🌮', packId: 'food', keywords: ['taco', 'mexican', 'food']),
      Sticker(url: '🥐', packId: 'food', keywords: ['croissant', 'bread', 'french']),
      Sticker(url: '🫐', packId: 'food', keywords: ['blueberry', 'fruit', 'healthy']),
      Sticker(url: '🍿', packId: 'food', keywords: ['popcorn', 'movie', 'snack']),
    ],
  ),
];

/// All built-in stickers flattened for search.
List<Sticker> get allBuiltInStickers =>
    kBuiltInStickerPacks.expand((p) => p.stickers).toList();

/// Find stickers matching a search query across all built-in packs.
List<Sticker> searchStickers(String query) {
  if (query.trim().isEmpty) return [];
  final lower = query.toLowerCase().trim();
  return allBuiltInStickers.where((s) {
    // Match by emoji character
    if (s.url.contains(lower)) return true;
    // Match by keyword
    return s.keywords.any((kw) => kw.contains(lower));
  }).toList();
}
