import '../logic/dates.dart';

/// Couleurs proposées pour les matières, dans l'ordre d'attribution.
/// Palette catégorielle validée (daltonisme, contraste) en clair et en sombre.
const subjectPalette = <int>[
  0xFF2A78D6, // bleu
  0xFFEB6834, // orange
  0xFF1BAF7A, // aqua
  0xFFEDA100, // jaune
  0xFFE87BA4, // magenta
  0xFF008300, // vert
  0xFF6250D6, // violet
  0xFFE34948, // rouge
];

/// Mêmes teintes, ajustées pour le thème sombre.
const subjectPaletteDark = <int>[
  0xFF3987E5,
  0xFFD95926,
  0xFF199E70,
  0xFFC98500,
  0xFFD55181,
  0xFF008300,
  0xFF9085E9,
  0xFFE66767,
];

// Couleurs de la première version, converties vers la teinte la plus proche.
const _legacyColors = <int, int>{
  0xFF3F51B5: 0xFF2A78D6,
  0xFF009688: 0xFF1BAF7A,
  0xFFE91E63: 0xFFE87BA4,
  0xFFFF9800: 0xFFEB6834,
  0xFF9C27B0: 0xFF6250D6,
  0xFF4CAF50: 0xFF008300,
  0xFF2196F3: 0xFF2A78D6,
  0xFF795548: 0xFFEDA100,
};

/// Chapitre d'une matière (ex. « Chapitre 1 : nombres complexes »). Les
/// sujets sans chapitre sont rangés dans « Autre ».
class Chapter {
  Chapter({required this.id, required this.name});

  final String id;
  String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory Chapter.fromJson(Map<String, dynamic> j) =>
      Chapter(id: j['id'] as String, name: j['name'] as String);
}

class Subject {
  Subject({
    required this.id,
    required this.name,
    required this.colorValue,
    this.examDate,
    this.updatedAt = 0,
    List<Chapter>? chapters,
  }) : chapters = chapters ?? [];

  final String id;
  String name;
  int colorValue;
  DateTime? examDate;

  /// Chapitres, dans l'ordre choisi.
  final List<Chapter> chapters;

  Chapter? chapterById(String? id) {
    if (id == null) return null;
    for (final c in chapters) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Dernière modification (ms depuis 1970), pour la synchronisation.
  int updatedAt;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'color': colorValue,
        'examDate': examDate == null ? null : dateKey(examDate!),
        'chapters': chapters.map((c) => c.toJson()).toList(),
        'u': updatedAt,
      };

  factory Subject.fromJson(Map<String, dynamic> j) {
    final color = (j['color'] as num).toInt();
    return Subject(
      id: j['id'] as String,
      name: j['name'] as String,
      colorValue: _legacyColors[color] ?? color,
      examDate:
          j['examDate'] == null ? null : DateTime.parse(j['examDate'] as String),
      updatedAt: (j['u'] as num?)?.toInt() ?? 0,
      chapters: [
        for (final c in j['chapters'] as List? ?? const [])
          Chapter.fromJson(Map<String, dynamic>.from(c as Map)),
      ],
    );
  }
}
