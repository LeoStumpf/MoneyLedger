// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $GroupsTable extends Groups with TableInfo<$GroupsTable, Group> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GroupsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('EUR'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _sigMeta = const VerificationMeta('sig');
  @override
  late final GeneratedColumn<String> sig = GeneratedColumn<String>(
    'sig',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pendingSignMeta = const VerificationMeta(
    'pendingSign',
  );
  @override
  late final GeneratedColumn<bool> pendingSign = GeneratedColumn<bool>(
    'pending_sign',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pending_sign" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _categoriesJsonMeta = const VerificationMeta(
    'categoriesJson',
  );
  @override
  late final GeneratedColumn<String> categoriesJson = GeneratedColumn<String>(
    'categories_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    roomId,
    name,
    currency,
    updatedAt,
    sig,
    pendingSign,
    categoriesJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'groups';
  @override
  VerificationContext validateIntegrity(
    Insertable<Group> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('sig')) {
      context.handle(
        _sigMeta,
        sig.isAcceptableOrUnknown(data['sig']!, _sigMeta),
      );
    }
    if (data.containsKey('pending_sign')) {
      context.handle(
        _pendingSignMeta,
        pendingSign.isAcceptableOrUnknown(
          data['pending_sign']!,
          _pendingSignMeta,
        ),
      );
    }
    if (data.containsKey('categories_json')) {
      context.handle(
        _categoriesJsonMeta,
        categoriesJson.isAcceptableOrUnknown(
          data['categories_json']!,
          _categoriesJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {roomId};
  @override
  Group map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Group(
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      sig: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sig'],
      ),
      pendingSign: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pending_sign'],
      )!,
      categoriesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}categories_json'],
      ),
    );
  }

  @override
  $GroupsTable createAlias(String alias) {
    return $GroupsTable(attachedDatabase, alias);
  }
}

class Group extends DataClass implements Insertable<Group> {
  final String roomId;
  final String name;
  final String currency;
  final int updatedAt;
  final String? sig;
  final bool pendingSign;
  final String? categoriesJson;
  const Group({
    required this.roomId,
    required this.name,
    required this.currency,
    required this.updatedAt,
    this.sig,
    required this.pendingSign,
    this.categoriesJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['room_id'] = Variable<String>(roomId);
    map['name'] = Variable<String>(name);
    map['currency'] = Variable<String>(currency);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || sig != null) {
      map['sig'] = Variable<String>(sig);
    }
    map['pending_sign'] = Variable<bool>(pendingSign);
    if (!nullToAbsent || categoriesJson != null) {
      map['categories_json'] = Variable<String>(categoriesJson);
    }
    return map;
  }

  GroupsCompanion toCompanion(bool nullToAbsent) {
    return GroupsCompanion(
      roomId: Value(roomId),
      name: Value(name),
      currency: Value(currency),
      updatedAt: Value(updatedAt),
      sig: sig == null && nullToAbsent ? const Value.absent() : Value(sig),
      pendingSign: Value(pendingSign),
      categoriesJson: categoriesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(categoriesJson),
    );
  }

