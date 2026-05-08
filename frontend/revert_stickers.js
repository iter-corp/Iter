const fs = require('fs');

function fromCodePoint(hexStr) {
  const codePoints = hexStr.split('_').map(h => parseInt(h, 16));
  return String.fromCodePoint(...codePoints);
}

let file = fs.readFileSync('lib/src/services/sticker_data.dart', 'utf8');

const transformed = file.replace(/Sticker\(url:\s*'https:\/\/fonts.gstatic.com\/s\/e\/notoemoji\/latest\/([a-f0-9_]+)\/512.webp'/g, (match, hex) => {
  let emoji = fromCodePoint(hex);
  return `Sticker(url: '${emoji}'`;
});

fs.writeFileSync('lib/src/services/sticker_data.dart', transformed);
