// lib/core/utils/app_error_handler.dart

import 'package:flutter/material.dart';

class AppErrorHandler {
  /// Translates raw ugly exceptions into friendly UI text.
  /// Ideal for forms, snackbars, and small error banners so users don't lose typed data.
  static String getFriendlyMessage(Object? error) {
    if (error == null) return 'An unexpected error occurred.';
    
    final errorStr = error.toString().toLowerCase();
    if (errorStr.contains('socketexception') || 
        errorStr.contains('failed host lookup') || 
        errorStr.contains('network is unreachable') ||
        errorStr.contains('clientexception')) {
      return 'No Internet Connection. Please check your network and try again.';
    }
    
    if (errorStr.contains('jwt expired')) {
      return 'Your session has expired. Please log out and log back in.';
    }
    
    return error.toString();
  }
}

/// A full-screen widget that displays a beautiful Offline/Error state
/// with a built-in Retry button. Ideal for Dashboards and Detail screens.
class AppErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;

  const AppErrorView({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final errorStr = error.toString().toLowerCase();
    
    final isOffline = errorStr.contains('socketexception') || 
                      errorStr.contains('failed host lookup') || 
                      errorStr.contains('network') ||
                      errorStr.contains('clientexception');

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFD9534F).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOffline ? Icons.wifi_off_rounded : Icons.error_outline_rounded, 
                  size: 56, 
                  color: const Color(0xFFD9534F),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isOffline ? 'No Internet Connection' : 'Something went wrong',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isOffline 
                    ? 'It looks like you are offline. Please check your network connection and try again.'
                    : 'An unexpected error occurred while processing your request.\n\n${AppErrorHandler.getFriendlyMessage(error)}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}