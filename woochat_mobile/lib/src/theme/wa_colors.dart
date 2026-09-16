import 'package:flutter/material.dart';

/// WhatsApp Web's current dark theme, token for token.
///
/// Every value here was read from web.whatsapp.com's own `--WDS-*` design
/// tokens with the page in dark mode (11 Sep 2026), so this is the real
/// palette rather than an approximation of a screenshot. The WDS name each
/// value came from is noted beside it.
///
/// This is the ONE place a colour is defined. [AppTheme] builds the
/// `ThemeData` from it, and every widget that needs a specific surface reads
/// it from here — so a palette change is a one-file edit.
class Wa {
  const Wa._();

  // ---- Surfaces --------------------------------------------------------

  /// The conversation area behind the bubbles.
  /// `--WDS-systems-chat-background-wallpaper`
  static const Color chatBackground = Color(0xFF161717);

  /// The app's base surface: chats list, scaffold default.
  /// `--WDS-surface-default` / `--WDS-background-wash-plain`
  static const Color background = Color(0xFF161717);

  /// Header bars, the nav bar, and anything raised off the base.
  /// `--WDS-surface-elevated-default` / `--navbar-background`
  static const Color header = Color(0xFF1D1F1F);

  /// Input fields, the composer, and the incoming bubble.
  /// `--WDS-surface-elevated-emphasized` / `--WDS-systems-chat-surface-composer`
  static const Color input = Color(0xFF242626);

  /// Dropdowns, menus, dialogs and bottom sheets.
  /// `--WDS-surface-elevated-default`
  static const Color menu = Color(0xFF1D1F1F);

  /// A hovered row. `--WDS-surface-highlight` (white at 10%).
  static const Color menuHover = Color(0x1AFFFFFF);

  /// Hairline borders and dividers. `--WDS-lines-divider` (white at 10%).
  static const Color border = Color(0x1AFFFFFF);

  /// A drawn outline, e.g. an unfocused field. `--WDS-lines-outline-default`
  static const Color outline = Color(0xFF757778);

  // ---- Text and icons --------------------------------------------------

  /// `--WDS-content-default`
  static const Color title = Color(0xFFFAFAFA);

  /// Timestamps, placeholders, subtitles, icons.
  /// `--WDS-content-deemphasized` (white at 60%)
  static const Color secondaryText = Color(0x99FFFFFF);

  /// `--WDS-content-deemphasized` — icons share the muted text colour.
  static const Color icon = Color(0x99FFFFFF);

  /// `--WDS-content-disabled`
  static const Color disabled = Color(0xFF424445);

  // ---- Accent ----------------------------------------------------------

  /// Send button, links, active states, unread badges. `--WDS-accent`
  static const Color accent = Color(0xFF21C063);

  /// Text drawn on the accent. `--WDS-content-on-accent`
  static const Color onAccent = Color(0xFF0A0A0A);

  /// A tinted accent surface. `--WDS-accent-deemphasized`
  static const Color accentSoft = Color(0xFF103529);

  // ---- Bubbles ---------------------------------------------------------

  /// `--WDS-systems-bubble-surface-outgoing`
  static const Color outboundBubble = Color(0xFF144D37);

  /// `--WDS-systems-bubble-surface-incoming`
  static const Color inboundBubble = Color(0xFF242626);

  /// Time and ticks inside a bubble.
  /// `--WDS-systems-bubble-content-deemphasized` (white at 60%)
  static const Color bubbleMeta = Color(0x99FFFFFF);

  // ---- Semantic --------------------------------------------------------

  /// The blue double tick. `--WDS-content-read`
  static const Color tickBlue = Color(0xFF53BDEB);
  static const Color error = Color(0xFFFFB4AB);

  /// Schedules chip once it is narrowed to failed sends. `--danger`
  static const Color scheduleFailed = Color(0xFFF15C6D);

  static const Color warning = Color(0xFFFABD32);
  static const Color warningBackground = Color(0xE63B2A1A);

  // ---- Chat row extras (matching the web sidebar) ----------------------

  /// The dimmer grey of the owner line. Web `#667781`.
  static const Color mutedText = Color(0xFF667781);

  /// The 🛍 product chip. Web `#f0b429` on 15% of itself.
  static const Color productChip = Color(0xFFF0B429);
  static const Color productChipBackground = Color(0x26F0B429);

  /// The latest-note line. Web `#dca67a`.
  static const Color note = Color(0xFFDCA67A);

  /// Quick replies, the same amber the attach menu uses.
  /// `--attachment-type-quick-replies-color`
  static const Color quickReply = Color(0xFFFFBC38);

  /// Tint behind a row that still has unread messages. Web `#1f2f36`.
  static const Color rowUnread = Color(0xFF1F2F36);

  /// Tint behind a row picked in select mode. Web `#12463a`.
  static const Color rowSelected = Color(0xFF12463A);

  // ---- Names kept for existing call sites ------------------------------
  //
  // These are aliases onto the palette above, not extra colours.

  /// Popup menus and a hovered chat row.
  static const Color rowHover = menu;
  static const Color surfaceContainer = header;
  static const Color divider = border;
  static const Color chipActiveBackground = accent;
  static const Color chipInactiveBackground = input;
  static const Color navActive = accent;
  static const Color navInactive = icon;

  /// Bottom sheets.
  static const Color sheet = menu;
}

/// The conversation thread's colours, by role. Every value is a [Wa] colour;
/// this only names them for what the thread uses them as.
class Thread {
  const Thread._();

  static const Color background = Wa.chatBackground;
  static const Color inbound = Wa.inboundBubble;
  static const Color outbound = Wa.outboundBubble;
  static const Color text = Wa.title;
  static const Color meta = Wa.bubbleMeta;
  static const Color composer = Wa.header;
  static const Color input = Wa.input;
  static const Color divider = Wa.header;
  static const Color warning = Wa.warning;
  static const Color warningBackground = Wa.warningBackground;

  /// The wallpaper doodle's stroke colour.
  /// `--WDS-systems-chat-foreground-wallpaper` (white at 10%)
  static const Color dot = Color(0x1AFFFFFF);
}
