/// 书籍信息
class FoliateBookInfo {
  const FoliateBookInfo({
    required this.title,
    this.author,
    this.language,
    this.identifier,
    this.description,
    this.publisher,
    this.published,
    this.cover,
    this.totalSections = 0,
  });

  factory FoliateBookInfo.fromMap(Map<String, dynamic> map) => FoliateBookInfo(
        title: map['title'] as String? ?? '',
        author: map['author'] as String?,
        language: map['language'] as String?,
        identifier: map['identifier'] as String?,
        description: map['description'] as String?,
        publisher: map['publisher'] as String?,
        published: map['published'] as String?,
        cover: map['cover'] as String?,
        totalSections: map['totalSections'] as int? ?? 0,
      );

  final String title;
  final String? author;
  final String? language;
  final String? identifier;
  final String? description;
  final String? publisher;
  final String? published;
  final String? cover;
  final int totalSections;

  @override
  String toString() => 'FoliateBookInfo(title: $title, author: $author)';
}

/// 目录项
class FoliateTocItem {
  const FoliateTocItem({
    required this.label,
    required this.href,
    this.id,
    this.level = 1,
    this.startPercentage = 0,
    this.startPage = 0,
    this.subitems = const [],
  });

  factory FoliateTocItem.fromMap(Map<String, dynamic> map) => FoliateTocItem(
        label: map['label'] as String? ?? '',
        href: map['href'] as String? ?? '',
        id: map['id'] as int?,
        level: map['level'] as int? ?? 1,
        startPercentage: (map['startPercentage'] as num?)?.toDouble() ?? 0,
        startPage: map['startPage'] as int? ?? 0,
        subitems: (map['subitems'] as List<dynamic>?)
                ?.map((e) => FoliateTocItem.fromMap(e as Map<String, dynamic>))
                .toList() ??
            [],
      );

  final String label;
  final String href;
  final int? id;
  final int level;
  final double startPercentage;
  final int startPage;
  final List<FoliateTocItem> subitems;

  @override
  String toString() => 'FoliateTocItem(label: $label, level: $level)';
}
