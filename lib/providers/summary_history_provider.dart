import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ffi_learn/models/summary_record.dart';

class SummaryHistoryProvider extends ChangeNotifier {
  static const _historyKey = 'summary_history_v1';

  List<SummaryRecord> _items = <SummaryRecord>[];

  List<SummaryRecord> get items => List<SummaryRecord>.unmodifiable(_items);

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_historyKey);
      if (raw == null || raw.isEmpty) {
        _items = <SummaryRecord>[];
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _items = <SummaryRecord>[];
        return;
      }

      _items = decoded
          .whereType<Map<String, dynamic>>()
          .map(SummaryRecord.fromJson)
          .toList();
      _items.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
    } catch (_) {
      _items = <SummaryRecord>[];
    }
  }

  Future<void> add({
    required String transcript,
    required String summary,
    required Duration duration,
  }) async {
    final now = DateTime.now();
    final record = SummaryRecord(
      id: now.microsecondsSinceEpoch.toString(),
      createdAtIso: now.toIso8601String(),
      transcript: transcript,
      summary: summary,
      durationSeconds: duration.inSeconds,
    );

    _items = <SummaryRecord>[record, ..._items];
    await _persist();
    notifyListeners();
  }

  Future<void> clearAll() async {
    _items = <SummaryRecord>[];
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(
      _items.map((item) => item.toJson()).toList(),
    );
    await prefs.setString(_historyKey, raw);
  }
}
