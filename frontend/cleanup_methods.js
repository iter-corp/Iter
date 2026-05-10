const fs = require('fs');
const file = 'lib/src/features/widgets/sticker_picker_sheet.dart';
let lines = fs.readFileSync(file, 'utf8').split('\n');

// _showCreateCustomPackSheet down to _showCustomPackOptions ends around line 371
// Let's find exactly the line indices.
let start1 = lines.findIndex(l => l.includes('Future<void> _showCreateCustomPackSheet() async {'));
let end1 = lines.findIndex(l => l.includes('Widget _buildStickerWidget(String url, {double size = 56}) {'));

if (start1 !== -1 && end1 !== -1) {
  // Remove from start1 up to end1 - 1
  lines.splice(start1, end1 - start1);
}

// Find _showCustomPackGrid
let start2 = lines.findIndex(l => l.includes('void _showCustomPackGrid(CustomStickerPack pack) {'));
let end2 = lines.findIndex(l => l.includes('class _StickerItem {'));

if (start2 !== -1 && end2 !== -1) {
  // Remove from start2 up to end2 - 1
  // we need to be careful to also remove the comment /// Internal model for flattened sticker items
  let prevComment = end2 - 1;
  if (lines[prevComment].includes('/// Internal model')) {
    end2 = prevComment;
  }
  lines.splice(start2, end2 - start2);
}

fs.writeFileSync(file, lines.join('\n'));
