import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/email_branding.dart';
import '../../routes/portal_navigation.dart';
import '../../services/auth_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/brand_logo.dart';
import '../../widgets/common/login_error_dialog.dart';
import '../auth/forgot_password_page.dart';
import '../auth/signup_page.dart';

const Color _cardFill = Color(0xE60B1D33);
const Color _gold = Color(0xFFE4A11A);
const Color _inputFill = Color(0xFF071422);
const Color _inputBorder = Color(0xFF2A4060);
const Color _muted = Color(0xFFB7C3D4);
const Color _page = Color(0xFF071526);
const Color _panel = Color(0xFF0B2240);
const Color _line = Color(0xFF1C3D66);

/// Public landing. Web uses the firm-portal design; the app keeps the original page.
class ClientLandingPage extends StatelessWidget {
  const ClientLandingPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return const _AppLandingPage();
    }
    return const _WebLandingPage();
  }
}

class _WebLandingPage extends StatefulWidget {
  const _WebLandingPage();

  @override
  State<_WebLandingPage> createState() => _WebLandingPageState();
}

enum _SiteSection { home, features, about, contact }

class _WebLandingPageState extends State<_WebLandingPage> {
  bool _signupOpen = false;
  _SiteSection _section = _SiteSection.home;
  final _scroll = ScrollController();
  final _featuresKey = GlobalKey();
  final _aboutKey = GlobalKey();
  final _contactKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_syncSection);
  }

  void _openSignup() {
    setState(() => _signupOpen = true);
  }

  void _closeSignup() {
    if (!_signupOpen) return;
    setState(() => _signupOpen = false);
  }

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  void _scrollHome() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    );
  }

  void _go(_SiteSection section, VoidCallback scroll) {
    setState(() => _section = section);
    scroll();
  }

  void _syncSection() {
    if (!_scroll.hasClients) return;
    final y = _scroll.offset + 140;
    final features = _reveal(_featuresKey);
    final about = _reveal(_aboutKey);
    final contact = _reveal(_contactKey);
    final next = contact.isFinite && y >= contact
        ? _SiteSection.contact
        : about.isFinite && y >= about
            ? _SiteSection.about
            : features.isFinite && y >= features
                ? _SiteSection.features
                : _SiteSection.home;
    if (next != _section && mounted) {
      setState(() => _section = next);
    }
  }

  double _reveal(GlobalKey key) {
    final object = key.currentContext?.findRenderObject();
    if (object == null) return double.infinity;
    final viewport = RenderAbstractViewport.maybeOf(object);
    if (viewport == null) return double.infinity;
    return viewport.getOffsetToReveal(object, 0).offset;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_signupOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSignup();
      },
      child: Scaffold(
        backgroundColor: _page,
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (!_signupOpen)
              Column(
                children: [
                  _SiteNav(
                    section: _section,
                    onHome: () => _go(_SiteSection.home, _scrollHome),
                    onFeatures: () =>
                        _go(_SiteSection.features, () => _scrollTo(_featuresKey)),
                    onAbout: () =>
                        _go(_SiteSection.about, () => _scrollTo(_aboutKey)),
                    onContact: () =>
                        _go(_SiteSection.contact, () => _scrollTo(_contactKey)),
                    onLogin: () =>
                        _go(_SiteSection.contact, () => _scrollTo(_contactKey)),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _HeroSection(
                            onGetStarted: () => _scrollTo(_contactKey),
                            onLearnMore: () => _scrollTo(_featuresKey),
                          ),
                          _FeaturesSection(key: _featuresKey),
                          const _PartnerSection(),
                          _CommitmentSection(key: _aboutKey),
                          _CtaSection(
                            onGetStarted: () => _scrollTo(_contactKey),
                          ),
                          _SiteFooter(
                            key: _contactKey,
                            onCreateAccount: _openSignup,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            if (_signupOpen)
              Positioned.fill(
                child: SignupPage(onClose: _closeSignup),
              ),
          ],
        ),
      ),
    );
  }
}

