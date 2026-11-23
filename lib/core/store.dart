import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'models.dart';

final storeProvider = Provider<LocalStore>(
  (ref) => throw StateError('Banco não inicializado.'),
);
final changesProvider = StreamProvider<int>(
  (ref) => ref.watch(storeProvider).changes,
);

class Record {
  final String id, kind;
  final Json data;
  const Record(this.id, this.kind, this.data);
}

// ponytail: document schema keeps modules small; add typed Drift tables when cross-document queries become necessary.
class LocalStore extends GeneratedDatabase {
  LocalStore(super.executor);
  final _events = StreamController<int>.broadcast();
  int _revision = 0;
  static Future<LocalStore> open() async {
    final dir = await getApplicationSupportDirectory();
    return LocalStore(
      NativeDatabase.createInBackground(
        File(p.join(dir.path, 'fitness.sqlite')),
      ),
    );
  }

  @override
  int get schemaVersion => 1;
  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await customStatement(
        'CREATE TABLE records (id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload TEXT NOT NULL CHECK(json_valid(payload)), updated INTEGER NOT NULL)',
      );
      await customStatement(
        'CREATE INDEX records_kind ON records(kind, updated)',
      );
    },
    beforeOpen: (_) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA secure_delete = ON');
    },
  );
  Stream<int> get changes => _events.stream;
  void _changed() => _events.add(++_revision);
  String newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
  Future<List<Record>> list(String kind) async {
    final rows = await customSelect(
      'SELECT id, kind, payload FROM records WHERE kind = ? ORDER BY updated DESC',
      variables: [Variable(kind)],
    ).get();
    return rows
        .map(
          (r) => Record(
            r.read<String>('id'),
            r.read<String>('kind'),
            jsonDecode(r.read<String>('payload')) as Json,
          ),
        )
        .toList();
  }

  Future<Json?> get(String id) async {
    final row = await customSelect(
      'SELECT payload FROM records WHERE id = ?',
      variables: [Variable(id)],
    ).getSingleOrNull();
    return row == null ? null : jsonDecode(row.read<String>('payload')) as Json;
  }

  Future<String> put(String kind, Json data, {String? id}) async {
    final key = id ?? newId();
    await customStatement(
      'INSERT INTO records(id, kind, payload, updated) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload, updated=excluded.updated',
      [key, kind, jsonEncode(data), DateTime.now().microsecondsSinceEpoch],
    );
    _changed();
    return key;
  }

  Future<void> remove(String id) async {
    await customStatement('DELETE FROM records WHERE id = ?', [id]);
    _changed();
  }

  Future<Macros> daily(DateTime day) async {
    final meals = await list('meal');
    return meals
        .where(
          (r) =>
              dayKey(DateTime.parse(r.data['date'] as String)) == dayKey(day),
        )
        .fold<Macros>(
          Macros.zero,
          (sum, r) => sum + Meal.fromJson(r.data).total,
        );
  }

  Future<Json> export() async {
    final rows = await customSelect(
      "SELECT kind, payload FROM records WHERE kind NOT IN ('provider', 'chat', 'consent') ORDER BY updated",
    ).get();
    return {
      'version': 1,
      'exportedAt': DateTime.now().toUtc().toIso8601String(),
      'records': rows.map((r) {
        final data = jsonDecode(r.read<String>('payload')) as Json;
        data.remove('photo');
        return {'kind': r.read<String>('kind'), 'data': data};
      }).toList(),
    };
  }

  Future<void> erase() async {
    await customStatement('DELETE FROM records');
    await customStatement('VACUUM');
    _changed();
  }

  @override
  Future<void> close() async {
    await _events.close();
    await super.close();
  }
}
