const fs = require('fs');
const file = fs.readFileSync('lib/src/services/sticker_data.dart', 'utf8');

function toCodePoint(unicodeSurrogates, sep) {
  var r = [], c = 0, p = 0, i = 0;
  while (i < unicodeSurrogates.length) {
    c = unicodeSurrogates.charCodeAt(i++);
    if (p) {
      r.push((0x10000 + ((p - 0xD800) << 10) + (c - 0xDC00)).toString(16));
      p = 0;
    } else if (0xD800 <= c && c <= 0xDBFF) {
      p = c;
    } else {
      r.push(c.toString(16));
    }
  }
  return r.join(sep || '-');
}

const transformed = file.replace(/Sticker\(url:\s*'([^']+)'/g, (match, emoji) => {
  if (emoji.startsWith('http') || emoji.startsWith('asset')) return match;
  let hex = toCodePoint(emoji, '_');
  let hexNoto = hex.replace('_fe0f', '');
  return `Sticker(url: 'https://fonts.gstatic.com/s/e/notoemoji/latest/${hexNoto}/512.webp'`;
});

fs.writeFileSync('lib/src/services/sticker_data.dart', transformed);
