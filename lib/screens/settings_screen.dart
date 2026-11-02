import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_scope.dart';
import '../data/app_state.dart';
import '../logic/format.dart';
import '../logic/scheduler.dart';
import '../services/cloud_sync.dart';
import '../services/fx.dart';
import '../services/home_widgets.dart';
import '../services/notifications.dart';
import '../theme.dart';
import '../widgets/celebrations.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';
import '../widgets/sync_badge.dart';
import 'routes.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget paceTile(Pace p) {
      final selected = app.paceKey == p.key;
      return ListTile(
        leading: Icon(
          selected
              ? Icons.radio_button_checked_rounded
              : Icons.radio_button_unchecked_rounded,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(p.label),
        subtitle: Text(p.description),
        onTap: () {
          Fx.instance.toggle();
          app.setPace(p.key);
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          const _GroupTitle('Compte'),
          const _AccountGroup(),
          const _GroupTitle('Rappels'),
          _Group(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Notifications'),
                subtitle: Text(
                  app.reminderEnabled
                      ? 'Chaque jour de révision à '
                          '${formatTime(app.reminderHour, app.reminderMinute)}'
                      : 'Désactivées',
                ),
                value: app.reminderEnabled,
                onChanged: (value) async {
                  Fx.instance.toggle();
                  if (value) {
                    final ok =
                        await NotificationService.instance.requestPermission();
                    if (!context.mounted) return;
                    if (!ok) {
                      showInfoSnack(
                        context,
                        'Notifications refusées : autorise-les dans les '
                        'réglages du téléphone.',
                      );
                      return;
                    }
                  }
                  await app.setReminder(enabled: value);
                },
              ),
              ListTile(
                leading: const Icon(Icons.schedule_rounded),
                title: const Text('Heure du rappel'),
                subtitle: Text(formatTime(app.reminderHour, app.reminderMinute)),
                enabled: app.reminderEnabled,
                onTap: () async {
                  final picked = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: app.reminderHour,
                      minute: app.reminderMinute,
                    ),
                  );
                  if (picked != null) {
                    await app.setReminder(
                      hour: picked.hour,
                      minute: picked.minute,
                    );
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.notification_add_outlined),
                title: const Text('Envoyer une notification de test'),
                subtitle: const Text('Pour vérifier que tout fonctionne'),
                enabled: app.reminderEnabled,
                onTap: () async {
                  final ok = await NotificationService.instance.showTest();
                  if (!context.mounted) return;
                  if (!ok) {
                    showInfoSnack(
                      context,
                      'Impossible d\'afficher une notification ici.',
                    );
                  }
                },
              ),
            ],
          ),
          const _GroupTitle('Rythme des révisions'),
          _Group(children: [for (final p in paces) paceTile(p)]),
          const _Hint(
            'Après chaque révision, tu indiques comment elle s\'est passée : '
            'Oublié (rappel demain), Difficile, Bien ou Facile. Plus c\'était '
            'facile, plus le prochain rappel est loin, et chaque sujet apprend '
            'à son propre rythme. Le rythme général rapproche ou espace tous '
            'les rappels ; il s\'applique à la prochaine révision de chaque '
            'sujet.',
          ),
          const _GroupTitle('Apparence'),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<ThemeMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('Auto'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('Clair'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('Sombre'),
                ),
              ],
              selected: {app.themeMode},
              onSelectionChanged: (s) {
                Fx.instance.toggle();
                app.setThemeMode(s.first);
              },
            ),
          ),
          const _GroupTitle('Sons et vibrations'),
          _Group(
            children: [
              SwitchListTile(
                secondary: const Icon(Icons.music_note_outlined),
                title: const Text('Sons'),
                subtitle: const Text('Un son différent pour chaque note'),
                value: app.soundOn,
                onChanged: (v) {
                  app.setSound(v);
                  Fx.instance.toggle();
                },
              ),
              SwitchListTile(
                secondary: const Icon(Icons.vibration_rounded),
                title: const Text('Vibrations'),
                value: app.hapticsOn,
                onChanged: (v) {
                  app.setHaptics(v);
                  Fx.instance.toggle();
                },
              ),
              ListTile(
                leading: const Icon(Icons.headphones_outlined),
                title: const Text('Écouter les sons'),
                enabled: app.soundOn || app.hapticsOn,
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Fx.instance.tap();
                  _showSoundBoard(context);
                },
              ),
            ],
          ),
          const _Hint(
            'Les sons se mêlent à ta musique sans la couper et suivent le '
            'volume multimédia du téléphone.',
          ),
          const _GroupTitle('Widgets'),
          if (HomeWidgets.instance.available)
            _Group(
              children: [
                ListTile(
                  leading: const Icon(Icons.view_agenda_outlined),
                  title: const Text('Ajouter « Révisions du jour »'),
                  subtitle: const Text('Sujets à revoir, série, bouton +'),
                  onTap: () => _pinWidget(context, HomeWidgets.todayWidget),
                ),
                ListTile(
                  leading: const Icon(Icons.local_fire_department_outlined),
                  title: const Text('Ajouter « Série »'),
                  subtitle: const Text('Ta flamme et la progression du jour'),
                  onTap: () => _pinWidget(context, HomeWidgets.streakWidget),
                ),
              ],
            ),
          const _Hint(
            'Tu peux aussi faire un appui long sur l\'écran d\'accueil → '
            'Widgets → Retiens. Les widgets se mettent à jour tout seuls, '
            'même sans ouvrir l\'app.',
          ),
          const _GroupTitle('Données'),
          _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.upload_outlined),
                title: const Text('Copier une sauvegarde'),
                subtitle: const Text('À coller dans une note ou un mail'),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: app.exportJson()));
                  if (!context.mounted) return;
                  showInfoSnack(
                    context,
                    'Sauvegarde copiée. Colle-la dans un endroit sûr.',
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: const Text('Restaurer une sauvegarde'),
                subtitle: const Text('Remplace les données actuelles'),
                onTap: () => _restore(context, app),
              ),
              ListTile(
                leading: Icon(Icons.delete_forever_outlined, color: scheme.error),
                title: Text(
                  'Tout effacer',
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () => _reset(context, app),
              ),
            ],
          ),
          ListenableBuilder(
            listenable: CloudSync.instance,
            builder: (context, _) {
              final sync = CloudSync.instance;
              return _Hint(
                sync.signedIn
                    ? 'Tes données sont sur ce téléphone et dans ton compte, '
                        'synchronisées automatiquement. « Tout effacer » efface '
                        'aussi le compte.'
                    : sync.available
                        ? 'Tes données restent sur ce téléphone. Crée un compte '
                            'pour les sauvegarder et les synchroniser, ou copie '
                            'une sauvegarde avant de changer de téléphone.'
                        : 'Tes données restent sur ce téléphone : aucun compte, '
                            'aucun serveur. Pense à copier une sauvegarde avant '
                            'de changer de téléphone.',
              );
            },
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              'Retiens 1.4',
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pinWidget(BuildContext context, String widget) async {
    Fx.instance.tap();
    final ok = await HomeWidgets.instance.pin(widget);
    if (!ok && context.mounted) {
      showInfoSnack(
        context,
        'Ton écran d\'accueil ne le permet pas d\'ici : appui long sur '
        'l\'écran d\'accueil → Widgets → Retiens.',
      );
    }
  }

  /// Planche de sons : chaque bouton joue l'effet (avec son éclat).
  void _showSoundBoard(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final items = <(IconData, Color, String, VoidCallback)>[
          for (final r in Rating.values)
            (ratingIcon(r), ratingColor(ctx, r), r.label, () => Fx.instance.rated(r)),
          (Icons.emoji_events_rounded, trophyColor, 'Journée terminée', () {
            Fx.instance.dayComplete();
            showConfetti(ctx);
          }),
          (Icons.local_fire_department_rounded, streakColor, 'Série', Fx.instance.streak),
          (Icons.workspace_premium_rounded, goodColor, 'Souvenir solide', Fx.instance.levelUp),
          (Icons.snooze_rounded, theme.colorScheme.secondary, 'Demain', Fx.instance.postponed),
          (Icons.undo_rounded, theme.colorScheme.onSurfaceVariant, 'Annuler', Fx.instance.undone),
          (Icons.add_task_rounded, theme.colorScheme.primary, 'Ajout', Fx.instance.added),
          (Icons.swipe_right_rounded, theme.colorScheme.tertiary, 'Balayage', Fx.instance.swipeArmed),
        ];
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Écouter les sons', style: theme.textTheme.titleLarge),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.05,
                children: [
                  for (var i = 0; i < items.length; i++)
                    FadeSlideIn(
                      delay: stagger(i, stepMs: 35, max: 12),
                      scale: 0.8,
                      offset: 8,
                      child: _SoundButton(
                        icon: items[i].$1,
                        color: items[i].$2,
                        label: items[i].$3,
                        onTap: items[i].$4,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _restore(BuildContext context, AppState app) async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final raw = await showDialog<String>(
      context: context,
      builder: (_) => _RestoreDialog(initial: clip?.text ?? ''),
    );
    if (raw == null || !context.mounted) return;

    final summary = app.inspectBackup(raw);
    if (summary == null) {
      showInfoSnack(context, 'Ce texte n\'est pas une sauvegarde Retiens.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurer ?'),
        content: Text(
          'La sauvegarde contient ${plural(summary.subjects, 'matière')} et '
          '${plural(summary.topics, 'sujet')}. Elle remplacera tes données '
          'actuelles.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restaurer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final done = await app.importJson(raw);
    if (!context.mounted) return;
    showInfoSnack(
      context,
      done ? 'Sauvegarde restaurée.' : 'La restauration a échoué.',
    );
  }

  Future<void> _reset(BuildContext context, AppState app) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tout effacer ?'),
        content: Text(
          CloudSync.instance.signedIn
              ? 'Matières, sujets et historique seront effacés, sur ce '
                  'téléphone et dans ton compte (et donc sur tes autres '
                  'appareils). Action irréversible.'
              : 'Matières, sujets et historique seront effacés. Action '
                  'irréversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Tout effacer'),
          ),
        ],
      ),
    );
    if (ok == true) {
      Fx.instance.deleted();
      await app.resetAll();
    }
  }
}

