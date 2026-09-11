class LibraryEntry {
  LibraryEntry({
    required this.id,
    required this.title,
    required this.importedAt,
    required this.lastOpenedAt,
    required this.pageCount,
  });

  factory LibraryEntry.fromJson(Map<String, dynamic> json) => LibraryEntry(
        id: json['id'] as String,
        title: json['title'] as String,
        importedAt: DateTime.parse(json['importedAt'] as String),
        lastOpenedAt: DateTime.parse(json['lastOpenedAt'] as String),
        pageCount: json['pageCount'] as int,
      );

  final String id;
  String title;
  final DateTime importedAt;
  DateTime lastOpenedAt;
  final int pageCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'importedAt': importedAt.toIso8601String(),
        'lastOpenedAt': lastOpenedAt.toIso8601String(),
        'pageCount': pageCount,
      };
}
