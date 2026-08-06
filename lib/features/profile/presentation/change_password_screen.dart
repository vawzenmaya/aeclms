// lib/features/profile/presentation/change_password_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/widgets/custom_loader.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Supabase securely updates the password for the currently authenticated user
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordCtrl.text),
      );

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated successfully.'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
      );
      
      Navigator.of(context).pop(); // Return to settings screen
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'An unexpected error occurred. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Security', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -0.5)),
        centerTitle: true,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Security Hero
                    _StaggeredFadeIn(
                      index: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: scheme.primary.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: scheme.primary.withOpacity(0.2), width: 2),
                          ),
                          child: Icon(Icons.shield_rounded, size: 64, color: scheme.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _StaggeredFadeIn(
                      index: 1,
                      child: Text(
                        'Update Your Password',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _StaggeredFadeIn(
                      index: 2,
                      child: Text(
                        'Ensure your account stays secure by using a strong password.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurface.withOpacity(0.6), height: 1.4),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Inputs Card
                    _StaggeredFadeIn(
                      index: 3,
                      child: Container(
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardTheme.color,
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: scheme.outlineVariant.withOpacity(0.5)),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 24, offset: const Offset(0, 8)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Credentials', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                            const SizedBox(height: 24),
                            
                            // New Password Field
                            TextFormField(
                              controller: _newPasswordCtrl,
                              obscureText: _obscureNew,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                labelText: 'New Password',
                                prefixIcon: Icon(Icons.lock_outline_rounded, size: 22, color: scheme.onSurface.withOpacity(0.5)),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureNew ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    color: scheme.onSurface.withOpacity(0.5),
                                    size: 20,
                                  ),
                                  onPressed: () => setState(() => _obscureNew = !_obscureNew), // FIXED HERE
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Please enter a new password';
                                if (v.length < 6) return 'Password must be at least 6 characters';
                                return null;
                              },
                            ),
                            const SizedBox(height: 20),
                            
                            // Confirm Password Field
                            TextFormField(
                              controller: _confirmPasswordCtrl,
                              obscureText: _obscureConfirm,
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                              decoration: InputDecoration(
                                labelText: 'Confirm New Password',
                                prefixIcon: Icon(Icons.lock_reset_rounded, size: 22, color: scheme.onSurface.withOpacity(0.5)),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                    color: scheme.onSurface.withOpacity(0.5),
                                    size: 20,
                                  ),
                                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm), // FIXED HERE
                                ),
                              ),
                              validator: (v) {
                                if (v == null || v.isEmpty) return 'Please confirm your password';
                                if (v != _newPasswordCtrl.text) return 'Passwords do not match';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom Action Dock
          _StaggeredFadeIn(
            index: 4,
            child: Container(
              padding: EdgeInsets.fromLTRB(24, 20, 24, MediaQuery.of(context).padding.bottom + 20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardTheme.color,
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 24, offset: const Offset(0, -8)),
                ],
                borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                border: Border(top: BorderSide(color: scheme.outlineVariant.withOpacity(0.5))),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD9534F).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFD9534F).withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.error_outline_rounded, color: Color(0xFFD9534F)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Color(0xFFD9534F), fontWeight: FontWeight.w600, height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                  
                  FilledButton(
                    onPressed: _saving ? null : _updatePassword,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: _saving
                        ? const CustomLoader(size: 24, color: Colors.white)
                        : const Text(
                            'Update Password',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A lightweight wrapper to provide a staggered fade & slide entrance animation.
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