/// Compte : créer / se connecter, ou état de la synchronisation et actions.
class _AccountGroup extends StatelessWidget {
  const _AccountGroup();

  @override
  Widget build(BuildContext context) {
    final sync = CloudSync.instance;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        if (!sync.available) {
          return const _Group(
            children: [
              ListTile(
                enabled: false,
                leading: Icon(Icons.cloud_off_outlined),
                title: Text('Synchronisation indisponible'),
                subtitle: Text(
                  'Cette version de l\'app n\'a pas encore sa configuration '
                  'Firebase.',
                ),
              ),
            ],
          );
        }
        final user = sync.user;
        if (user == null) {
          return _Group(
            children: [
              ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: const Text('Créer un compte'),
                subtitle: const Text(
                  'Sauvegarde automatique et synchronisation entre tes appareils',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Fx.instance.tap();
                  openAccount(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.login_rounded),
                title: const Text('Se connecter'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  Fx.instance.tap();
                  openAccount(context, create: false);
                },
              ),
            ],
          );
        }
        final email = user.email ?? 'Compte';
        return _Group(
          children: [
            ListTile(
              leading: CircleAvatar(
                backgroundColor: scheme.primaryContainer,
                foregroundColor: scheme.onPrimaryContainer,
                child: Text(email.characters.first.toUpperCase()),
              ),
              title: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Row(
                children: [
                  Icon(
                    syncStatusIcon(sync.status),
                    size: 16,
                    color: sync.status == SyncStatus.error
                        ? scheme.error
                        : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(syncStatusText(sync))),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.sync_rounded),
              title: const Text('Synchroniser maintenant'),
              enabled: sync.status != SyncStatus.syncing,
              onTap: () {
                Fx.instance.tap();
                sync.syncNow();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Se déconnecter'),
              subtitle: const Text('Tes données restent sur ce téléphone'),
              onTap: () => _signOut(context),
            ),
            ListTile(
              leading: Icon(Icons.person_remove_outlined, color: scheme.error),
              title: Text(
                'Supprimer le compte',
                style: TextStyle(color: scheme.error),
              ),
              onTap: () => _deleteAccount(context),
            ),
          ],
        );
      },
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Tes données restent sur ce téléphone mais ne seront plus '
          'synchronisées. Tu pourras te reconnecter quand tu veux.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    Fx.instance.toggle();
    await CloudSync.instance.signOut();
    if (context.mounted) showInfoSnack(context, 'Déconnecté.');
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _DeleteAccountDialog(),
    );
    if (password == null || !context.mounted) return;
    final error = await CloudSync.instance.deleteAccount(password);
    if (!context.mounted) return;
    if (error != null) {
      Fx.instance.error();
      showInfoSnack(context, error);
      return;
    }
    Fx.instance.deleted();
    showInfoSnack(
      context,
      'Compte supprimé. Tes données restent sur ce téléphone.',
    );
  }
}

