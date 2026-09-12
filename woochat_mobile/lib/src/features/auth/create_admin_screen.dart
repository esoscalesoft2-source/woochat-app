import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/auth_repository.dart';
import '../../routing/app_router.dart';
import '../../theme/wa_colors.dart';

/// The "Create Admin" mockup's token names, resolved onto the app-wide
/// WhatsApp palette so this screen is the same black as every other.
///
/// The mockup lit a focused field up to near-white with dark text; nothing in
/// WhatsApp does that, so a focused field now stays dark and shows an accent
/// border instead.
class _T {
  const _T._();
  static const Color background = Wa.chatBackground;
  static const Color card = Wa.background;
  static const Color input = Wa.input;
  static const Color inputActive = Wa.input;
  static const Color inputActiveText = Wa.title;
  static const Color border = Wa.border;
  static const Color brand = Wa.accent;
  static const Color onBrand = Colors.white;
  static const Color textPrimary = Wa.title;
  static const Color textSecondary = Wa.secondaryText;
  static const Color placeholder = Wa.secondaryText;

  /// Accent tints for the badge halo and the button's glow.
  static const Color brandHalo = Color(0x1F21C063);
  static const Color brandGlow = Color(0x7321C063);
  static const Color focusedIcon = Wa.icon;
}

/// `/signup` — creates a Supabase account plus its profile metadata.
class CreateAdminScreen extends StatefulWidget {
  const CreateAdminScreen({super.key});

  @override
  State<CreateAdminScreen> createState() => _CreateAdminScreenState();
}

class _CreateAdminScreenState extends State<CreateAdminScreen> {
  final _formKey = GlobalKey<FormState>();
  final _auth = const AuthRepository();

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _whatsapp = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _pincode = TextEditingController();

  late final List<TextEditingController> _all = <TextEditingController>[
    _firstName, _lastName, _whatsapp, _phone, _password,
    _confirm, _email, _address, _city, _state, _pincode,
  ];

