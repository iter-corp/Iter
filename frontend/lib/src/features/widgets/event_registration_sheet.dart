import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_strings.dart';
import '../../providers/auth_providers.dart';
import '../../providers/event_registration_providers.dart';
import '../../theme/app_theme.dart';

/// Small curated list of common country calling codes. Keeps the sheet
/// lightweight without pulling in a full country library.
const List<({String code, String label})> _countryCodes = [
  (code: '+1', label: '🇺🇸 US / CA +1'),
  (code: '+20', label: '🇪🇬 Egypt +20'),
  (code: '+27', label: '🇿🇦 South Africa +27'),
  (code: '+33', label: '🇫🇷 France +33'),
  (code: '+44', label: '🇬🇧 UK +44'),
  (code: '+49', label: '🇩🇪 Germany +49'),
  (code: '+61', label: '🇦🇺 Australia +61'),
  (code: '+81', label: '🇯🇵 Japan +81'),
  (code: '+86', label: '🇨🇳 China +86'),
  (code: '+90', label: '🇹🇷 Türkiye +90'),
  (code: '+91', label: '🇮🇳 India +91'),
  (code: '+92', label: '🇵🇰 Pakistan +92'),
  (code: '+93', label: '🇦🇫 Afghanistan +93'),
  (code: '+94', label: '🇱🇰 Sri Lanka +94'),
  (code: '+961', label: '🇱🇧 Lebanon +961'),
  (code: '+962', label: '🇯🇴 Jordan +962'),
  (code: '+963', label: '🇸🇾 Syria +963'),
  (code: '+964', label: '🇮🇶 Iraq +964'),
  (code: '+965', label: '🇰🇼 Kuwait +965'),
  (code: '+966', label: '🇸🇦 Saudi Arabia +966'),
  (code: '+968', label: '🇴🇲 Oman +968'),
  (code: '+971', label: '🇦🇪 UAE +971'),
  (code: '+972', label: '🇮🇱 Israel +972'),
  (code: '+974', label: '🇶🇦 Qatar +974'),
  (code: '+973', label: '🇧🇭 Bahrain +973'),
  (code: '+212', label: '🇲🇦 Morocco +212'),
  (code: '+213', label: '🇩🇿 Algeria +213'),
  (code: '+216', label: '🇹🇳 Tunisia +216'),
  (code: '+218', label: '🇱🇾 Libya +218'),
];

Future<void> showEventRegistrationSheet(
  BuildContext context, {
  required String eventId,
  required String eventTitle,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _EventRegistrationForm(
      eventId: eventId,
      eventTitle: eventTitle,
    ),
  );
}

class _EventRegistrationForm extends ConsumerStatefulWidget {
  final String eventId;
  final String eventTitle;

  const _EventRegistrationForm({
    required this.eventId,
    required this.eventTitle,
  });

  @override
  ConsumerState<_EventRegistrationForm> createState() =>
      _EventRegistrationFormState();
}

class _EventRegistrationFormState
    extends ConsumerState<_EventRegistrationForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _countryCode = '+1';
  bool _hydrated = false;
  bool _submitting = false;

  void _hydrateFromProfile() {
    if (_hydrated) return;
    final userDoc = ref.read(currentUserDocProvider).value;
    if (userDoc == null) return;
    _nameCtrl.text = (userDoc['username'] as String?) ?? '';
    _emailCtrl.text = (userDoc['email'] as String?) ?? '';
    _hydrated = true;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _submitting = true);
    try {
      await ref.read(eventRegistrationServiceProvider).submit(
            eventId: widget.eventId,
            eventTitle: widget.eventTitle,
            name: _nameCtrl.text.trim(),
            email: _emailCtrl.text.trim(),
            phone: _phoneCtrl.text.trim(),
            countryCode: _countryCode,
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.t.eventRegRequestSubmitted),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t.eventRegFailed(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _hydrateFromProfile();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.borderColor,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  context.t.eventRegRegisterFor,
                  style: TextStyle(color: context.textSecondary, fontSize: 13),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.eventTitle,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 20),
                _LabeledField(
                  label: context.t.eventRegFullName,
                  child: TextFormField(
                    controller: _nameCtrl,
                    decoration: _inputDecoration(context.t.eventRegNameHint),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? context.t.eventRegRequired
                        : null,
                  ),
                ),
                _LabeledField(
                  label: context.t.eventRegEmail,
                  child: TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: _inputDecoration(context.t.eventRegEmailHint),
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return context.t.eventRegRequired;
                      if (!t.contains('@') || !t.contains('.')) {
                        return context.t.eventRegInvalidEmail;
                      }
                      return null;
                    },
                  ),
                ),
                _LabeledField(
                  label: context.t.eventRegPhone,
                  child: Row(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: context.inputFill,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _countryCode,
                            items: _countryCodes
                                .map(
                                  (c) => DropdownMenuItem(
                                    value: c.code,
                                    child: Text(
                                      c.label,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) {
                                setState(() => _countryCode = v);
                              }
                            },
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration:
                              _inputDecoration(context.t.eventRegPhoneHint),
                          validator: (v) {
                            final t = v?.trim() ?? '';
                            if (t.isEmpty) return context.t.eventRegRequired;
                            if (t.length < 6) return context.t.eventRegTooShort;
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _submitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFCE5DE5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            context.t.eventRegSubmitRequest,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: context.inputFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      );
}

class _LabeledField extends StatelessWidget {
  final String label;
  final Widget child;

  const _LabeledField({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: context.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
