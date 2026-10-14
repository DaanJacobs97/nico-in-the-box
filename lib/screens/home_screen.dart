import 'package:flutter/material.dart';

import 'host_setup_screen.dart';
import 'join_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.inventory_2_rounded,
                    size: 96,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Nico in the Box',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Party games on your local network',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 48),
                  FilledButton.icon(
                    icon: const Icon(Icons.wifi_tethering),
                    label: const Text('Host a game'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const HostSetupScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.search),
                    label: const Text('Join a game'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const JoinScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