  factory Group.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Group(
      roomId: serializer.fromJson<String>(json['roomId']),
      name: serializer.fromJson<String>(json['name']),
      currency: serializer.fromJson<String>(json['currency']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      sig: serializer.fromJson<String?>(json['sig']),
      pendingSign: serializer.fromJson<bool>(json['pendingSign']),
      categoriesJson: serializer.fromJson<String?>(json['categoriesJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'roomId': serializer.toJson<String>(roomId),
      'name': serializer.toJson<String>(name),
      'currency': serializer.toJson<String>(currency),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'sig': serializer.toJson<String?>(sig),
      'pendingSign': serializer.toJson<bool>(pendingSign),
      'categoriesJson': serializer.toJson<String?>(categoriesJson),
    };
  }

  Group copyWith({
    String? roomId,
    String? name,
    String? currency,
    int? updatedAt,
    Value<String?> sig = const Value.absent(),
    bool? pendingSign,
    Value<String?> categoriesJson = const Value.absent(),
  }) => Group(
    roomId: roomId ?? this.roomId,
    name: name ?? this.name,
    currency: currency ?? this.currency,
    updatedAt: updatedAt ?? this.updatedAt,
    sig: sig.present ? sig.value : this.sig,
    pendingSign: pendingSign ?? this.pendingSign,
    categoriesJson: categoriesJson.present
        ? categoriesJson.value
        : this.categoriesJson,
  );
  Group copyWithCompanion(GroupsCompanion data) {
    return Group(
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      name: data.name.present ? data.name.value : this.name,
      currency: data.currency.present ? data.currency.value : this.currency,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sig: data.sig.present ? data.sig.value : this.sig,
      pendingSign: data.pendingSign.present
          ? data.pendingSign.value
          : this.pendingSign,
      categoriesJson: data.categoriesJson.present
          ? data.categoriesJson.value
          : this.categoriesJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Group(')
          ..write('roomId: $roomId, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sig: $sig, ')
          ..write('pendingSign: $pendingSign, ')
          ..write('categoriesJson: $categoriesJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    roomId,
    name,
    currency,
    updatedAt,
    sig,
    pendingSign,
    categoriesJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Group &&
          other.roomId == this.roomId &&
          other.name == this.name &&
          other.currency == this.currency &&
          other.updatedAt == this.updatedAt &&
          other.sig == this.sig &&
          other.pendingSign == this.pendingSign &&
          other.categoriesJson == this.categoriesJson);
}

class GroupsCompanion extends UpdateCompanion<Group> {
  final Value<String> roomId;
  final Value<String> name;
  final Value<String> currency;
  final Value<int> updatedAt;
  final Value<String?> sig;
  final Value<bool> pendingSign;
  final Value<String?> categoriesJson;
  final Value<int> rowid;
  const GroupsCompanion({
    this.roomId = const Value.absent(),
    this.name = const Value.absent(),
    this.currency = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sig = const Value.absent(),
    this.pendingSign = const Value.absent(),
    this.categoriesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GroupsCompanion.insert({
    required String roomId,
    required String name,
    this.currency = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sig = const Value.absent(),
    this.pendingSign = const Value.absent(),
    this.categoriesJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : roomId = Value(roomId),
       name = Value(name);
  static Insertable<Group> custom({
    Expression<String>? roomId,
    Expression<String>? name,
    Expression<String>? currency,
    Expression<int>? updatedAt,
    Expression<String>? sig,
    Expression<bool>? pendingSign,
    Expression<String>? categoriesJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (roomId != null) 'room_id': roomId,
      if (name != null) 'name': name,
      if (currency != null) 'currency': currency,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sig != null) 'sig': sig,
      if (pendingSign != null) 'pending_sign': pendingSign,
      if (categoriesJson != null) 'categories_json': categoriesJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GroupsCompanion copyWith({
    Value<String>? roomId,
    Value<String>? name,
    Value<String>? currency,
    Value<int>? updatedAt,
    Value<String?>? sig,
    Value<bool>? pendingSign,
    Value<String?>? categoriesJson,
    Value<int>? rowid,
  }) {
    return GroupsCompanion(
      roomId: roomId ?? this.roomId,
      name: name ?? this.name,
      currency: currency ?? this.currency,
      updatedAt: updatedAt ?? this.updatedAt,
      sig: sig ?? this.sig,
      pendingSign: pendingSign ?? this.pendingSign,
      categoriesJson: categoriesJson ?? this.categoriesJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (sig.present) {
      map['sig'] = Variable<String>(sig.value);
    }
    if (pendingSign.present) {
      map['pending_sign'] = Variable<bool>(pendingSign.value);
    }
    if (categoriesJson.present) {
      map['categories_json'] = Variable<String>(categoriesJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GroupsCompanion(')
          ..write('roomId: $roomId, ')
          ..write('name: $name, ')
          ..write('currency: $currency, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sig: $sig, ')
          ..write('pendingSign: $pendingSign, ')
          ..write('categoriesJson: $categoriesJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExpensesTable extends Expenses with TableInfo<$ExpensesTable, Expense> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpensesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _matrixEventIdMeta = const VerificationMeta(
    'matrixEventId',
  );
  @override
  late final GeneratedColumn<String> matrixEventId = GeneratedColumn<String>(
    'matrix_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _descriptionMeta = const VerificationMeta(
    'description',
  );
  @override
  late final GeneratedColumn<String> description = GeneratedColumn<String>(
    'description',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _paidByMeta = const VerificationMeta('paidBy');
  @override
  late final GeneratedColumn<String> paidBy = GeneratedColumn<String>(
    'paid_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _splitsJsonMeta = const VerificationMeta(
    'splitsJson',
  );
  @override
  late final GeneratedColumn<String> splitsJson = GeneratedColumn<String>(
    'splits_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sigMeta = const VerificationMeta('sig');
  @override
  late final GeneratedColumn<String> sig = GeneratedColumn<String>(
    'sig',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pendingSignMeta = const VerificationMeta(
    'pendingSign',
  );
  @override
  late final GeneratedColumn<bool> pendingSign = GeneratedColumn<bool>(
    'pending_sign',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pending_sign" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _versionHashMeta = const VerificationMeta(
    'versionHash',
  );
  @override
  late final GeneratedColumn<String> versionHash = GeneratedColumn<String>(
    'version_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    roomId,
    matrixEventId,
    description,
    amountCents,
    currency,
    paidBy,
    splitsJson,
    createdAt,
    updatedAt,
    deleted,
    sig,
    origin,
    pendingSign,
    category,
    note,
    versionHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expenses';
  @override
  VerificationContext validateIntegrity(
    Insertable<Expense> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('matrix_event_id')) {
      context.handle(
        _matrixEventIdMeta,
        matrixEventId.isAcceptableOrUnknown(
          data['matrix_event_id']!,
          _matrixEventIdMeta,
        ),
      );
    }
    if (data.containsKey('description')) {
      context.handle(
        _descriptionMeta,
        description.isAcceptableOrUnknown(
          data['description']!,
          _descriptionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_descriptionMeta);
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('paid_by')) {
      context.handle(
        _paidByMeta,
        paidBy.isAcceptableOrUnknown(data['paid_by']!, _paidByMeta),
      );
    } else if (isInserting) {
      context.missing(_paidByMeta);
    }
    if (data.containsKey('splits_json')) {
      context.handle(
        _splitsJsonMeta,
        splitsJson.isAcceptableOrUnknown(data['splits_json']!, _splitsJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_splitsJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('sig')) {
      context.handle(
        _sigMeta,
        sig.isAcceptableOrUnknown(data['sig']!, _sigMeta),
      );
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    }
    if (data.containsKey('pending_sign')) {
      context.handle(
        _pendingSignMeta,
        pendingSign.isAcceptableOrUnknown(
          data['pending_sign']!,
          _pendingSignMeta,
        ),
      );
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('version_hash')) {
      context.handle(
        _versionHashMeta,
        versionHash.isAcceptableOrUnknown(
          data['version_hash']!,
          _versionHashMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Expense map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Expense(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      matrixEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}matrix_event_id'],
      ),
      description: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}description'],
      )!,
      amountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_cents'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      paidBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}paid_by'],
      )!,
      splitsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}splits_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      sig: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sig'],
      ),
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      ),
      pendingSign: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pending_sign'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      versionHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_hash'],
      ),
    );
  }

  @override
  $ExpensesTable createAlias(String alias) {
    return $ExpensesTable(attachedDatabase, alias);
  }
}

class Expense extends DataClass implements Insertable<Expense> {
  final String id;
  final String roomId;
  final String? matrixEventId;
  final String description;
  final int amountCents;
  final String currency;
  final String paidBy;
  final String splitsJson;
  final int createdAt;
  final int updatedAt;
  final bool deleted;
  final String? sig;
  final String? origin;
  final bool pendingSign;
  final String? category;
  final String? note;
  final String? versionHash;
  const Expense({
    required this.id,
    required this.roomId,
    this.matrixEventId,
    required this.description,
    required this.amountCents,
    required this.currency,
    required this.paidBy,
    required this.splitsJson,
    required this.createdAt,
    required this.updatedAt,
    required this.deleted,
    this.sig,
    this.origin,
    required this.pendingSign,
    this.category,
    this.note,
    this.versionHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['room_id'] = Variable<String>(roomId);
    if (!nullToAbsent || matrixEventId != null) {
      map['matrix_event_id'] = Variable<String>(matrixEventId);
    }
    map['description'] = Variable<String>(description);
    map['amount_cents'] = Variable<int>(amountCents);
    map['currency'] = Variable<String>(currency);
    map['paid_by'] = Variable<String>(paidBy);
    map['splits_json'] = Variable<String>(splitsJson);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['deleted'] = Variable<bool>(deleted);
    if (!nullToAbsent || sig != null) {
      map['sig'] = Variable<String>(sig);
    }
    if (!nullToAbsent || origin != null) {
      map['origin'] = Variable<String>(origin);
    }
    map['pending_sign'] = Variable<bool>(pendingSign);
    if (!nullToAbsent || category != null) {
      map['category'] = Variable<String>(category);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || versionHash != null) {
      map['version_hash'] = Variable<String>(versionHash);
    }
    return map;
  }

  ExpensesCompanion toCompanion(bool nullToAbsent) {
    return ExpensesCompanion(
      id: Value(id),
      roomId: Value(roomId),
      matrixEventId: matrixEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(matrixEventId),
      description: Value(description),
      amountCents: Value(amountCents),
      currency: Value(currency),
      paidBy: Value(paidBy),
      splitsJson: Value(splitsJson),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      sig: sig == null && nullToAbsent ? const Value.absent() : Value(sig),
      origin: origin == null && nullToAbsent
          ? const Value.absent()
          : Value(origin),
      pendingSign: Value(pendingSign),
      category: category == null && nullToAbsent
          ? const Value.absent()
          : Value(category),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      versionHash: versionHash == null && nullToAbsent
          ? const Value.absent()
          : Value(versionHash),
    );
  }

  factory Expense.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Expense(
      id: serializer.fromJson<String>(json['id']),
      roomId: serializer.fromJson<String>(json['roomId']),
      matrixEventId: serializer.fromJson<String?>(json['matrixEventId']),
      description: serializer.fromJson<String>(json['description']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      currency: serializer.fromJson<String>(json['currency']),
      paidBy: serializer.fromJson<String>(json['paidBy']),
      splitsJson: serializer.fromJson<String>(json['splitsJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      sig: serializer.fromJson<String?>(json['sig']),
      origin: serializer.fromJson<String?>(json['origin']),
      pendingSign: serializer.fromJson<bool>(json['pendingSign']),
      category: serializer.fromJson<String?>(json['category']),
      note: serializer.fromJson<String?>(json['note']),
      versionHash: serializer.fromJson<String?>(json['versionHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'roomId': serializer.toJson<String>(roomId),
      'matrixEventId': serializer.toJson<String?>(matrixEventId),
      'description': serializer.toJson<String>(description),
      'amountCents': serializer.toJson<int>(amountCents),
      'currency': serializer.toJson<String>(currency),
      'paidBy': serializer.toJson<String>(paidBy),
      'splitsJson': serializer.toJson<String>(splitsJson),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deleted': serializer.toJson<bool>(deleted),
      'sig': serializer.toJson<String?>(sig),
      'origin': serializer.toJson<String?>(origin),
      'pendingSign': serializer.toJson<bool>(pendingSign),
      'category': serializer.toJson<String?>(category),
      'note': serializer.toJson<String?>(note),
      'versionHash': serializer.toJson<String?>(versionHash),
    };
  }

  Expense copyWith({
    String? id,
    String? roomId,
    Value<String?> matrixEventId = const Value.absent(),
    String? description,
    int? amountCents,
    String? currency,
    String? paidBy,
    String? splitsJson,
    int? createdAt,
    int? updatedAt,
    bool? deleted,
    Value<String?> sig = const Value.absent(),
    Value<String?> origin = const Value.absent(),
    bool? pendingSign,
    Value<String?> category = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<String?> versionHash = const Value.absent(),
  }) => Expense(
    id: id ?? this.id,
    roomId: roomId ?? this.roomId,
    matrixEventId: matrixEventId.present
        ? matrixEventId.value
        : this.matrixEventId,
    description: description ?? this.description,
    amountCents: amountCents ?? this.amountCents,
    currency: currency ?? this.currency,
    paidBy: paidBy ?? this.paidBy,
    splitsJson: splitsJson ?? this.splitsJson,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
    sig: sig.present ? sig.value : this.sig,
    origin: origin.present ? origin.value : this.origin,
    pendingSign: pendingSign ?? this.pendingSign,
    category: category.present ? category.value : this.category,
    note: note.present ? note.value : this.note,
    versionHash: versionHash.present ? versionHash.value : this.versionHash,
  );
  Expense copyWithCompanion(ExpensesCompanion data) {
    return Expense(
      id: data.id.present ? data.id.value : this.id,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      matrixEventId: data.matrixEventId.present
          ? data.matrixEventId.value
          : this.matrixEventId,
      description: data.description.present
          ? data.description.value
          : this.description,
      amountCents: data.amountCents.present
          ? data.amountCents.value
          : this.amountCents,
      currency: data.currency.present ? data.currency.value : this.currency,
      paidBy: data.paidBy.present ? data.paidBy.value : this.paidBy,
      splitsJson: data.splitsJson.present
          ? data.splitsJson.value
          : this.splitsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      sig: data.sig.present ? data.sig.value : this.sig,
      origin: data.origin.present ? data.origin.value : this.origin,
      pendingSign: data.pendingSign.present
          ? data.pendingSign.value
          : this.pendingSign,
      category: data.category.present ? data.category.value : this.category,
      note: data.note.present ? data.note.value : this.note,
      versionHash: data.versionHash.present
          ? data.versionHash.value
          : this.versionHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Expense(')
          ..write('id: $id, ')
          ..write('roomId: $roomId, ')
          ..write('matrixEventId: $matrixEventId, ')
          ..write('description: $description, ')
          ..write('amountCents: $amountCents, ')
          ..write('currency: $currency, ')
          ..write('paidBy: $paidBy, ')
          ..write('splitsJson: $splitsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('sig: $sig, ')
          ..write('origin: $origin, ')
          ..write('pendingSign: $pendingSign, ')
          ..write('category: $category, ')
          ..write('note: $note, ')
          ..write('versionHash: $versionHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    roomId,
    matrixEventId,
    description,
    amountCents,
    currency,
    paidBy,
    splitsJson,
    createdAt,
    updatedAt,
    deleted,
    sig,
    origin,
    pendingSign,
    category,
    note,
    versionHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Expense &&
          other.id == this.id &&
          other.roomId == this.roomId &&
          other.matrixEventId == this.matrixEventId &&
          other.description == this.description &&
          other.amountCents == this.amountCents &&
          other.currency == this.currency &&
          other.paidBy == this.paidBy &&
          other.splitsJson == this.splitsJson &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deleted == this.deleted &&
          other.sig == this.sig &&
          other.origin == this.origin &&
          other.pendingSign == this.pendingSign &&
          other.category == this.category &&
          other.note == this.note &&
          other.versionHash == this.versionHash);
}

class ExpensesCompanion extends UpdateCompanion<Expense> {
  final Value<String> id;
  final Value<String> roomId;
  final Value<String?> matrixEventId;
  final Value<String> description;
  final Value<int> amountCents;
  final Value<String> currency;
  final Value<String> paidBy;
  final Value<String> splitsJson;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<bool> deleted;
  final Value<String?> sig;
  final Value<String?> origin;
  final Value<bool> pendingSign;
  final Value<String?> category;
  final Value<String?> note;
  final Value<String?> versionHash;
  final Value<int> rowid;
  const ExpensesCompanion({
    this.id = const Value.absent(),
    this.roomId = const Value.absent(),
    this.matrixEventId = const Value.absent(),
    this.description = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.currency = const Value.absent(),
    this.paidBy = const Value.absent(),
    this.splitsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.sig = const Value.absent(),
    this.origin = const Value.absent(),
    this.pendingSign = const Value.absent(),
    this.category = const Value.absent(),
    this.note = const Value.absent(),
    this.versionHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExpensesCompanion.insert({
    required String id,
    required String roomId,
    this.matrixEventId = const Value.absent(),
    required String description,
    required int amountCents,
    required String currency,
    required String paidBy,
    required String splitsJson,
    required int createdAt,
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.sig = const Value.absent(),
    this.origin = const Value.absent(),
    this.pendingSign = const Value.absent(),
    this.category = const Value.absent(),
    this.note = const Value.absent(),
    this.versionHash = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       roomId = Value(roomId),
       description = Value(description),
       amountCents = Value(amountCents),
       currency = Value(currency),
       paidBy = Value(paidBy),
       splitsJson = Value(splitsJson),
       createdAt = Value(createdAt);
  static Insertable<Expense> custom({
    Expression<String>? id,
    Expression<String>? roomId,
    Expression<String>? matrixEventId,
    Expression<String>? description,
    Expression<int>? amountCents,
    Expression<String>? currency,
    Expression<String>? paidBy,
    Expression<String>? splitsJson,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<bool>? deleted,
    Expression<String>? sig,
    Expression<String>? origin,
    Expression<bool>? pendingSign,
    Expression<String>? category,
    Expression<String>? note,
    Expression<String>? versionHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (roomId != null) 'room_id': roomId,
      if (matrixEventId != null) 'matrix_event_id': matrixEventId,
      if (description != null) 'description': description,
      if (amountCents != null) 'amount_cents': amountCents,
      if (currency != null) 'currency': currency,
      if (paidBy != null) 'paid_by': paidBy,
      if (splitsJson != null) 'splits_json': splitsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deleted != null) 'deleted': deleted,
      if (sig != null) 'sig': sig,
      if (origin != null) 'origin': origin,
      if (pendingSign != null) 'pending_sign': pendingSign,
      if (category != null) 'category': category,
      if (note != null) 'note': note,
      if (versionHash != null) 'version_hash': versionHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExpensesCompanion copyWith({
    Value<String>? id,
    Value<String>? roomId,
    Value<String?>? matrixEventId,
    Value<String>? description,
    Value<int>? amountCents,
    Value<String>? currency,
    Value<String>? paidBy,
    Value<String>? splitsJson,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<bool>? deleted,
    Value<String?>? sig,
    Value<String?>? origin,
    Value<bool>? pendingSign,
    Value<String?>? category,
    Value<String?>? note,
    Value<String?>? versionHash,
    Value<int>? rowid,
  }) {
    return ExpensesCompanion(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      matrixEventId: matrixEventId ?? this.matrixEventId,
      description: description ?? this.description,
      amountCents: amountCents ?? this.amountCents,
      currency: currency ?? this.currency,
      paidBy: paidBy ?? this.paidBy,
      splitsJson: splitsJson ?? this.splitsJson,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      sig: sig ?? this.sig,
      origin: origin ?? this.origin,
      pendingSign: pendingSign ?? this.pendingSign,
      category: category ?? this.category,
      note: note ?? this.note,
      versionHash: versionHash ?? this.versionHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (matrixEventId.present) {
      map['matrix_event_id'] = Variable<String>(matrixEventId.value);
    }
    if (description.present) {
      map['description'] = Variable<String>(description.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (paidBy.present) {
      map['paid_by'] = Variable<String>(paidBy.value);
    }
    if (splitsJson.present) {
      map['splits_json'] = Variable<String>(splitsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (sig.present) {
      map['sig'] = Variable<String>(sig.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (pendingSign.present) {
      map['pending_sign'] = Variable<bool>(pendingSign.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (versionHash.present) {
      map['version_hash'] = Variable<String>(versionHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpensesCompanion(')
          ..write('id: $id, ')
          ..write('roomId: $roomId, ')
          ..write('matrixEventId: $matrixEventId, ')
          ..write('description: $description, ')
          ..write('amountCents: $amountCents, ')
          ..write('currency: $currency, ')
          ..write('paidBy: $paidBy, ')
          ..write('splitsJson: $splitsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('sig: $sig, ')
          ..write('origin: $origin, ')
          ..write('pendingSign: $pendingSign, ')
          ..write('category: $category, ')
          ..write('note: $note, ')
          ..write('versionHash: $versionHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettlementsTable extends Settlements
    with TableInfo<$SettlementsTable, Settlement> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettlementsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<String> roomId = GeneratedColumn<String>(
    'room_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _matrixEventIdMeta = const VerificationMeta(
    'matrixEventId',
  );
  @override
  late final GeneratedColumn<String> matrixEventId = GeneratedColumn<String>(
    'matrix_event_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountCentsMeta = const VerificationMeta(
    'amountCents',
  );
  @override
  late final GeneratedColumn<int> amountCents = GeneratedColumn<int>(
    'amount_cents',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fromUserMeta = const VerificationMeta(
    'fromUser',
  );
  @override
  late final GeneratedColumn<String> fromUser = GeneratedColumn<String>(
    'from_user',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toUserMeta = const VerificationMeta('toUser');
  @override
  late final GeneratedColumn<String> toUser = GeneratedColumn<String>(
    'to_user',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _deletedMeta = const VerificationMeta(
    'deleted',
  );
  @override
  late final GeneratedColumn<bool> deleted = GeneratedColumn<bool>(
    'deleted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("deleted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sigMeta = const VerificationMeta('sig');
  @override
  late final GeneratedColumn<String> sig = GeneratedColumn<String>(
    'sig',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _originMeta = const VerificationMeta('origin');
  @override
  late final GeneratedColumn<String> origin = GeneratedColumn<String>(
    'origin',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pendingSignMeta = const VerificationMeta(
    'pendingSign',
  );
  @override
  late final GeneratedColumn<bool> pendingSign = GeneratedColumn<bool>(
    'pending_sign',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pending_sign" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _versionHashMeta = const VerificationMeta(
    'versionHash',
  );
  @override
  late final GeneratedColumn<String> versionHash = GeneratedColumn<String>(
    'version_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    roomId,
    matrixEventId,
    amountCents,
    currency,
    fromUser,
    toUser,
    createdAt,
    updatedAt,
    deleted,
    sig,
    origin,
    pendingSign,
    versionHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settlements';
  @override
  VerificationContext validateIntegrity(
    Insertable<Settlement> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roomIdMeta);
    }
    if (data.containsKey('matrix_event_id')) {
      context.handle(
        _matrixEventIdMeta,
        matrixEventId.isAcceptableOrUnknown(
          data['matrix_event_id']!,
          _matrixEventIdMeta,
        ),
      );
    }
    if (data.containsKey('amount_cents')) {
      context.handle(
        _amountCentsMeta,
        amountCents.isAcceptableOrUnknown(
          data['amount_cents']!,
          _amountCentsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountCentsMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    } else if (isInserting) {
      context.missing(_currencyMeta);
    }
    if (data.containsKey('from_user')) {
      context.handle(
        _fromUserMeta,
        fromUser.isAcceptableOrUnknown(data['from_user']!, _fromUserMeta),
      );
    } else if (isInserting) {
      context.missing(_fromUserMeta);
    }
    if (data.containsKey('to_user')) {
      context.handle(
        _toUserMeta,
        toUser.isAcceptableOrUnknown(data['to_user']!, _toUserMeta),
      );
    } else if (isInserting) {
      context.missing(_toUserMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    if (data.containsKey('deleted')) {
      context.handle(
        _deletedMeta,
        deleted.isAcceptableOrUnknown(data['deleted']!, _deletedMeta),
      );
    }
    if (data.containsKey('sig')) {
      context.handle(
        _sigMeta,
        sig.isAcceptableOrUnknown(data['sig']!, _sigMeta),
      );
    }
    if (data.containsKey('origin')) {
      context.handle(
        _originMeta,
        origin.isAcceptableOrUnknown(data['origin']!, _originMeta),
      );
    }
    if (data.containsKey('pending_sign')) {
      context.handle(
        _pendingSignMeta,
        pendingSign.isAcceptableOrUnknown(
          data['pending_sign']!,
          _pendingSignMeta,
        ),
      );
    }
    if (data.containsKey('version_hash')) {
      context.handle(
        _versionHashMeta,
        versionHash.isAcceptableOrUnknown(
          data['version_hash']!,
          _versionHashMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Settlement map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Settlement(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}room_id'],
      )!,
      matrixEventId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}matrix_event_id'],
      ),
      amountCents: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_cents'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      fromUser: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_user'],
      )!,
      toUser: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_user'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      deleted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}deleted'],
      )!,
      sig: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sig'],
      ),
      origin: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}origin'],
      ),
      pendingSign: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pending_sign'],
      )!,
      versionHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_hash'],
      ),
    );
  }

  @override
  $SettlementsTable createAlias(String alias) {
    return $SettlementsTable(attachedDatabase, alias);
  }
}

class Settlement extends DataClass implements Insertable<Settlement> {
  final String id;
  final String roomId;
  final String? matrixEventId;
  final int amountCents;
  final String currency;
  final String fromUser;
  final String toUser;
  final int createdAt;
  final int updatedAt;
  final bool deleted;
  final String? sig;
  final String? origin;
  final bool pendingSign;
  final String? versionHash;
  const Settlement({
    required this.id,
    required this.roomId,
    this.matrixEventId,
    required this.amountCents,
    required this.currency,
    required this.fromUser,
    required this.toUser,
    required this.createdAt,
    required this.updatedAt,
    required this.deleted,
    this.sig,
    this.origin,
    required this.pendingSign,
    this.versionHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['room_id'] = Variable<String>(roomId);
    if (!nullToAbsent || matrixEventId != null) {
      map['matrix_event_id'] = Variable<String>(matrixEventId);
    }
    map['amount_cents'] = Variable<int>(amountCents);
    map['currency'] = Variable<String>(currency);
    map['from_user'] = Variable<String>(fromUser);
    map['to_user'] = Variable<String>(toUser);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    map['deleted'] = Variable<bool>(deleted);
    if (!nullToAbsent || sig != null) {
      map['sig'] = Variable<String>(sig);
    }
    if (!nullToAbsent || origin != null) {
      map['origin'] = Variable<String>(origin);
    }
    map['pending_sign'] = Variable<bool>(pendingSign);
    if (!nullToAbsent || versionHash != null) {
      map['version_hash'] = Variable<String>(versionHash);
    }
    return map;
  }

  SettlementsCompanion toCompanion(bool nullToAbsent) {
    return SettlementsCompanion(
      id: Value(id),
      roomId: Value(roomId),
      matrixEventId: matrixEventId == null && nullToAbsent
          ? const Value.absent()
          : Value(matrixEventId),
      amountCents: Value(amountCents),
      currency: Value(currency),
      fromUser: Value(fromUser),
      toUser: Value(toUser),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
      deleted: Value(deleted),
      sig: sig == null && nullToAbsent ? const Value.absent() : Value(sig),
      origin: origin == null && nullToAbsent
          ? const Value.absent()
          : Value(origin),
      pendingSign: Value(pendingSign),
      versionHash: versionHash == null && nullToAbsent
          ? const Value.absent()
          : Value(versionHash),
    );
  }

  factory Settlement.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Settlement(
      id: serializer.fromJson<String>(json['id']),
      roomId: serializer.fromJson<String>(json['roomId']),
      matrixEventId: serializer.fromJson<String?>(json['matrixEventId']),
      amountCents: serializer.fromJson<int>(json['amountCents']),
      currency: serializer.fromJson<String>(json['currency']),
      fromUser: serializer.fromJson<String>(json['fromUser']),
      toUser: serializer.fromJson<String>(json['toUser']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      deleted: serializer.fromJson<bool>(json['deleted']),
      sig: serializer.fromJson<String?>(json['sig']),
      origin: serializer.fromJson<String?>(json['origin']),
      pendingSign: serializer.fromJson<bool>(json['pendingSign']),
      versionHash: serializer.fromJson<String?>(json['versionHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'roomId': serializer.toJson<String>(roomId),
      'matrixEventId': serializer.toJson<String?>(matrixEventId),
      'amountCents': serializer.toJson<int>(amountCents),
      'currency': serializer.toJson<String>(currency),
      'fromUser': serializer.toJson<String>(fromUser),
      'toUser': serializer.toJson<String>(toUser),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'deleted': serializer.toJson<bool>(deleted),
      'sig': serializer.toJson<String?>(sig),
      'origin': serializer.toJson<String?>(origin),
      'pendingSign': serializer.toJson<bool>(pendingSign),
      'versionHash': serializer.toJson<String?>(versionHash),
    };
  }

  Settlement copyWith({
    String? id,
    String? roomId,
    Value<String?> matrixEventId = const Value.absent(),
    int? amountCents,
    String? currency,
    String? fromUser,
    String? toUser,
    int? createdAt,
    int? updatedAt,
    bool? deleted,
    Value<String?> sig = const Value.absent(),
    Value<String?> origin = const Value.absent(),
    bool? pendingSign,
    Value<String?> versionHash = const Value.absent(),
  }) => Settlement(
    id: id ?? this.id,
    roomId: roomId ?? this.roomId,
    matrixEventId: matrixEventId.present
        ? matrixEventId.value
        : this.matrixEventId,
    amountCents: amountCents ?? this.amountCents,
    currency: currency ?? this.currency,
    fromUser: fromUser ?? this.fromUser,
    toUser: toUser ?? this.toUser,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deleted: deleted ?? this.deleted,
    sig: sig.present ? sig.value : this.sig,
    origin: origin.present ? origin.value : this.origin,
    pendingSign: pendingSign ?? this.pendingSign,
    versionHash: versionHash.present ? versionHash.value : this.versionHash,
  );
  Settlement copyWithCompanion(SettlementsCompanion data) {
    return Settlement(
      id: data.id.present ? data.id.value : this.id,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      matrixEventId: data.matrixEventId.present
          ? data.matrixEventId.value
          : this.matrixEventId,
      amountCents: data.amountCents.present
          ? data.amountCents.value
          : this.amountCents,
      currency: data.currency.present ? data.currency.value : this.currency,
      fromUser: data.fromUser.present ? data.fromUser.value : this.fromUser,
      toUser: data.toUser.present ? data.toUser.value : this.toUser,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      deleted: data.deleted.present ? data.deleted.value : this.deleted,
      sig: data.sig.present ? data.sig.value : this.sig,
      origin: data.origin.present ? data.origin.value : this.origin,
      pendingSign: data.pendingSign.present
          ? data.pendingSign.value
          : this.pendingSign,
      versionHash: data.versionHash.present
          ? data.versionHash.value
          : this.versionHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Settlement(')
          ..write('id: $id, ')
          ..write('roomId: $roomId, ')
          ..write('matrixEventId: $matrixEventId, ')
          ..write('amountCents: $amountCents, ')
          ..write('currency: $currency, ')
          ..write('fromUser: $fromUser, ')
          ..write('toUser: $toUser, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('sig: $sig, ')
          ..write('origin: $origin, ')
          ..write('pendingSign: $pendingSign, ')
          ..write('versionHash: $versionHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    roomId,
    matrixEventId,
    amountCents,
    currency,
    fromUser,
    toUser,
    createdAt,
    updatedAt,
    deleted,
    sig,
    origin,
    pendingSign,
    versionHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Settlement &&
          other.id == this.id &&
          other.roomId == this.roomId &&
          other.matrixEventId == this.matrixEventId &&
          other.amountCents == this.amountCents &&
          other.currency == this.currency &&
          other.fromUser == this.fromUser &&
          other.toUser == this.toUser &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt &&
          other.deleted == this.deleted &&
          other.sig == this.sig &&
          other.origin == this.origin &&
          other.pendingSign == this.pendingSign &&
          other.versionHash == this.versionHash);
}

class SettlementsCompanion extends UpdateCompanion<Settlement> {
  final Value<String> id;
  final Value<String> roomId;
  final Value<String?> matrixEventId;
  final Value<int> amountCents;
  final Value<String> currency;
  final Value<String> fromUser;
  final Value<String> toUser;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<bool> deleted;
  final Value<String?> sig;
  final Value<String?> origin;
  final Value<bool> pendingSign;
  final Value<String?> versionHash;
  final Value<int> rowid;
  const SettlementsCompanion({
    this.id = const Value.absent(),
    this.roomId = const Value.absent(),
    this.matrixEventId = const Value.absent(),
    this.amountCents = const Value.absent(),
    this.currency = const Value.absent(),
    this.fromUser = const Value.absent(),
    this.toUser = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.sig = const Value.absent(),
    this.origin = const Value.absent(),
    this.pendingSign = const Value.absent(),
    this.versionHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettlementsCompanion.insert({
    required String id,
    required String roomId,
    this.matrixEventId = const Value.absent(),
    required int amountCents,
    required String currency,
    required String fromUser,
    required String toUser,
    required int createdAt,
    this.updatedAt = const Value.absent(),
    this.deleted = const Value.absent(),
    this.sig = const Value.absent(),
    this.origin = const Value.absent(),
    this.pendingSign = const Value.absent(),
    this.versionHash = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       roomId = Value(roomId),
       amountCents = Value(amountCents),
       currency = Value(currency),
       fromUser = Value(fromUser),
       toUser = Value(toUser),
       createdAt = Value(createdAt);
  static Insertable<Settlement> custom({
    Expression<String>? id,
    Expression<String>? roomId,
    Expression<String>? matrixEventId,
    Expression<int>? amountCents,
    Expression<String>? currency,
    Expression<String>? fromUser,
    Expression<String>? toUser,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<bool>? deleted,
    Expression<String>? sig,
    Expression<String>? origin,
    Expression<bool>? pendingSign,
    Expression<String>? versionHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (roomId != null) 'room_id': roomId,
      if (matrixEventId != null) 'matrix_event_id': matrixEventId,
      if (amountCents != null) 'amount_cents': amountCents,
      if (currency != null) 'currency': currency,
      if (fromUser != null) 'from_user': fromUser,
      if (toUser != null) 'to_user': toUser,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (deleted != null) 'deleted': deleted,
      if (sig != null) 'sig': sig,
      if (origin != null) 'origin': origin,
      if (pendingSign != null) 'pending_sign': pendingSign,
      if (versionHash != null) 'version_hash': versionHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettlementsCompanion copyWith({
    Value<String>? id,
    Value<String>? roomId,
    Value<String?>? matrixEventId,
    Value<int>? amountCents,
    Value<String>? currency,
    Value<String>? fromUser,
    Value<String>? toUser,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<bool>? deleted,
    Value<String?>? sig,
    Value<String?>? origin,
    Value<bool>? pendingSign,
    Value<String?>? versionHash,
    Value<int>? rowid,
  }) {
    return SettlementsCompanion(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      matrixEventId: matrixEventId ?? this.matrixEventId,
      amountCents: amountCents ?? this.amountCents,
      currency: currency ?? this.currency,
      fromUser: fromUser ?? this.fromUser,
      toUser: toUser ?? this.toUser,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      deleted: deleted ?? this.deleted,
      sig: sig ?? this.sig,
      origin: origin ?? this.origin,
      pendingSign: pendingSign ?? this.pendingSign,
      versionHash: versionHash ?? this.versionHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<String>(roomId.value);
    }
    if (matrixEventId.present) {
      map['matrix_event_id'] = Variable<String>(matrixEventId.value);
    }
    if (amountCents.present) {
      map['amount_cents'] = Variable<int>(amountCents.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (fromUser.present) {
      map['from_user'] = Variable<String>(fromUser.value);
    }
    if (toUser.present) {
      map['to_user'] = Variable<String>(toUser.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (deleted.present) {
      map['deleted'] = Variable<bool>(deleted.value);
    }
    if (sig.present) {
      map['sig'] = Variable<String>(sig.value);
    }
    if (origin.present) {
      map['origin'] = Variable<String>(origin.value);
    }
    if (pendingSign.present) {
      map['pending_sign'] = Variable<bool>(pendingSign.value);
    }
    if (versionHash.present) {
      map['version_hash'] = Variable<String>(versionHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettlementsCompanion(')
          ..write('id: $id, ')
          ..write('roomId: $roomId, ')
          ..write('matrixEventId: $matrixEventId, ')
          ..write('amountCents: $amountCents, ')
          ..write('currency: $currency, ')
          ..write('fromUser: $fromUser, ')
          ..write('toUser: $toUser, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('deleted: $deleted, ')
          ..write('sig: $sig, ')
          ..write('origin: $origin, ')
          ..write('pendingSign: $pendingSign, ')
          ..write('versionHash: $versionHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MembersTable extends Members with TableInfo<$MembersTable, Member> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MembersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _matrixIdMeta = const VerificationMeta(
    'matrixId',
  );
  @override
  late final GeneratedColumn<String> matrixId = GeneratedColumn<String>(
    'matrix_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sigMeta = const VerificationMeta('sig');
  @override
  late final GeneratedColumn<String> sig = GeneratedColumn<String>(
    'sig',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pendingSignMeta = const VerificationMeta(
    'pendingSign',
  );
  @override
  late final GeneratedColumn<bool> pendingSign = GeneratedColumn<bool>(
    'pending_sign',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("pending_sign" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    userId,
    displayName,
    matrixId,
    status,
    updatedAt,
    sig,
    pendingSign,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'members';
  @override
  VerificationContext validateIntegrity(
    Insertable<Member> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    }
    if (data.containsKey('matrix_id')) {
      context.handle(
        _matrixIdMeta,
        matrixId.isAcceptableOrUnknown(data['matrix_id']!, _matrixIdMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('sig')) {
      context.handle(
        _sigMeta,
        sig.isAcceptableOrUnknown(data['sig']!, _sigMeta),
      );
    }
    if (data.containsKey('pending_sign')) {
      context.handle(
        _pendingSignMeta,
        pendingSign.isAcceptableOrUnknown(
          data['pending_sign']!,
          _pendingSignMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, userId};
  @override
  Member map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Member(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      matrixId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}matrix_id'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      sig: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sig'],
      ),
      pendingSign: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}pending_sign'],
      )!,
    );
  }

  @override
  $MembersTable createAlias(String alias) {
    return $MembersTable(attachedDatabase, alias);
  }
}

class Member extends DataClass implements Insertable<Member> {
  final String groupId;
  final String userId;
  final String displayName;
  final String? matrixId;
  final String status;
  final int updatedAt;
  final String? sig;
  final bool pendingSign;
  const Member({
    required this.groupId,
    required this.userId,
    required this.displayName,
    this.matrixId,
    required this.status,
    required this.updatedAt,
    this.sig,
    required this.pendingSign,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['user_id'] = Variable<String>(userId);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || matrixId != null) {
      map['matrix_id'] = Variable<String>(matrixId);
    }
    map['status'] = Variable<String>(status);
    map['updated_at'] = Variable<int>(updatedAt);
    if (!nullToAbsent || sig != null) {
      map['sig'] = Variable<String>(sig);
    }
    map['pending_sign'] = Variable<bool>(pendingSign);
    return map;
  }

  MembersCompanion toCompanion(bool nullToAbsent) {
    return MembersCompanion(
      groupId: Value(groupId),
      userId: Value(userId),
      displayName: Value(displayName),
      matrixId: matrixId == null && nullToAbsent
          ? const Value.absent()
          : Value(matrixId),
      status: Value(status),
      updatedAt: Value(updatedAt),
      sig: sig == null && nullToAbsent ? const Value.absent() : Value(sig),
      pendingSign: Value(pendingSign),
    );
  }

  factory Member.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Member(
      groupId: serializer.fromJson<String>(json['groupId']),
      userId: serializer.fromJson<String>(json['userId']),
      displayName: serializer.fromJson<String>(json['displayName']),
      matrixId: serializer.fromJson<String?>(json['matrixId']),
      status: serializer.fromJson<String>(json['status']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      sig: serializer.fromJson<String?>(json['sig']),
      pendingSign: serializer.fromJson<bool>(json['pendingSign']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'userId': serializer.toJson<String>(userId),
      'displayName': serializer.toJson<String>(displayName),
      'matrixId': serializer.toJson<String?>(matrixId),
      'status': serializer.toJson<String>(status),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'sig': serializer.toJson<String?>(sig),
      'pendingSign': serializer.toJson<bool>(pendingSign),
    };
  }

  Member copyWith({
    String? groupId,
    String? userId,
    String? displayName,
    Value<String?> matrixId = const Value.absent(),
    String? status,
    int? updatedAt,
    Value<String?> sig = const Value.absent(),
    bool? pendingSign,
  }) => Member(
    groupId: groupId ?? this.groupId,
    userId: userId ?? this.userId,
    displayName: displayName ?? this.displayName,
    matrixId: matrixId.present ? matrixId.value : this.matrixId,
    status: status ?? this.status,
    updatedAt: updatedAt ?? this.updatedAt,
    sig: sig.present ? sig.value : this.sig,
    pendingSign: pendingSign ?? this.pendingSign,
  );
  Member copyWithCompanion(MembersCompanion data) {
    return Member(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      userId: data.userId.present ? data.userId.value : this.userId,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      matrixId: data.matrixId.present ? data.matrixId.value : this.matrixId,
      status: data.status.present ? data.status.value : this.status,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      sig: data.sig.present ? data.sig.value : this.sig,
      pendingSign: data.pendingSign.present
          ? data.pendingSign.value
          : this.pendingSign,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Member(')
          ..write('groupId: $groupId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('matrixId: $matrixId, ')
          ..write('status: $status, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sig: $sig, ')
          ..write('pendingSign: $pendingSign')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    userId,
    displayName,
    matrixId,
    status,
    updatedAt,
    sig,
    pendingSign,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Member &&
          other.groupId == this.groupId &&
          other.userId == this.userId &&
          other.displayName == this.displayName &&
          other.matrixId == this.matrixId &&
          other.status == this.status &&
          other.updatedAt == this.updatedAt &&
          other.sig == this.sig &&
          other.pendingSign == this.pendingSign);
}

class MembersCompanion extends UpdateCompanion<Member> {
  final Value<String> groupId;
  final Value<String> userId;
  final Value<String> displayName;
  final Value<String?> matrixId;
  final Value<String> status;
  final Value<int> updatedAt;
  final Value<String?> sig;
  final Value<bool> pendingSign;
  final Value<int> rowid;
  const MembersCompanion({
    this.groupId = const Value.absent(),
    this.userId = const Value.absent(),
    this.displayName = const Value.absent(),
    this.matrixId = const Value.absent(),
    this.status = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sig = const Value.absent(),
    this.pendingSign = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MembersCompanion.insert({
    required String groupId,
    required String userId,
    this.displayName = const Value.absent(),
    this.matrixId = const Value.absent(),
    this.status = const Value.absent(),
    required int updatedAt,
    this.sig = const Value.absent(),
    this.pendingSign = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       userId = Value(userId),
       updatedAt = Value(updatedAt);
  static Insertable<Member> custom({
    Expression<String>? groupId,
    Expression<String>? userId,
    Expression<String>? displayName,
    Expression<String>? matrixId,
    Expression<String>? status,
    Expression<int>? updatedAt,
    Expression<String>? sig,
    Expression<bool>? pendingSign,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (userId != null) 'user_id': userId,
      if (displayName != null) 'display_name': displayName,
      if (matrixId != null) 'matrix_id': matrixId,
      if (status != null) 'status': status,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (sig != null) 'sig': sig,
      if (pendingSign != null) 'pending_sign': pendingSign,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MembersCompanion copyWith({
    Value<String>? groupId,
    Value<String>? userId,
    Value<String>? displayName,
    Value<String?>? matrixId,
    Value<String>? status,
    Value<int>? updatedAt,
    Value<String?>? sig,
    Value<bool>? pendingSign,
    Value<int>? rowid,
  }) {
    return MembersCompanion(
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      matrixId: matrixId ?? this.matrixId,
      status: status ?? this.status,
      updatedAt: updatedAt ?? this.updatedAt,
      sig: sig ?? this.sig,
      pendingSign: pendingSign ?? this.pendingSign,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (matrixId.present) {
      map['matrix_id'] = Variable<String>(matrixId.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (sig.present) {
      map['sig'] = Variable<String>(sig.value);
    }
    if (pendingSign.present) {
      map['pending_sign'] = Variable<bool>(pendingSign.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MembersCompanion(')
          ..write('groupId: $groupId, ')
          ..write('userId: $userId, ')
          ..write('displayName: $displayName, ')
          ..write('matrixId: $matrixId, ')
          ..write('status: $status, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('sig: $sig, ')
          ..write('pendingSign: $pendingSign, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PeerSyncStatesTable extends PeerSyncStates
    with TableInfo<$PeerSyncStatesTable, PeerSyncState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PeerSyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastInSyncAtMeta = const VerificationMeta(
    'lastInSyncAt',
  );
  @override
  late final GeneratedColumn<int> lastInSyncAt = GeneratedColumn<int>(
    'last_in_sync_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastDigestSentAtMeta = const VerificationMeta(
    'lastDigestSentAt',
  );
  @override
  late final GeneratedColumn<int> lastDigestSentAt = GeneratedColumn<int>(
    'last_digest_sent_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    userId,
    lastInSyncAt,
    lastDigestSentAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'peer_sync_states';
  @override
  VerificationContext validateIntegrity(
    Insertable<PeerSyncState> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('last_in_sync_at')) {
      context.handle(
        _lastInSyncAtMeta,
        lastInSyncAt.isAcceptableOrUnknown(
          data['last_in_sync_at']!,
          _lastInSyncAtMeta,
        ),
      );
    }
    if (data.containsKey('last_digest_sent_at')) {
      context.handle(
        _lastDigestSentAtMeta,
        lastDigestSentAt.isAcceptableOrUnknown(
          data['last_digest_sent_at']!,
          _lastDigestSentAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, userId};
  @override
  PeerSyncState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PeerSyncState(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      lastInSyncAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_in_sync_at'],
      )!,
      lastDigestSentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_digest_sent_at'],
      )!,
    );
  }

  @override
  $PeerSyncStatesTable createAlias(String alias) {
    return $PeerSyncStatesTable(attachedDatabase, alias);
  }
}

class PeerSyncState extends DataClass implements Insertable<PeerSyncState> {
  final String groupId;
  final String userId;
  final int lastInSyncAt;
  final int lastDigestSentAt;
  const PeerSyncState({
    required this.groupId,
    required this.userId,
    required this.lastInSyncAt,
    required this.lastDigestSentAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['user_id'] = Variable<String>(userId);
    map['last_in_sync_at'] = Variable<int>(lastInSyncAt);
    map['last_digest_sent_at'] = Variable<int>(lastDigestSentAt);
    return map;
  }

  PeerSyncStatesCompanion toCompanion(bool nullToAbsent) {
    return PeerSyncStatesCompanion(
      groupId: Value(groupId),
      userId: Value(userId),
      lastInSyncAt: Value(lastInSyncAt),
      lastDigestSentAt: Value(lastDigestSentAt),
    );
  }

  factory PeerSyncState.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PeerSyncState(
      groupId: serializer.fromJson<String>(json['groupId']),
      userId: serializer.fromJson<String>(json['userId']),
      lastInSyncAt: serializer.fromJson<int>(json['lastInSyncAt']),
      lastDigestSentAt: serializer.fromJson<int>(json['lastDigestSentAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'userId': serializer.toJson<String>(userId),
      'lastInSyncAt': serializer.toJson<int>(lastInSyncAt),
      'lastDigestSentAt': serializer.toJson<int>(lastDigestSentAt),
    };
  }

  PeerSyncState copyWith({
    String? groupId,
    String? userId,
    int? lastInSyncAt,
    int? lastDigestSentAt,
  }) => PeerSyncState(
    groupId: groupId ?? this.groupId,
    userId: userId ?? this.userId,
    lastInSyncAt: lastInSyncAt ?? this.lastInSyncAt,
    lastDigestSentAt: lastDigestSentAt ?? this.lastDigestSentAt,
  );
  PeerSyncState copyWithCompanion(PeerSyncStatesCompanion data) {
    return PeerSyncState(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      userId: data.userId.present ? data.userId.value : this.userId,
      lastInSyncAt: data.lastInSyncAt.present
          ? data.lastInSyncAt.value
          : this.lastInSyncAt,
      lastDigestSentAt: data.lastDigestSentAt.present
          ? data.lastDigestSentAt.value
          : this.lastDigestSentAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PeerSyncState(')
          ..write('groupId: $groupId, ')
          ..write('userId: $userId, ')
          ..write('lastInSyncAt: $lastInSyncAt, ')
          ..write('lastDigestSentAt: $lastDigestSentAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(groupId, userId, lastInSyncAt, lastDigestSentAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PeerSyncState &&
          other.groupId == this.groupId &&
          other.userId == this.userId &&
          other.lastInSyncAt == this.lastInSyncAt &&
          other.lastDigestSentAt == this.lastDigestSentAt);
}

class PeerSyncStatesCompanion extends UpdateCompanion<PeerSyncState> {
  final Value<String> groupId;
  final Value<String> userId;
  final Value<int> lastInSyncAt;
  final Value<int> lastDigestSentAt;
  final Value<int> rowid;
  const PeerSyncStatesCompanion({
    this.groupId = const Value.absent(),
    this.userId = const Value.absent(),
    this.lastInSyncAt = const Value.absent(),
    this.lastDigestSentAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PeerSyncStatesCompanion.insert({
    required String groupId,
    required String userId,
    this.lastInSyncAt = const Value.absent(),
    this.lastDigestSentAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       userId = Value(userId);
  static Insertable<PeerSyncState> custom({
    Expression<String>? groupId,
    Expression<String>? userId,
    Expression<int>? lastInSyncAt,
    Expression<int>? lastDigestSentAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (userId != null) 'user_id': userId,
      if (lastInSyncAt != null) 'last_in_sync_at': lastInSyncAt,
      if (lastDigestSentAt != null) 'last_digest_sent_at': lastDigestSentAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PeerSyncStatesCompanion copyWith({
    Value<String>? groupId,
    Value<String>? userId,
    Value<int>? lastInSyncAt,
    Value<int>? lastDigestSentAt,
    Value<int>? rowid,
  }) {
    return PeerSyncStatesCompanion(
      groupId: groupId ?? this.groupId,
      userId: userId ?? this.userId,
      lastInSyncAt: lastInSyncAt ?? this.lastInSyncAt,
      lastDigestSentAt: lastDigestSentAt ?? this.lastDigestSentAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lastInSyncAt.present) {
      map['last_in_sync_at'] = Variable<int>(lastInSyncAt.value);
    }
    if (lastDigestSentAt.present) {
      map['last_digest_sent_at'] = Variable<int>(lastDigestSentAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PeerSyncStatesCompanion(')
          ..write('groupId: $groupId, ')
          ..write('userId: $userId, ')
          ..write('lastInSyncAt: $lastInSyncAt, ')
          ..write('lastDigestSentAt: $lastDigestSentAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSetting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSetting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSetting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSetting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSetting extends DataClass implements Insertable<AppSetting> {
  final String key;
  final String value;
  const AppSetting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), value: Value(value));
  }

  factory AppSetting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSetting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  AppSetting copyWith({String? key, String? value}) =>
      AppSetting(key: key ?? this.key, value: value ?? this.value);
  AppSetting copyWithCompanion(AppSettingsCompanion data) {
    return AppSetting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSetting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSetting &&
          other.key == this.key &&
          other.value == this.value);
}

class AppSettingsCompanion extends UpdateCompanion<AppSetting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<AppSetting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $KnownDeviceKeysTable extends KnownDeviceKeys
    with TableInfo<$KnownDeviceKeysTable, KnownDeviceKey> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $KnownDeviceKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
    'user_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ed25519KeyMeta = const VerificationMeta(
    'ed25519Key',
  );
  @override
  late final GeneratedColumn<String> ed25519Key = GeneratedColumn<String>(
    'ed25519_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attestedByMeta = const VerificationMeta(
    'attestedBy',
  );
  @override
  late final GeneratedColumn<String> attestedBy = GeneratedColumn<String>(
    'attested_by',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstSeenAtMeta = const VerificationMeta(
    'firstSeenAt',
  );
  @override
  late final GeneratedColumn<int> firstSeenAt = GeneratedColumn<int>(
    'first_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _attestedGroupMeta = const VerificationMeta(
    'attestedGroup',
  );
  @override
  late final GeneratedColumn<String> attestedGroup = GeneratedColumn<String>(
    'attested_group',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    userId,
    deviceId,
    ed25519Key,
    source,
    attestedBy,
    firstSeenAt,
    attestedGroup,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'known_device_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<KnownDeviceKey> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(
        _userIdMeta,
        userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta),
      );
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('ed25519_key')) {
      context.handle(
        _ed25519KeyMeta,
        ed25519Key.isAcceptableOrUnknown(data['ed25519_key']!, _ed25519KeyMeta),
      );
    } else if (isInserting) {
      context.missing(_ed25519KeyMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('attested_by')) {
      context.handle(
        _attestedByMeta,
        attestedBy.isAcceptableOrUnknown(data['attested_by']!, _attestedByMeta),
      );
    }
    if (data.containsKey('first_seen_at')) {
      context.handle(
        _firstSeenAtMeta,
        firstSeenAt.isAcceptableOrUnknown(
          data['first_seen_at']!,
          _firstSeenAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstSeenAtMeta);
    }
    if (data.containsKey('attested_group')) {
      context.handle(
        _attestedGroupMeta,
        attestedGroup.isAcceptableOrUnknown(
          data['attested_group']!,
          _attestedGroupMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    userId,
    deviceId,
    ed25519Key,
    attestedGroup,
  };
  @override
  KnownDeviceKey map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return KnownDeviceKey(
      userId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}user_id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      ed25519Key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ed25519_key'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      attestedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attested_by'],
      ),
      firstSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_seen_at'],
      )!,
      attestedGroup: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}attested_group'],
      )!,
    );
  }

  @override
  $KnownDeviceKeysTable createAlias(String alias) {
    return $KnownDeviceKeysTable(attachedDatabase, alias);
  }
}

class KnownDeviceKey extends DataClass implements Insertable<KnownDeviceKey> {
  final String userId;
  final String deviceId;
  final String ed25519Key;
  final String source;
  final String? attestedBy;
  final int firstSeenAt;
  final String attestedGroup;
  const KnownDeviceKey({
    required this.userId,
    required this.deviceId,
    required this.ed25519Key,
    required this.source,
    this.attestedBy,
    required this.firstSeenAt,
    required this.attestedGroup,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['device_id'] = Variable<String>(deviceId);
    map['ed25519_key'] = Variable<String>(ed25519Key);
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || attestedBy != null) {
      map['attested_by'] = Variable<String>(attestedBy);
    }
    map['first_seen_at'] = Variable<int>(firstSeenAt);
    map['attested_group'] = Variable<String>(attestedGroup);
    return map;
  }

  KnownDeviceKeysCompanion toCompanion(bool nullToAbsent) {
    return KnownDeviceKeysCompanion(
      userId: Value(userId),
      deviceId: Value(deviceId),
      ed25519Key: Value(ed25519Key),
      source: Value(source),
      attestedBy: attestedBy == null && nullToAbsent
          ? const Value.absent()
          : Value(attestedBy),
      firstSeenAt: Value(firstSeenAt),
      attestedGroup: Value(attestedGroup),
    );
  }

  factory KnownDeviceKey.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return KnownDeviceKey(
      userId: serializer.fromJson<String>(json['userId']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      ed25519Key: serializer.fromJson<String>(json['ed25519Key']),
      source: serializer.fromJson<String>(json['source']),
      attestedBy: serializer.fromJson<String?>(json['attestedBy']),
      firstSeenAt: serializer.fromJson<int>(json['firstSeenAt']),
      attestedGroup: serializer.fromJson<String>(json['attestedGroup']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'deviceId': serializer.toJson<String>(deviceId),
      'ed25519Key': serializer.toJson<String>(ed25519Key),
      'source': serializer.toJson<String>(source),
      'attestedBy': serializer.toJson<String?>(attestedBy),
      'firstSeenAt': serializer.toJson<int>(firstSeenAt),
      'attestedGroup': serializer.toJson<String>(attestedGroup),
    };
  }

  KnownDeviceKey copyWith({
    String? userId,
    String? deviceId,
    String? ed25519Key,
    String? source,
    Value<String?> attestedBy = const Value.absent(),
    int? firstSeenAt,
    String? attestedGroup,
  }) => KnownDeviceKey(
    userId: userId ?? this.userId,
    deviceId: deviceId ?? this.deviceId,
    ed25519Key: ed25519Key ?? this.ed25519Key,
    source: source ?? this.source,
    attestedBy: attestedBy.present ? attestedBy.value : this.attestedBy,
    firstSeenAt: firstSeenAt ?? this.firstSeenAt,
    attestedGroup: attestedGroup ?? this.attestedGroup,
  );
  KnownDeviceKey copyWithCompanion(KnownDeviceKeysCompanion data) {
    return KnownDeviceKey(
      userId: data.userId.present ? data.userId.value : this.userId,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      ed25519Key: data.ed25519Key.present
          ? data.ed25519Key.value
          : this.ed25519Key,
      source: data.source.present ? data.source.value : this.source,
      attestedBy: data.attestedBy.present
          ? data.attestedBy.value
          : this.attestedBy,
      firstSeenAt: data.firstSeenAt.present
          ? data.firstSeenAt.value
          : this.firstSeenAt,
      attestedGroup: data.attestedGroup.present
          ? data.attestedGroup.value
          : this.attestedGroup,
    );
  }

  @override
  String toString() {
    return (StringBuffer('KnownDeviceKey(')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId, ')
          ..write('ed25519Key: $ed25519Key, ')
          ..write('source: $source, ')
          ..write('attestedBy: $attestedBy, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('attestedGroup: $attestedGroup')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    userId,
    deviceId,
    ed25519Key,
    source,
    attestedBy,
    firstSeenAt,
    attestedGroup,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is KnownDeviceKey &&
          other.userId == this.userId &&
          other.deviceId == this.deviceId &&
          other.ed25519Key == this.ed25519Key &&
          other.source == this.source &&
          other.attestedBy == this.attestedBy &&
          other.firstSeenAt == this.firstSeenAt &&
          other.attestedGroup == this.attestedGroup);
}

class KnownDeviceKeysCompanion extends UpdateCompanion<KnownDeviceKey> {
  final Value<String> userId;
  final Value<String> deviceId;
  final Value<String> ed25519Key;
  final Value<String> source;
  final Value<String?> attestedBy;
  final Value<int> firstSeenAt;
  final Value<String> attestedGroup;
  final Value<int> rowid;
  const KnownDeviceKeysCompanion({
    this.userId = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.ed25519Key = const Value.absent(),
    this.source = const Value.absent(),
    this.attestedBy = const Value.absent(),
    this.firstSeenAt = const Value.absent(),
    this.attestedGroup = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  KnownDeviceKeysCompanion.insert({
    required String userId,
    required String deviceId,
    required String ed25519Key,
    required String source,
    this.attestedBy = const Value.absent(),
    required int firstSeenAt,
    this.attestedGroup = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : userId = Value(userId),
       deviceId = Value(deviceId),
       ed25519Key = Value(ed25519Key),
       source = Value(source),
       firstSeenAt = Value(firstSeenAt);
  static Insertable<KnownDeviceKey> custom({
    Expression<String>? userId,
    Expression<String>? deviceId,
    Expression<String>? ed25519Key,
    Expression<String>? source,
    Expression<String>? attestedBy,
    Expression<int>? firstSeenAt,
    Expression<String>? attestedGroup,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (deviceId != null) 'device_id': deviceId,
      if (ed25519Key != null) 'ed25519_key': ed25519Key,
      if (source != null) 'source': source,
      if (attestedBy != null) 'attested_by': attestedBy,
      if (firstSeenAt != null) 'first_seen_at': firstSeenAt,
      if (attestedGroup != null) 'attested_group': attestedGroup,
      if (rowid != null) 'rowid': rowid,
    });
  }

  KnownDeviceKeysCompanion copyWith({
    Value<String>? userId,
    Value<String>? deviceId,
    Value<String>? ed25519Key,
    Value<String>? source,
    Value<String?>? attestedBy,
    Value<int>? firstSeenAt,
    Value<String>? attestedGroup,
    Value<int>? rowid,
  }) {
    return KnownDeviceKeysCompanion(
      userId: userId ?? this.userId,
      deviceId: deviceId ?? this.deviceId,
      ed25519Key: ed25519Key ?? this.ed25519Key,
      source: source ?? this.source,
      attestedBy: attestedBy ?? this.attestedBy,
      firstSeenAt: firstSeenAt ?? this.firstSeenAt,
      attestedGroup: attestedGroup ?? this.attestedGroup,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (ed25519Key.present) {
      map['ed25519_key'] = Variable<String>(ed25519Key.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (attestedBy.present) {
      map['attested_by'] = Variable<String>(attestedBy.value);
    }
    if (firstSeenAt.present) {
      map['first_seen_at'] = Variable<int>(firstSeenAt.value);
    }
    if (attestedGroup.present) {
      map['attested_group'] = Variable<String>(attestedGroup.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('KnownDeviceKeysCompanion(')
          ..write('userId: $userId, ')
          ..write('deviceId: $deviceId, ')
          ..write('ed25519Key: $ed25519Key, ')
          ..write('source: $source, ')
          ..write('attestedBy: $attestedBy, ')
          ..write('firstSeenAt: $firstSeenAt, ')
          ..write('attestedGroup: $attestedGroup, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RejectedVersionsTable extends RejectedVersions
    with TableInfo<$RejectedVersionsTable, RejectedVersion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RejectedVersionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _groupIdMeta = const VerificationMeta(
    'groupId',
  );
  @override
  late final GeneratedColumn<String> groupId = GeneratedColumn<String>(
    'group_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordIdMeta = const VerificationMeta(
    'recordId',
  );
  @override
  late final GeneratedColumn<String> recordId = GeneratedColumn<String>(
    'record_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _relayedByMeta = const VerificationMeta(
    'relayedBy',
  );
  @override
  late final GeneratedColumn<String> relayedBy = GeneratedColumn<String>(
    'relayed_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _claimedSignerMeta = const VerificationMeta(
    'claimedSigner',
  );
  @override
  late final GeneratedColumn<String> claimedSigner = GeneratedColumn<String>(
    'claimed_signer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rejectedAtMeta = const VerificationMeta(
    'rejectedAt',
  );
  @override
  late final GeneratedColumn<int> rejectedAt = GeneratedColumn<int>(
    'rejected_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionHashMeta = const VerificationMeta(
    'versionHash',
  );
  @override
  late final GeneratedColumn<String> versionHash = GeneratedColumn<String>(
    'version_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    kind,
    recordId,
    updatedAt,
    reason,
    relayedBy,
    claimedSigner,
    rejectedAt,
    versionHash,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rejected_versions';
  @override
  VerificationContext validateIntegrity(
    Insertable<RejectedVersion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('group_id')) {
      context.handle(
        _groupIdMeta,
        groupId.isAcceptableOrUnknown(data['group_id']!, _groupIdMeta),
      );
    } else if (isInserting) {
      context.missing(_groupIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('record_id')) {
      context.handle(
        _recordIdMeta,
        recordId.isAcceptableOrUnknown(data['record_id']!, _recordIdMeta),
      );
    } else if (isInserting) {
      context.missing(_recordIdMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('relayed_by')) {
      context.handle(
        _relayedByMeta,
        relayedBy.isAcceptableOrUnknown(data['relayed_by']!, _relayedByMeta),
      );
    } else if (isInserting) {
      context.missing(_relayedByMeta);
    }
    if (data.containsKey('claimed_signer')) {
      context.handle(
        _claimedSignerMeta,
        claimedSigner.isAcceptableOrUnknown(
          data['claimed_signer']!,
          _claimedSignerMeta,
        ),
      );
    }
    if (data.containsKey('rejected_at')) {
      context.handle(
        _rejectedAtMeta,
        rejectedAt.isAcceptableOrUnknown(data['rejected_at']!, _rejectedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_rejectedAtMeta);
    }
    if (data.containsKey('version_hash')) {
      context.handle(
        _versionHashMeta,
        versionHash.isAcceptableOrUnknown(
          data['version_hash']!,
          _versionHashMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {
    groupId,
    kind,
    recordId,
    updatedAt,
    versionHash,
  };
  @override
  RejectedVersion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RejectedVersion(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      recordId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}record_id'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      relayedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}relayed_by'],
      )!,
      claimedSigner: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}claimed_signer'],
      ),
      rejectedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rejected_at'],
      )!,
      versionHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_hash'],
      )!,
    );
  }

  @override
  $RejectedVersionsTable createAlias(String alias) {
    return $RejectedVersionsTable(attachedDatabase, alias);
  }
}

class RejectedVersion extends DataClass implements Insertable<RejectedVersion> {
  final String groupId;
  final String kind;
  final String recordId;
  final int updatedAt;
  final String reason;
  final String relayedBy;
  final String? claimedSigner;
  final int rejectedAt;

  /// The G27 content hash of the refused version ('' = unknown: a refusal
  /// recorded before schema v9 — matches any version at [updatedAt]).
  final String versionHash;
  const RejectedVersion({
    required this.groupId,
    required this.kind,
    required this.recordId,
    required this.updatedAt,
    required this.reason,
    required this.relayedBy,
    this.claimedSigner,
    required this.rejectedAt,
    required this.versionHash,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['kind'] = Variable<String>(kind);
    map['record_id'] = Variable<String>(recordId);
    map['updated_at'] = Variable<int>(updatedAt);
    map['reason'] = Variable<String>(reason);
    map['relayed_by'] = Variable<String>(relayedBy);
    if (!nullToAbsent || claimedSigner != null) {
      map['claimed_signer'] = Variable<String>(claimedSigner);
    }
    map['rejected_at'] = Variable<int>(rejectedAt);
    map['version_hash'] = Variable<String>(versionHash);
    return map;
  }

  RejectedVersionsCompanion toCompanion(bool nullToAbsent) {
    return RejectedVersionsCompanion(
      groupId: Value(groupId),
      kind: Value(kind),
      recordId: Value(recordId),
      updatedAt: Value(updatedAt),
      reason: Value(reason),
      relayedBy: Value(relayedBy),
      claimedSigner: claimedSigner == null && nullToAbsent
          ? const Value.absent()
          : Value(claimedSigner),
      rejectedAt: Value(rejectedAt),
      versionHash: Value(versionHash),
    );
  }

  factory RejectedVersion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RejectedVersion(
      groupId: serializer.fromJson<String>(json['groupId']),
      kind: serializer.fromJson<String>(json['kind']),
      recordId: serializer.fromJson<String>(json['recordId']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      reason: serializer.fromJson<String>(json['reason']),
      relayedBy: serializer.fromJson<String>(json['relayedBy']),
      claimedSigner: serializer.fromJson<String?>(json['claimedSigner']),
      rejectedAt: serializer.fromJson<int>(json['rejectedAt']),
      versionHash: serializer.fromJson<String>(json['versionHash']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'kind': serializer.toJson<String>(kind),
      'recordId': serializer.toJson<String>(recordId),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'reason': serializer.toJson<String>(reason),
      'relayedBy': serializer.toJson<String>(relayedBy),
      'claimedSigner': serializer.toJson<String?>(claimedSigner),
      'rejectedAt': serializer.toJson<int>(rejectedAt),
      'versionHash': serializer.toJson<String>(versionHash),
    };
  }

  RejectedVersion copyWith({
    String? groupId,
    String? kind,
    String? recordId,
    int? updatedAt,
    String? reason,
    String? relayedBy,
    Value<String?> claimedSigner = const Value.absent(),
    int? rejectedAt,
    String? versionHash,
  }) => RejectedVersion(
    groupId: groupId ?? this.groupId,
    kind: kind ?? this.kind,
    recordId: recordId ?? this.recordId,
    updatedAt: updatedAt ?? this.updatedAt,
    reason: reason ?? this.reason,
    relayedBy: relayedBy ?? this.relayedBy,
    claimedSigner: claimedSigner.present
        ? claimedSigner.value
        : this.claimedSigner,
    rejectedAt: rejectedAt ?? this.rejectedAt,
    versionHash: versionHash ?? this.versionHash,
  );
  RejectedVersion copyWithCompanion(RejectedVersionsCompanion data) {
    return RejectedVersion(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      kind: data.kind.present ? data.kind.value : this.kind,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      reason: data.reason.present ? data.reason.value : this.reason,
      relayedBy: data.relayedBy.present ? data.relayedBy.value : this.relayedBy,
      claimedSigner: data.claimedSigner.present
          ? data.claimedSigner.value
          : this.claimedSigner,
      rejectedAt: data.rejectedAt.present
          ? data.rejectedAt.value
          : this.rejectedAt,
      versionHash: data.versionHash.present
          ? data.versionHash.value
          : this.versionHash,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RejectedVersion(')
          ..write('groupId: $groupId, ')
          ..write('kind: $kind, ')
          ..write('recordId: $recordId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('reason: $reason, ')
          ..write('relayedBy: $relayedBy, ')
          ..write('claimedSigner: $claimedSigner, ')
          ..write('rejectedAt: $rejectedAt, ')
          ..write('versionHash: $versionHash')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    kind,
    recordId,
    updatedAt,
    reason,
    relayedBy,
    claimedSigner,
    rejectedAt,
    versionHash,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RejectedVersion &&
          other.groupId == this.groupId &&
          other.kind == this.kind &&
          other.recordId == this.recordId &&
          other.updatedAt == this.updatedAt &&
          other.reason == this.reason &&
          other.relayedBy == this.relayedBy &&
          other.claimedSigner == this.claimedSigner &&
          other.rejectedAt == this.rejectedAt &&
          other.versionHash == this.versionHash);
}

class RejectedVersionsCompanion extends UpdateCompanion<RejectedVersion> {
  final Value<String> groupId;
  final Value<String> kind;
  final Value<String> recordId;
  final Value<int> updatedAt;
  final Value<String> reason;
  final Value<String> relayedBy;
  final Value<String?> claimedSigner;
  final Value<int> rejectedAt;
  final Value<String> versionHash;
  final Value<int> rowid;
  const RejectedVersionsCompanion({
    this.groupId = const Value.absent(),
    this.kind = const Value.absent(),
    this.recordId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.reason = const Value.absent(),
    this.relayedBy = const Value.absent(),
    this.claimedSigner = const Value.absent(),
    this.rejectedAt = const Value.absent(),
    this.versionHash = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RejectedVersionsCompanion.insert({
    required String groupId,
    required String kind,
    required String recordId,
    required int updatedAt,
    required String reason,
    required String relayedBy,
    this.claimedSigner = const Value.absent(),
    required int rejectedAt,
    this.versionHash = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       kind = Value(kind),
       recordId = Value(recordId),
       updatedAt = Value(updatedAt),
       reason = Value(reason),
       relayedBy = Value(relayedBy),
       rejectedAt = Value(rejectedAt);
  static Insertable<RejectedVersion> custom({
    Expression<String>? groupId,
    Expression<String>? kind,
    Expression<String>? recordId,
    Expression<int>? updatedAt,
    Expression<String>? reason,
    Expression<String>? relayedBy,
    Expression<String>? claimedSigner,
    Expression<int>? rejectedAt,
    Expression<String>? versionHash,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (kind != null) 'kind': kind,
      if (recordId != null) 'record_id': recordId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (reason != null) 'reason': reason,
      if (relayedBy != null) 'relayed_by': relayedBy,
      if (claimedSigner != null) 'claimed_signer': claimedSigner,
      if (rejectedAt != null) 'rejected_at': rejectedAt,
      if (versionHash != null) 'version_hash': versionHash,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RejectedVersionsCompanion copyWith({
    Value<String>? groupId,
    Value<String>? kind,
    Value<String>? recordId,
    Value<int>? updatedAt,
    Value<String>? reason,
    Value<String>? relayedBy,
    Value<String?>? claimedSigner,
    Value<int>? rejectedAt,
    Value<String>? versionHash,
    Value<int>? rowid,
  }) {
    return RejectedVersionsCompanion(
      groupId: groupId ?? this.groupId,
      kind: kind ?? this.kind,
      recordId: recordId ?? this.recordId,
      updatedAt: updatedAt ?? this.updatedAt,
      reason: reason ?? this.reason,
      relayedBy: relayedBy ?? this.relayedBy,
      claimedSigner: claimedSigner ?? this.claimedSigner,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      versionHash: versionHash ?? this.versionHash,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (recordId.present) {
      map['record_id'] = Variable<String>(recordId.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (relayedBy.present) {
      map['relayed_by'] = Variable<String>(relayedBy.value);
    }
    if (claimedSigner.present) {
      map['claimed_signer'] = Variable<String>(claimedSigner.value);
    }
    if (rejectedAt.present) {
      map['rejected_at'] = Variable<int>(rejectedAt.value);
    }
    if (versionHash.present) {
      map['version_hash'] = Variable<String>(versionHash.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RejectedVersionsCompanion(')
          ..write('groupId: $groupId, ')
          ..write('kind: $kind, ')
          ..write('recordId: $recordId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('reason: $reason, ')
          ..write('relayedBy: $relayedBy, ')
          ..write('claimedSigner: $claimedSigner, ')
          ..write('rejectedAt: $rejectedAt, ')
          ..write('versionHash: $versionHash, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $GroupsTable groups = $GroupsTable(this);
  late final $ExpensesTable expenses = $ExpensesTable(this);
  late final $SettlementsTable settlements = $SettlementsTable(this);
  late final $MembersTable members = $MembersTable(this);
  late final $PeerSyncStatesTable peerSyncStates = $PeerSyncStatesTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $KnownDeviceKeysTable knownDeviceKeys = $KnownDeviceKeysTable(
    this,
  );
  late final $RejectedVersionsTable rejectedVersions = $RejectedVersionsTable(
    this,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    groups,
    expenses,
    settlements,
    members,
    peerSyncStates,
    appSettings,
    knownDeviceKeys,
    rejectedVersions,
  ];
}

typedef $$GroupsTableCreateCompanionBuilder =
    GroupsCompanion Function({
      required String roomId,
      required String name,
      Value<String> currency,
      Value<int> updatedAt,
      Value<String?> sig,
      Value<bool> pendingSign,
      Value<String?> categoriesJson,
      Value<int> rowid,
    });
typedef $$GroupsTableUpdateCompanionBuilder =
    GroupsCompanion Function({
      Value<String> roomId,
      Value<String> name,
      Value<String> currency,
      Value<int> updatedAt,
      Value<String?> sig,
      Value<bool> pendingSign,
      Value<String?> categoriesJson,
      Value<int> rowid,
    });

class $$GroupsTableFilterComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get categoriesJson => $composableBuilder(
    column: $table.categoriesJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GroupsTableOrderingComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get categoriesJson => $composableBuilder(
    column: $table.categoriesJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GroupsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GroupsTable> {
  $$GroupsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get roomId =>
      $composableBuilder(column: $table.roomId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get sig =>
      $composableBuilder(column: $table.sig, builder: (column) => column);

  GeneratedColumn<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => column,
  );

  GeneratedColumn<String> get categoriesJson => $composableBuilder(
    column: $table.categoriesJson,
    builder: (column) => column,
  );
}

class $$GroupsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GroupsTable,
          Group,
          $$GroupsTableFilterComposer,
          $$GroupsTableOrderingComposer,
          $$GroupsTableAnnotationComposer,
          $$GroupsTableCreateCompanionBuilder,
          $$GroupsTableUpdateCompanionBuilder,
          (Group, BaseReferences<_$AppDatabase, $GroupsTable, Group>),
          Group,
          PrefetchHooks Function()
        > {
  $$GroupsTableTableManager(_$AppDatabase db, $GroupsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GroupsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GroupsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GroupsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> roomId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> sig = const Value.absent(),
                Value<bool> pendingSign = const Value.absent(),
                Value<String?> categoriesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupsCompanion(
                roomId: roomId,
                name: name,
                currency: currency,
                updatedAt: updatedAt,
                sig: sig,
                pendingSign: pendingSign,
                categoriesJson: categoriesJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String roomId,
                required String name,
                Value<String> currency = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> sig = const Value.absent(),
                Value<bool> pendingSign = const Value.absent(),
                Value<String?> categoriesJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupsCompanion.insert(
                roomId: roomId,
                name: name,
                currency: currency,
                updatedAt: updatedAt,
                sig: sig,
                pendingSign: pendingSign,
                categoriesJson: categoriesJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GroupsTable, Group>(table),
                  BaseReferences<_$AppDatabase, $GroupsTable, Group>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GroupsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GroupsTable,
      Group,
      $$GroupsTableFilterComposer,
      $$GroupsTableOrderingComposer,
      $$GroupsTableAnnotationComposer,
      $$GroupsTableCreateCompanionBuilder,
      $$GroupsTableUpdateCompanionBuilder,
      (Group, BaseReferences<_$AppDatabase, $GroupsTable, Group>),
      Group,
      PrefetchHooks Function()
    >;
typedef $$ExpensesTableCreateCompanionBuilder =
    ExpensesCompanion Function({
      required String id,
      required String roomId,
      Value<String?> matrixEventId,
      required String description,
      required int amountCents,
      required String currency,
      required String paidBy,
      required String splitsJson,
      required int createdAt,
      Value<int> updatedAt,
      Value<bool> deleted,
      Value<String?> sig,
      Value<String?> origin,
      Value<bool> pendingSign,
      Value<String?> category,
      Value<String?> note,
      Value<String?> versionHash,
      Value<int> rowid,
    });
typedef $$ExpensesTableUpdateCompanionBuilder =
    ExpensesCompanion Function({
      Value<String> id,
      Value<String> roomId,
      Value<String?> matrixEventId,
      Value<String> description,
      Value<int> amountCents,
      Value<String> currency,
      Value<String> paidBy,
      Value<String> splitsJson,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<bool> deleted,
      Value<String?> sig,
      Value<String?> origin,
      Value<bool> pendingSign,
      Value<String?> category,
      Value<String?> note,
      Value<String?> versionHash,
      Value<int> rowid,
    });

class $$ExpensesTableFilterComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get matrixEventId => $composableBuilder(
    column: $table.matrixEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paidBy => $composableBuilder(
    column: $table.paidBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get splitsJson => $composableBuilder(
    column: $table.splitsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExpensesTableOrderingComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matrixEventId => $composableBuilder(
    column: $table.matrixEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paidBy => $composableBuilder(
    column: $table.paidBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get splitsJson => $composableBuilder(
    column: $table.splitsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExpensesTableAnnotationComposer
    extends Composer<_$AppDatabase, $ExpensesTable> {
  $$ExpensesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get roomId =>
      $composableBuilder(column: $table.roomId, builder: (column) => column);

  GeneratedColumn<String> get matrixEventId => $composableBuilder(
    column: $table.matrixEventId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get description => $composableBuilder(
    column: $table.description,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get paidBy =>
      $composableBuilder(column: $table.paidBy, builder: (column) => column);

  GeneratedColumn<String> get splitsJson => $composableBuilder(
    column: $table.splitsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get sig =>
      $composableBuilder(column: $table.sig, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => column,
  );
}

class $$ExpensesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ExpensesTable,
          Expense,
          $$ExpensesTableFilterComposer,
          $$ExpensesTableOrderingComposer,
          $$ExpensesTableAnnotationComposer,
          $$ExpensesTableCreateCompanionBuilder,
          $$ExpensesTableUpdateCompanionBuilder,
          (Expense, BaseReferences<_$AppDatabase, $ExpensesTable, Expense>),
          Expense,
          PrefetchHooks Function()
        > {
  $$ExpensesTableTableManager(_$AppDatabase db, $ExpensesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpensesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpensesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpensesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> roomId = const Value.absent(),
                Value<String?> matrixEventId = const Value.absent(),
                Value<String> description = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> paidBy = const Value.absent(),
                Value<String> splitsJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> sig = const Value.absent(),
                Value<String?> origin = const Value.absent(),
                Value<bool> pendingSign = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> versionHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpensesCompanion(
                id: id,
                roomId: roomId,
                matrixEventId: matrixEventId,
                description: description,
                amountCents: amountCents,
                currency: currency,
                paidBy: paidBy,
                splitsJson: splitsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deleted: deleted,
                sig: sig,
                origin: origin,
                pendingSign: pendingSign,
                category: category,
                note: note,
                versionHash: versionHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String roomId,
                Value<String?> matrixEventId = const Value.absent(),
                required String description,
                required int amountCents,
                required String currency,
                required String paidBy,
                required String splitsJson,
                required int createdAt,
                Value<int> updatedAt = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> sig = const Value.absent(),
                Value<String?> origin = const Value.absent(),
                Value<bool> pendingSign = const Value.absent(),
                Value<String?> category = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> versionHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExpensesCompanion.insert(
                id: id,
                roomId: roomId,
                matrixEventId: matrixEventId,
                description: description,
                amountCents: amountCents,
                currency: currency,
                paidBy: paidBy,
                splitsJson: splitsJson,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deleted: deleted,
                sig: sig,
                origin: origin,
                pendingSign: pendingSign,
                category: category,
                note: note,
                versionHash: versionHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExpensesTable, Expense>(table),
                  BaseReferences<_$AppDatabase, $ExpensesTable, Expense>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExpensesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ExpensesTable,
      Expense,
      $$ExpensesTableFilterComposer,
      $$ExpensesTableOrderingComposer,
      $$ExpensesTableAnnotationComposer,
      $$ExpensesTableCreateCompanionBuilder,
      $$ExpensesTableUpdateCompanionBuilder,
      (Expense, BaseReferences<_$AppDatabase, $ExpensesTable, Expense>),
      Expense,
      PrefetchHooks Function()
    >;
typedef $$SettlementsTableCreateCompanionBuilder =
    SettlementsCompanion Function({
      required String id,
      required String roomId,
      Value<String?> matrixEventId,
      required int amountCents,
      required String currency,
      required String fromUser,
      required String toUser,
      required int createdAt,
      Value<int> updatedAt,
      Value<bool> deleted,
      Value<String?> sig,
      Value<String?> origin,
      Value<bool> pendingSign,
      Value<String?> versionHash,
      Value<int> rowid,
    });
typedef $$SettlementsTableUpdateCompanionBuilder =
    SettlementsCompanion Function({
      Value<String> id,
      Value<String> roomId,
      Value<String?> matrixEventId,
      Value<int> amountCents,
      Value<String> currency,
      Value<String> fromUser,
      Value<String> toUser,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<bool> deleted,
      Value<String?> sig,
      Value<String?> origin,
      Value<bool> pendingSign,
      Value<String?> versionHash,
      Value<int> rowid,
    });

class $$SettlementsTableFilterComposer
    extends Composer<_$AppDatabase, $SettlementsTable> {
  $$SettlementsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get matrixEventId => $composableBuilder(
    column: $table.matrixEventId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromUser => $composableBuilder(
    column: $table.fromUser,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toUser => $composableBuilder(
    column: $table.toUser,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettlementsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettlementsTable> {
  $$SettlementsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get roomId => $composableBuilder(
    column: $table.roomId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matrixEventId => $composableBuilder(
    column: $table.matrixEventId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromUser => $composableBuilder(
    column: $table.fromUser,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toUser => $composableBuilder(
    column: $table.toUser,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get deleted => $composableBuilder(
    column: $table.deleted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get origin => $composableBuilder(
    column: $table.origin,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettlementsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettlementsTable> {
  $$SettlementsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get roomId =>
      $composableBuilder(column: $table.roomId, builder: (column) => column);

  GeneratedColumn<String> get matrixEventId => $composableBuilder(
    column: $table.matrixEventId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountCents => $composableBuilder(
    column: $table.amountCents,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get fromUser =>
      $composableBuilder(column: $table.fromUser, builder: (column) => column);

  GeneratedColumn<String> get toUser =>
      $composableBuilder(column: $table.toUser, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<bool> get deleted =>
      $composableBuilder(column: $table.deleted, builder: (column) => column);

  GeneratedColumn<String> get sig =>
      $composableBuilder(column: $table.sig, builder: (column) => column);

  GeneratedColumn<String> get origin =>
      $composableBuilder(column: $table.origin, builder: (column) => column);

  GeneratedColumn<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => column,
  );

  GeneratedColumn<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => column,
  );
}

class $$SettlementsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettlementsTable,
          Settlement,
          $$SettlementsTableFilterComposer,
          $$SettlementsTableOrderingComposer,
          $$SettlementsTableAnnotationComposer,
          $$SettlementsTableCreateCompanionBuilder,
          $$SettlementsTableUpdateCompanionBuilder,
          (
            Settlement,
            BaseReferences<_$AppDatabase, $SettlementsTable, Settlement>,
          ),
          Settlement,
          PrefetchHooks Function()
        > {
  $$SettlementsTableTableManager(_$AppDatabase db, $SettlementsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettlementsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettlementsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettlementsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> roomId = const Value.absent(),
                Value<String?> matrixEventId = const Value.absent(),
                Value<int> amountCents = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> fromUser = const Value.absent(),
                Value<String> toUser = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> sig = const Value.absent(),
                Value<String?> origin = const Value.absent(),
                Value<bool> pendingSign = const Value.absent(),
                Value<String?> versionHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettlementsCompanion(
                id: id,
                roomId: roomId,
                matrixEventId: matrixEventId,
                amountCents: amountCents,
                currency: currency,
                fromUser: fromUser,
                toUser: toUser,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deleted: deleted,
                sig: sig,
                origin: origin,
                pendingSign: pendingSign,
                versionHash: versionHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String roomId,
                Value<String?> matrixEventId = const Value.absent(),
                required int amountCents,
                required String currency,
                required String fromUser,
                required String toUser,
                required int createdAt,
                Value<int> updatedAt = const Value.absent(),
                Value<bool> deleted = const Value.absent(),
                Value<String?> sig = const Value.absent(),
                Value<String?> origin = const Value.absent(),
                Value<bool> pendingSign = const Value.absent(),
                Value<String?> versionHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettlementsCompanion.insert(
                id: id,
                roomId: roomId,
                matrixEventId: matrixEventId,
                amountCents: amountCents,
                currency: currency,
                fromUser: fromUser,
                toUser: toUser,
                createdAt: createdAt,
                updatedAt: updatedAt,
                deleted: deleted,
                sig: sig,
                origin: origin,
                pendingSign: pendingSign,
                versionHash: versionHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettlementsTable, Settlement>(table),
                  BaseReferences<_$AppDatabase, $SettlementsTable, Settlement>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettlementsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettlementsTable,
      Settlement,
      $$SettlementsTableFilterComposer,
      $$SettlementsTableOrderingComposer,
      $$SettlementsTableAnnotationComposer,
      $$SettlementsTableCreateCompanionBuilder,
      $$SettlementsTableUpdateCompanionBuilder,
      (
        Settlement,
        BaseReferences<_$AppDatabase, $SettlementsTable, Settlement>,
      ),
      Settlement,
      PrefetchHooks Function()
    >;
typedef $$MembersTableCreateCompanionBuilder =
    MembersCompanion Function({
      required String groupId,
      required String userId,
      Value<String> displayName,
      Value<String?> matrixId,
      Value<String> status,
      required int updatedAt,
      Value<String?> sig,
      Value<bool> pendingSign,
      Value<int> rowid,
    });
typedef $$MembersTableUpdateCompanionBuilder =
    MembersCompanion Function({
      Value<String> groupId,
      Value<String> userId,
      Value<String> displayName,
      Value<String?> matrixId,
      Value<String> status,
      Value<int> updatedAt,
      Value<String?> sig,
      Value<bool> pendingSign,
      Value<int> rowid,
    });

class $$MembersTableFilterComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get matrixId => $composableBuilder(
    column: $table.matrixId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MembersTableOrderingComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matrixId => $composableBuilder(
    column: $table.matrixId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sig => $composableBuilder(
    column: $table.sig,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MembersTableAnnotationComposer
    extends Composer<_$AppDatabase, $MembersTable> {
  $$MembersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get matrixId =>
      $composableBuilder(column: $table.matrixId, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get sig =>
      $composableBuilder(column: $table.sig, builder: (column) => column);

  GeneratedColumn<bool> get pendingSign => $composableBuilder(
    column: $table.pendingSign,
    builder: (column) => column,
  );
}

class $$MembersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MembersTable,
          Member,
          $$MembersTableFilterComposer,
          $$MembersTableOrderingComposer,
          $$MembersTableAnnotationComposer,
          $$MembersTableCreateCompanionBuilder,
          $$MembersTableUpdateCompanionBuilder,
          (Member, BaseReferences<_$AppDatabase, $MembersTable, Member>),
          Member,
          PrefetchHooks Function()
        > {
  $$MembersTableTableManager(_$AppDatabase db, $MembersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MembersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MembersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MembersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<String?> matrixId = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String?> sig = const Value.absent(),
                Value<bool> pendingSign = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MembersCompanion(
                groupId: groupId,
                userId: userId,
                displayName: displayName,
                matrixId: matrixId,
                status: status,
                updatedAt: updatedAt,
                sig: sig,
                pendingSign: pendingSign,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String userId,
                Value<String> displayName = const Value.absent(),
                Value<String?> matrixId = const Value.absent(),
                Value<String> status = const Value.absent(),
                required int updatedAt,
                Value<String?> sig = const Value.absent(),
                Value<bool> pendingSign = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MembersCompanion.insert(
                groupId: groupId,
                userId: userId,
                displayName: displayName,
                matrixId: matrixId,
                status: status,
                updatedAt: updatedAt,
                sig: sig,
                pendingSign: pendingSign,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MembersTable, Member>(table),
                  BaseReferences<_$AppDatabase, $MembersTable, Member>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MembersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MembersTable,
      Member,
      $$MembersTableFilterComposer,
      $$MembersTableOrderingComposer,
      $$MembersTableAnnotationComposer,
      $$MembersTableCreateCompanionBuilder,
      $$MembersTableUpdateCompanionBuilder,
      (Member, BaseReferences<_$AppDatabase, $MembersTable, Member>),
      Member,
      PrefetchHooks Function()
    >;
typedef $$PeerSyncStatesTableCreateCompanionBuilder =
    PeerSyncStatesCompanion Function({
      required String groupId,
      required String userId,
      Value<int> lastInSyncAt,
      Value<int> lastDigestSentAt,
      Value<int> rowid,
    });
typedef $$PeerSyncStatesTableUpdateCompanionBuilder =
    PeerSyncStatesCompanion Function({
      Value<String> groupId,
      Value<String> userId,
      Value<int> lastInSyncAt,
      Value<int> lastDigestSentAt,
      Value<int> rowid,
    });

class $$PeerSyncStatesTableFilterComposer
    extends Composer<_$AppDatabase, $PeerSyncStatesTable> {
  $$PeerSyncStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastInSyncAt => $composableBuilder(
    column: $table.lastInSyncAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastDigestSentAt => $composableBuilder(
    column: $table.lastDigestSentAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PeerSyncStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $PeerSyncStatesTable> {
  $$PeerSyncStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastInSyncAt => $composableBuilder(
    column: $table.lastInSyncAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastDigestSentAt => $composableBuilder(
    column: $table.lastDigestSentAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PeerSyncStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $PeerSyncStatesTable> {
  $$PeerSyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get lastInSyncAt => $composableBuilder(
    column: $table.lastInSyncAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastDigestSentAt => $composableBuilder(
    column: $table.lastDigestSentAt,
    builder: (column) => column,
  );
}

class $$PeerSyncStatesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PeerSyncStatesTable,
          PeerSyncState,
          $$PeerSyncStatesTableFilterComposer,
          $$PeerSyncStatesTableOrderingComposer,
          $$PeerSyncStatesTableAnnotationComposer,
          $$PeerSyncStatesTableCreateCompanionBuilder,
          $$PeerSyncStatesTableUpdateCompanionBuilder,
          (
            PeerSyncState,
            BaseReferences<_$AppDatabase, $PeerSyncStatesTable, PeerSyncState>,
          ),
          PeerSyncState,
          PrefetchHooks Function()
        > {
  $$PeerSyncStatesTableTableManager(
    _$AppDatabase db,
    $PeerSyncStatesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PeerSyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PeerSyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PeerSyncStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> userId = const Value.absent(),
                Value<int> lastInSyncAt = const Value.absent(),
                Value<int> lastDigestSentAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeerSyncStatesCompanion(
                groupId: groupId,
                userId: userId,
                lastInSyncAt: lastInSyncAt,
                lastDigestSentAt: lastDigestSentAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String userId,
                Value<int> lastInSyncAt = const Value.absent(),
                Value<int> lastDigestSentAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PeerSyncStatesCompanion.insert(
                groupId: groupId,
                userId: userId,
                lastInSyncAt: lastInSyncAt,
                lastDigestSentAt: lastDigestSentAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PeerSyncStatesTable, PeerSyncState>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PeerSyncStatesTable,
                    PeerSyncState
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PeerSyncStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PeerSyncStatesTable,
      PeerSyncState,
      $$PeerSyncStatesTableFilterComposer,
      $$PeerSyncStatesTableOrderingComposer,
      $$PeerSyncStatesTableAnnotationComposer,
      $$PeerSyncStatesTableCreateCompanionBuilder,
      $$PeerSyncStatesTableUpdateCompanionBuilder,
      (
        PeerSyncState,
        BaseReferences<_$AppDatabase, $PeerSyncStatesTable, PeerSyncState>,
      ),
      PeerSyncState,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSetting,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSetting,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
          ),
          AppSetting,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSetting>(table),
                  BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSetting,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSetting,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSetting>,
      ),
      AppSetting,
      PrefetchHooks Function()
    >;
typedef $$KnownDeviceKeysTableCreateCompanionBuilder =
    KnownDeviceKeysCompanion Function({
      required String userId,
      required String deviceId,
      required String ed25519Key,
      required String source,
      Value<String?> attestedBy,
      required int firstSeenAt,
      Value<String> attestedGroup,
      Value<int> rowid,
    });
typedef $$KnownDeviceKeysTableUpdateCompanionBuilder =
    KnownDeviceKeysCompanion Function({
      Value<String> userId,
      Value<String> deviceId,
      Value<String> ed25519Key,
      Value<String> source,
      Value<String?> attestedBy,
      Value<int> firstSeenAt,
      Value<String> attestedGroup,
      Value<int> rowid,
    });

class $$KnownDeviceKeysTableFilterComposer
    extends Composer<_$AppDatabase, $KnownDeviceKeysTable> {
  $$KnownDeviceKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ed25519Key => $composableBuilder(
    column: $table.ed25519Key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attestedBy => $composableBuilder(
    column: $table.attestedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get attestedGroup => $composableBuilder(
    column: $table.attestedGroup,
    builder: (column) => ColumnFilters(column),
  );
}

class $$KnownDeviceKeysTableOrderingComposer
    extends Composer<_$AppDatabase, $KnownDeviceKeysTable> {
  $$KnownDeviceKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
    column: $table.userId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ed25519Key => $composableBuilder(
    column: $table.ed25519Key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attestedBy => $composableBuilder(
    column: $table.attestedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get attestedGroup => $composableBuilder(
    column: $table.attestedGroup,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$KnownDeviceKeysTableAnnotationComposer
    extends Composer<_$AppDatabase, $KnownDeviceKeysTable> {
  $$KnownDeviceKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get ed25519Key => $composableBuilder(
    column: $table.ed25519Key,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get attestedBy => $composableBuilder(
    column: $table.attestedBy,
    builder: (column) => column,
  );

  GeneratedColumn<int> get firstSeenAt => $composableBuilder(
    column: $table.firstSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get attestedGroup => $composableBuilder(
    column: $table.attestedGroup,
    builder: (column) => column,
  );
}

class $$KnownDeviceKeysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $KnownDeviceKeysTable,
          KnownDeviceKey,
          $$KnownDeviceKeysTableFilterComposer,
          $$KnownDeviceKeysTableOrderingComposer,
          $$KnownDeviceKeysTableAnnotationComposer,
          $$KnownDeviceKeysTableCreateCompanionBuilder,
          $$KnownDeviceKeysTableUpdateCompanionBuilder,
          (
            KnownDeviceKey,
            BaseReferences<
              _$AppDatabase,
              $KnownDeviceKeysTable,
              KnownDeviceKey
            >,
          ),
          KnownDeviceKey,
          PrefetchHooks Function()
        > {
  $$KnownDeviceKeysTableTableManager(
    _$AppDatabase db,
    $KnownDeviceKeysTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$KnownDeviceKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$KnownDeviceKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$KnownDeviceKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> userId = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<String> ed25519Key = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> attestedBy = const Value.absent(),
                Value<int> firstSeenAt = const Value.absent(),
                Value<String> attestedGroup = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnownDeviceKeysCompanion(
                userId: userId,
                deviceId: deviceId,
                ed25519Key: ed25519Key,
                source: source,
                attestedBy: attestedBy,
                firstSeenAt: firstSeenAt,
                attestedGroup: attestedGroup,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String userId,
                required String deviceId,
                required String ed25519Key,
                required String source,
                Value<String?> attestedBy = const Value.absent(),
                required int firstSeenAt,
                Value<String> attestedGroup = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => KnownDeviceKeysCompanion.insert(
                userId: userId,
                deviceId: deviceId,
                ed25519Key: ed25519Key,
                source: source,
                attestedBy: attestedBy,
                firstSeenAt: firstSeenAt,
                attestedGroup: attestedGroup,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$KnownDeviceKeysTable, KnownDeviceKey>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $KnownDeviceKeysTable,
                    KnownDeviceKey
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$KnownDeviceKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $KnownDeviceKeysTable,
      KnownDeviceKey,
      $$KnownDeviceKeysTableFilterComposer,
      $$KnownDeviceKeysTableOrderingComposer,
      $$KnownDeviceKeysTableAnnotationComposer,
      $$KnownDeviceKeysTableCreateCompanionBuilder,
      $$KnownDeviceKeysTableUpdateCompanionBuilder,
      (
        KnownDeviceKey,
        BaseReferences<_$AppDatabase, $KnownDeviceKeysTable, KnownDeviceKey>,
      ),
      KnownDeviceKey,
      PrefetchHooks Function()
    >;
typedef $$RejectedVersionsTableCreateCompanionBuilder =
    RejectedVersionsCompanion Function({
      required String groupId,
      required String kind,
      required String recordId,
      required int updatedAt,
      required String reason,
      required String relayedBy,
      Value<String?> claimedSigner,
      required int rejectedAt,
      Value<String> versionHash,
      Value<int> rowid,
    });
typedef $$RejectedVersionsTableUpdateCompanionBuilder =
    RejectedVersionsCompanion Function({
      Value<String> groupId,
      Value<String> kind,
      Value<String> recordId,
      Value<int> updatedAt,
      Value<String> reason,
      Value<String> relayedBy,
      Value<String?> claimedSigner,
      Value<int> rejectedAt,
      Value<String> versionHash,
      Value<int> rowid,
    });

class $$RejectedVersionsTableFilterComposer
    extends Composer<_$AppDatabase, $RejectedVersionsTable> {
  $$RejectedVersionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get relayedBy => $composableBuilder(
    column: $table.relayedBy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get claimedSigner => $composableBuilder(
    column: $table.claimedSigner,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rejectedAt => $composableBuilder(
    column: $table.rejectedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RejectedVersionsTableOrderingComposer
    extends Composer<_$AppDatabase, $RejectedVersionsTable> {
  $$RejectedVersionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get groupId => $composableBuilder(
    column: $table.groupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recordId => $composableBuilder(
    column: $table.recordId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get relayedBy => $composableBuilder(
    column: $table.relayedBy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get claimedSigner => $composableBuilder(
    column: $table.claimedSigner,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rejectedAt => $composableBuilder(
    column: $table.rejectedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RejectedVersionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RejectedVersionsTable> {
  $$RejectedVersionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get relayedBy =>
      $composableBuilder(column: $table.relayedBy, builder: (column) => column);

  GeneratedColumn<String> get claimedSigner => $composableBuilder(
    column: $table.claimedSigner,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rejectedAt => $composableBuilder(
    column: $table.rejectedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => column,
  );
}

class $$RejectedVersionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RejectedVersionsTable,
          RejectedVersion,
          $$RejectedVersionsTableFilterComposer,
          $$RejectedVersionsTableOrderingComposer,
          $$RejectedVersionsTableAnnotationComposer,
          $$RejectedVersionsTableCreateCompanionBuilder,
          $$RejectedVersionsTableUpdateCompanionBuilder,
          (
            RejectedVersion,
            BaseReferences<
              _$AppDatabase,
              $RejectedVersionsTable,
              RejectedVersion
            >,
          ),
          RejectedVersion,
          PrefetchHooks Function()
        > {
  $$RejectedVersionsTableTableManager(
    _$AppDatabase db,
    $RejectedVersionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RejectedVersionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RejectedVersionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RejectedVersionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<String> relayedBy = const Value.absent(),
                Value<String?> claimedSigner = const Value.absent(),
                Value<int> rejectedAt = const Value.absent(),
                Value<String> versionHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RejectedVersionsCompanion(
                groupId: groupId,
                kind: kind,
                recordId: recordId,
                updatedAt: updatedAt,
                reason: reason,
                relayedBy: relayedBy,
                claimedSigner: claimedSigner,
                rejectedAt: rejectedAt,
                versionHash: versionHash,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String kind,
                required String recordId,
                required int updatedAt,
                required String reason,
                required String relayedBy,
                Value<String?> claimedSigner = const Value.absent(),
                required int rejectedAt,
                Value<String> versionHash = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RejectedVersionsCompanion.insert(
                groupId: groupId,
                kind: kind,
                recordId: recordId,
                updatedAt: updatedAt,
                reason: reason,
                relayedBy: relayedBy,
                claimedSigner: claimedSigner,
                rejectedAt: rejectedAt,
                versionHash: versionHash,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RejectedVersionsTable, RejectedVersion>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RejectedVersionsTable,
                    RejectedVersion
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RejectedVersionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RejectedVersionsTable,
      RejectedVersion,
      $$RejectedVersionsTableFilterComposer,
      $$RejectedVersionsTableOrderingComposer,
      $$RejectedVersionsTableAnnotationComposer,
      $$RejectedVersionsTableCreateCompanionBuilder,
      $$RejectedVersionsTableUpdateCompanionBuilder,
      (
        RejectedVersion,
        BaseReferences<_$AppDatabase, $RejectedVersionsTable, RejectedVersion>,
      ),
      RejectedVersion,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$GroupsTableTableManager get groups =>
      $$GroupsTableTableManager(_db, _db.groups);
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db, _db.expenses);
  $$SettlementsTableTableManager get settlements =>
      $$SettlementsTableTableManager(_db, _db.settlements);
  $$MembersTableTableManager get members =>
      $$MembersTableTableManager(_db, _db.members);
  $$PeerSyncStatesTableTableManager get peerSyncStates =>
      $$PeerSyncStatesTableTableManager(_db, _db.peerSyncStates);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$KnownDeviceKeysTableTableManager get knownDeviceKeys =>
      $$KnownDeviceKeysTableTableManager(_db, _db.knownDeviceKeys);
  $$RejectedVersionsTableTableManager get rejectedVersions =>
      $$RejectedVersionsTableTableManager(_db, _db.rejectedVersions);
}
