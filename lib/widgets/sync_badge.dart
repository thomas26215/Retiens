import 'package:flutter/material.dart';

import '../logic/format.dart';
import '../services/cloud_sync.dart';

/// Libellé de l'état de la synchronisation.
String syncStatusText(CloudSync sync) {
  final last = sync.lastSync;
  return switch (sync.status) {
    SyncStatus.unavailable => 'Synchronisation indisponible',
    SyncStatus.signedOut => 'Non connecté',
    SyncStatus.syncing => 'Synchronisation…',
    SyncStatus.synced => last == null
        ? 'Synchronisé'
        : 'Synchronisé à ${formatTime(last.hour, last.minute)}',
    SyncStatus.offline => 'Hors ligne : envoi au retour du réseau',
    SyncStatus.error => sync.lastError ?? 'La synchronisation a échoué.',
  };
}

IconData syncStatusIcon(SyncStatus s) => switch (s) {
      SyncStatus.synced => Icons.cloud_done_outlined,
      SyncStatus.syncing => Icons.cloud_sync_outlined,
      SyncStatus.offline => Icons.cloud_off_outlined,
      SyncStatus.error => Icons.sync_problem_rounded,
      _ => Icons.cloud_outlined,
    };

/// Petit nuage d'état (connecté seulement) ; ouvre les réglages.
class SyncBadge extends StatelessWidget {
  const SyncBadge({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sync = CloudSync.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        if (!sync.signedIn) return const SizedBox.shrink();
        final scheme = Theme.of(context).colorScheme;
        final error = sync.status == SyncStatus.error;
        return IconButton(
          tooltip: syncStatusText(sync),
          onPressed: onTap,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: FadeTransition(opacity: anim, child: child)),
            child: Icon(
              syncStatusIcon(sync.status),
              key: ValueKey(sync.status),
              color: error ? scheme.error : null,
            ),
          ),
        );
      },
    );
  }
}
