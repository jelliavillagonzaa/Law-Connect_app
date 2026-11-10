/// Public branding assets for EmailJS templates and other outbound email.
class EmailBranding {
  EmailBranding._();

  /// Hardcoded HTTPS logo — use this exact URL in EmailJS template img src.
  /// Do NOT use cid:logo.png (broken in Gmail).
  static const String logoUrl =
      'https://jurislink-app.web.app/email-logo.png';

  /// Fallback if email-logo.png is not deployed yet.
  static const String legacyLogoUrl =
      'https://jurislink-app.web.app/logo.png';

  static const String websiteUrl = 'https://jurislink-app.web.app/';

  /// Dedicated download page with instant 1-tap download button.
  static const String downloadAppUrl = 'https://jurislink-app.web.app/download';

  /// GitHub releases repository page.
  static const String githubReleasesUrl =
      'https://github.com/jelliavillagonzaa/Law-Connect_app/releases';

  /// EmailJS template must use: src="{{logo_url}}" (NOT cid:logo.png).
  static const String emailJsLogoHtml =
      '<a href="$websiteUrl">'
      '<img style="height:48px;vertical-align:middle" height="48" '
      'src="$logoUrl" alt="Law Connect logo" />'
      '</a>';
}