class _SiteNav extends StatelessWidget {
  const _SiteNav({
    required this.section,
    required this.onHome,
    required this.onFeatures,
    required this.onAbout,
    required this.onContact,
    required this.onLogin,
  });

  final _SiteSection section;
  final VoidCallback onHome;
  final VoidCallback onFeatures;
  final VoidCallback onAbout;
  final VoidCallback onContact;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final pad = w < 720 ? 16.0 : 40.0;
    final compact = w < 860;

    return Material(
      color: _page,
      child: Container(
        padding: EdgeInsets.fromLTRB(pad, 12, pad, 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        child: Row(
          children: [
            const _BrandLockup(),
            const Spacer(),
            if (!compact) ...[
              _SlidingNav(
                section: section,
                onHome: onHome,
                onFeatures: onFeatures,
                onAbout: onAbout,
                onContact: onContact,
              ),
              const SizedBox(width: 14),
              OutlinedButton.icon(
                onPressed: () => launchUrl(
                  Uri.parse(EmailBranding.downloadAppUrl),
                  mode: LaunchMode.externalApplication,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.25)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                ),
                icon: const Icon(Icons.download_rounded, size: 16, color: _gold),
                label: const Text(
                  'Download App',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              _GoldPill(label: 'Login', onTap: onLogin),
            ] else
              PopupMenuButton<VoidCallback>(
                color: _panel,
                icon: const Icon(Icons.menu_rounded, color: Colors.white),
                onSelected: (action) => action(),
                itemBuilder: (context) => [
                  for (final item in [
                    ('Home', onHome),
                    ('Features', onFeatures),
                    ('About', onAbout),
                    ('Contact', onContact),
                    ('Download App', () => launchUrl(Uri.parse(EmailBranding.downloadAppUrl), mode: LaunchMode.externalApplication)),
                    ('Login', onLogin),
                  ])
                    PopupMenuItem(
                      value: item.$2,
                      child: Text(
                        item.$1,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        BrandLogo(size: 46),
        SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Law Connect',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                height: 1.1,
              ),
            ),
            SizedBox(height: 2),
            Text(
              'FIRM PORTAL',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
                color: _gold,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SlidingNav extends StatelessWidget {
  const _SlidingNav({
    required this.section,
    required this.onHome,
    required this.onFeatures,
    required this.onAbout,
    required this.onContact,
  });

  final _SiteSection section;
  final VoidCallback onHome;
  final VoidCallback onFeatures;
  final VoidCallback onAbout;
  final VoidCallback onContact;

  static const _width = 108.0;

  @override
  Widget build(BuildContext context) {
    final index = section.index.clamp(0, 3);
    final links = [
      ('Home', onHome),
      ('Features', onFeatures),
      ('About', onAbout),
      ('Contact', onContact),
    ];

    return SizedBox(
      width: _width * links.length,
      height: 48,
      child: Stack(
        children: [
          Row(
            children: [
              for (var i = 0; i < links.length; i++)
                SizedBox(
                  width: _width,
                  child: TextButton(
                    onPressed: links[i].$2,
                    style: TextButton.styleFrom(
                      foregroundColor: i == index ? _gold : Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                    child: Text(
                      links[i].$1,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            left: index * _width + (_width - 36) / 2,
            bottom: 2,
            width: 36,
            height: 2,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: _gold,
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GoldPill extends StatelessWidget {
  const _GoldPill({required this.label, required this.onTap, this.filled = false});

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final child = Text(
      label,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: filled ? const Color(0xFF1B1404) : _gold,
      ),
    );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(24));
    if (filled) {
      return ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: const Color(0xFF1B1404),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          shape: shape,
        ),
        child: child,
      );
    }
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: _gold,
        side: const BorderSide(color: _gold, width: 1.4),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        shape: shape,
      ),
      child: child,
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.onGetStarted, required this.onLearnMore});

  final VoidCallback onGetStarted;
  final VoidCallback onLearnMore;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final wide = w >= 980;
    final pad = w < 720 ? 20.0 : 48.0;

    final copy = Column(
      crossAxisAlignment:
          wide ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: _gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _gold.withValues(alpha: 0.45)),
          ),
          child: const Text(
            'Your Trusted Legal Partner',
            style: TextStyle(
              color: _gold,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Text.rich(
          TextSpan(
            style: TextStyle(
              fontSize: wide ? 48 : 34,
              height: 1.12,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            children: const [
              TextSpan(text: 'Transform Your\nLegal Practice with\n'),
              TextSpan(
                text: 'Smart Case Management',
                style: TextStyle(color: _gold),
              ),
            ],
          ),
          textAlign: wide ? TextAlign.start : TextAlign.center,
        ),
        const SizedBox(height: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Text(
            'Law Connect brings cases, appointments, documents, notary, and billing into one firm portal — so the office and clients stay organized.',
            textAlign: wide ? TextAlign.start : TextAlign.center,
            style: TextStyle(
              fontSize: wide ? 16 : 15,
              height: 1.55,
              color: Colors.white.withValues(alpha: 0.88),
            ),
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: wide ? WrapAlignment.start : WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton(
              onPressed: onGetStarted,
              style: ElevatedButton.styleFrom(
                backgroundColor: _gold,
                foregroundColor: const Color(0xFF1B1404),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Get Started',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
            _GoldPill(label: 'Learn More', onTap: onLearnMore),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                Uri.parse(EmailBranding.downloadAppUrl),
                mode: LaunchMode.externalApplication,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              icon: const Icon(Icons.download_rounded, size: 18, color: _gold),
              label: const Text(
                'Download App',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ],
    );

    final statue = ShaderMask(
      shaderCallback: (rect) {
        return const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.transparent, Colors.white, Colors.white],
          stops: [0.0, 0.18, 1],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstIn,
      child: Image.asset(
        'assets/Landingpage.png',
        height: wide ? 500 : 260,
        width: double.infinity,
        fit: BoxFit.cover,
        alignment: const Alignment(0.86, 0.12),
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => const SizedBox(height: 240),
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, wide ? 36 : 24, pad, wide ? 28 : 20),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(flex: 6, child: copy),
                    const SizedBox(width: 28),
                    Expanded(flex: 5, child: statue),
                  ],
                )
              : Column(
                  children: [
                    copy,
                    const SizedBox(height: 24),
                    statue,
                  ],
                ),
        ),
      ),
    );
  }
}

class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection({super.key});

  @override
  Widget build(BuildContext context) {
    const items = [
      (
        Icons.folder_open_rounded,
        'Case Management',
        'Open a case, follow its status, and keep every update together.',
      ),
      (
        Icons.event_available_rounded,
        'Appointments',
        'Book consultations and see the hearings that are coming up.',
      ),
      (
        Icons.description_outlined,
        'Documents',
        'Keep case files in the portal instead of scattered email.',
      ),
      (
        Icons.draw_outlined,
        'Notary Services',
        'Request a notary visit and follow the office schedule.',
      ),
      (
        Icons.payments_outlined,
        'Billing & Payments',
        'See balances and legal fees without a separate ledger.',
      ),
      (
        Icons.chat_bubble_outline_rounded,
        'Messages',
        'Clients, staff, and attorneys stay in one conversation.',
      ),
      (
        Icons.calendar_month_rounded,
        'Calendar',
        'Hearings, visits, and deadlines on a single schedule.',
      ),
      (
        Icons.people_outline_rounded,
        'Clients',
        'The office keeps each client record beside the case.',
      ),
      (
        Icons.task_alt_rounded,
        'Tasks',
        'Staff tasks stay attached to the work of the firm.',
      ),
      (
        Icons.assessment_outlined,
        'Reports & Logs',
        'Review activity and reports from the same portal.',
      ),
    ];

    return ColoredBox(
      color: const Color(0xFF08182C),
      child: _PageFrame(
        padY: 64,
        child: Column(
          children: [
            const Text(
              'Why Choose Law Connect?',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Every tool the firm already uses — cases through reports — in one portal.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.5,
                color: Colors.white.withValues(alpha: 0.75),
              ),
            ),
            const SizedBox(height: 32),
            LayoutBuilder(
              builder: (context, constraints) {
                final cols = constraints.maxWidth >= 1100
                    ? 5
                    : constraints.maxWidth >= 820
                        ? 3
                        : constraints.maxWidth >= 520
                            ? 2
                            : 1;
                const gap = 16.0;
                final cardW =
                    (constraints.maxWidth - gap * (cols - 1)) / cols;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: cardW,
                        child: _FeatureCard(
                          icon: item.$1,
                          title: item.$2,
                          body: item.$3,
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _FeatureCard extends StatefulWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  State<_FeatureCard> createState() => _FeatureCardState();
}

class _FeatureCardState extends State<_FeatureCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(0, _hover ? -6 : 0, 0),
        transformAlignment: Alignment.center,
        padding: const EdgeInsets.fromLTRB(18, 26, 18, 22),
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _hover ? _gold : _line, width: _hover ? 1.4 : 1),
          boxShadow: _hover
              ? [
                  BoxShadow(
                    color: _gold.withValues(alpha: 0.18),
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                  ),
                ]
              : null,
        ),
        child: Column(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _gold, width: 1.5),
                color: _gold.withValues(alpha: _hover ? 0.12 : 0.05),
              ),
              child: Icon(widget.icon, color: _gold, size: 26),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.body,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, height: 1.45, color: _muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _PartnerSection extends StatelessWidget {
  const _PartnerSection();

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final copy = const Padding(
      padding: EdgeInsets.all(36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Building Stronger\nLegal Solutions',
            style: TextStyle(
              fontSize: 32,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'More than a system — it is your partner in every case. Attorneys, staff, and clients use the same portal for the work of the firm.',
            style: TextStyle(fontSize: 15, height: 1.55, color: _muted),
          ),
        ],
      ),
    );

    return _PageFrame(
      padY: 56,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ColoredBox(
          color: _panel,
          child: wide
              ? SizedBox(
                  height: 360,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: copy),
                      const Expanded(flex: 6, child: _FramedPhoto(file: 'brainstorming.webp')),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    copy,
                    const SizedBox(
                      height: 240,
                      child: _FramedPhoto(file: 'brainstorming.webp'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _CommitmentSection extends StatelessWidget {
  const _CommitmentSection({super.key});

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final photo = const _FramedPhoto(file: 'justice-court.webp');
    const copy = Padding(
      padding: EdgeInsets.all(36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Trusted by the firm',
            style: TextStyle(
              color: _gold,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Your Success\nOur Commitment',
            style: TextStyle(
              fontSize: 32,
              height: 1.15,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 14),
          Text(
            'Clients can follow cases and appointments. The office handles documents, notary, and billing without leaving the portal.',
            style: TextStyle(fontSize: 15, height: 1.55, color: _muted),
          ),
          SizedBox(height: 22),
          Row(
            children: [
              Expanded(child: _Stat(value: 'Cases', label: 'Tracked in one place')),
              SizedBox(
                height: 42,
                child: VerticalDivider(color: _gold, thickness: 1),
              ),
              Expanded(
                child: _Stat(value: 'One portal', label: 'Clients, staff, attorneys'),
              ),
            ],
          ),
        ],
      ),
    );

    return _PageFrame(
      padY: 8,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: ColoredBox(
          color: const Color(0xFF0A1C36),
          child: wide
              ? SizedBox(
                  height: 380,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: photo),
                      const Expanded(flex: 6, child: copy),
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(
                      height: 240,
                      child: _FramedPhoto(file: 'justice-court.webp'),
                    ),
                    copy,
                  ],
                ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: _gold,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: _muted, fontSize: 13)),
      ],
    );
  }
}

class _CtaSection extends StatelessWidget {
  const _CtaSection({required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 800;
    final pad = MediaQuery.sizeOf(context).width < 720 ? 20.0 : 48.0;

    return Padding(
      padding: const EdgeInsets.only(top: 56),
      child: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(color: Color(0xFF061526)),
          ),
          const Positioned.fill(
            child: _SitePhoto(file: 'supreme-court.webp', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF061526).withValues(alpha: 0.82),
                    const Color(0xFF061526).withValues(alpha: 0.45),
                  ],
                ),
              ),
            ),
          ),
          Padding(
              padding: EdgeInsets.symmetric(horizontal: pad, vertical: 40),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1180),
                  child: wide
                      ? Row(
                          children: [
                            const Expanded(child: _CtaCopy()),
                            const SizedBox(width: 24),
                            _GoldPill(
                              label: 'Get Started  →',
                              onTap: onGetStarted,
                              filled: true,
                            ),
                          ],
                        )
                      : Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const _CtaCopy(),
                            const SizedBox(height: 16),
                            _GoldPill(
                              label: 'Get Started  →',
                              onTap: onGetStarted,
                              filled: true,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
    );
  }
}

class _CtaCopy extends StatelessWidget {
  const _CtaCopy();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Ready to streamline\nyour legal practice?',
          style: TextStyle(
            color: Colors.white,
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w800,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Sign in to the firm portal and manage cases from one place.',
          style: TextStyle(color: _muted, fontSize: 14, height: 1.4),
        ),
      ],
    );
  }
}

class _SiteFooter extends StatelessWidget {
  const _SiteFooter({super.key, required this.onCreateAccount});

  final VoidCallback onCreateAccount;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 980;
    const services = [
      (Icons.folder_open_rounded, 'Case Management'),
      (Icons.event_available_rounded, 'Appointments'),
      (Icons.description_outlined, 'Documents'),
      (Icons.draw_outlined, 'Notary Services'),
      (Icons.payments_outlined, 'Billing & Payments'),
      (Icons.chat_bubble_outline_rounded, 'Messages'),
      (Icons.calendar_month_rounded, 'Calendar'),
      (Icons.people_outline_rounded, 'Clients'),
      (Icons.task_alt_rounded, 'Tasks'),
      (Icons.assessment_outlined, 'Reports & Logs'),
    ];

    final brand = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _BrandLockup(),
        const SizedBox(height: 22),
        Wrap(
          spacing: 18,
          runSpacing: 14,
          children: [
            for (final item in services)
              SizedBox(
                width: 190,
                child: Row(
                  children: [
                    Icon(item.$1, color: _gold, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.$2,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 28),
        Text(
          '© ${DateTime.now().year} Law Connect. All rights reserved.',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    );

    final login = ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: _FirmPortalLoginCard(onCreateAccount: onCreateAccount),
    );

    return ColoredBox(
      color: const Color(0xFF06101C),
      child: _PageFrame(
        padY: 48,
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(flex: 6, child: brand),
                  Container(
                    width: 1,
                    height: 280,
                    margin: const EdgeInsets.symmetric(horizontal: 28),
                    color: _gold.withValues(alpha: 0.35),
                  ),
                  Expanded(
                    flex: 5,
                    child: Align(alignment: Alignment.center, child: login),
                  ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  brand,
                  const SizedBox(height: 28),
                  login,
                ],
              ),
      ),
    );
  }
}

class _FramedPhoto extends StatelessWidget {
  const _FramedPhoto({required this.file});

  final String file;

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: _SitePhoto(file: file),
    );
  }
}

class _SitePhoto extends StatelessWidget {
  const _SitePhoto({required this.file, this.fit = BoxFit.cover});

  final String file;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final url = Uri.base.resolve('images/$file').toString();
    return SizedBox.expand(
      child: Image.network(
        url,
        fit: fit,
        alignment: Alignment.center,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => Image.asset(
          'assets/$file',
          fit: fit,
          alignment: Alignment.center,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => const ColoredBox(
            color: Color(0xFF102743),
            child: Center(
              child: Icon(Icons.image_outlined, color: _gold, size: 36),
            ),
          ),
        ),
      ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.child, this.padY = 0});

  final Widget child;
  final double padY;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final padX = w < 720 ? 20.0 : 48.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(padX, padY, padX, padY),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: child,
        ),
      ),
    );
  }
}

class _FirmPortalLoginCard extends StatefulWidget {
  const _FirmPortalLoginCard({required this.onCreateAccount});

  final VoidCallback onCreateAccount;

  @override
  State<_FirmPortalLoginCard> createState() => _FirmPortalLoginCardState();
}

class _FirmPortalLoginCardState extends State<_FirmPortalLoginCard> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_prefetchForTypedEmail);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      prefetchAllPortalDashboards();
    });
  }

  void _prefetchForTypedEmail() {
    final email = _emailController.text.trim();
    if (email.contains('@')) {
      prefetchPortalDashboard(AuthService.resolvePortalRole(email));
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _authService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (result['success'] == true) {
        if (!mounted) return;

        final role = result['role'] ?? 'client';
        final portalRole = AuthService.resolvePortalRole(
          _emailController.text.trim(),
          firestoreRole: role,
        );
        try {
          navigateToPortalDashboard(portalRole);
        } catch (e) {
          Get.offAllNamed(
            switch (portalRole.toLowerCase()) {
              'admin' => '/AdminDashboard',
              'attorney' => '/AttorneyDashboard',
              'staff' => '/StaffDashboard',
              _ => '/ClientDashboard',
            },
          );
        }
      } else {
        if (!mounted) return;
        await showLoginErrorDialog(
          context,
          message: result['message'] ?? 'Invalid email or password',
          onForgotPassword: () {
            Get.to(() => const ForgotPasswordPage());
          },
        );
      }
    } catch (e) {
      if (!mounted) return;
      await showLoginErrorDialog(
        context,
        message: e,
        onForgotPassword: () {
          Get.to(() => const ForgotPasswordPage());
        },
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData prefix,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF8A97AB), fontSize: 14),
      prefixIcon: Icon(prefix, color: _gold.withValues(alpha: 0.9), size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: _inputFill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _inputBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _gold, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 22),
      decoration: BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 36,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: _gold, width: 1.4),
                ),
                child: const Icon(Icons.balance, color: _gold, size: 28),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Welcome back',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Sign in to access your firm portal',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _muted),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _emailController,
              focusNode: _emailFocus,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: _gold,
              onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
              decoration: _fieldDecoration(
                hint: 'Email',
                prefix: Icons.mail_outline_rounded,
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your email';
                }
                if (!value.contains('@')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _passwordController,
              focusNode: _passwordFocus,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              cursorColor: _gold,
              onFieldSubmitted: (_) => _login(),
              decoration: _fieldDecoration(
                hint: 'Password',
                prefix: Icons.lock_outline_rounded,
                suffix: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    color: _muted,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Get.to(() => const ForgotPasswordPage()),
                style: TextButton.styleFrom(
                  foregroundColor: _gold,
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _gold,
                  foregroundColor: const Color(0xFF1B1404),
                  disabledBackgroundColor: _gold.withValues(alpha: 0.7),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF1B1404),
                        ),
                      )
                    : const Text(
                        'Login',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.16))),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: TextStyle(color: _muted, fontSize: 13)),
                ),
                Expanded(child: Divider(color: Colors.white.withValues(alpha: 0.16))),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: widget.onCreateAccount,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _gold,
                  side: const BorderSide(color: _gold, width: 1.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.person_add_alt_1_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Create account',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.verified_user_outlined,
                  size: 16,
                  color: AppTheme.royalBlue.withValues(alpha: 0.95),
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Your information is handled in line with professional confidentiality standards.',
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.4,
                      color: _muted,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}

