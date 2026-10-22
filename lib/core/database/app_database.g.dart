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
  static const VerificationMeta _linkAuthorMeta = const VerificationMeta(
    'linkAuthor',
  );
  @override
  late final GeneratedColumn<String> linkAuthor = GeneratedColumn<String>(
    'link_author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkEpochMeta = const VerificationMeta(
    'linkEpoch',
  );
  @override
  late final GeneratedColumn<int> linkEpoch = GeneratedColumn<int>(
    'link_epoch',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _linkSecretMeta = const VerificationMeta(
    'linkSecret',
  );
  @override
  late final GeneratedColumn<String> linkSecret = GeneratedColumn<String>(
    'link_secret',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lockedAtMeta = const VerificationMeta(
    'lockedAt',
  );
  @override
  late final GeneratedColumn<int> lockedAt = GeneratedColumn<int>(
    'locked_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exchangeRatesJsonMeta = const VerificationMeta(
    'exchangeRatesJson',
  );
  @override
  late final GeneratedColumn<String> exchangeRatesJson =
      GeneratedColumn<String>(
        'exchange_rates_json',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _fieldClocksJsonMeta = const VerificationMeta(
    'fieldClocksJson',
  );
  @override
  late final GeneratedColumn<String> fieldClocksJson = GeneratedColumn<String>(
    'field_clocks_json',
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
    linkAuthor,
    linkEpoch,
    linkSecret,
    lockedAt,
    exchangeRatesJson,
    fieldClocksJson,
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
    if (data.containsKey('link_author')) {
      context.handle(
        _linkAuthorMeta,
        linkAuthor.isAcceptableOrUnknown(data['link_author']!, _linkAuthorMeta),
      );
    }
    if (data.containsKey('link_epoch')) {
      context.handle(
        _linkEpochMeta,
        linkEpoch.isAcceptableOrUnknown(data['link_epoch']!, _linkEpochMeta),
      );
    }
    if (data.containsKey('link_secret')) {
      context.handle(
        _linkSecretMeta,
        linkSecret.isAcceptableOrUnknown(data['link_secret']!, _linkSecretMeta),
      );
    }
    if (data.containsKey('locked_at')) {
      context.handle(
        _lockedAtMeta,
        lockedAt.isAcceptableOrUnknown(data['locked_at']!, _lockedAtMeta),
      );
    }
    if (data.containsKey('exchange_rates_json')) {
      context.handle(
        _exchangeRatesJsonMeta,
        exchangeRatesJson.isAcceptableOrUnknown(
          data['exchange_rates_json']!,
          _exchangeRatesJsonMeta,
        ),
      );
    }
    if (data.containsKey('field_clocks_json')) {
      context.handle(
        _fieldClocksJsonMeta,
        fieldClocksJson.isAcceptableOrUnknown(
          data['field_clocks_json']!,
          _fieldClocksJsonMeta,
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
      linkAuthor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_author'],
      ),
      linkEpoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}link_epoch'],
      ),
      linkSecret: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_secret'],
      ),
      lockedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}locked_at'],
      ),
      exchangeRatesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exchange_rates_json'],
      ),
      fieldClocksJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}field_clocks_json'],
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
  final String? linkAuthor;
  final int? linkEpoch;
  final String? linkSecret;
  final int? lockedAt;
  final String? exchangeRatesJson;
  final String? fieldClocksJson;
  const Group({
    required this.roomId,
    required this.name,
    required this.currency,
    required this.updatedAt,
    this.sig,
    required this.pendingSign,
    this.categoriesJson,
    this.linkAuthor,
    this.linkEpoch,
    this.linkSecret,
    this.lockedAt,
    this.exchangeRatesJson,
    this.fieldClocksJson,
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
    if (!nullToAbsent || linkAuthor != null) {
      map['link_author'] = Variable<String>(linkAuthor);
    }
    if (!nullToAbsent || linkEpoch != null) {
      map['link_epoch'] = Variable<int>(linkEpoch);
    }
    if (!nullToAbsent || linkSecret != null) {
      map['link_secret'] = Variable<String>(linkSecret);
    }
    if (!nullToAbsent || lockedAt != null) {
      map['locked_at'] = Variable<int>(lockedAt);
    }
    if (!nullToAbsent || exchangeRatesJson != null) {
      map['exchange_rates_json'] = Variable<String>(exchangeRatesJson);
    }
    if (!nullToAbsent || fieldClocksJson != null) {
      map['field_clocks_json'] = Variable<String>(fieldClocksJson);
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
      linkAuthor: linkAuthor == null && nullToAbsent
          ? const Value.absent()
          : Value(linkAuthor),
      linkEpoch: linkEpoch == null && nullToAbsent
          ? const Value.absent()
          : Value(linkEpoch),
      linkSecret: linkSecret == null && nullToAbsent
          ? const Value.absent()
          : Value(linkSecret),
      lockedAt: lockedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lockedAt),
      exchangeRatesJson: exchangeRatesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(exchangeRatesJson),
      fieldClocksJson: fieldClocksJson == null && nullToAbsent
          ? const Value.absent()
          : Value(fieldClocksJson),
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
      linkAuthor: serializer.fromJson<String?>(json['linkAuthor']),
      linkEpoch: serializer.fromJson<int?>(json['linkEpoch']),
      linkSecret: serializer.fromJson<String?>(json['linkSecret']),
      lockedAt: serializer.fromJson<int?>(json['lockedAt']),
      exchangeRatesJson: serializer.fromJson<String?>(
        json['exchangeRatesJson'],
      ),
      fieldClocksJson: serializer.fromJson<String?>(json['fieldClocksJson']),
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
      'linkAuthor': serializer.toJson<String?>(linkAuthor),
      'linkEpoch': serializer.toJson<int?>(linkEpoch),
      'linkSecret': serializer.toJson<String?>(linkSecret),
      'lockedAt': serializer.toJson<int?>(lockedAt),
      'exchangeRatesJson': serializer.toJson<String?>(exchangeRatesJson),
      'fieldClocksJson': serializer.toJson<String?>(fieldClocksJson),
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
    Value<String?> linkAuthor = const Value.absent(),
    Value<int?> linkEpoch = const Value.absent(),
    Value<String?> linkSecret = const Value.absent(),
    Value<int?> lockedAt = const Value.absent(),
    Value<String?> exchangeRatesJson = const Value.absent(),
    Value<String?> fieldClocksJson = const Value.absent(),
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
    linkAuthor: linkAuthor.present ? linkAuthor.value : this.linkAuthor,
    linkEpoch: linkEpoch.present ? linkEpoch.value : this.linkEpoch,
    linkSecret: linkSecret.present ? linkSecret.value : this.linkSecret,
    lockedAt: lockedAt.present ? lockedAt.value : this.lockedAt,
    exchangeRatesJson: exchangeRatesJson.present
        ? exchangeRatesJson.value
        : this.exchangeRatesJson,
    fieldClocksJson: fieldClocksJson.present
        ? fieldClocksJson.value
        : this.fieldClocksJson,
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
      linkAuthor: data.linkAuthor.present
          ? data.linkAuthor.value
          : this.linkAuthor,
      linkEpoch: data.linkEpoch.present ? data.linkEpoch.value : this.linkEpoch,
      linkSecret: data.linkSecret.present
          ? data.linkSecret.value
          : this.linkSecret,
      lockedAt: data.lockedAt.present ? data.lockedAt.value : this.lockedAt,
      exchangeRatesJson: data.exchangeRatesJson.present
          ? data.exchangeRatesJson.value
          : this.exchangeRatesJson,
      fieldClocksJson: data.fieldClocksJson.present
          ? data.fieldClocksJson.value
          : this.fieldClocksJson,
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
          ..write('categoriesJson: $categoriesJson, ')
          ..write('linkAuthor: $linkAuthor, ')
          ..write('linkEpoch: $linkEpoch, ')
          ..write('linkSecret: $linkSecret, ')
          ..write('lockedAt: $lockedAt, ')
          ..write('exchangeRatesJson: $exchangeRatesJson, ')
          ..write('fieldClocksJson: $fieldClocksJson')
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
    linkAuthor,
    linkEpoch,
    linkSecret,
    lockedAt,
    exchangeRatesJson,
    fieldClocksJson,
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
          other.categoriesJson == this.categoriesJson &&
          other.linkAuthor == this.linkAuthor &&
          other.linkEpoch == this.linkEpoch &&
          other.linkSecret == this.linkSecret &&
          other.lockedAt == this.lockedAt &&
          other.exchangeRatesJson == this.exchangeRatesJson &&
          other.fieldClocksJson == this.fieldClocksJson);
}

