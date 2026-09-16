/// WhatsApp lets a business send free-form text or media only inside 24
/// hours of the customer's last message. Outside that, only an approved
/// template goes through. A scheduled send has to satisfy the rule at the
/// moment it will be SENT, not the moment it is queued.
class ScheduleRules {
  const ScheduleRules._();

  static const Duration window = Duration(hours: 24);

  /// When the customer's window closes, or null if they never wrote in.
  static DateTime? windowExpiresAt(DateTime? lastInboundAt) =>
      lastInboundAt?.add(window);

  static bool isWindowOpen(DateTime? lastInboundAt, {DateTime? now}) {
    final expires = windowExpiresAt(lastInboundAt);
    return expires != null && expires.isAfter(now ?? DateTime.now());
  }

  /// Whether a send at [scheduledAt] may be free-form.
  ///
  /// Two things have to hold: the window is open now, AND the send is no
  /// more than 24 hours away. A time further out needs a template even
  /// though the window is open today — it will have closed by then. And a
  /// window that is already closed makes every time a template time.
  static bool withinWindow(
    DateTime? lastInboundAt,
    DateTime scheduledAt, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    return isWindowOpen(lastInboundAt, now: at) &&
        !scheduledAt.isAfter(at.add(window));
  }
}