/// Original app landing — used on mobile/desktop so the website redesign
/// does not change in-app screens.
class _AppLandingPage extends StatelessWidget {
  const _AppLandingPage();

  static Widget _brandLogo(double size) => BrandLogo(size: size);

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isWide = w >= 900;
    final pad = w < 600 ? 24.0 : 40.0;

    return Scaffold(
      backgroundColor: AppTheme.navy,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final topInset = constraints.maxHeight < 700 ? 32.0 : 56.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(pad, topInset, pad, 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - topInset - 32,
                ),
                child: Align(
                  alignment: const Alignment(0, 0.42),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: isWide
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 5,
                                child: Transform.translate(
                                  offset: const Offset(0, -20),
                                  child: _AppHeroColumn(
                                    logo: _brandLogo(100),
                                    compact: false,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                              Expanded(
                                flex: 4,
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 44),
                                  child: _AppSidePanel(),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Transform.translate(
                                offset: const Offset(0, -16),
                                child: _AppHeroColumn(
                                  logo: _brandLogo(88),
                                  compact: true,
                                ),
                              ),
                              const SizedBox(height: 28),
                              _AppSidePanel(),
                            ],
                          ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AppHeroColumn extends StatelessWidget {
  const _AppHeroColumn({required this.logo, required this.compact});

  final Widget logo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment:
              compact ? MainAxisAlignment.center : MainAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            logo,
            const SizedBox(width: 16),
            Flexible(
              child: Column(
                crossAxisAlignment: compact
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    'Law Connect',
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.white,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Firm portal',
                    textAlign: compact ? TextAlign.center : TextAlign.start,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.gold.withValues(alpha: 0.95),
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 28 : 36),
        Text(
          'Counsel you can trust.\nClarity when it matters.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 30 : 36,
            fontWeight: FontWeight.w700,
            height: 1.15,
            color: AppTheme.white,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Secure access to cases, appointments, and messages—'
          'built for a modern law practice.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            fontSize: compact ? 15 : 16,
            height: 1.55,
            color: AppTheme.white.withValues(alpha: 0.82),
          ),
        ),
        SizedBox(height: compact ? 22 : 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: compact ? WrapAlignment.center : WrapAlignment.start,
          children: const [
            _AppFeatureChip(icon: Icons.gavel_rounded, label: 'Case updates'),
            _AppFeatureChip(
              icon: Icons.calendar_month_rounded,
              label: 'Appointments',
            ),
            _AppFeatureChip(icon: Icons.lock_rounded, label: 'Private & secure'),
          ],
        ),
      ],
    );
  }
}

class _AppFeatureChip extends StatelessWidget {
  const _AppFeatureChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: AppTheme.gold),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _AppSidePanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.white,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Welcome',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppTheme.royalBlue,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to access the portal, or create an account to get started with the firm.',
            style: TextStyle(
              fontSize: 14,
              height: 1.45,
              color: Colors.grey[800],
            ),
          ),
          const SizedBox(height: 24),
          AppButton(
            text: 'Sign in',
            onPressed: () => Get.toNamed('/LoginPage'),
          ),
          const SizedBox(height: 12),
          AppButton(
            text: 'Create account',
            isSecondary: true,
            onPressed: () {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SignupPage(),
                  fullscreenDialog: true,
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          Divider(color: Colors.grey[300]),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 20,
                color: AppTheme.royalBlue.withValues(alpha: 0.85),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your information is handled in line with professional confidentiality standards.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: Colors.grey[700],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
