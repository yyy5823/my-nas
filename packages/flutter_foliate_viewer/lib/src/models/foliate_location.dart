/// 阅读位置信息
class FoliateLocation {
  const FoliateLocation({
    required this.cfi,
    required this.fraction,
    required this.sectionIndex,
    required this.sectionFraction,
    this.totalSections = 0,
    this.chapterCurrentPage = 0,
    this.chapterTotalPages = 0,
  });

  factory FoliateLocation.fromMap(Map<String, dynamic> map) => FoliateLocation(
        cfi: map['cfi'] as String? ?? '',
        // book.js 传递的 key 是 'percentage'，也兼容 'fraction'
        fraction: (map['percentage'] as num?)?.toDouble() ??
            (map['fraction'] as num?)?.toDouble() ??
            0.0,
        sectionIndex: map['index'] as int? ?? map['sectionIndex'] as int? ?? 0,
        sectionFraction:
            (map['sectionFraction'] as num?)?.toDouble() ?? 0.0,
        totalSections: map['totalSections'] as int? ?? 0,
        chapterCurrentPage: map['chapterCurrentPage'] as int? ?? 0,
        chapterTotalPages: map['chapterTotalPages'] as int? ?? 0,
      );

  /// EPUB CFI 位置标识
  final String cfi;

  /// 全书阅读进度 (0.0 - 1.0)
  final double fraction;

  /// 当前章节索引
  final int sectionIndex;

  /// 当前章节内进度 (0.0 - 1.0)
  final double sectionFraction;

  /// 总章节数
  final int totalSections;

  /// 当前章节的当前页码
  final int chapterCurrentPage;

  /// 当前章节的总页数
  final int chapterTotalPages;

  /// 阅读进度百分比
  double get progressPercent => fraction * 100;

  Map<String, dynamic> toMap() => {
        'cfi': cfi,
        'fraction': fraction,
        'sectionIndex': sectionIndex,
        'sectionFraction': sectionFraction,
        'totalSections': totalSections,
        'chapterCurrentPage': chapterCurrentPage,
        'chapterTotalPages': chapterTotalPages,
      };

  @override
  String toString() =>
      'FoliateLocation(cfi: $cfi, fraction: ${fraction.toStringAsFixed(3)})';
}
