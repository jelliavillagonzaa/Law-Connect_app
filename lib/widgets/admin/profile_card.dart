import 'package:flutter/material.dart';

import '../../models/user_model.dart';
import '../common/safe_network_avatar.dart';
import 'admin_ui_theme.dart';

class ProfileCard extends StatefulWidget {
  const ProfileCard({
    super.key,
    required this.user,
    required this.onLogout,
  });

  final UserModel user;
  final VoidCallback onLogout;

  @override
  State<ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<ProfileCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SafeNetworkAvatar(
                photoUrl: user.photoUrl,
                radius: 14,
                fallbackLetter: user.name.isNotEmpty ? user.name[0] : 'A',
                backgroundColor: const Color(0xFF5C4033),
                foregroundColor: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      user.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          MouseRegion(
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            cursor: SystemMouseCursors.click,
            child: AnimatedContainer(
              duration: AdminUi.anim,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _hover ? AdminUi.secondary : const Color(0xFF16325C),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onLogout,
                  borderRadius: BorderRadius.circular(8),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded, size: 14, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'Logout',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
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
