const fs = require('fs');
const file = 'lib/src/features/widgets/sticker_picker_sheet.dart';
let lines = fs.readFileSync(file, 'utf8').split('\n');

// 1. Remove _showCreateCustomPackSheet, _addStickerToCustomPack, _showCustomPackOptions
// Lines 126 to 371
lines.splice(125, 371 - 126 + 1);

// Save and reload lines to update indices
fs.writeFileSync(file, lines.join('\n'));
lines = fs.readFileSync(file, 'utf8').split('\n');

// Find _showCustomPackGrid and remove it
let gridStart = lines.findIndex(l => l.includes('void _showCustomPackGrid(CustomStickerPack pack) {'));
let gridEnd = -1;
if (gridStart !== -1) {
  let braceCount = 0;
  for (let i = gridStart; i < lines.length; i++) {
    if (lines[i].includes('{')) braceCount += (lines[i].match(/{/g) || []).length;
    if (lines[i].includes('}')) braceCount -= (lines[i].match(/}/g) || []).length;
    if (braceCount === 0 && i > gridStart) {
      gridEnd = i;
      break;
    }
  }
  if (gridEnd !== -1) {
    lines.splice(gridStart, gridEnd - gridStart + 1);
  }
}

// Find Custom packs dropdown + create button and remove it
let dropStart = lines.findIndex(l => l.includes('// Custom packs dropdown + create button'));
if (dropStart !== -1) {
  let dropEnd = dropStart;
  let braceCount = 0;
  for (let i = dropStart + 1; i < lines.length; i++) {
    if (lines[i].includes('Container(')) braceCount++;
    if (lines[i].includes('(')) braceCount += (lines[i].match(/\(/g) || []).length;
    if (lines[i].includes(')')) braceCount -= (lines[i].match(/\)/g) || []).length;
    if (braceCount <= 0 && lines[i].includes('),')) { // heuristic for the end of the container
       dropEnd = i;
       break;
    }
  }
  // Let's be safer and just remove 631 to 698 of the ORIGINAL file, which is now shifted.
}

fs.writeFileSync(file, lines.join('\n'));