  bool _busy = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    for (final controller in _all) {
      controller.dispose();
    }
    super.dispose();
  }

  /// Only non-empty values are sent, so the metadata stays clean.
  Map<String, dynamic> _profile() {
    final first = _firstName.text.trim();
    final last = _lastName.text.trim();

    final entries = <String, String>{
      'first_name': first,
      'last_name': last,
      'full_name': <String>[first, last].where((p) => p.isNotEmpty).join(' '),
      'whatsapp_number': _whatsapp.text.trim(),
      'phone': _phone.text.trim(),
      'address': _address.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'pincode': _pincode.text.trim(),
    };

    return <String, dynamic>{
      for (final entry in entries.entries)
        if (entry.value.isNotEmpty) entry.key: entry.value,
    };
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final hasSession = await _auth.signUp(
        email: _email.text,
        password: _password.text,
        profile: _profile(),
      );

      if (!mounted) return;
      if (hasSession) {
        // The router's redirect takes over from here.
        return;
      }

      // Email confirmation is enabled on the project.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text(
              'Account created. Confirm the link in your inbox, then sign in.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      context.go(Routes.login);
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Could not create the account. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.background,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: <Widget>[
                  _card(),
                  const SizedBox(height: 16),
                  const _BottomMeta(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _T.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _T.border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: _T.brandHalo,
            blurRadius: 60,
            spreadRadius: -15,
          ),
          BoxShadow(
            color: Color(0x99000000),
            blurRadius: 30,
            spreadRadius: -10,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _CardHeader(),
            const SizedBox(height: 20),
            _row(
              _AdminField(
                controller: _firstName,
                hint: 'First Name',
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                validator: _required('Enter the first name'),
              ),
              _AdminField(
                controller: _lastName,
                hint: 'Last Name',
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
                validator: _required('Enter the last name'),
              ),
            ),
            _row(
              _AdminField(
                controller: _whatsapp,
                hint: 'WhatsApp Number',
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                inputFormatters: _phoneFormatters,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Enter the WhatsApp number';
                  if (text.replaceAll(RegExp(r'\D'), '').length < 8) {
                    return 'Enter a valid number';
                  }
                  return null;
                },
              ),
              _AdminField(
                controller: _phone,
                hint: 'Phone Number',
                enabled: !_busy,
                keyboardType: TextInputType.phone,
                inputFormatters: _phoneFormatters,
              ),
            ),
            _row(
              _AdminField(
                controller: _password,
                hint: 'Password',
                enabled: !_busy,
                obscureText: _obscurePassword,
                prefixIcon: Icons.lock_outline,
                onToggleObscure: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                validator: (value) {
                  final text = value ?? '';
                  if (text.isEmpty) return 'Enter a password';
                  if (text.length < 6) return 'Use at least 6 characters';
                  return null;
                },
              ),
              _AdminField(
                controller: _confirm,
                hint: 'Confirm',
                enabled: !_busy,
                obscureText: _obscureConfirm,
                prefixIcon: Icons.lock_outline,
                onToggleObscure: () =>
                    setState(() => _obscureConfirm = !_obscureConfirm),
                validator: (value) {
                  if ((value ?? '').isEmpty) return 'Confirm the password';
                  if (value != _password.text) return 'Passwords do not match';
                  return null;
                },
              ),
            ),
            _row(
              _AdminField(
                controller: _email,
                hint: 'Email Address',
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Enter the email address';
                  if (!text.contains('@') || !text.contains('.')) {
                    return 'Enter a valid email address';
                  }
                  return null;
                },
              ),
              _AdminField(
                controller: _address,
                hint: 'Address',
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
              ),
            ),
            _row(
              _AdminField(
                controller: _city,
                hint: 'City',
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
              ),
              _AdminField(
                controller: _state,
                hint: 'State',
                enabled: !_busy,
                textCapitalization: TextCapitalization.words,
              ),
            ),
            _AdminField(
              controller: _pincode,
              hint: 'Pincode',
              enabled: !_busy,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(10),
              ],
            ),
            if (_error != null) ...<Widget>[
              const SizedBox(height: 12),
              _ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 20),
            _SubmitButton(busy: _busy, onPressed: _submit),
            const SizedBox(height: 16),
            _LoginFooter(enabled: !_busy),
          ],
        ),
      ),
    );
  }

  static List<TextInputFormatter> get _phoneFormatters =>
      <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s-]')),
        LengthLimitingTextInputFormatter(20),
      ];

  String? Function(String?) _required(String message) =>
      (value) => (value?.trim().isEmpty ?? true) ? message : null;

  /// Two fields side by side, matching the mockup's 2-column grid.
  Widget _row(Widget left, Widget right) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: left),
          const SizedBox(width: 10),
          Expanded(child: right),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  const _CardHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _T.input,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _T.border),
          ),
          child: const Icon(Icons.chat_bubble_outline, size: 20, color: _T.brand),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: <Widget>[
                  Text(
                    'Create Admin',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: _T.textPrimary,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _T.brand.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: _T.brand.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Text(
                      'WOO CHAT',
                      style: GoogleFonts.inter(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _T.brand,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Manage your WhatsApp admin access',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _T.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A field that turns light when focused, as in the mockup.
class _AdminField extends StatefulWidget {
  const _AdminField({
    required this.controller,
    required this.hint,
    required this.enabled,
    this.validator,
    this.obscureText = false,
    this.onToggleObscure,
    this.prefixIcon,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final String? Function(String?)? validator;
  final bool obscureText;
  final VoidCallback? onToggleObscure;
  final IconData? prefixIcon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  @override
  State<_AdminField> createState() => _AdminFieldState();
}

class _AdminFieldState extends State<_AdminField> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus != _focused) {
        setState(() => _focused = _focusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fill = _focused ? _T.inputActive : _T.input;
    final textColor = _focused ? _T.inputActiveText : _T.textPrimary;
    final iconColor = _focused ? _T.focusedIcon : _T.textSecondary;

    OutlineInputBorder border(Color color) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color),
        );

    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      inputFormatters: widget.inputFormatters,
      textCapitalization: widget.textCapitalization,
      autocorrect: false,
      cursorColor: _focused ? _T.brand : _T.textPrimary,
      style: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: _focused ? FontWeight.w600 : FontWeight.w400,
        color: textColor,
      ),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: GoogleFonts.inter(fontSize: 13, color: _T.placeholder),
        filled: true,
        fillColor: fill,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        prefixIcon: widget.prefixIcon == null
            ? null
            : Icon(widget.prefixIcon, size: 16, color: iconColor),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        suffixIcon: widget.onToggleObscure == null
            ? null
            : IconButton(
                onPressed: widget.onToggleObscure,
                iconSize: 16,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: Icon(
                  widget.obscureText
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: iconColor,
                ),
                tooltip: widget.obscureText ? 'Show' : 'Hide',
              ),
        border: border(_T.border),
        enabledBorder: border(_T.border),
        disabledBorder: border(_T.border),
        focusedBorder: border(_T.brand),
        errorBorder: border(Wa.error),
        focusedErrorBorder: border(Wa.error),
        errorStyle: GoogleFonts.inter(
          fontSize: 11,
          color: Wa.error,
        ),
      ),
      validator: widget.validator,
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({required this.busy, required this.onPressed});

  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: busy
            ? null
            : const <BoxShadow>[
                BoxShadow(
                  color: _T.brandGlow,
                  blurRadius: 20,
                  spreadRadius: -2,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _T.brand,
          foregroundColor: _T.onBrand,
          disabledBackgroundColor: _T.brand.withValues(alpha: 0.5),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: busy
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _T.onBrand,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'Create Admin',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _T.onBrand,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.arrow_forward, size: 16),
                ],
              ),
      ),
    );
  }
}

class _LoginFooter extends StatelessWidget {
  const _LoginFooter({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            'Already have account? ',
            style: GoogleFonts.inter(fontSize: 13, color: _T.textSecondary),
          ),
          GestureDetector(
            onTap: enabled ? () => context.go(Routes.login) : null,
            child: Text(
              'Login',
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _T.brand,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomMeta extends StatelessWidget {
  const _BottomMeta();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: _T.brand,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            // Flexible so the label wraps on narrow screens instead of
            // overflowing the row.
            Flexible(
              child: Text(
                'End-to-end encrypted CRM channel',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: _T.placeholder,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'WOO CHAT • DEEP SPACE',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 10,
            letterSpacing: 2,
            color: _T.placeholder.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Wa.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Wa.error.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.error_outline, color: Wa.error, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: Wa.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
