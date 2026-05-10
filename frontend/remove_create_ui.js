const fs = require('fs');
const file = 'lib/src/features/widgets/sticker_picker_sheet.dart';
let text = fs.readFileSync(file, 'utf8');

// Remove imports
text = text.replace("import 'package:image_picker/image_picker.dart';\n", '');
text = text.replace("import 'package:image_cropper/image_cropper.dart';\n", '');

// Remove the Container for custom packs dropdown
const targetContainer = `                  // Custom packs dropdown + create button
                  Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(
                            color: context.borderColor, width: 0.5),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (customPacks.isNotEmpty)
                          PopupMenuButton<String>(
                            tooltip: 'My sticker packs',
                            icon: Icon(Icons.folder_special_outlined,
                                size: 20, color: context.textSecondary),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 38,
                              minHeight: 38,
                            ),
                            onSelected: (packId) {
                              final pack = customPacks.firstWhere(
                                  (p) => p.id == packId);
                              _showCustomPackGrid(pack);
                            },
                            itemBuilder: (_) => customPacks
                                .map((p) => PopupMenuItem<String>(
                                      value: p.id,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.folder_outlined,
                                              size: 18,
                                              color: Color(0xFFB05ECC)),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              p.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          Text(
                                            '\${p.stickerUrls.length}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: context.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ))
                                .toList(),
                          ),
                        // Add (+) button
                        GestureDetector(
                          onTap: _showCreateCustomPackSheet,
                          child: Container(
                            width: 38,
                            height: 44,
                            alignment: Alignment.center,
                            child: Icon(Icons.add_circle_outline,
                                size: 22, color: context.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),`;
text = text.replace(targetContainer, '');

fs.writeFileSync(file, text);
