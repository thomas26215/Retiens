import 'package:flutter/material.dart';

import '../services/cloud_sync.dart';
import '../services/fx.dart';
import '../widgets/celebrations.dart';
import '../widgets/common.dart';
import '../widgets/motion.dart';

/// Connexion ou création d'un compte (e-mail + mot de passe).
class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, this.createAccount = true});

  /// Ouvre sur « Créer un compte » (sinon « Se connecter »).
  final bool createAccount;

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  late bool _create = widget.createAccount;
  bool _busy = false;
  bool _showPassword = false;
  String? _error;
  int _shake = 0;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _fail(String message) {
    Fx.instance.error();
    setState(() {
      _error = message;
      _shake++;
      _busy = false;
    });
  }

  Future<void> _submit(Offset? origin) async {
    final email = _email.text.trim();
    final password = _password.text;
    if (!email.contains('@') || !email.contains('.')) {
      return _fail('Entre une adresse e-mail valide.');
    }
    if (password.length < 6) {
      return _fail('Le mot de passe doit faire au moins 6 caractères.');
    }
    if (_create && password != _confirm.text) {
      return _fail('Les deux mots de passe ne sont pas identiques.');
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final sync = CloudSync.instance;
    final error = _create
        ? await sync.signUp(email, password)
        : await sync.signIn(email, password);
    if (!mounted) return;
    if (error != null) return _fail(error);

    Fx.instance.added();
    if (origin != null) {
      showBurst(
        context,
        center: origin,
        icon: Icons.cloud_done_rounded,
        color: Theme.of(context).colorScheme.primary,
        label: _create ? 'Compte créé' : 'Connecté',
      );
    }
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            _create
                ? 'Compte créé : tes données sont sauvegardées et synchronisées.'
                : 'Connecté : tes données sont synchronisées.',
          ),
        ),
      );
  }

  Future<void> _forgotPassword() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      return _fail('Entre d\'abord ton adresse e-mail ci-dessus.');
    }
    setState(() => _busy = true);
    final error = await CloudSync.instance.resetPassword(email);
    if (!mounted) return;
    setState(() => _busy = false);
    if (error != null) return _fail(error);
    Fx.instance.tap();
    showInfoSnack(context, 'E-mail envoyé à $email pour choisir un nouveau mot de passe.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
        children: [
          FadeSlideIn(
            scale: 0.6,
            offset: 0,
            duration: const Duration(milliseconds: 650),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(
                  Icons.cloud_sync_rounded,
                  size: 34,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(
              _create ? 'Créer un compte' : 'Se connecter',
              key: ValueKey(_create),
              style: theme.textTheme.headlineMedium,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tes matières, sujets et révisions sont sauvegardés dans ton compte '
            'et synchronisés automatiquement sur tous tes appareils.',
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: true, label: Text('Nouveau compte')),
                ButtonSegment(value: false, label: Text('J\'ai un compte')),
              ],
              selected: {_create},
              onSelectionChanged: _busy
                  ? null
                  : (s) {
                      Fx.instance.toggle();
                      setState(() {
                        _create = s.first;
                        _error = null;
                      });
                    },
            ),
          ),
          const SizedBox(height: 20),
          Shake(
            trigger: _shake,
            child: Column(
              children: [
                TextField(
                  controller: _email,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  enabled: !_busy,
                  obscureText: !_showPassword,
                  autofillHints: [
                    _create ? AutofillHints.newPassword : AutofillHints.password,
                  ],
                  textInputAction:
                      _create ? TextInputAction.next : TextInputAction.done,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    helperText: _create ? '6 caractères minimum' : null,
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? 'Masquer' : 'Afficher',
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOutCubic,
                  child: _create
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextField(
                            controller: _confirm,
                            enabled: !_busy,
                            obscureText: !_showPassword,
                            textInputAction: TextInputAction.done,
                            decoration: const InputDecoration(
                              labelText: 'Confirmer le mot de passe',
                              prefixIcon: Icon(Icons.lock_reset_rounded),
                            ),
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            child: _error == null
                ? const SizedBox(width: double.infinity)
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, color: scheme.error, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _error!,
                            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.error),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 24),
          Pressable(
            child: Builder(
              builder: (button) => FilledButton(
                onPressed: _busy ? null : () => _submit(centerOf(button)),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: _busy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Text(_create ? 'Créer mon compte' : 'Me connecter'),
                ),
              ),
            ),
          ),
          if (!_create) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : _forgotPassword,
              child: const Text('Mot de passe oublié ?'),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            'Les données de ce téléphone sont gardées et fusionnées avec celles '
            'du compte : rien n\'est perdu. Elles sont hébergées par Firebase '
            '(Google Cloud).',
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