class GroupsCompanion extends UpdateCompanion<Group> {
  final Value<String> roomId;
  final Value<String> name;
  final Value<String> currency;
  final Value<int> updatedAt;
  final Value<String?> sig;
  final Value<bool> pendingSign;
  final Value<String?> categoriesJson;
  final Value<String?> linkAuthor;
  final Value<int?> linkEpoch;
  final Value<String?> linkSecret;
  final Value<int?> lockedAt;
  final Value<String?> exchangeRatesJson;
  final Value<String?> fieldClocksJson;
  final Value<int> rowid;
  const GroupsCompanion({
    this.roomId = const Value.absent(),
    this.name = const Value.absent(),
    this.currency = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.sig = const Value.absent(),
    this.pendingSign = const Value.absent(),
    this.categoriesJson = const Value.absent(),
    this.linkAuthor = const Value.absent(),
    this.linkEpoch = const Value.absent(),
    this.linkSecret = const Value.absent(),
    this.lockedAt = const Value.absent(),
    this.exchangeRatesJson = const Value.absent(),
    this.fieldClocksJson = const Value.absent(),
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
    this.linkAuthor = const Value.absent(),
    this.linkEpoch = const Value.absent(),
    this.linkSecret = const Value.absent(),
    this.lockedAt = const Value.absent(),
    this.exchangeRatesJson = const Value.absent(),
    this.fieldClocksJson = const Value.absent(),
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
    Expression<String>? linkAuthor,
    Expression<int>? linkEpoch,
    Expression<String>? linkSecret,
    Expression<int>? lockedAt,
    Expression<String>? exchangeRatesJson,
    Expression<String>? fieldClocksJson,
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
      if (linkAuthor != null) 'link_author': linkAuthor,
      if (linkEpoch != null) 'link_epoch': linkEpoch,
      if (linkSecret != null) 'link_secret': linkSecret,
      if (lockedAt != null) 'locked_at': lockedAt,
      if (exchangeRatesJson != null) 'exchange_rates_json': exchangeRatesJson,
      if (fieldClocksJson != null) 'field_clocks_json': fieldClocksJson,
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
    Value<String?>? linkAuthor,
    Value<int?>? linkEpoch,
    Value<String?>? linkSecret,
    Value<int?>? lockedAt,
    Value<String?>? exchangeRatesJson,
    Value<String?>? fieldClocksJson,
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
      linkAuthor: linkAuthor ?? this.linkAuthor,
      linkEpoch: linkEpoch ?? this.linkEpoch,
      linkSecret: linkSecret ?? this.linkSecret,
      lockedAt: lockedAt ?? this.lockedAt,
      exchangeRatesJson: exchangeRatesJson ?? this.exchangeRatesJson,
      fieldClocksJson: fieldClocksJson ?? this.fieldClocksJson,
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
    if (linkAuthor.present) {
      map['link_author'] = Variable<String>(linkAuthor.value);
    }
    if (linkEpoch.present) {
      map['link_epoch'] = Variable<int>(linkEpoch.value);
    }
    if (linkSecret.present) {
      map['link_secret'] = Variable<String>(linkSecret.value);
    }
    if (lockedAt.present) {
      map['locked_at'] = Variable<int>(lockedAt.value);
    }
    if (exchangeRatesJson.present) {
      map['exchange_rates_json'] = Variable<String>(exchangeRatesJson.value);
    }
    if (fieldClocksJson.present) {
      map['field_clocks_json'] = Variable<String>(fieldClocksJson.value);
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
          ..write('linkAuthor: $linkAuthor, ')
          ..write('linkEpoch: $linkEpoch, ')
          ..write('linkSecret: $linkSecret, ')
          ..write('lockedAt: $lockedAt, ')
          ..write('exchangeRatesJson: $exchangeRatesJson, ')
          ..write('fieldClocksJson: $fieldClocksJson, ')
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
  static const VerificationMeta _expenseDateMeta = const VerificationMeta(
    'expenseDate',
  );
  @override
  late final GeneratedColumn<String> expenseDate = GeneratedColumn<String>(
    'expense_date',
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
  static const VerificationMeta _linkAuthorMeta = const VerificationMeta(
    'linkAuthor',
  );
  @override
  late final GeneratedColumn<String> linkAuthor = GeneratedColumn<String>(
    'link_author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _payersJsonMeta = const VerificationMeta(
    'payersJson',
  );
  @override
  late final GeneratedColumn<String> payersJson = GeneratedColumn<String>(
    'payers_json',
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
    expenseDate,
    versionHash,
    linkAuthor,
    payersJson,
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
    if (data.containsKey('expense_date')) {
      context.handle(
        _expenseDateMeta,
        expenseDate.isAcceptableOrUnknown(
          data['expense_date']!,
          _expenseDateMeta,
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
    if (data.containsKey('link_author')) {
      context.handle(
        _linkAuthorMeta,
        linkAuthor.isAcceptableOrUnknown(data['link_author']!, _linkAuthorMeta),
      );
    }
    if (data.containsKey('payers_json')) {
      context.handle(
        _payersJsonMeta,
        payersJson.isAcceptableOrUnknown(data['payers_json']!, _payersJsonMeta),
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
      expenseDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expense_date'],
      ),
      versionHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_hash'],
      ),
      linkAuthor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_author'],
      ),
      payersJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payers_json'],
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
  final String? expenseDate;
  final String? versionHash;
  final String? linkAuthor;
  final String? payersJson;
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
    this.expenseDate,
    this.versionHash,
    this.linkAuthor,
    this.payersJson,
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
    if (!nullToAbsent || expenseDate != null) {
      map['expense_date'] = Variable<String>(expenseDate);
    }
    if (!nullToAbsent || versionHash != null) {
      map['version_hash'] = Variable<String>(versionHash);
    }
    if (!nullToAbsent || linkAuthor != null) {
      map['link_author'] = Variable<String>(linkAuthor);
    }
    if (!nullToAbsent || payersJson != null) {
      map['payers_json'] = Variable<String>(payersJson);
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
      expenseDate: expenseDate == null && nullToAbsent
          ? const Value.absent()
          : Value(expenseDate),
      versionHash: versionHash == null && nullToAbsent
          ? const Value.absent()
          : Value(versionHash),
      linkAuthor: linkAuthor == null && nullToAbsent
          ? const Value.absent()
          : Value(linkAuthor),
      payersJson: payersJson == null && nullToAbsent
          ? const Value.absent()
          : Value(payersJson),
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
      expenseDate: serializer.fromJson<String?>(json['expenseDate']),
      versionHash: serializer.fromJson<String?>(json['versionHash']),
      linkAuthor: serializer.fromJson<String?>(json['linkAuthor']),
      payersJson: serializer.fromJson<String?>(json['payersJson']),
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
      'expenseDate': serializer.toJson<String?>(expenseDate),
      'versionHash': serializer.toJson<String?>(versionHash),
      'linkAuthor': serializer.toJson<String?>(linkAuthor),
      'payersJson': serializer.toJson<String?>(payersJson),
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
    Value<String?> expenseDate = const Value.absent(),
    Value<String?> versionHash = const Value.absent(),
    Value<String?> linkAuthor = const Value.absent(),
    Value<String?> payersJson = const Value.absent(),
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
    expenseDate: expenseDate.present ? expenseDate.value : this.expenseDate,
    versionHash: versionHash.present ? versionHash.value : this.versionHash,
    linkAuthor: linkAuthor.present ? linkAuthor.value : this.linkAuthor,
    payersJson: payersJson.present ? payersJson.value : this.payersJson,
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
      expenseDate: data.expenseDate.present
          ? data.expenseDate.value
          : this.expenseDate,
      versionHash: data.versionHash.present
          ? data.versionHash.value
          : this.versionHash,
      linkAuthor: data.linkAuthor.present
          ? data.linkAuthor.value
          : this.linkAuthor,
      payersJson: data.payersJson.present
          ? data.payersJson.value
          : this.payersJson,
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
          ..write('expenseDate: $expenseDate, ')
          ..write('versionHash: $versionHash, ')
          ..write('linkAuthor: $linkAuthor, ')
          ..write('payersJson: $payersJson')
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
    expenseDate,
    versionHash,
    linkAuthor,
    payersJson,
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
          other.expenseDate == this.expenseDate &&
          other.versionHash == this.versionHash &&
          other.linkAuthor == this.linkAuthor &&
          other.payersJson == this.payersJson);
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
  final Value<String?> expenseDate;
  final Value<String?> versionHash;
  final Value<String?> linkAuthor;
  final Value<String?> payersJson;
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
    this.expenseDate = const Value.absent(),
    this.versionHash = const Value.absent(),
    this.linkAuthor = const Value.absent(),
    this.payersJson = const Value.absent(),
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
    this.expenseDate = const Value.absent(),
    this.versionHash = const Value.absent(),
    this.linkAuthor = const Value.absent(),
    this.payersJson = const Value.absent(),
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
    Expression<String>? expenseDate,
    Expression<String>? versionHash,
    Expression<String>? linkAuthor,
    Expression<String>? payersJson,
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
      if (expenseDate != null) 'expense_date': expenseDate,
      if (versionHash != null) 'version_hash': versionHash,
      if (linkAuthor != null) 'link_author': linkAuthor,
      if (payersJson != null) 'payers_json': payersJson,
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
    Value<String?>? expenseDate,
    Value<String?>? versionHash,
    Value<String?>? linkAuthor,
    Value<String?>? payersJson,
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
      expenseDate: expenseDate ?? this.expenseDate,
      versionHash: versionHash ?? this.versionHash,
      linkAuthor: linkAuthor ?? this.linkAuthor,
      payersJson: payersJson ?? this.payersJson,
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
    if (expenseDate.present) {
      map['expense_date'] = Variable<String>(expenseDate.value);
    }
    if (versionHash.present) {
      map['version_hash'] = Variable<String>(versionHash.value);
    }
    if (linkAuthor.present) {
      map['link_author'] = Variable<String>(linkAuthor.value);
    }
    if (payersJson.present) {
      map['payers_json'] = Variable<String>(payersJson.value);
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
          ..write('expenseDate: $expenseDate, ')
          ..write('versionHash: $versionHash, ')
          ..write('linkAuthor: $linkAuthor, ')
          ..write('payersJson: $payersJson, ')
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
  static const VerificationMeta _settlementDateMeta = const VerificationMeta(
    'settlementDate',
  );
  @override
  late final GeneratedColumn<String> settlementDate = GeneratedColumn<String>(
    'settlement_date',
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
  static const VerificationMeta _linkAuthorMeta = const VerificationMeta(
    'linkAuthor',
  );
  @override
  late final GeneratedColumn<String> linkAuthor = GeneratedColumn<String>(
    'link_author',
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
    settlementDate,
    versionHash,
    linkAuthor,
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
    if (data.containsKey('settlement_date')) {
      context.handle(
        _settlementDateMeta,
        settlementDate.isAcceptableOrUnknown(
          data['settlement_date']!,
          _settlementDateMeta,
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
    if (data.containsKey('link_author')) {
      context.handle(
        _linkAuthorMeta,
        linkAuthor.isAcceptableOrUnknown(data['link_author']!, _linkAuthorMeta),
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
      settlementDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}settlement_date'],
      ),
      versionHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_hash'],
      ),
      linkAuthor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_author'],
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
  final String? settlementDate;
  final String? versionHash;
  final String? linkAuthor;
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
    this.settlementDate,
    this.versionHash,
    this.linkAuthor,
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
    if (!nullToAbsent || settlementDate != null) {
      map['settlement_date'] = Variable<String>(settlementDate);
    }
    if (!nullToAbsent || versionHash != null) {
      map['version_hash'] = Variable<String>(versionHash);
    }
    if (!nullToAbsent || linkAuthor != null) {
      map['link_author'] = Variable<String>(linkAuthor);
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
      settlementDate: settlementDate == null && nullToAbsent
          ? const Value.absent()
          : Value(settlementDate),
      versionHash: versionHash == null && nullToAbsent
          ? const Value.absent()
          : Value(versionHash),
      linkAuthor: linkAuthor == null && nullToAbsent
          ? const Value.absent()
          : Value(linkAuthor),
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
      settlementDate: serializer.fromJson<String?>(json['settlementDate']),
      versionHash: serializer.fromJson<String?>(json['versionHash']),
      linkAuthor: serializer.fromJson<String?>(json['linkAuthor']),
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
      'settlementDate': serializer.toJson<String?>(settlementDate),
      'versionHash': serializer.toJson<String?>(versionHash),
      'linkAuthor': serializer.toJson<String?>(linkAuthor),
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
    Value<String?> settlementDate = const Value.absent(),
    Value<String?> versionHash = const Value.absent(),
    Value<String?> linkAuthor = const Value.absent(),
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
    settlementDate: settlementDate.present
        ? settlementDate.value
        : this.settlementDate,
    versionHash: versionHash.present ? versionHash.value : this.versionHash,
    linkAuthor: linkAuthor.present ? linkAuthor.value : this.linkAuthor,
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
      settlementDate: data.settlementDate.present
          ? data.settlementDate.value
          : this.settlementDate,
      versionHash: data.versionHash.present
          ? data.versionHash.value
          : this.versionHash,
      linkAuthor: data.linkAuthor.present
          ? data.linkAuthor.value
          : this.linkAuthor,
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
          ..write('settlementDate: $settlementDate, ')
          ..write('versionHash: $versionHash, ')
          ..write('linkAuthor: $linkAuthor')
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
    settlementDate,
    versionHash,
    linkAuthor,
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
          other.settlementDate == this.settlementDate &&
          other.versionHash == this.versionHash &&
          other.linkAuthor == this.linkAuthor);
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
  final Value<String?> settlementDate;
  final Value<String?> versionHash;
  final Value<String?> linkAuthor;
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
    this.settlementDate = const Value.absent(),
    this.versionHash = const Value.absent(),
    this.linkAuthor = const Value.absent(),
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
    this.settlementDate = const Value.absent(),
    this.versionHash = const Value.absent(),
    this.linkAuthor = const Value.absent(),
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
    Expression<String>? settlementDate,
    Expression<String>? versionHash,
    Expression<String>? linkAuthor,
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
      if (settlementDate != null) 'settlement_date': settlementDate,
      if (versionHash != null) 'version_hash': versionHash,
      if (linkAuthor != null) 'link_author': linkAuthor,
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
    Value<String?>? settlementDate,
    Value<String?>? versionHash,
    Value<String?>? linkAuthor,
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
      settlementDate: settlementDate ?? this.settlementDate,
      versionHash: versionHash ?? this.versionHash,
      linkAuthor: linkAuthor ?? this.linkAuthor,
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
    if (settlementDate.present) {
      map['settlement_date'] = Variable<String>(settlementDate.value);
    }
    if (versionHash.present) {
      map['version_hash'] = Variable<String>(versionHash.value);
    }
    if (linkAuthor.present) {
      map['link_author'] = Variable<String>(linkAuthor.value);
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
          ..write('settlementDate: $settlementDate, ')
          ..write('versionHash: $versionHash, ')
          ..write('linkAuthor: $linkAuthor, ')
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
  static const VerificationMeta _linkAuthorMeta = const VerificationMeta(
    'linkAuthor',
  );
  @override
  late final GeneratedColumn<String> linkAuthor = GeneratedColumn<String>(
    'link_author',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paymentJsonMeta = const VerificationMeta(
    'paymentJson',
  );
  @override
  late final GeneratedColumn<String> paymentJson = GeneratedColumn<String>(
    'payment_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
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
    linkAuthor,
    paymentJson,
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
    if (data.containsKey('link_author')) {
      context.handle(
        _linkAuthorMeta,
        linkAuthor.isAcceptableOrUnknown(data['link_author']!, _linkAuthorMeta),
      );
    }
    if (data.containsKey('payment_json')) {
      context.handle(
        _paymentJsonMeta,
        paymentJson.isAcceptableOrUnknown(
          data['payment_json']!,
          _paymentJsonMeta,
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
      linkAuthor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_author'],
      ),
      paymentJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payment_json'],
      ),
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
  final String? linkAuthor;
  final String? paymentJson;
  const Member({
    required this.groupId,
    required this.userId,
    required this.displayName,
    this.matrixId,
    required this.status,
    required this.updatedAt,
    this.sig,
    required this.pendingSign,
    this.linkAuthor,
    this.paymentJson,
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
    if (!nullToAbsent || linkAuthor != null) {
      map['link_author'] = Variable<String>(linkAuthor);
    }
    if (!nullToAbsent || paymentJson != null) {
      map['payment_json'] = Variable<String>(paymentJson);
    }
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
      linkAuthor: linkAuthor == null && nullToAbsent
          ? const Value.absent()
          : Value(linkAuthor),
      paymentJson: paymentJson == null && nullToAbsent
          ? const Value.absent()
          : Value(paymentJson),
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
      linkAuthor: serializer.fromJson<String?>(json['linkAuthor']),
      paymentJson: serializer.fromJson<String?>(json['paymentJson']),
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
      'linkAuthor': serializer.toJson<String?>(linkAuthor),
      'paymentJson': serializer.toJson<String?>(paymentJson),
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
    Value<String?> linkAuthor = const Value.absent(),
    Value<String?> paymentJson = const Value.absent(),
  }) => Member(
    groupId: groupId ?? this.groupId,
    userId: userId ?? this.userId,
    displayName: displayName ?? this.displayName,
    matrixId: matrixId.present ? matrixId.value : this.matrixId,
    status: status ?? this.status,
    updatedAt: updatedAt ?? this.updatedAt,
    sig: sig.present ? sig.value : this.sig,
    pendingSign: pendingSign ?? this.pendingSign,
    linkAuthor: linkAuthor.present ? linkAuthor.value : this.linkAuthor,
    paymentJson: paymentJson.present ? paymentJson.value : this.paymentJson,
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
      linkAuthor: data.linkAuthor.present
          ? data.linkAuthor.value
          : this.linkAuthor,
      paymentJson: data.paymentJson.present
          ? data.paymentJson.value
          : this.paymentJson,
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
          ..write('pendingSign: $pendingSign, ')
          ..write('linkAuthor: $linkAuthor, ')
          ..write('paymentJson: $paymentJson')
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
    linkAuthor,
    paymentJson,
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
          other.pendingSign == this.pendingSign &&
          other.linkAuthor == this.linkAuthor &&
          other.paymentJson == this.paymentJson);
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
  final Value<String?> linkAuthor;
  final Value<String?> paymentJson;
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
    this.linkAuthor = const Value.absent(),
    this.paymentJson = const Value.absent(),
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
    this.linkAuthor = const Value.absent(),
    this.paymentJson = const Value.absent(),
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
    Expression<String>? linkAuthor,
    Expression<String>? paymentJson,
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
      if (linkAuthor != null) 'link_author': linkAuthor,
      if (paymentJson != null) 'payment_json': paymentJson,
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
    Value<String?>? linkAuthor,
    Value<String?>? paymentJson,
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
      linkAuthor: linkAuthor ?? this.linkAuthor,
      paymentJson: paymentJson ?? this.paymentJson,
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
    if (linkAuthor.present) {
      map['link_author'] = Variable<String>(linkAuthor.value);
    }
    if (paymentJson.present) {
      map['payment_json'] = Variable<String>(paymentJson.value);
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
          ..write('linkAuthor: $linkAuthor, ')
          ..write('paymentJson: $paymentJson, ')
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

class $RecordHistoryTable extends RecordHistory
    with TableInfo<$RecordHistoryTable, HistoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecordHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
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
  static const VerificationMeta _versionHashMeta = const VerificationMeta(
    'versionHash',
  );
  @override
  late final GeneratedColumn<String> versionHash = GeneratedColumn<String>(
    'version_hash',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _contentMeta = const VerificationMeta(
    'content',
  );
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
    'content',
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
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<int> recordedAt = GeneratedColumn<int>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    groupId,
    kind,
    recordId,
    updatedAt,
    versionHash,
    content,
    source,
    recordedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'record_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<HistoryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
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
    if (data.containsKey('version_hash')) {
      context.handle(
        _versionHashMeta,
        versionHash.isAcceptableOrUnknown(
          data['version_hash']!,
          _versionHashMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_versionHashMeta);
    }
    if (data.containsKey('content')) {
      context.handle(
        _contentMeta,
        content.isAcceptableOrUnknown(data['content']!, _contentMeta),
      );
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HistoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HistoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
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
      versionHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}version_hash'],
      )!,
      content: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recorded_at'],
      )!,
    );
  }

  @override
  $RecordHistoryTable createAlias(String alias) {
    return $RecordHistoryTable(attachedDatabase, alias);
  }
}

class HistoryRow extends DataClass implements Insertable<HistoryRow> {
  final int id;
  final String groupId;
  final String kind;
  final String recordId;
  final int updatedAt;
  final String versionHash;
  final String content;
  final String source;
  final int recordedAt;
  const HistoryRow({
    required this.id,
    required this.groupId,
    required this.kind,
    required this.recordId,
    required this.updatedAt,
    required this.versionHash,
    required this.content,
    required this.source,
    required this.recordedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['group_id'] = Variable<String>(groupId);
    map['kind'] = Variable<String>(kind);
    map['record_id'] = Variable<String>(recordId);
    map['updated_at'] = Variable<int>(updatedAt);
    map['version_hash'] = Variable<String>(versionHash);
    map['content'] = Variable<String>(content);
    map['source'] = Variable<String>(source);
    map['recorded_at'] = Variable<int>(recordedAt);
    return map;
  }

  RecordHistoryCompanion toCompanion(bool nullToAbsent) {
    return RecordHistoryCompanion(
      id: Value(id),
      groupId: Value(groupId),
      kind: Value(kind),
      recordId: Value(recordId),
      updatedAt: Value(updatedAt),
      versionHash: Value(versionHash),
      content: Value(content),
      source: Value(source),
      recordedAt: Value(recordedAt),
    );
  }

  factory HistoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HistoryRow(
      id: serializer.fromJson<int>(json['id']),
      groupId: serializer.fromJson<String>(json['groupId']),
      kind: serializer.fromJson<String>(json['kind']),
      recordId: serializer.fromJson<String>(json['recordId']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
      versionHash: serializer.fromJson<String>(json['versionHash']),
      content: serializer.fromJson<String>(json['content']),
      source: serializer.fromJson<String>(json['source']),
      recordedAt: serializer.fromJson<int>(json['recordedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'groupId': serializer.toJson<String>(groupId),
      'kind': serializer.toJson<String>(kind),
      'recordId': serializer.toJson<String>(recordId),
      'updatedAt': serializer.toJson<int>(updatedAt),
      'versionHash': serializer.toJson<String>(versionHash),
      'content': serializer.toJson<String>(content),
      'source': serializer.toJson<String>(source),
      'recordedAt': serializer.toJson<int>(recordedAt),
    };
  }

  HistoryRow copyWith({
    int? id,
    String? groupId,
    String? kind,
    String? recordId,
    int? updatedAt,
    String? versionHash,
    String? content,
    String? source,
    int? recordedAt,
  }) => HistoryRow(
    id: id ?? this.id,
    groupId: groupId ?? this.groupId,
    kind: kind ?? this.kind,
    recordId: recordId ?? this.recordId,
    updatedAt: updatedAt ?? this.updatedAt,
    versionHash: versionHash ?? this.versionHash,
    content: content ?? this.content,
    source: source ?? this.source,
    recordedAt: recordedAt ?? this.recordedAt,
  );
  HistoryRow copyWithCompanion(RecordHistoryCompanion data) {
    return HistoryRow(
      id: data.id.present ? data.id.value : this.id,
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      kind: data.kind.present ? data.kind.value : this.kind,
      recordId: data.recordId.present ? data.recordId.value : this.recordId,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      versionHash: data.versionHash.present
          ? data.versionHash.value
          : this.versionHash,
      content: data.content.present ? data.content.value : this.content,
      source: data.source.present ? data.source.value : this.source,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HistoryRow(')
          ..write('id: $id, ')
          ..write('groupId: $groupId, ')
          ..write('kind: $kind, ')
          ..write('recordId: $recordId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('versionHash: $versionHash, ')
          ..write('content: $content, ')
          ..write('source: $source, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    groupId,
    kind,
    recordId,
    updatedAt,
    versionHash,
    content,
    source,
    recordedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HistoryRow &&
          other.id == this.id &&
          other.groupId == this.groupId &&
          other.kind == this.kind &&
          other.recordId == this.recordId &&
          other.updatedAt == this.updatedAt &&
          other.versionHash == this.versionHash &&
          other.content == this.content &&
          other.source == this.source &&
          other.recordedAt == this.recordedAt);
}

class RecordHistoryCompanion extends UpdateCompanion<HistoryRow> {
  final Value<int> id;
  final Value<String> groupId;
  final Value<String> kind;
  final Value<String> recordId;
  final Value<int> updatedAt;
  final Value<String> versionHash;
  final Value<String> content;
  final Value<String> source;
  final Value<int> recordedAt;
  const RecordHistoryCompanion({
    this.id = const Value.absent(),
    this.groupId = const Value.absent(),
    this.kind = const Value.absent(),
    this.recordId = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.versionHash = const Value.absent(),
    this.content = const Value.absent(),
    this.source = const Value.absent(),
    this.recordedAt = const Value.absent(),
  });
  RecordHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String groupId,
    required String kind,
    required String recordId,
    required int updatedAt,
    required String versionHash,
    required String content,
    required String source,
    required int recordedAt,
  }) : groupId = Value(groupId),
       kind = Value(kind),
       recordId = Value(recordId),
       updatedAt = Value(updatedAt),
       versionHash = Value(versionHash),
       content = Value(content),
       source = Value(source),
       recordedAt = Value(recordedAt);
  static Insertable<HistoryRow> custom({
    Expression<int>? id,
    Expression<String>? groupId,
    Expression<String>? kind,
    Expression<String>? recordId,
    Expression<int>? updatedAt,
    Expression<String>? versionHash,
    Expression<String>? content,
    Expression<String>? source,
    Expression<int>? recordedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (groupId != null) 'group_id': groupId,
      if (kind != null) 'kind': kind,
      if (recordId != null) 'record_id': recordId,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (versionHash != null) 'version_hash': versionHash,
      if (content != null) 'content': content,
      if (source != null) 'source': source,
      if (recordedAt != null) 'recorded_at': recordedAt,
    });
  }

  RecordHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? groupId,
    Value<String>? kind,
    Value<String>? recordId,
    Value<int>? updatedAt,
    Value<String>? versionHash,
    Value<String>? content,
    Value<String>? source,
    Value<int>? recordedAt,
  }) {
    return RecordHistoryCompanion(
      id: id ?? this.id,
      groupId: groupId ?? this.groupId,
      kind: kind ?? this.kind,
      recordId: recordId ?? this.recordId,
      updatedAt: updatedAt ?? this.updatedAt,
      versionHash: versionHash ?? this.versionHash,
      content: content ?? this.content,
      source: source ?? this.source,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
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
    if (versionHash.present) {
      map['version_hash'] = Variable<String>(versionHash.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<int>(recordedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecordHistoryCompanion(')
          ..write('id: $id, ')
          ..write('groupId: $groupId, ')
          ..write('kind: $kind, ')
          ..write('recordId: $recordId, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('versionHash: $versionHash, ')
          ..write('content: $content, ')
          ..write('source: $source, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }
}

class $LinkChannelsTable extends LinkChannels
    with TableInfo<$LinkChannelsTable, LinkChannel> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LinkChannelsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _epochMeta = const VerificationMeta('epoch');
  @override
  late final GeneratedColumn<int> epoch = GeneratedColumn<int>(
    'epoch',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _secretMeta = const VerificationMeta('secret');
  @override
  late final GeneratedColumn<String> secret = GeneratedColumn<String>(
    'secret',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _myParticipantIdMeta = const VerificationMeta(
    'myParticipantId',
  );
  @override
  late final GeneratedColumn<String> myParticipantId = GeneratedColumn<String>(
    'my_participant_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _nostrPrivMeta = const VerificationMeta(
    'nostrPriv',
  );
  @override
  late final GeneratedColumn<String> nostrPriv = GeneratedColumn<String>(
    'nostr_priv',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastPublishedHashMeta = const VerificationMeta(
    'lastPublishedHash',
  );
  @override
  late final GeneratedColumn<String> lastPublishedHash =
      GeneratedColumn<String>(
        'last_published_hash',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _lastPublishedAtMeta = const VerificationMeta(
    'lastPublishedAt',
  );
  @override
  late final GeneratedColumn<int> lastPublishedAt = GeneratedColumn<int>(
    'last_published_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastCreatedAtMeta = const VerificationMeta(
    'lastCreatedAt',
  );
  @override
  late final GeneratedColumn<int> lastCreatedAt = GeneratedColumn<int>(
    'last_created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _partsMeta = const VerificationMeta('parts');
  @override
  late final GeneratedColumn<int> parts = GeneratedColumn<int>(
    'parts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _openedAtMeta = const VerificationMeta(
    'openedAt',
  );
  @override
  late final GeneratedColumn<int> openedAt = GeneratedColumn<int>(
    'opened_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    epoch,
    secret,
    myParticipantId,
    nostrPriv,
    lastPublishedHash,
    lastPublishedAt,
    lastCreatedAt,
    parts,
    openedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'link_channels';
  @override
  VerificationContext validateIntegrity(
    Insertable<LinkChannel> instance, {
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
    if (data.containsKey('epoch')) {
      context.handle(
        _epochMeta,
        epoch.isAcceptableOrUnknown(data['epoch']!, _epochMeta),
      );
    } else if (isInserting) {
      context.missing(_epochMeta);
    }
    if (data.containsKey('secret')) {
      context.handle(
        _secretMeta,
        secret.isAcceptableOrUnknown(data['secret']!, _secretMeta),
      );
    } else if (isInserting) {
      context.missing(_secretMeta);
    }
    if (data.containsKey('my_participant_id')) {
      context.handle(
        _myParticipantIdMeta,
        myParticipantId.isAcceptableOrUnknown(
          data['my_participant_id']!,
          _myParticipantIdMeta,
        ),
      );
    }
    if (data.containsKey('nostr_priv')) {
      context.handle(
        _nostrPrivMeta,
        nostrPriv.isAcceptableOrUnknown(data['nostr_priv']!, _nostrPrivMeta),
      );
    } else if (isInserting) {
      context.missing(_nostrPrivMeta);
    }
    if (data.containsKey('last_published_hash')) {
      context.handle(
        _lastPublishedHashMeta,
        lastPublishedHash.isAcceptableOrUnknown(
          data['last_published_hash']!,
          _lastPublishedHashMeta,
        ),
      );
    }
    if (data.containsKey('last_published_at')) {
      context.handle(
        _lastPublishedAtMeta,
        lastPublishedAt.isAcceptableOrUnknown(
          data['last_published_at']!,
          _lastPublishedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_created_at')) {
      context.handle(
        _lastCreatedAtMeta,
        lastCreatedAt.isAcceptableOrUnknown(
          data['last_created_at']!,
          _lastCreatedAtMeta,
        ),
      );
    }
    if (data.containsKey('parts')) {
      context.handle(
        _partsMeta,
        parts.isAcceptableOrUnknown(data['parts']!, _partsMeta),
      );
    }
    if (data.containsKey('opened_at')) {
      context.handle(
        _openedAtMeta,
        openedAt.isAcceptableOrUnknown(data['opened_at']!, _openedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_openedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId};
  @override
  LinkChannel map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LinkChannel(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      epoch: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}epoch'],
      )!,
      secret: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}secret'],
      )!,
      myParticipantId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}my_participant_id'],
      ),
      nostrPriv: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}nostr_priv'],
      )!,
      lastPublishedHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_published_hash'],
      ),
      lastPublishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_published_at'],
      )!,
      lastCreatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_created_at'],
      )!,
      parts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}parts'],
      )!,
      openedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}opened_at'],
      )!,
    );
  }

  @override
  $LinkChannelsTable createAlias(String alias) {
    return $LinkChannelsTable(attachedDatabase, alias);
  }
}

class LinkChannel extends DataClass implements Insertable<LinkChannel> {
  final String groupId;

  /// Key epoch of [secret] (a *Reset invite link* starts a new one).
  final int epoch;

  /// The link secret (32 bytes, base64url without padding — the link's `k`):
  /// a cache of the meta's `link.secret` for [epoch].
  final String secret;

  /// Who this device is in the group ("Which participant are you?"); NULL
  /// until picked. Device-local — never a synced claim (§6.1).
  final String? myParticipantId;

  /// This device's secp256k1 Nostr private key for this group (64 hex
  /// chars) — random per (device, group), not derived from [secret] (§3.1).
  final String nostrPriv;

  /// Change detection: digest of the snapshot we last published (NULL =
  /// nothing published yet).
  final String? lastPublishedHash;

  /// When we last published (ms epoch, our clock; 0 = never) — drives the
  /// 10-day refresh.
  final int lastPublishedAt;

  /// The Nostr `created_at` (**seconds**) of our latest event — kept
  /// strictly increasing per (pubkey, d) (§4.5; 0 = none yet).
  final int lastCreatedAt;

  /// How many parts our last snapshot was sharded into (1, 2, 4 or 8, §5.4)
  /// — needed to retire parts when the count shrinks.
  final int parts;

  /// When this device opened / joined the channel (ms epoch).
  final int openedAt;
  const LinkChannel({
    required this.groupId,
    required this.epoch,
    required this.secret,
    this.myParticipantId,
    required this.nostrPriv,
    this.lastPublishedHash,
    required this.lastPublishedAt,
    required this.lastCreatedAt,
    required this.parts,
    required this.openedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['epoch'] = Variable<int>(epoch);
    map['secret'] = Variable<String>(secret);
    if (!nullToAbsent || myParticipantId != null) {
      map['my_participant_id'] = Variable<String>(myParticipantId);
    }
    map['nostr_priv'] = Variable<String>(nostrPriv);
    if (!nullToAbsent || lastPublishedHash != null) {
      map['last_published_hash'] = Variable<String>(lastPublishedHash);
    }
    map['last_published_at'] = Variable<int>(lastPublishedAt);
    map['last_created_at'] = Variable<int>(lastCreatedAt);
    map['parts'] = Variable<int>(parts);
    map['opened_at'] = Variable<int>(openedAt);
    return map;
  }

  LinkChannelsCompanion toCompanion(bool nullToAbsent) {
    return LinkChannelsCompanion(
      groupId: Value(groupId),
      epoch: Value(epoch),
      secret: Value(secret),
      myParticipantId: myParticipantId == null && nullToAbsent
          ? const Value.absent()
          : Value(myParticipantId),
      nostrPriv: Value(nostrPriv),
      lastPublishedHash: lastPublishedHash == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPublishedHash),
      lastPublishedAt: Value(lastPublishedAt),
      lastCreatedAt: Value(lastCreatedAt),
      parts: Value(parts),
      openedAt: Value(openedAt),
    );
  }

  factory LinkChannel.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LinkChannel(
      groupId: serializer.fromJson<String>(json['groupId']),
      epoch: serializer.fromJson<int>(json['epoch']),
      secret: serializer.fromJson<String>(json['secret']),
      myParticipantId: serializer.fromJson<String?>(json['myParticipantId']),
      nostrPriv: serializer.fromJson<String>(json['nostrPriv']),
      lastPublishedHash: serializer.fromJson<String?>(
        json['lastPublishedHash'],
      ),
      lastPublishedAt: serializer.fromJson<int>(json['lastPublishedAt']),
      lastCreatedAt: serializer.fromJson<int>(json['lastCreatedAt']),
      parts: serializer.fromJson<int>(json['parts']),
      openedAt: serializer.fromJson<int>(json['openedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'epoch': serializer.toJson<int>(epoch),
      'secret': serializer.toJson<String>(secret),
      'myParticipantId': serializer.toJson<String?>(myParticipantId),
      'nostrPriv': serializer.toJson<String>(nostrPriv),
      'lastPublishedHash': serializer.toJson<String?>(lastPublishedHash),
      'lastPublishedAt': serializer.toJson<int>(lastPublishedAt),
      'lastCreatedAt': serializer.toJson<int>(lastCreatedAt),
      'parts': serializer.toJson<int>(parts),
      'openedAt': serializer.toJson<int>(openedAt),
    };
  }

  LinkChannel copyWith({
    String? groupId,
    int? epoch,
    String? secret,
    Value<String?> myParticipantId = const Value.absent(),
    String? nostrPriv,
    Value<String?> lastPublishedHash = const Value.absent(),
    int? lastPublishedAt,
    int? lastCreatedAt,
    int? parts,
    int? openedAt,
  }) => LinkChannel(
    groupId: groupId ?? this.groupId,
    epoch: epoch ?? this.epoch,
    secret: secret ?? this.secret,
    myParticipantId: myParticipantId.present
        ? myParticipantId.value
        : this.myParticipantId,
    nostrPriv: nostrPriv ?? this.nostrPriv,
    lastPublishedHash: lastPublishedHash.present
        ? lastPublishedHash.value
        : this.lastPublishedHash,
    lastPublishedAt: lastPublishedAt ?? this.lastPublishedAt,
    lastCreatedAt: lastCreatedAt ?? this.lastCreatedAt,
    parts: parts ?? this.parts,
    openedAt: openedAt ?? this.openedAt,
  );
  LinkChannel copyWithCompanion(LinkChannelsCompanion data) {
    return LinkChannel(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      epoch: data.epoch.present ? data.epoch.value : this.epoch,
      secret: data.secret.present ? data.secret.value : this.secret,
      myParticipantId: data.myParticipantId.present
          ? data.myParticipantId.value
          : this.myParticipantId,
      nostrPriv: data.nostrPriv.present ? data.nostrPriv.value : this.nostrPriv,
      lastPublishedHash: data.lastPublishedHash.present
          ? data.lastPublishedHash.value
          : this.lastPublishedHash,
      lastPublishedAt: data.lastPublishedAt.present
          ? data.lastPublishedAt.value
          : this.lastPublishedAt,
      lastCreatedAt: data.lastCreatedAt.present
          ? data.lastCreatedAt.value
          : this.lastCreatedAt,
      parts: data.parts.present ? data.parts.value : this.parts,
      openedAt: data.openedAt.present ? data.openedAt.value : this.openedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LinkChannel(')
          ..write('groupId: $groupId, ')
          ..write('epoch: $epoch, ')
          ..write('secret: $secret, ')
          ..write('myParticipantId: $myParticipantId, ')
          ..write('nostrPriv: $nostrPriv, ')
          ..write('lastPublishedHash: $lastPublishedHash, ')
          ..write('lastPublishedAt: $lastPublishedAt, ')
          ..write('lastCreatedAt: $lastCreatedAt, ')
          ..write('parts: $parts, ')
          ..write('openedAt: $openedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    epoch,
    secret,
    myParticipantId,
    nostrPriv,
    lastPublishedHash,
    lastPublishedAt,
    lastCreatedAt,
    parts,
    openedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LinkChannel &&
          other.groupId == this.groupId &&
          other.epoch == this.epoch &&
          other.secret == this.secret &&
          other.myParticipantId == this.myParticipantId &&
          other.nostrPriv == this.nostrPriv &&
          other.lastPublishedHash == this.lastPublishedHash &&
          other.lastPublishedAt == this.lastPublishedAt &&
          other.lastCreatedAt == this.lastCreatedAt &&
          other.parts == this.parts &&
          other.openedAt == this.openedAt);
}

class LinkChannelsCompanion extends UpdateCompanion<LinkChannel> {
  final Value<String> groupId;
  final Value<int> epoch;
  final Value<String> secret;
  final Value<String?> myParticipantId;
  final Value<String> nostrPriv;
  final Value<String?> lastPublishedHash;
  final Value<int> lastPublishedAt;
  final Value<int> lastCreatedAt;
  final Value<int> parts;
  final Value<int> openedAt;
  final Value<int> rowid;
  const LinkChannelsCompanion({
    this.groupId = const Value.absent(),
    this.epoch = const Value.absent(),
    this.secret = const Value.absent(),
    this.myParticipantId = const Value.absent(),
    this.nostrPriv = const Value.absent(),
    this.lastPublishedHash = const Value.absent(),
    this.lastPublishedAt = const Value.absent(),
    this.lastCreatedAt = const Value.absent(),
    this.parts = const Value.absent(),
    this.openedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LinkChannelsCompanion.insert({
    required String groupId,
    required int epoch,
    required String secret,
    this.myParticipantId = const Value.absent(),
    required String nostrPriv,
    this.lastPublishedHash = const Value.absent(),
    this.lastPublishedAt = const Value.absent(),
    this.lastCreatedAt = const Value.absent(),
    this.parts = const Value.absent(),
    required int openedAt,
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       epoch = Value(epoch),
       secret = Value(secret),
       nostrPriv = Value(nostrPriv),
       openedAt = Value(openedAt);
  static Insertable<LinkChannel> custom({
    Expression<String>? groupId,
    Expression<int>? epoch,
    Expression<String>? secret,
    Expression<String>? myParticipantId,
    Expression<String>? nostrPriv,
    Expression<String>? lastPublishedHash,
    Expression<int>? lastPublishedAt,
    Expression<int>? lastCreatedAt,
    Expression<int>? parts,
    Expression<int>? openedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (epoch != null) 'epoch': epoch,
      if (secret != null) 'secret': secret,
      if (myParticipantId != null) 'my_participant_id': myParticipantId,
      if (nostrPriv != null) 'nostr_priv': nostrPriv,
      if (lastPublishedHash != null) 'last_published_hash': lastPublishedHash,
      if (lastPublishedAt != null) 'last_published_at': lastPublishedAt,
      if (lastCreatedAt != null) 'last_created_at': lastCreatedAt,
      if (parts != null) 'parts': parts,
      if (openedAt != null) 'opened_at': openedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LinkChannelsCompanion copyWith({
    Value<String>? groupId,
    Value<int>? epoch,
    Value<String>? secret,
    Value<String?>? myParticipantId,
    Value<String>? nostrPriv,
    Value<String?>? lastPublishedHash,
    Value<int>? lastPublishedAt,
    Value<int>? lastCreatedAt,
    Value<int>? parts,
    Value<int>? openedAt,
    Value<int>? rowid,
  }) {
    return LinkChannelsCompanion(
      groupId: groupId ?? this.groupId,
      epoch: epoch ?? this.epoch,
      secret: secret ?? this.secret,
      myParticipantId: myParticipantId ?? this.myParticipantId,
      nostrPriv: nostrPriv ?? this.nostrPriv,
      lastPublishedHash: lastPublishedHash ?? this.lastPublishedHash,
      lastPublishedAt: lastPublishedAt ?? this.lastPublishedAt,
      lastCreatedAt: lastCreatedAt ?? this.lastCreatedAt,
      parts: parts ?? this.parts,
      openedAt: openedAt ?? this.openedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (epoch.present) {
      map['epoch'] = Variable<int>(epoch.value);
    }
    if (secret.present) {
      map['secret'] = Variable<String>(secret.value);
    }
    if (myParticipantId.present) {
      map['my_participant_id'] = Variable<String>(myParticipantId.value);
    }
    if (nostrPriv.present) {
      map['nostr_priv'] = Variable<String>(nostrPriv.value);
    }
    if (lastPublishedHash.present) {
      map['last_published_hash'] = Variable<String>(lastPublishedHash.value);
    }
    if (lastPublishedAt.present) {
      map['last_published_at'] = Variable<int>(lastPublishedAt.value);
    }
    if (lastCreatedAt.present) {
      map['last_created_at'] = Variable<int>(lastCreatedAt.value);
    }
    if (parts.present) {
      map['parts'] = Variable<int>(parts.value);
    }
    if (openedAt.present) {
      map['opened_at'] = Variable<int>(openedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LinkChannelsCompanion(')
          ..write('groupId: $groupId, ')
          ..write('epoch: $epoch, ')
          ..write('secret: $secret, ')
          ..write('myParticipantId: $myParticipantId, ')
          ..write('nostrPriv: $nostrPriv, ')
          ..write('lastPublishedHash: $lastPublishedHash, ')
          ..write('lastPublishedAt: $lastPublishedAt, ')
          ..write('lastCreatedAt: $lastCreatedAt, ')
          ..write('parts: $parts, ')
          ..write('openedAt: $openedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LinkPeersTable extends LinkPeers
    with TableInfo<$LinkPeersTable, LinkPeer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LinkPeersTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _pubkeyMeta = const VerificationMeta('pubkey');
  @override
  late final GeneratedColumn<String> pubkey = GeneratedColumn<String>(
    'pubkey',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _meMeta = const VerificationMeta('me');
  @override
  late final GeneratedColumn<String> me = GeneratedColumn<String>(
    'me',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _eventIdsJsonMeta = const VerificationMeta(
    'eventIdsJson',
  );
  @override
  late final GeneratedColumn<String> eventIdsJson = GeneratedColumn<String>(
    'event_ids_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _lastCreatedAtMeta = const VerificationMeta(
    'lastCreatedAt',
  );
  @override
  late final GeneratedColumn<int> lastCreatedAt = GeneratedColumn<int>(
    'last_created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<int> lastSeenAt = GeneratedColumn<int>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _snapshotDigestMeta = const VerificationMeta(
    'snapshotDigest',
  );
  @override
  late final GeneratedColumn<String> snapshotDigest = GeneratedColumn<String>(
    'snapshot_digest',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    groupId,
    pubkey,
    me,
    eventIdsJson,
    lastCreatedAt,
    lastSeenAt,
    snapshotDigest,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'link_peers';
  @override
  VerificationContext validateIntegrity(
    Insertable<LinkPeer> instance, {
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
    if (data.containsKey('pubkey')) {
      context.handle(
        _pubkeyMeta,
        pubkey.isAcceptableOrUnknown(data['pubkey']!, _pubkeyMeta),
      );
    } else if (isInserting) {
      context.missing(_pubkeyMeta);
    }
    if (data.containsKey('me')) {
      context.handle(_meMeta, me.isAcceptableOrUnknown(data['me']!, _meMeta));
    }
    if (data.containsKey('event_ids_json')) {
      context.handle(
        _eventIdsJsonMeta,
        eventIdsJson.isAcceptableOrUnknown(
          data['event_ids_json']!,
          _eventIdsJsonMeta,
        ),
      );
    }
    if (data.containsKey('last_created_at')) {
      context.handle(
        _lastCreatedAtMeta,
        lastCreatedAt.isAcceptableOrUnknown(
          data['last_created_at']!,
          _lastCreatedAtMeta,
        ),
      );
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('snapshot_digest')) {
      context.handle(
        _snapshotDigestMeta,
        snapshotDigest.isAcceptableOrUnknown(
          data['snapshot_digest']!,
          _snapshotDigestMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {groupId, pubkey};
  @override
  LinkPeer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LinkPeer(
      groupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_id'],
      )!,
      pubkey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pubkey'],
      )!,
      me: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}me'],
      ),
      eventIdsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}event_ids_json'],
      )!,
      lastCreatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_created_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen_at'],
      )!,
      snapshotDigest: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot_digest'],
      ),
    );
  }

  @override
  $LinkPeersTable createAlias(String alias) {
    return $LinkPeersTable(attachedDatabase, alias);
  }
}

class LinkPeer extends DataClass implements Insertable<LinkPeer> {
  final String groupId;

  /// The publisher's Nostr pubkey (x-only, 64 hex chars).
  final String pubkey;

  /// The participant the publisher's latest event names as its `me` — a
  /// hint only ("used on another phone"); NULL = none.
  final String? me;

  /// The id of the latest event processed **per part** (JSON object
  /// `{"<part index>": "<event id>"}`): a sharded snapshot is several
  /// events, each skipped before decrypting once seen.
  final String eventIdsJson;

  /// Newest Nostr `created_at` (seconds) seen from this publisher (any part)
  /// — the base of the live subscription's `since`.
  final int lastCreatedAt;

  /// When this device last received an event of it (ms epoch, our clock) —
  /// "Ben's phone last published …".
  final int lastSeenAt;

  /// Digest of the publisher's snapshot as last merged (to compare with
  /// ours: "Ben has everything", §5.3); NULL = unknown.
  final String? snapshotDigest;
  const LinkPeer({
    required this.groupId,
    required this.pubkey,
    this.me,
    required this.eventIdsJson,
    required this.lastCreatedAt,
    required this.lastSeenAt,
    this.snapshotDigest,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['group_id'] = Variable<String>(groupId);
    map['pubkey'] = Variable<String>(pubkey);
    if (!nullToAbsent || me != null) {
      map['me'] = Variable<String>(me);
    }
    map['event_ids_json'] = Variable<String>(eventIdsJson);
    map['last_created_at'] = Variable<int>(lastCreatedAt);
    map['last_seen_at'] = Variable<int>(lastSeenAt);
    if (!nullToAbsent || snapshotDigest != null) {
      map['snapshot_digest'] = Variable<String>(snapshotDigest);
    }
    return map;
  }

  LinkPeersCompanion toCompanion(bool nullToAbsent) {
    return LinkPeersCompanion(
      groupId: Value(groupId),
      pubkey: Value(pubkey),
      me: me == null && nullToAbsent ? const Value.absent() : Value(me),
      eventIdsJson: Value(eventIdsJson),
      lastCreatedAt: Value(lastCreatedAt),
      lastSeenAt: Value(lastSeenAt),
      snapshotDigest: snapshotDigest == null && nullToAbsent
          ? const Value.absent()
          : Value(snapshotDigest),
    );
  }

  factory LinkPeer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LinkPeer(
      groupId: serializer.fromJson<String>(json['groupId']),
      pubkey: serializer.fromJson<String>(json['pubkey']),
      me: serializer.fromJson<String?>(json['me']),
      eventIdsJson: serializer.fromJson<String>(json['eventIdsJson']),
      lastCreatedAt: serializer.fromJson<int>(json['lastCreatedAt']),
      lastSeenAt: serializer.fromJson<int>(json['lastSeenAt']),
      snapshotDigest: serializer.fromJson<String?>(json['snapshotDigest']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'groupId': serializer.toJson<String>(groupId),
      'pubkey': serializer.toJson<String>(pubkey),
      'me': serializer.toJson<String?>(me),
      'eventIdsJson': serializer.toJson<String>(eventIdsJson),
      'lastCreatedAt': serializer.toJson<int>(lastCreatedAt),
      'lastSeenAt': serializer.toJson<int>(lastSeenAt),
      'snapshotDigest': serializer.toJson<String?>(snapshotDigest),
    };
  }

  LinkPeer copyWith({
    String? groupId,
    String? pubkey,
    Value<String?> me = const Value.absent(),
    String? eventIdsJson,
    int? lastCreatedAt,
    int? lastSeenAt,
    Value<String?> snapshotDigest = const Value.absent(),
  }) => LinkPeer(
    groupId: groupId ?? this.groupId,
    pubkey: pubkey ?? this.pubkey,
    me: me.present ? me.value : this.me,
    eventIdsJson: eventIdsJson ?? this.eventIdsJson,
    lastCreatedAt: lastCreatedAt ?? this.lastCreatedAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    snapshotDigest: snapshotDigest.present
        ? snapshotDigest.value
        : this.snapshotDigest,
  );
  LinkPeer copyWithCompanion(LinkPeersCompanion data) {
    return LinkPeer(
      groupId: data.groupId.present ? data.groupId.value : this.groupId,
      pubkey: data.pubkey.present ? data.pubkey.value : this.pubkey,
      me: data.me.present ? data.me.value : this.me,
      eventIdsJson: data.eventIdsJson.present
          ? data.eventIdsJson.value
          : this.eventIdsJson,
      lastCreatedAt: data.lastCreatedAt.present
          ? data.lastCreatedAt.value
          : this.lastCreatedAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      snapshotDigest: data.snapshotDigest.present
          ? data.snapshotDigest.value
          : this.snapshotDigest,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LinkPeer(')
          ..write('groupId: $groupId, ')
          ..write('pubkey: $pubkey, ')
          ..write('me: $me, ')
          ..write('eventIdsJson: $eventIdsJson, ')
          ..write('lastCreatedAt: $lastCreatedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('snapshotDigest: $snapshotDigest')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    groupId,
    pubkey,
    me,
    eventIdsJson,
    lastCreatedAt,
    lastSeenAt,
    snapshotDigest,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LinkPeer &&
          other.groupId == this.groupId &&
          other.pubkey == this.pubkey &&
          other.me == this.me &&
          other.eventIdsJson == this.eventIdsJson &&
          other.lastCreatedAt == this.lastCreatedAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.snapshotDigest == this.snapshotDigest);
}

class LinkPeersCompanion extends UpdateCompanion<LinkPeer> {
  final Value<String> groupId;
  final Value<String> pubkey;
  final Value<String?> me;
  final Value<String> eventIdsJson;
  final Value<int> lastCreatedAt;
  final Value<int> lastSeenAt;
  final Value<String?> snapshotDigest;
  final Value<int> rowid;
  const LinkPeersCompanion({
    this.groupId = const Value.absent(),
    this.pubkey = const Value.absent(),
    this.me = const Value.absent(),
    this.eventIdsJson = const Value.absent(),
    this.lastCreatedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.snapshotDigest = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LinkPeersCompanion.insert({
    required String groupId,
    required String pubkey,
    this.me = const Value.absent(),
    this.eventIdsJson = const Value.absent(),
    this.lastCreatedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.snapshotDigest = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : groupId = Value(groupId),
       pubkey = Value(pubkey);
  static Insertable<LinkPeer> custom({
    Expression<String>? groupId,
    Expression<String>? pubkey,
    Expression<String>? me,
    Expression<String>? eventIdsJson,
    Expression<int>? lastCreatedAt,
    Expression<int>? lastSeenAt,
    Expression<String>? snapshotDigest,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (groupId != null) 'group_id': groupId,
      if (pubkey != null) 'pubkey': pubkey,
      if (me != null) 'me': me,
      if (eventIdsJson != null) 'event_ids_json': eventIdsJson,
      if (lastCreatedAt != null) 'last_created_at': lastCreatedAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (snapshotDigest != null) 'snapshot_digest': snapshotDigest,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LinkPeersCompanion copyWith({
    Value<String>? groupId,
    Value<String>? pubkey,
    Value<String?>? me,
    Value<String>? eventIdsJson,
    Value<int>? lastCreatedAt,
    Value<int>? lastSeenAt,
    Value<String?>? snapshotDigest,
    Value<int>? rowid,
  }) {
    return LinkPeersCompanion(
      groupId: groupId ?? this.groupId,
      pubkey: pubkey ?? this.pubkey,
      me: me ?? this.me,
      eventIdsJson: eventIdsJson ?? this.eventIdsJson,
      lastCreatedAt: lastCreatedAt ?? this.lastCreatedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      snapshotDigest: snapshotDigest ?? this.snapshotDigest,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (groupId.present) {
      map['group_id'] = Variable<String>(groupId.value);
    }
    if (pubkey.present) {
      map['pubkey'] = Variable<String>(pubkey.value);
    }
    if (me.present) {
      map['me'] = Variable<String>(me.value);
    }
    if (eventIdsJson.present) {
      map['event_ids_json'] = Variable<String>(eventIdsJson.value);
    }
    if (lastCreatedAt.present) {
      map['last_created_at'] = Variable<int>(lastCreatedAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<int>(lastSeenAt.value);
    }
    if (snapshotDigest.present) {
      map['snapshot_digest'] = Variable<String>(snapshotDigest.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LinkPeersCompanion(')
          ..write('groupId: $groupId, ')
          ..write('pubkey: $pubkey, ')
          ..write('me: $me, ')
          ..write('eventIdsJson: $eventIdsJson, ')
          ..write('lastCreatedAt: $lastCreatedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('snapshotDigest: $snapshotDigest, ')
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
  late final $RecordHistoryTable recordHistory = $RecordHistoryTable(this);
  late final $LinkChannelsTable linkChannels = $LinkChannelsTable(this);
  late final $LinkPeersTable linkPeers = $LinkPeersTable(this);
  late final Index recordHistoryGroup = Index(
    'record_history_group',
    'CREATE INDEX record_history_group ON record_history (group_id, recorded_at)',
  );
  late final Index recordHistoryRecord = Index(
    'record_history_record',
    'CREATE INDEX record_history_record ON record_history (group_id, kind, record_id)',
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
    recordHistory,
    linkChannels,
    linkPeers,
    recordHistoryGroup,
    recordHistoryRecord,
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
      Value<String?> linkAuthor,
      Value<int?> linkEpoch,
      Value<String?> linkSecret,
      Value<int?> lockedAt,
      Value<String?> exchangeRatesJson,
      Value<String?> fieldClocksJson,
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
      Value<String?> linkAuthor,
      Value<int?> linkEpoch,
      Value<String?> linkSecret,
      Value<int?> lockedAt,
      Value<String?> exchangeRatesJson,
      Value<String?> fieldClocksJson,
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

  ColumnFilters<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get linkEpoch => $composableBuilder(
    column: $table.linkEpoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkSecret => $composableBuilder(
    column: $table.linkSecret,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lockedAt => $composableBuilder(
    column: $table.lockedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exchangeRatesJson => $composableBuilder(
    column: $table.exchangeRatesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
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

  ColumnOrderings<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get linkEpoch => $composableBuilder(
    column: $table.linkEpoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkSecret => $composableBuilder(
    column: $table.linkSecret,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lockedAt => $composableBuilder(
    column: $table.lockedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exchangeRatesJson => $composableBuilder(
    column: $table.exchangeRatesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
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

  GeneratedColumn<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get linkEpoch =>
      $composableBuilder(column: $table.linkEpoch, builder: (column) => column);

  GeneratedColumn<String> get linkSecret => $composableBuilder(
    column: $table.linkSecret,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lockedAt =>
      $composableBuilder(column: $table.lockedAt, builder: (column) => column);

  GeneratedColumn<String> get exchangeRatesJson => $composableBuilder(
    column: $table.exchangeRatesJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get fieldClocksJson => $composableBuilder(
    column: $table.fieldClocksJson,
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
                Value<String?> linkAuthor = const Value.absent(),
                Value<int?> linkEpoch = const Value.absent(),
                Value<String?> linkSecret = const Value.absent(),
                Value<int?> lockedAt = const Value.absent(),
                Value<String?> exchangeRatesJson = const Value.absent(),
                Value<String?> fieldClocksJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupsCompanion(
                roomId: roomId,
                name: name,
                currency: currency,
                updatedAt: updatedAt,
                sig: sig,
                pendingSign: pendingSign,
                categoriesJson: categoriesJson,
                linkAuthor: linkAuthor,
                linkEpoch: linkEpoch,
                linkSecret: linkSecret,
                lockedAt: lockedAt,
                exchangeRatesJson: exchangeRatesJson,
                fieldClocksJson: fieldClocksJson,
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
                Value<String?> linkAuthor = const Value.absent(),
                Value<int?> linkEpoch = const Value.absent(),
                Value<String?> linkSecret = const Value.absent(),
                Value<int?> lockedAt = const Value.absent(),
                Value<String?> exchangeRatesJson = const Value.absent(),
                Value<String?> fieldClocksJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GroupsCompanion.insert(
                roomId: roomId,
                name: name,
                currency: currency,
                updatedAt: updatedAt,
                sig: sig,
                pendingSign: pendingSign,
                categoriesJson: categoriesJson,
                linkAuthor: linkAuthor,
                linkEpoch: linkEpoch,
                linkSecret: linkSecret,
                lockedAt: lockedAt,
                exchangeRatesJson: exchangeRatesJson,
                fieldClocksJson: fieldClocksJson,
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
      Value<String?> expenseDate,
      Value<String?> versionHash,
      Value<String?> linkAuthor,
      Value<String?> payersJson,
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
      Value<String?> expenseDate,
      Value<String?> versionHash,
      Value<String?> linkAuthor,
      Value<String?> payersJson,
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

  ColumnFilters<String> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payersJson => $composableBuilder(
    column: $table.payersJson,
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

  ColumnOrderings<String> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payersJson => $composableBuilder(
    column: $table.payersJson,
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

  GeneratedColumn<String> get expenseDate => $composableBuilder(
    column: $table.expenseDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get payersJson => $composableBuilder(
    column: $table.payersJson,
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
                Value<String?> expenseDate = const Value.absent(),
                Value<String?> versionHash = const Value.absent(),
                Value<String?> linkAuthor = const Value.absent(),
                Value<String?> payersJson = const Value.absent(),
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
                expenseDate: expenseDate,
                versionHash: versionHash,
                linkAuthor: linkAuthor,
                payersJson: payersJson,
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
                Value<String?> expenseDate = const Value.absent(),
                Value<String?> versionHash = const Value.absent(),
                Value<String?> linkAuthor = const Value.absent(),
                Value<String?> payersJson = const Value.absent(),
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
                expenseDate: expenseDate,
                versionHash: versionHash,
                linkAuthor: linkAuthor,
                payersJson: payersJson,
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
      Value<String?> settlementDate,
      Value<String?> versionHash,
      Value<String?> linkAuthor,
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
      Value<String?> settlementDate,
      Value<String?> versionHash,
      Value<String?> linkAuthor,
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

  ColumnFilters<String> get settlementDate => $composableBuilder(
    column: $table.settlementDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
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

  ColumnOrderings<String> get settlementDate => $composableBuilder(
    column: $table.settlementDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
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

  GeneratedColumn<String> get settlementDate => $composableBuilder(
    column: $table.settlementDate,
    builder: (column) => column,
  );

  GeneratedColumn<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
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
                Value<String?> settlementDate = const Value.absent(),
                Value<String?> versionHash = const Value.absent(),
                Value<String?> linkAuthor = const Value.absent(),
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
                settlementDate: settlementDate,
                versionHash: versionHash,
                linkAuthor: linkAuthor,
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
                Value<String?> settlementDate = const Value.absent(),
                Value<String?> versionHash = const Value.absent(),
                Value<String?> linkAuthor = const Value.absent(),
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
                settlementDate: settlementDate,
                versionHash: versionHash,
                linkAuthor: linkAuthor,
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
      Value<String?> linkAuthor,
      Value<String?> paymentJson,
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
      Value<String?> linkAuthor,
      Value<String?> paymentJson,
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

  ColumnFilters<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get paymentJson => $composableBuilder(
    column: $table.paymentJson,
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

  ColumnOrderings<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get paymentJson => $composableBuilder(
    column: $table.paymentJson,
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

  GeneratedColumn<String> get linkAuthor => $composableBuilder(
    column: $table.linkAuthor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get paymentJson => $composableBuilder(
    column: $table.paymentJson,
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
                Value<String?> linkAuthor = const Value.absent(),
                Value<String?> paymentJson = const Value.absent(),
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
                linkAuthor: linkAuthor,
                paymentJson: paymentJson,
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
                Value<String?> linkAuthor = const Value.absent(),
                Value<String?> paymentJson = const Value.absent(),
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
                linkAuthor: linkAuthor,
                paymentJson: paymentJson,
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
typedef $$RecordHistoryTableCreateCompanionBuilder =
    RecordHistoryCompanion Function({
      Value<int> id,
      required String groupId,
      required String kind,
      required String recordId,
      required int updatedAt,
      required String versionHash,
      required String content,
      required String source,
      required int recordedAt,
    });
typedef $$RecordHistoryTableUpdateCompanionBuilder =
    RecordHistoryCompanion Function({
      Value<int> id,
      Value<String> groupId,
      Value<String> kind,
      Value<String> recordId,
      Value<int> updatedAt,
      Value<String> versionHash,
      Value<String> content,
      Value<String> source,
      Value<int> recordedAt,
    });

class $$RecordHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $RecordHistoryTable> {
  $$RecordHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

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

  ColumnFilters<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecordHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $RecordHistoryTable> {
  $$RecordHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

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

  ColumnOrderings<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get content => $composableBuilder(
    column: $table.content,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecordHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecordHistoryTable> {
  $$RecordHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get recordId =>
      $composableBuilder(column: $table.recordId, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<String> get versionHash => $composableBuilder(
    column: $table.versionHash,
    builder: (column) => column,
  );

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<int> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );
}

class $$RecordHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecordHistoryTable,
          HistoryRow,
          $$RecordHistoryTableFilterComposer,
          $$RecordHistoryTableOrderingComposer,
          $$RecordHistoryTableAnnotationComposer,
          $$RecordHistoryTableCreateCompanionBuilder,
          $$RecordHistoryTableUpdateCompanionBuilder,
          (
            HistoryRow,
            BaseReferences<_$AppDatabase, $RecordHistoryTable, HistoryRow>,
          ),
          HistoryRow,
          PrefetchHooks Function()
        > {
  $$RecordHistoryTableTableManager(_$AppDatabase db, $RecordHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecordHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecordHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecordHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> groupId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> recordId = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<String> versionHash = const Value.absent(),
                Value<String> content = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<int> recordedAt = const Value.absent(),
              }) => RecordHistoryCompanion(
                id: id,
                groupId: groupId,
                kind: kind,
                recordId: recordId,
                updatedAt: updatedAt,
                versionHash: versionHash,
                content: content,
                source: source,
                recordedAt: recordedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String groupId,
                required String kind,
                required String recordId,
                required int updatedAt,
                required String versionHash,
                required String content,
                required String source,
                required int recordedAt,
              }) => RecordHistoryCompanion.insert(
                id: id,
                groupId: groupId,
                kind: kind,
                recordId: recordId,
                updatedAt: updatedAt,
                versionHash: versionHash,
                content: content,
                source: source,
                recordedAt: recordedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RecordHistoryTable, HistoryRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RecordHistoryTable,
                    HistoryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecordHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecordHistoryTable,
      HistoryRow,
      $$RecordHistoryTableFilterComposer,
      $$RecordHistoryTableOrderingComposer,
      $$RecordHistoryTableAnnotationComposer,
      $$RecordHistoryTableCreateCompanionBuilder,
      $$RecordHistoryTableUpdateCompanionBuilder,
      (
        HistoryRow,
        BaseReferences<_$AppDatabase, $RecordHistoryTable, HistoryRow>,
      ),
      HistoryRow,
      PrefetchHooks Function()
    >;
typedef $$LinkChannelsTableCreateCompanionBuilder =
    LinkChannelsCompanion Function({
      required String groupId,
      required int epoch,
      required String secret,
      Value<String?> myParticipantId,
      required String nostrPriv,
      Value<String?> lastPublishedHash,
      Value<int> lastPublishedAt,
      Value<int> lastCreatedAt,
      Value<int> parts,
      required int openedAt,
      Value<int> rowid,
    });
typedef $$LinkChannelsTableUpdateCompanionBuilder =
    LinkChannelsCompanion Function({
      Value<String> groupId,
      Value<int> epoch,
      Value<String> secret,
      Value<String?> myParticipantId,
      Value<String> nostrPriv,
      Value<String?> lastPublishedHash,
      Value<int> lastPublishedAt,
      Value<int> lastCreatedAt,
      Value<int> parts,
      Value<int> openedAt,
      Value<int> rowid,
    });

class $$LinkChannelsTableFilterComposer
    extends Composer<_$AppDatabase, $LinkChannelsTable> {
  $$LinkChannelsTableFilterComposer({
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

  ColumnFilters<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get secret => $composableBuilder(
    column: $table.secret,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get myParticipantId => $composableBuilder(
    column: $table.myParticipantId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get nostrPriv => $composableBuilder(
    column: $table.nostrPriv,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastPublishedHash => $composableBuilder(
    column: $table.lastPublishedHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastPublishedAt => $composableBuilder(
    column: $table.lastPublishedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastCreatedAt => $composableBuilder(
    column: $table.lastCreatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get parts => $composableBuilder(
    column: $table.parts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LinkChannelsTableOrderingComposer
    extends Composer<_$AppDatabase, $LinkChannelsTable> {
  $$LinkChannelsTableOrderingComposer({
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

  ColumnOrderings<int> get epoch => $composableBuilder(
    column: $table.epoch,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get secret => $composableBuilder(
    column: $table.secret,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get myParticipantId => $composableBuilder(
    column: $table.myParticipantId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get nostrPriv => $composableBuilder(
    column: $table.nostrPriv,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastPublishedHash => $composableBuilder(
    column: $table.lastPublishedHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastPublishedAt => $composableBuilder(
    column: $table.lastPublishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCreatedAt => $composableBuilder(
    column: $table.lastCreatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get parts => $composableBuilder(
    column: $table.parts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get openedAt => $composableBuilder(
    column: $table.openedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LinkChannelsTableAnnotationComposer
    extends Composer<_$AppDatabase, $LinkChannelsTable> {
  $$LinkChannelsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<int> get epoch =>
      $composableBuilder(column: $table.epoch, builder: (column) => column);

  GeneratedColumn<String> get secret =>
      $composableBuilder(column: $table.secret, builder: (column) => column);

  GeneratedColumn<String> get myParticipantId => $composableBuilder(
    column: $table.myParticipantId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get nostrPriv =>
      $composableBuilder(column: $table.nostrPriv, builder: (column) => column);

  GeneratedColumn<String> get lastPublishedHash => $composableBuilder(
    column: $table.lastPublishedHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastPublishedAt => $composableBuilder(
    column: $table.lastPublishedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastCreatedAt => $composableBuilder(
    column: $table.lastCreatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get parts =>
      $composableBuilder(column: $table.parts, builder: (column) => column);

  GeneratedColumn<int> get openedAt =>
      $composableBuilder(column: $table.openedAt, builder: (column) => column);
}

class $$LinkChannelsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LinkChannelsTable,
          LinkChannel,
          $$LinkChannelsTableFilterComposer,
          $$LinkChannelsTableOrderingComposer,
          $$LinkChannelsTableAnnotationComposer,
          $$LinkChannelsTableCreateCompanionBuilder,
          $$LinkChannelsTableUpdateCompanionBuilder,
          (
            LinkChannel,
            BaseReferences<_$AppDatabase, $LinkChannelsTable, LinkChannel>,
          ),
          LinkChannel,
          PrefetchHooks Function()
        > {
  $$LinkChannelsTableTableManager(_$AppDatabase db, $LinkChannelsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LinkChannelsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LinkChannelsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LinkChannelsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<int> epoch = const Value.absent(),
                Value<String> secret = const Value.absent(),
                Value<String?> myParticipantId = const Value.absent(),
                Value<String> nostrPriv = const Value.absent(),
                Value<String?> lastPublishedHash = const Value.absent(),
                Value<int> lastPublishedAt = const Value.absent(),
                Value<int> lastCreatedAt = const Value.absent(),
                Value<int> parts = const Value.absent(),
                Value<int> openedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LinkChannelsCompanion(
                groupId: groupId,
                epoch: epoch,
                secret: secret,
                myParticipantId: myParticipantId,
                nostrPriv: nostrPriv,
                lastPublishedHash: lastPublishedHash,
                lastPublishedAt: lastPublishedAt,
                lastCreatedAt: lastCreatedAt,
                parts: parts,
                openedAt: openedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required int epoch,
                required String secret,
                Value<String?> myParticipantId = const Value.absent(),
                required String nostrPriv,
                Value<String?> lastPublishedHash = const Value.absent(),
                Value<int> lastPublishedAt = const Value.absent(),
                Value<int> lastCreatedAt = const Value.absent(),
                Value<int> parts = const Value.absent(),
                required int openedAt,
                Value<int> rowid = const Value.absent(),
              }) => LinkChannelsCompanion.insert(
                groupId: groupId,
                epoch: epoch,
                secret: secret,
                myParticipantId: myParticipantId,
                nostrPriv: nostrPriv,
                lastPublishedHash: lastPublishedHash,
                lastPublishedAt: lastPublishedAt,
                lastCreatedAt: lastCreatedAt,
                parts: parts,
                openedAt: openedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LinkChannelsTable, LinkChannel>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $LinkChannelsTable,
                    LinkChannel
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LinkChannelsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LinkChannelsTable,
      LinkChannel,
      $$LinkChannelsTableFilterComposer,
      $$LinkChannelsTableOrderingComposer,
      $$LinkChannelsTableAnnotationComposer,
      $$LinkChannelsTableCreateCompanionBuilder,
      $$LinkChannelsTableUpdateCompanionBuilder,
      (
        LinkChannel,
        BaseReferences<_$AppDatabase, $LinkChannelsTable, LinkChannel>,
      ),
      LinkChannel,
      PrefetchHooks Function()
    >;
typedef $$LinkPeersTableCreateCompanionBuilder =
    LinkPeersCompanion Function({
      required String groupId,
      required String pubkey,
      Value<String?> me,
      Value<String> eventIdsJson,
      Value<int> lastCreatedAt,
      Value<int> lastSeenAt,
      Value<String?> snapshotDigest,
      Value<int> rowid,
    });
typedef $$LinkPeersTableUpdateCompanionBuilder =
    LinkPeersCompanion Function({
      Value<String> groupId,
      Value<String> pubkey,
      Value<String?> me,
      Value<String> eventIdsJson,
      Value<int> lastCreatedAt,
      Value<int> lastSeenAt,
      Value<String?> snapshotDigest,
      Value<int> rowid,
    });

class $$LinkPeersTableFilterComposer
    extends Composer<_$AppDatabase, $LinkPeersTable> {
  $$LinkPeersTableFilterComposer({
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

  ColumnFilters<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get me => $composableBuilder(
    column: $table.me,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get eventIdsJson => $composableBuilder(
    column: $table.eventIdsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastCreatedAt => $composableBuilder(
    column: $table.lastCreatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshotDigest => $composableBuilder(
    column: $table.snapshotDigest,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LinkPeersTableOrderingComposer
    extends Composer<_$AppDatabase, $LinkPeersTable> {
  $$LinkPeersTableOrderingComposer({
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

  ColumnOrderings<String> get pubkey => $composableBuilder(
    column: $table.pubkey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get me => $composableBuilder(
    column: $table.me,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get eventIdsJson => $composableBuilder(
    column: $table.eventIdsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastCreatedAt => $composableBuilder(
    column: $table.lastCreatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshotDigest => $composableBuilder(
    column: $table.snapshotDigest,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LinkPeersTableAnnotationComposer
    extends Composer<_$AppDatabase, $LinkPeersTable> {
  $$LinkPeersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get groupId =>
      $composableBuilder(column: $table.groupId, builder: (column) => column);

  GeneratedColumn<String> get pubkey =>
      $composableBuilder(column: $table.pubkey, builder: (column) => column);

  GeneratedColumn<String> get me =>
      $composableBuilder(column: $table.me, builder: (column) => column);

  GeneratedColumn<String> get eventIdsJson => $composableBuilder(
    column: $table.eventIdsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastCreatedAt => $composableBuilder(
    column: $table.lastCreatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snapshotDigest => $composableBuilder(
    column: $table.snapshotDigest,
    builder: (column) => column,
  );
}

class $$LinkPeersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LinkPeersTable,
          LinkPeer,
          $$LinkPeersTableFilterComposer,
          $$LinkPeersTableOrderingComposer,
          $$LinkPeersTableAnnotationComposer,
          $$LinkPeersTableCreateCompanionBuilder,
          $$LinkPeersTableUpdateCompanionBuilder,
          (LinkPeer, BaseReferences<_$AppDatabase, $LinkPeersTable, LinkPeer>),
          LinkPeer,
          PrefetchHooks Function()
        > {
  $$LinkPeersTableTableManager(_$AppDatabase db, $LinkPeersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LinkPeersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LinkPeersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LinkPeersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> groupId = const Value.absent(),
                Value<String> pubkey = const Value.absent(),
                Value<String?> me = const Value.absent(),
                Value<String> eventIdsJson = const Value.absent(),
                Value<int> lastCreatedAt = const Value.absent(),
                Value<int> lastSeenAt = const Value.absent(),
                Value<String?> snapshotDigest = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LinkPeersCompanion(
                groupId: groupId,
                pubkey: pubkey,
                me: me,
                eventIdsJson: eventIdsJson,
                lastCreatedAt: lastCreatedAt,
                lastSeenAt: lastSeenAt,
                snapshotDigest: snapshotDigest,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String groupId,
                required String pubkey,
                Value<String?> me = const Value.absent(),
                Value<String> eventIdsJson = const Value.absent(),
                Value<int> lastCreatedAt = const Value.absent(),
                Value<int> lastSeenAt = const Value.absent(),
                Value<String?> snapshotDigest = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LinkPeersCompanion.insert(
                groupId: groupId,
                pubkey: pubkey,
                me: me,
                eventIdsJson: eventIdsJson,
                lastCreatedAt: lastCreatedAt,
                lastSeenAt: lastSeenAt,
                snapshotDigest: snapshotDigest,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$LinkPeersTable, LinkPeer>(table),
                  BaseReferences<_$AppDatabase, $LinkPeersTable, LinkPeer>(
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

typedef $$LinkPeersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LinkPeersTable,
      LinkPeer,
      $$LinkPeersTableFilterComposer,
      $$LinkPeersTableOrderingComposer,
      $$LinkPeersTableAnnotationComposer,
      $$LinkPeersTableCreateCompanionBuilder,
      $$LinkPeersTableUpdateCompanionBuilder,
      (LinkPeer, BaseReferences<_$AppDatabase, $LinkPeersTable, LinkPeer>),
      LinkPeer,
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
  $$RecordHistoryTableTableManager get recordHistory =>
      $$RecordHistoryTableTableManager(_db, _db.recordHistory);
  $$LinkChannelsTableTableManager get linkChannels =>
      $$LinkChannelsTableTableManager(_db, _db.linkChannels);
  $$LinkPeersTableTableManager get linkPeers =>
      $$LinkPeersTableTableManager(_db, _db.linkPeers);
}
