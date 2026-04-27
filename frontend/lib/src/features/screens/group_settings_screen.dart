import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../theme/app_theme.dart';

/// Group chat settings screen - allows admins to manage group permissions
/// such as restricting messaging, enabling admin-only mode, and controlling media sharing.
class GroupSettingsScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String groupName;

  const GroupSettingsScreen({
    super.key,
    required this.chatId,
    required this.groupName,
  });

  @override
  ConsumerState<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  late bool _restrictMessaging;
  late bool _adminOnly;
  late bool _mediaShare;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .get();

      final data = doc.data();
      setState(() {
        _restrictMessaging = data?['restrictMessaging'] ?? false;
        _adminOnly = data?['adminOnly'] ?? false;
        _mediaShare = data?['mediaShare'] ?? true;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load settings: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
        'restrictMessaging': _restrictMessaging,
        'adminOnly': _adminOnly,
        'mediaShare': _mediaShare,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings saved successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to save settings: $e';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.groupName} Settings'),
        centerTitle: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  if (_errorMessage != null) ...[
                    Container(
                      color: Colors.red.shade100,
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.all(16),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade900),
                      ),
                    ),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Text(
                          'Messaging Permissions',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 16),

                        // Restrict Messaging Toggle
                        _buildPermissionCard(
                          icon: Icons.lock_outline,
                          title: 'Restrict Messaging',
                          subtitle:
                              'Only group admins can send messages. Members can still view messages.',
                          value: _restrictMessaging,
                          onChanged: (value) {
                            setState(() {
                              _restrictMessaging = value;
                              // If restrict is enabled, disable adminOnly (they conflict)
                              if (value) {
                                _adminOnly = false;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // Admin Only Toggle
                        _buildPermissionCard(
                          icon: Icons.admin_panel_settings_outlined,
                          title: 'Admin-Only Mode',
                          subtitle:
                              'Only group admins can send messages (alternative to restrict).',
                          value: _adminOnly,
                          onChanged: (value) {
                            setState(() {
                              _adminOnly = value;
                              // If admin-only is enabled, disable restrict (they conflict)
                              if (value) {
                                _restrictMessaging = false;
                              }
                            });
                          },
                        ),
                        const SizedBox(height: 12),

                        // Media Sharing Toggle
                        _buildPermissionCard(
                          icon: Icons.image_outlined,
                          title: 'Enable Media Sharing',
                          subtitle:
                              'Allow members to share images and send voice messages.',
                          value: _mediaShare,
                          onChanged: (value) {
                            setState(() => _mediaShare = value);
                          },
                        ),
                        const SizedBox(height: 24),

                        // Permission Summary
                        _buildPermissionSummary(),
                        const SizedBox(height: 24),

                        // Save Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isSaving ? null : _saveSettings,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFB05ECC),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              disabledBackgroundColor: Colors.grey.shade400,
                            ),
                            child: _isSaving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
                                    ),
                                  )
                                : const Text(
                                    'Save Settings',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildPermissionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required Function(bool) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.inputFill,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value ? const Color(0xFFB05ECC) : Colors.transparent,
          width: value ? 2 : 0,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFB05ECC), size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFFB05ECC),
            activeTrackColor: const Color(0xFFB05ECC).withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionSummary() {
    String summary = 'Current Permissions: ';

    if (_restrictMessaging) {
      summary += 'Messaging Restricted (Admins Only)';
    } else if (_adminOnly) {
      summary += 'Admin-Only Mode';
    } else {
      summary += 'All Members Can Message';
    }

    if (!_mediaShare) {
      summary += ' • Media Sharing Disabled';
    } else {
      summary += ' • Media Sharing Enabled';
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.purpleSoft,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        summary,
        style: TextStyle(
          color: context.textPrimary,
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
