import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/auth_repository.dart';
import '../../routing/app_router.dart';
import '../../theme/wa_colors.dart';

/// The login mockup's token names, resolved onto the app-wide WhatsApp
/// palette so this screen is the same black as every other.
class _T {
  const _T._();
  static const Color background = Wa.chatBackground;
  static const Color accent = Wa.accent;
  static const Color accentBright = Wa.accent;
  static const Color accentLime = Wa.accent;
  static const Color cardBackground = Color(0xF21D1F1F);
  static const Color surfaceHigh = Wa.input;
  static const Color muted = Wa.secondaryText;
  static const Color subline = Wa.secondaryText;

  /// The soft glows behind the card — tints of the accent.
  static const Color glowStrong = Color(0x3321C063);
  static const Color glowSoft = Color(0x1A21C063);
  static const Color glowNone = Color(0x0021C063);
  static const Color cardShadow = Color(0x2621C063);
  static const Color fieldBorder = Wa.border;
  static const double pagePadding = 16;
}

/// Sign in against the existing Supabase Auth project.
///
/// Creating an account lives on its own screen at /signup.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.notice});

  /// Why the user is here without having tapped Sign out — shown once above
  /// the form so an expired session reads as that, not as a bug.
  final String? notice;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _auth = const AuthRepository();

  bool _busy = false;
  bool _obscurePassword = true;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _auth.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
      // The router redirect moves on to /chats once the session lands.
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Enter your email address first, then tap '
          'Forgot Password.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _auth.sendPasswordReset(email);
      _showMessage('Password reset link sent to $email.');
    } on AuthException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send the reset email.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: _T.surfaceHigh,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.background,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          const _AmbientGlows(),
          SafeArea(
            child: SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  // Mobile-first layout; stays centred on wide windows.
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Padding(
                        // Top space leaves room for the badge that overlaps
                        // the card's top edge.
                        padding: const EdgeInsets.fromLTRB(
                          _T.pagePadding,
                          32,
                          _T.pagePadding,
                          8,
                        ),
                        child: _AuthCard(
                          formKey: _formKey,
                          emailController: _emailController,
                          passwordController: _passwordController,
                          busy: _busy,
                          obscurePassword: _obscurePassword,
                          error: _error,
                          notice: widget.notice,
                          onToggleObscure: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          onSubmit: _submit,
                          onForgotPassword: _forgotPassword,
                        ),
                      ),
                      const _MarketingPanel(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The three radial background glows from the design.
class _AmbientGlows extends StatelessWidget {
  const _AmbientGlows();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.topLeft,
                radius: 1.2,
                colors: <Color>[_T.glowStrong, _T.glowNone],
                stops: <double>[0.0, 0.5],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.bottomRight,
                radius: 1.2,
                colors: <Color>[_T.glowSoft, _T.glowNone],
                stops: <double>[0.0, 0.5],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.centerRight,
                radius: 1.0,
                colors: <Color>[_T.glowSoft, _T.glowNone],
                stops: <double>[0.0, 0.5],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand header, headline and the feature grid above the auth card.
class _MarketingPanel extends StatelessWidget {
  const _MarketingPanel();

  static const List<(IconData, String)> _features = <(IconData, String)>[
    (Icons.group_outlined, 'Shared Team Inbox'),
    (Icons.bolt_outlined, 'No-Code Automations'),
    (Icons.campaign_outlined, 'Bulk Broadcasts'),
    (Icons.smart_toy_outlined, 'AI Auto-Replies'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(_T.pagePadding, 24, _T.pagePadding, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // The ring cut out of its dark square — the tinted box that
              // stood in for it is gone, and so is the black tile a square
              // icon would have put on the card.
              Image.asset(
                'assets/branding/app_icon_round.png',
                width: 48,
                height: 48,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const SizedBox(
                  width: 48,
                  height: 48,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'WOO Chat',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 22,
                  height: 28 / 22,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.22,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          const _Headline(),
          const SizedBox(height: 8),
          Text(
            'Team inbox, AI auto-replies, broadcasts, smart routing & a full '
            'CRM.',
            style: GoogleFonts.inter(
              fontSize: 15,
              height: 1.375,
              color: _T.subline,
            ),
          ),
          const SizedBox(height: 24),
          for (int row = 0; row < 2; row++) ...<Widget>[
            if (row > 0) const SizedBox(height: 12),
            // IntrinsicHeight gives the row a bounded cross axis so the two
            // cards can stretch to equal heights inside the scroll view.
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: _FeatureCard(
                      icon: _features[row * 2].$1,
                      label: _features[row * 2].$2,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FeatureCard(
                      icon: _features[row * 2 + 1].$1,
                      label: _features[row * 2 + 1].$2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// "The WhatsApp platform your **business** deserves." with the gradient word.
class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    final base = GoogleFonts.spaceGrotesk(
      fontSize: 28,
      height: 32 / 28,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.5,
      color: Colors.white,
    );

    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          const TextSpan(text: 'The WhatsApp platform your '),
          TextSpan(
            text: 'business',
            style: base.copyWith(
              foreground: Paint()
                ..shader = const LinearGradient(
                  colors: <Color>[_T.accentBright, _T.accentLime],
                ).createShader(const Rect.fromLTWH(0, 0, 170, 32)),
            ),
          ),
          const TextSpan(text: ' deserves.'),
        ],
      ),
      style: base,
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 16, color: _T.accentBright),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.15,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

/// The elevated card holding the credential form.
class _AuthCard extends StatelessWidget {
  const _AuthCard({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
      required this.busy,
    required this.obscurePassword,
    required this.error,
    required this.notice,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onForgotPassword,
    });

  /// The wordmark badge is 2:1 like the image inside it.
  static const double badgeWidth = 168;
  static const double badgeHeight = 84;

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool busy;
  final bool obscurePassword;
  final String? error;

  /// Why the user landed here without signing out, if that is what happened.
  final String? notice;
  final VoidCallback onToggleObscure;
  final VoidCallback onSubmit;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: <Widget>[
        Container(
          // Half the badge hangs above the card; the rest needs clearing
          // inside it before the heading starts.
          margin: const EdgeInsets.only(top: _AuthCard.badgeHeight / 2),
          padding: const EdgeInsets.fromLTRB(
            24,
            _AuthCard.badgeHeight / 2 + 18,
            24,
            24,
          ),
          decoration: BoxDecoration(
            color: _T.cardBackground,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            boxShadow: const <BoxShadow>[
              BoxShadow(
                color: _T.cardShadow,
                blurRadius: 40,
                spreadRadius: -10,
              ),
            ],
          ),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Text(
                  'Welcome Back',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sign in to your account',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(fontSize: 14, color: _T.muted),
                ),
                if (notice != null) ...<Widget>[
                  const SizedBox(height: 16),
                  Container(
                    key: const ValueKey<String>('sign-out-notice'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Wa.warningBackground,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Wa.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            notice!,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                _Field(
                  controller: emailController,
                  enabled: !busy,
                  hint: 'Email Address',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const <String>[AutofillHints.email],
                  validator: (value) {
                    final email = value?.trim() ?? '';
                    if (email.isEmpty) return 'Enter your email address';
                    if (!email.contains('@') || !email.contains('.')) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                _Field(
                  controller: passwordController,
                  enabled: !busy,
                  hint: 'Password',
                  icon: Icons.lock_outline,
                  obscureText: obscurePassword,
                  autofillHints: const <String>[AutofillHints.password],
                  onFieldSubmitted: (_) => onSubmit(),
                  suffix: IconButton(
                    onPressed: onToggleObscure,
                    icon: Icon(
                      obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      size: 18,
                      color: _T.muted,
                    ),
                    tooltip: obscurePassword ? 'Show password' : 'Hide password',
                  ),
                  validator: (value) {
                    final password = value ?? '';
                    if (password.isEmpty) return 'Enter your password';
                    return null;
                  },
                ),
                ...<Widget>[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: busy ? null : onForgotPassword,
                      style: TextButton.styleFrom(
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 4,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Forgot Password?',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: _T.accent,
                        ),
                      ),
                    ),
                  ),
                ],
                if (error != null) ...<Widget>[
                  const SizedBox(height: 16),
                  _ErrorBanner(message: error!),
                ],
                const SizedBox(height: 16),
                _SubmitButton(
                  label: 'Sign In',
                  busy: busy,
                  onPressed: onSubmit,
                ),
                const SizedBox(height: 16),
                _SignUpFooter(enabled: !busy),
              ],
            ),
          ),
        ),
        // The Woo Chat wordmark, overlapping the card's top edge. It is a
        // 2:1 image, so the badge is wide rather than square; its white and
        // orange lettering sit on the dark surface as designed.
        Container(
          width: _AuthCard.badgeWidth,
          height: _AuthCard.badgeHeight,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: _T.surfaceHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _T.background, width: 4),
          ),
          child: Image.asset(
            'assets/branding/app-logo.png',
            fit: BoxFit.contain,
            semanticLabel: 'Woo Chat',
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.enabled,
    required this.hint,
    required this.icon,
    required this.validator,
    this.obscureText = false,
    this.keyboardType,
    this.autofillHints,
    this.suffix,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final String hint;
  final IconData icon;
  final String? Function(String?) validator;
  final bool obscureText;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final Widget? suffix;
  final void Function(String)? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      borderSide: BorderSide(color: _T.fieldBorder),
    );

    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      autocorrect: false,
      onFieldSubmitted: onFieldSubmitted,
      textInputAction:
          onFieldSubmitted == null ? TextInputAction.next : TextInputAction.done,
      style: GoogleFonts.inter(fontSize: 15, color: Colors.white),
      cursorColor: _T.accent,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.inter(fontSize: 15, color: _T.muted),
        filled: true,
        fillColor: _T.surfaceHigh.withValues(alpha: 0.5),
        prefixIcon: Icon(icon, size: 18, color: _T.muted),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: border,
        enabledBorder: border,
        disabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: _T.accent),
        ),
        errorStyle: GoogleFonts.inter(fontSize: 12, color: Wa.error),
      ),
      validator: validator,
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.label,
    required this.busy,
    required this.onPressed,
  });

  final String label;
  final bool busy;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: _T.accent,
        foregroundColor: Colors.white,
        disabledBackgroundColor: _T.accent.withValues(alpha: 0.5),
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
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward, size: 18),
              ],
            ),
    );
  }
}

class _SignUpFooter extends StatelessWidget {
  const _SignUpFooter({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: <Widget>[
          Text(
            "Don't have an account? ",
            style: GoogleFonts.inter(fontSize: 14, color: _T.muted),
          ),
          GestureDetector(
            onTap: enabled ? () => context.go(Routes.signup) : null,
            child: Text(
              'Sign Up',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: _T.accent,
              ),
            ),
          ),
        ],
      ),
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