class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _password = TextEditingController();

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Supprimer le compte ?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Les données du compte seront effacées du serveur, ainsi que le '
            'compte. Elles restent sur ce téléphone. Confirme avec ton mot de '
            'passe.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Mot de passe'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
            minimumSize: const Size(0, 44),
          ),
          onPressed: _password.text.isEmpty
              ? null
              : () => Navigator.pop(context, _password.text),
          child: const Text('Supprimer'),
        ),
      ],
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(indent: 56),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _RestoreDialog extends StatefulWidget {
  const _RestoreDialog({required this.initial});

  final String initial;

  @override
  State<_RestoreDialog> createState() => _RestoreDialogState();
}

class _RestoreDialogState extends State<_RestoreDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial.trimLeft().startsWith('{') ? widget.initial : '',
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Restaurer une sauvegarde'),
      content: TextField(
        controller: _ctrl,
        minLines: 4,
        maxLines: 8,
        style: Theme.of(context).textTheme.bodySmall,
        decoration: const InputDecoration(
          hintText: 'Colle ici le texte de la sauvegarde',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Continuer'),
        ),
      ],
    );
  }
}

class _SoundButton extends StatelessWidget {
  const _SoundButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Pressable(
      scale: 0.9,
      child: Material(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          splashColor: color.withValues(alpha: 0.25),
          onTap: () {
            onTap();
            final at = centerOf(context);
            if (at != null) {
              showBurst(context, center: at, icon: icon, color: color, sparks: 10);
            }
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 30),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: theme.textTheme.labelMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
