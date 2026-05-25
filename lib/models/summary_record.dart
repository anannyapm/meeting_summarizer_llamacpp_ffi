class SummaryRecord {
  const SummaryRecord({
    required this.id,
    required this.createdAtIso,
    required this.transcript,
    required this.summary,
    required this.durationSeconds,
  });

  final String id;
  final String createdAtIso;
  final String transcript;
  final String summary;
  final int durationSeconds;

  DateTime get createdAt => DateTime.parse(createdAtIso);

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'createdAtIso': createdAtIso,
      'transcript': transcript,
      'summary': summary,
      'durationSeconds': durationSeconds,
    };
  }

  factory SummaryRecord.fromJson(Map<String, dynamic> json) {
    return SummaryRecord(
      id: json['id'] as String,
      createdAtIso: json['createdAtIso'] as String,
      transcript: json['transcript'] as String,
      summary: json['summary'] as String,
      durationSeconds: json['durationSeconds'] as int,
    );
  }
}
