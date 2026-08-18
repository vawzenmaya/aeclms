// lib/features/profile/presentation/settings_screen.dart

import 'package:aeclms/features/profile/presentation/change_password_screen.dart';
import 'package:aeclms/features/profile/presentation/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart'; // Needed for the profile refresh

import '../../../../main.dart';
import '../../auth/data/auth_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.profile,
    required this.authService,
  });

  final Profile profile;
  final AuthService authService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Local state for the push notifications toggle
  bool _pushNotificationsEnabled = true;
  
  // Local state to hold the dynamic name
  late String _fullName;

  @override
  void initState() {
    super.initState();
    _fullName = widget.profile.fullName;
  }

  // Fetches the newly updated name from the database without restarting the app
  Future<void> _refreshProfile() async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('full_name')
          .eq('id', widget.profile.id)
          .single();
          
      if (mounted) {
        setState(() {
          _fullName = response['full_name'] as String;
        });
      }
    } catch (e) {
      debugPrint('Failed to refresh profile name: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final email = widget.authService.currentUser?.email ?? 'Unknown Email';
    
    // Determine if dark mode is currently active
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        backgroundColor: scheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        children: [
          // 1. Profile Hero Section
          _StaggeredFadeIn(
            index: 0,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    scheme.primary.withValues(alpha: 0.15),
                    scheme.primary.withValues(alpha: 0.02),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.primary.withValues(alpha: 0.3), width: 2),
                    ),
                    child: CircleAvatar(
                      radius: 40,
                      backgroundColor: scheme.primary.withValues(alpha: 0.2),
                      child: Text(
                        _fullName.isNotEmpty ? _fullName[0].toUpperCase() : '?',
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: scheme.primary),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _fullName,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      email,
                      style: TextStyle(fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 32),

          // 2. Account Group
          _StaggeredFadeIn(
            index: 1,
            child: _SettingsGroup(
              title: 'Account',
              children: [
                _SettingsTile(
                  icon: Icons.person_outline_rounded,
                  title: 'Edit Profile',
                  subtitle: 'Update your name, phone, and employee ID',
                  onTap: () async {
                    // Await the result from EditProfileScreen
                    final didUpdate = await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => EditProfileScreen(profile: widget.profile),
                      ),
                    );
                    
                    // If it returned true, fetch the new data
                    if (didUpdate == true) {
                      _refreshProfile();
                    }
                  },
                ),
                _SettingsTile(
                  icon: Icons.shield_outlined,
                  title: 'Security',
                  subtitle: 'Change your password',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const ChangePasswordScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 3. Preferences Group
          _StaggeredFadeIn(
            index: 2,
            child: _SettingsGroup(
              title: 'Preferences',
              children: [
                _SettingsTile(
                  icon: Icons.notifications_outlined,
                  title: 'Push Notifications',
                  subtitle: 'Manage alerts and updates',
                  trailing: Switch(
                    value: _pushNotificationsEnabled,
                    onChanged: (val) {
                      setState(() => _pushNotificationsEnabled = val);
                    },
                    activeThumbColor: scheme.primary,
                  ),
                  onTap: () {
                    setState(() => _pushNotificationsEnabled = !_pushNotificationsEnabled);
                  },
                ),
                _SettingsTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Dark Mode',
                  subtitle: 'Toggle app appearance',
                  trailing: Switch(
                    value: isDarkMode,
                    onChanged: (val) {
                      appThemeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                    },
                    activeThumbColor: scheme.primary,
                  ),
                  onTap: () {
                    appThemeNotifier.value = !isDarkMode ? ThemeMode.dark : ThemeMode.light;
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // 4. Support Group
          _StaggeredFadeIn(
            index: 3,
            child: _SettingsGroup(
              title: 'Support',
              children: [
                _SettingsTile(
                  icon: Icons.help_outline_rounded,
                  title: 'Help Center',
                  onTap: () {},
                ),
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  title: 'About AECLMS',
                  subtitle: 'Version 1.0.0',
                  showChevron: false,
                  onTap: () {},
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          // 5. Log Out Action
          _StaggeredFadeIn(
            index: 4,
            child: FilledButton.icon(
              onPressed: () => _confirmSignOut(context),
              icon: const Icon(Icons.logout_rounded, size: 20),
              label: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFD9534F).withValues(alpha: 0.1),
                foregroundColor: const Color(0xFFD9534F),
                padding: const EdgeInsets.symmetric(vertical: 16),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                side: BorderSide(color: const Color(0xFFD9534F).withValues(alpha: 0.3)),
              ),
            ),
          ),
          
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final scheme = Theme.of(context).colorScheme;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: scheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Log Out?', style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text('Are you sure you want to log out of your account?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD9534F),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: const Text('Log Out', style: TextStyle(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      widget.authService.signOut();
    }
  }
}

class _SettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SettingsGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 16, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: scheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            children: List.generate(children.length, (index) {
              return Column(
                children: [
                  children[index],
                  if (index < children.length - 1)
                    Divider(height: 1, indent: 56, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool showChevron;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
    this.trailing,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: scheme.onSurface.withValues(alpha: 0.8)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.5), fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) 
                trailing!
              else if (showChevron)
                Icon(Icons.chevron_right_rounded, color: scheme.onSurface.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaggeredFadeIn extends StatefulWidget {
  final Widget child;
  final int index;

  const _StaggeredFadeIn({required this.child, required this.index});

  @override
  State<_StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<_StaggeredFadeIn> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    Future.delayed(Duration(milliseconds: 75 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}