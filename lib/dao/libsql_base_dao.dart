import 'package:libsql_dart/libsql_dart.dart';
import 'package:chatmcp/dao/libsql_database.dart';

/// Abstract base DAO class using libsql_dart
/// Provides generic CRUD operations with type safety
abstract class LibSqlBaseDao<T> {
  final String tableName;

  const LibSqlBaseDao(this.tableName);

  /// Get database client instance
  LibsqlClient get client => LibSqlDatabase.instance.client;

  /// Convert entity to JSON map for database storage
  Map<String, dynamic> toJson(T entity);

  /// Convert database JSON map to entity
  T fromJson(Map<String, dynamic> json);

  /// Insert a new entity
  Future<int> insert(T entity) async {
    final json = toJson(entity);
    final columns = json.keys.join(', ');
    final placeholders = List.filled(json.length, '?').join(', ');
    final values = json.values.toList();

    final sql = 'INSERT INTO $tableName ($columns) VALUES ($placeholders)';
    await client.execute(sql, positional: values);

    // Get last insert row ID
    final result = await client.query('SELECT last_insert_rowid()');
    return result[0]['last_insert_rowid()'] as int;
  }

  /// Insert or replace an entity
  Future<int> insertOrReplace(T entity) async {
    final json = toJson(entity);
    final columns = json.keys.join(', ');
    final placeholders = List.filled(json.length, '?').join(', ');
    final values = json.values.toList();

    final sql = 'INSERT OR REPLACE INTO $tableName ($columns) VALUES ($placeholders)';
    await client.execute(sql, positional: values);

    // Get last insert row ID
    final result = await client.query('SELECT last_insert_rowid()');
    return result[0]['last_insert_rowid()'] as int;
  }

  /// Query entities with optional filtering
  Future<List<T>> query({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
    int? limit,
    int? offset,
  }) async {
    String sql = 'SELECT * FROM $tableName';
    List<Object?> args = [];

    if (where != null) {
      sql += ' WHERE $where';
      if (whereArgs != null) {
        args.addAll(whereArgs);
      }
    }

    if (orderBy != null) {
      sql += ' ORDER BY $orderBy';
    }

    if (limit != null) {
      sql += ' LIMIT $limit';
    }

    if (offset != null) {
      sql += ' OFFSET $offset';
    }

    final results = await client.query(sql, positional: args.isNotEmpty ? args : null);
    return results.map((row) => fromJson(row)).toList();
  }

  /// Find entity by ID
  Future<T?> findById(int id) async {
    final results = await client.query(
      'SELECT * FROM $tableName WHERE id = ?',
      positional: [id],
    );

    if (results.isEmpty) return null;
    return fromJson(results.first);
  }

  /// Find entities by column value
  Future<List<T>> findByColumn(String column, Object? value, {String? orderBy}) async {
    final sql = 'SELECT * FROM $tableName WHERE $column = ?${orderBy != null ? ' ORDER BY $orderBy' : ''}';
    final results = await client.query(sql, positional: [value]);

    return results.map((row) => fromJson(row)).toList();
  }

  /// Update entity by ID
  Future<int> update(T entity, int id) async {
    final json = toJson(entity);
    if (json.isEmpty) return 0;

    final setClause = json.keys.map((key) => '$key = ?').join(', ');
    final values = [...json.values, id];

    final sql = 'UPDATE $tableName SET $setClause WHERE id = ?';
    await client.execute(sql, positional: values);

    // libsql_dart doesn't provide affected rows count directly, so we assume 1 row was updated
    return 1;
  }

  /// Update entities matching WHERE clause
  Future<int> updateWhere(
    Map<String, dynamic> updates,
    String where,
    List<Object?> whereArgs,
  ) async {
    if (updates.isEmpty) return 0;

    final setClause = updates.keys.map((key) => '$key = ?').join(', ');
    final args = [...updates.values, ...whereArgs];

    final sql = 'UPDATE $tableName SET $setClause WHERE $where';
    await client.execute(sql, positional: args);

    // libsql_dart doesn't provide affected rows count directly
    return 1;
  }

  /// Delete entity by ID
  Future<int> delete(int id) async {
    final sql = 'DELETE FROM $tableName WHERE id = ?';
    await client.execute(sql, positional: [id]);

    // libsql_dart doesn't provide affected rows count directly
    return 1;
  }

  /// Delete entities matching WHERE clause
  Future<int> deleteWhere(String where, List<Object?> whereArgs) async {
    final sql = 'DELETE FROM $tableName WHERE $where';
    await client.execute(sql, positional: whereArgs);

    // libsql_dart doesn't provide affected rows count directly
    return 1;
  }

  /// Count all entities
  Future<int> count({String? where, List<Object?>? whereArgs}) async {
    String sql = 'SELECT COUNT(*) as count FROM $tableName';
    List<Object?> args = [];

    if (where != null) {
      sql += ' WHERE $where';
      if (whereArgs != null) {
        args.addAll(whereArgs);
      }
    }

    final results = await client.query(sql, positional: args.isNotEmpty ? args : null);
    return results[0]['count'] as int;
  }

  /// Check if entity exists
  Future<bool> exists(int id) async {
    final results = await client.query(
      'SELECT 1 FROM $tableName WHERE id = ? LIMIT 1',
      positional: [id],
    );
    return results.isNotEmpty;
  }

  /// Get first entity matching criteria
  Future<T?> first({
    String? where,
    List<Object?>? whereArgs,
    String? orderBy,
  }) async {
    final results = await query(
      where: where,
      whereArgs: whereArgs,
      orderBy: orderBy,
      limit: 1,
    );

    return results.isNotEmpty ? results.first : null;
  }

  /// Execute custom query
  Future<List<T>> rawQuery(String sql, [List<Object?>? parameters]) async {
    final results = await client.query(sql, positional: parameters);
    return results.map((row) => fromJson(row)).toList();
  }

  /// Execute raw command
  Future<void> rawExecute(String sql, [List<Object?>? parameters]) async {
    await client.execute(sql, positional: parameters);
  }

  /// Perform operation within transaction
  Future<R> transaction<R>(Future<R> Function(Object txn) action) async {
    return await LibSqlDatabase.instance.transaction(action);
  }

  /// Batch insert operations
  Future<void> batchInsert(List<T> entities) async {
    if (entities.isEmpty) return;

    await transaction((txn) async {
      for (final entity in entities) {
        final json = toJson(entity);
        final columns = json.keys.join(', ');
        final placeholders = List.filled(json.length, '?').join(', ');
        final values = json.values.toList();

        final sql = 'INSERT INTO $tableName ($columns) VALUES ($placeholders)';
        await client.execute(sql, positional: values);
      }
    });
  }

  /// Batch insert or replace operations
  Future<void> batchInsertOrReplace(List<T> entities) async {
    if (entities.isEmpty) return;

    await transaction((txn) async {
      for (final entity in entities) {
        final json = toJson(entity);
        final columns = json.keys.join(', ');
        final placeholders = List.filled(json.length, '?').join(', ');
        final values = json.values.toList();

        final sql = 'INSERT OR REPLACE INTO $tableName ($columns) VALUES ($placeholders)';
        await client.execute(sql, positional: values);
      }
    });
  }
}