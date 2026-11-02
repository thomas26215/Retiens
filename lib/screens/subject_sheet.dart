import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../logic/dates.dart';
import '../logic/format.dart';
import '../models/subject.dart';
import '../services/fx.dart';
import '../theme.dart';
import '../widgets/motion.dart';

/// Création (subject == null) ou modification d'une matière, dans une feuille
/// en bas d'écran. Renvoie la matière enregistrée, ou `null` si annulé.
Future<Subject?> showSubjectSheet(BuildContext context, {Subject? subject}) {
  return showModalBottomSheet<Subject>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SubjectSheet(subject: subject),
  );
}

class _SubjectSheet extends StatefulWidget {
  const _SubjectSheet({this.subject});

  final Subject? subject;

  @override
  State<_SubjectSheet> createState() => _SubjectSheetState();
}

class _SubjectSheetState extends State<_SubjectSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.subject?.name ?? '');
  int? _color;
  DateTime? _exam;
  bool _showError = false;
  int _shake = 0;

  @override
  void initState() {
    super.initState();
    _exam = widget.subject?.examDate;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickExam() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _exam ?? now.add(const Duration(days: 60)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: "Date de l'examen",
    );
    if (picked != null) setState(() => _exam = dateOnly(picked));
  }

  void _save(int color) {
    final name = _name.text.trim();
    if (name.isEmpty) {
      Fx.instance.error();
      setState(() {
        _showError = true;
        _shake++;
      });
      return;
    }
    Fx.instance.added();
    final app = AppScope.of(context);
    final s = widget.subject;
    if (s == null) {
      Navigator.pop(context, app.addSubject(name, color, _exam));
    } else {
      app.updateSubject(s, name: name, colorValue: color, examDate: _exam);
      Navigator.pop(context, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final color = _color ?? widget.subject?.colorValue ?? app.nextSubjectColor();
    final exam = _exam;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.subject == null ? 'Nouvelle matière' : 'Modifier la matière',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            Shake(
              trigger: _shake,
              child: TextField(
              controller: _name,
              autofocus: widget.subject == null,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_showError) setState(() => _showError = false);
              },
              onSubmitted: (_) => _save(color),
              decoration: InputDecoration(
                labelText: 'Nom',
                hintText: 'Ex. Ingénierie des exigences',
                errorText: _showError ? 'Donne un nom à la matière' : null,
              ),
            ),
            ),
            const SizedBox(height: 20),
            Text('Couleur', style: theme.textTheme.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < subjectPalette.length; i++)
                  _Swatch(
                    color: Color(isDark ? subjectPaletteDark[i] : subjectPalette[i]),
                    selected: color == subjectPalette[i],
                    onTap: () {
                      Fx.instance.toggle();
                      setState(() => _color = subjectPalette[i]);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Examen', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Material(
              color: scheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                onTap: _pickExam,
                leading: const Icon(Icons.flag_outlined),
                title: Text(
                  exam == null
                      ? 'Ajouter une date d\'examen'
                      : capitalize(formatLongDay(exam)),
                ),
                subtitle: Text(
                  exam == null
                      ? 'Facultatif'
                      : formatRelativeDay(exam, app.today),
                ),
                trailing: exam == null
                    ? null
                    : IconButton(
                        tooltip: "Retirer la date d'examen",
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _exam = null),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Avec une date d'examen : plus aucun rappel après la veille, et "
              'une dernière révision est prévue ce jour-là.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _save(color),
                child: Text(
                  widget.subject == null ? 'Créer la matière' : 'Enregistrer',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ring = Theme.of(context).colorScheme.onSurface;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedScale(
        scale: selected ? 1.12 : 1,
        duration: const Duration(milliseconds: 350),
        curve: Curves.elasticOut,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 44,
        height: 44,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? ring : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) =>
                ScaleTransition(scale: anim, child: child),
            child: selected
                ? Icon(Icons.check_rounded, color: onColor(color), size: 20)
                : const SizedBox.shrink(),
          ),
        ),
      ),
      ),
    );
  }
}
