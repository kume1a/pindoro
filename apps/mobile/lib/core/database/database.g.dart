// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $RoundsTable extends Rounds with TableInfo<$RoundsTable, Round> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoundsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newId,
  );
  static const VerificationMeta _cityIdMeta = const VerificationMeta('cityId');
  @override
  late final GeneratedColumn<String> cityId = GeneratedColumn<String>(
    'city_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _areaJsonMeta = const VerificationMeta(
    'areaJson',
  );
  @override
  late final GeneratedColumn<String> areaJson = GeneratedColumn<String>(
    'area_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Difficulty, String> difficulty =
      GeneratedColumn<String>(
        'difficulty',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Difficulty>($RoundsTable.$converterdifficulty);
  static const VerificationMeta _packVersionMeta = const VerificationMeta(
    'packVersion',
  );
  @override
  late final GeneratedColumn<String> packVersion = GeneratedColumn<String>(
    'pack_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _finishedAtMeta = const VerificationMeta(
    'finishedAt',
  );
  @override
  late final GeneratedColumn<DateTime> finishedAt = GeneratedColumn<DateTime>(
    'finished_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _retryOfMeta = const VerificationMeta(
    'retryOf',
  );
  @override
  late final GeneratedColumn<String> retryOf = GeneratedColumn<String>(
    'retry_of',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES round (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cityId,
    areaJson,
    difficulty,
    packVersion,
    startedAt,
    finishedAt,
    retryOf,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'round';
  @override
  VerificationContext validateIntegrity(
    Insertable<Round> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('city_id')) {
      context.handle(
        _cityIdMeta,
        cityId.isAcceptableOrUnknown(data['city_id']!, _cityIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cityIdMeta);
    }
    if (data.containsKey('area_json')) {
      context.handle(
        _areaJsonMeta,
        areaJson.isAcceptableOrUnknown(data['area_json']!, _areaJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_areaJsonMeta);
    }
    if (data.containsKey('pack_version')) {
      context.handle(
        _packVersionMeta,
        packVersion.isAcceptableOrUnknown(
          data['pack_version']!,
          _packVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_packVersionMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    }
    if (data.containsKey('finished_at')) {
      context.handle(
        _finishedAtMeta,
        finishedAt.isAcceptableOrUnknown(data['finished_at']!, _finishedAtMeta),
      );
    }
    if (data.containsKey('retry_of')) {
      context.handle(
        _retryOfMeta,
        retryOf.isAcceptableOrUnknown(data['retry_of']!, _retryOfMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Round map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Round(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      cityId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}city_id'],
      )!,
      areaJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}area_json'],
      )!,
      difficulty: $RoundsTable.$converterdifficulty.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}difficulty'],
        )!,
      ),
      packVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_version'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      finishedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}finished_at'],
      ),
      retryOf: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}retry_of'],
      ),
    );
  }

  @override
  $RoundsTable createAlias(String alias) {
    return $RoundsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<Difficulty, String, String> $converterdifficulty =
      const EnumNameConverter<Difficulty>(Difficulty.values);
}

class Round extends DataClass implements Insertable<Round> {
  final String id;
  final String cityId;
  final String areaJson;
  final Difficulty difficulty;
  final String packVersion;
  final DateTime startedAt;
  final DateTime? finishedAt;

  /// The round whose Close and Miss streets this round retries.
  final String? retryOf;
  const Round({
    required this.id,
    required this.cityId,
    required this.areaJson,
    required this.difficulty,
    required this.packVersion,
    required this.startedAt,
    this.finishedAt,
    this.retryOf,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['city_id'] = Variable<String>(cityId);
    map['area_json'] = Variable<String>(areaJson);
    {
      map['difficulty'] = Variable<String>(
        $RoundsTable.$converterdifficulty.toSql(difficulty),
      );
    }
    map['pack_version'] = Variable<String>(packVersion);
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || finishedAt != null) {
      map['finished_at'] = Variable<DateTime>(finishedAt);
    }
    if (!nullToAbsent || retryOf != null) {
      map['retry_of'] = Variable<String>(retryOf);
    }
    return map;
  }

  RoundsCompanion toCompanion(bool nullToAbsent) {
    return RoundsCompanion(
      id: Value(id),
      cityId: Value(cityId),
      areaJson: Value(areaJson),
      difficulty: Value(difficulty),
      packVersion: Value(packVersion),
      startedAt: Value(startedAt),
      finishedAt: finishedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(finishedAt),
      retryOf: retryOf == null && nullToAbsent
          ? const Value.absent()
          : Value(retryOf),
    );
  }

  factory Round.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Round(
      id: serializer.fromJson<String>(json['id']),
      cityId: serializer.fromJson<String>(json['cityId']),
      areaJson: serializer.fromJson<String>(json['areaJson']),
      difficulty: $RoundsTable.$converterdifficulty.fromJson(
        serializer.fromJson<String>(json['difficulty']),
      ),
      packVersion: serializer.fromJson<String>(json['packVersion']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      finishedAt: serializer.fromJson<DateTime?>(json['finishedAt']),
      retryOf: serializer.fromJson<String?>(json['retryOf']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'cityId': serializer.toJson<String>(cityId),
      'areaJson': serializer.toJson<String>(areaJson),
      'difficulty': serializer.toJson<String>(
        $RoundsTable.$converterdifficulty.toJson(difficulty),
      ),
      'packVersion': serializer.toJson<String>(packVersion),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'finishedAt': serializer.toJson<DateTime?>(finishedAt),
      'retryOf': serializer.toJson<String?>(retryOf),
    };
  }

  Round copyWith({
    String? id,
    String? cityId,
    String? areaJson,
    Difficulty? difficulty,
    String? packVersion,
    DateTime? startedAt,
    Value<DateTime?> finishedAt = const Value.absent(),
    Value<String?> retryOf = const Value.absent(),
  }) => Round(
    id: id ?? this.id,
    cityId: cityId ?? this.cityId,
    areaJson: areaJson ?? this.areaJson,
    difficulty: difficulty ?? this.difficulty,
    packVersion: packVersion ?? this.packVersion,
    startedAt: startedAt ?? this.startedAt,
    finishedAt: finishedAt.present ? finishedAt.value : this.finishedAt,
    retryOf: retryOf.present ? retryOf.value : this.retryOf,
  );
  Round copyWithCompanion(RoundsCompanion data) {
    return Round(
      id: data.id.present ? data.id.value : this.id,
      cityId: data.cityId.present ? data.cityId.value : this.cityId,
      areaJson: data.areaJson.present ? data.areaJson.value : this.areaJson,
      difficulty: data.difficulty.present
          ? data.difficulty.value
          : this.difficulty,
      packVersion: data.packVersion.present
          ? data.packVersion.value
          : this.packVersion,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      finishedAt: data.finishedAt.present
          ? data.finishedAt.value
          : this.finishedAt,
      retryOf: data.retryOf.present ? data.retryOf.value : this.retryOf,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Round(')
          ..write('id: $id, ')
          ..write('cityId: $cityId, ')
          ..write('areaJson: $areaJson, ')
          ..write('difficulty: $difficulty, ')
          ..write('packVersion: $packVersion, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('retryOf: $retryOf')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cityId,
    areaJson,
    difficulty,
    packVersion,
    startedAt,
    finishedAt,
    retryOf,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Round &&
          other.id == this.id &&
          other.cityId == this.cityId &&
          other.areaJson == this.areaJson &&
          other.difficulty == this.difficulty &&
          other.packVersion == this.packVersion &&
          other.startedAt == this.startedAt &&
          other.finishedAt == this.finishedAt &&
          other.retryOf == this.retryOf);
}

class RoundsCompanion extends UpdateCompanion<Round> {
  final Value<String> id;
  final Value<String> cityId;
  final Value<String> areaJson;
  final Value<Difficulty> difficulty;
  final Value<String> packVersion;
  final Value<DateTime> startedAt;
  final Value<DateTime?> finishedAt;
  final Value<String?> retryOf;
  final Value<int> rowid;
  const RoundsCompanion({
    this.id = const Value.absent(),
    this.cityId = const Value.absent(),
    this.areaJson = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.packVersion = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.retryOf = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoundsCompanion.insert({
    this.id = const Value.absent(),
    required String cityId,
    required String areaJson,
    required Difficulty difficulty,
    required String packVersion,
    this.startedAt = const Value.absent(),
    this.finishedAt = const Value.absent(),
    this.retryOf = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : cityId = Value(cityId),
       areaJson = Value(areaJson),
       difficulty = Value(difficulty),
       packVersion = Value(packVersion);
  static Insertable<Round> custom({
    Expression<String>? id,
    Expression<String>? cityId,
    Expression<String>? areaJson,
    Expression<String>? difficulty,
    Expression<String>? packVersion,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? finishedAt,
    Expression<String>? retryOf,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cityId != null) 'city_id': cityId,
      if (areaJson != null) 'area_json': areaJson,
      if (difficulty != null) 'difficulty': difficulty,
      if (packVersion != null) 'pack_version': packVersion,
      if (startedAt != null) 'started_at': startedAt,
      if (finishedAt != null) 'finished_at': finishedAt,
      if (retryOf != null) 'retry_of': retryOf,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoundsCompanion copyWith({
    Value<String>? id,
    Value<String>? cityId,
    Value<String>? areaJson,
    Value<Difficulty>? difficulty,
    Value<String>? packVersion,
    Value<DateTime>? startedAt,
    Value<DateTime?>? finishedAt,
    Value<String?>? retryOf,
    Value<int>? rowid,
  }) {
    return RoundsCompanion(
      id: id ?? this.id,
      cityId: cityId ?? this.cityId,
      areaJson: areaJson ?? this.areaJson,
      difficulty: difficulty ?? this.difficulty,
      packVersion: packVersion ?? this.packVersion,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      retryOf: retryOf ?? this.retryOf,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (cityId.present) {
      map['city_id'] = Variable<String>(cityId.value);
    }
    if (areaJson.present) {
      map['area_json'] = Variable<String>(areaJson.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<String>(
        $RoundsTable.$converterdifficulty.toSql(difficulty.value),
      );
    }
    if (packVersion.present) {
      map['pack_version'] = Variable<String>(packVersion.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (finishedAt.present) {
      map['finished_at'] = Variable<DateTime>(finishedAt.value);
    }
    if (retryOf.present) {
      map['retry_of'] = Variable<String>(retryOf.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoundsCompanion(')
          ..write('id: $id, ')
          ..write('cityId: $cityId, ')
          ..write('areaJson: $areaJson, ')
          ..write('difficulty: $difficulty, ')
          ..write('packVersion: $packVersion, ')
          ..write('startedAt: $startedAt, ')
          ..write('finishedAt: $finishedAt, ')
          ..write('retryOf: $retryOf, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnswersTable extends Answers with TableInfo<$AnswersTable, Answer> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnswersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    clientDefault: newId,
  );
  static const VerificationMeta _roundIdMeta = const VerificationMeta(
    'roundId',
  );
  @override
  late final GeneratedColumn<String> roundId = GeneratedColumn<String>(
    'round_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES round (id)',
    ),
  );
  static const VerificationMeta _streetIdMeta = const VerificationMeta(
    'streetId',
  );
  @override
  late final GeneratedColumn<String> streetId = GeneratedColumn<String>(
    'street_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinLatMeta = const VerificationMeta('pinLat');
  @override
  late final GeneratedColumn<double> pinLat = GeneratedColumn<double>(
    'pin_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pinLonMeta = const VerificationMeta('pinLon');
  @override
  late final GeneratedColumn<double> pinLon = GeneratedColumn<double>(
    'pin_lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _distanceMMeta = const VerificationMeta(
    'distanceM',
  );
  @override
  late final GeneratedColumn<double> distanceM = GeneratedColumn<double>(
    'distance_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Tier, String> tier =
      GeneratedColumn<String>(
        'tier',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<Tier>($AnswersTable.$convertertier);
  static const VerificationMeta _xpMeta = const VerificationMeta('xp');
  @override
  late final GeneratedColumn<int> xp = GeneratedColumn<int>(
    'xp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _packVersionMeta = const VerificationMeta(
    'packVersion',
  );
  @override
  late final GeneratedColumn<String> packVersion = GeneratedColumn<String>(
    'pack_version',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    roundId,
    streetId,
    pinLat,
    pinLon,
    distanceM,
    tier,
    xp,
    packVersion,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'answer';
  @override
  VerificationContext validateIntegrity(
    Insertable<Answer> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('round_id')) {
      context.handle(
        _roundIdMeta,
        roundId.isAcceptableOrUnknown(data['round_id']!, _roundIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roundIdMeta);
    }
    if (data.containsKey('street_id')) {
      context.handle(
        _streetIdMeta,
        streetId.isAcceptableOrUnknown(data['street_id']!, _streetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streetIdMeta);
    }
    if (data.containsKey('pin_lat')) {
      context.handle(
        _pinLatMeta,
        pinLat.isAcceptableOrUnknown(data['pin_lat']!, _pinLatMeta),
      );
    } else if (isInserting) {
      context.missing(_pinLatMeta);
    }
    if (data.containsKey('pin_lon')) {
      context.handle(
        _pinLonMeta,
        pinLon.isAcceptableOrUnknown(data['pin_lon']!, _pinLonMeta),
      );
    } else if (isInserting) {
      context.missing(_pinLonMeta);
    }
    if (data.containsKey('distance_m')) {
      context.handle(
        _distanceMMeta,
        distanceM.isAcceptableOrUnknown(data['distance_m']!, _distanceMMeta),
      );
    } else if (isInserting) {
      context.missing(_distanceMMeta);
    }
    if (data.containsKey('xp')) {
      context.handle(_xpMeta, xp.isAcceptableOrUnknown(data['xp']!, _xpMeta));
    } else if (isInserting) {
      context.missing(_xpMeta);
    }
    if (data.containsKey('pack_version')) {
      context.handle(
        _packVersionMeta,
        packVersion.isAcceptableOrUnknown(
          data['pack_version']!,
          _packVersionMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_packVersionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Answer map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Answer(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      roundId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}round_id'],
      )!,
      streetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}street_id'],
      )!,
      pinLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pin_lat'],
      )!,
      pinLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pin_lon'],
      )!,
      distanceM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_m'],
      )!,
      tier: $AnswersTable.$convertertier.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}tier'],
        )!,
      ),
      xp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}xp'],
      )!,
      packVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_version'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AnswersTable createAlias(String alias) {
    return $AnswersTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<Tier, String, String> $convertertier =
      const EnumNameConverter<Tier>(Tier.values);
}

class Answer extends DataClass implements Insertable<Answer> {
  final String id;
  final String roundId;
  final String streetId;
  final double pinLat;
  final double pinLon;
  final double distanceM;
  final Tier tier;
  final int xp;
  final String packVersion;
  final DateTime createdAt;
  const Answer({
    required this.id,
    required this.roundId,
    required this.streetId,
    required this.pinLat,
    required this.pinLon,
    required this.distanceM,
    required this.tier,
    required this.xp,
    required this.packVersion,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['round_id'] = Variable<String>(roundId);
    map['street_id'] = Variable<String>(streetId);
    map['pin_lat'] = Variable<double>(pinLat);
    map['pin_lon'] = Variable<double>(pinLon);
    map['distance_m'] = Variable<double>(distanceM);
    {
      map['tier'] = Variable<String>($AnswersTable.$convertertier.toSql(tier));
    }
    map['xp'] = Variable<int>(xp);
    map['pack_version'] = Variable<String>(packVersion);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  AnswersCompanion toCompanion(bool nullToAbsent) {
    return AnswersCompanion(
      id: Value(id),
      roundId: Value(roundId),
      streetId: Value(streetId),
      pinLat: Value(pinLat),
      pinLon: Value(pinLon),
      distanceM: Value(distanceM),
      tier: Value(tier),
      xp: Value(xp),
      packVersion: Value(packVersion),
      createdAt: Value(createdAt),
    );
  }

  factory Answer.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Answer(
      id: serializer.fromJson<String>(json['id']),
      roundId: serializer.fromJson<String>(json['roundId']),
      streetId: serializer.fromJson<String>(json['streetId']),
      pinLat: serializer.fromJson<double>(json['pinLat']),
      pinLon: serializer.fromJson<double>(json['pinLon']),
      distanceM: serializer.fromJson<double>(json['distanceM']),
      tier: $AnswersTable.$convertertier.fromJson(
        serializer.fromJson<String>(json['tier']),
      ),
      xp: serializer.fromJson<int>(json['xp']),
      packVersion: serializer.fromJson<String>(json['packVersion']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'roundId': serializer.toJson<String>(roundId),
      'streetId': serializer.toJson<String>(streetId),
      'pinLat': serializer.toJson<double>(pinLat),
      'pinLon': serializer.toJson<double>(pinLon),
      'distanceM': serializer.toJson<double>(distanceM),
      'tier': serializer.toJson<String>(
        $AnswersTable.$convertertier.toJson(tier),
      ),
      'xp': serializer.toJson<int>(xp),
      'packVersion': serializer.toJson<String>(packVersion),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Answer copyWith({
    String? id,
    String? roundId,
    String? streetId,
    double? pinLat,
    double? pinLon,
    double? distanceM,
    Tier? tier,
    int? xp,
    String? packVersion,
    DateTime? createdAt,
  }) => Answer(
    id: id ?? this.id,
    roundId: roundId ?? this.roundId,
    streetId: streetId ?? this.streetId,
    pinLat: pinLat ?? this.pinLat,
    pinLon: pinLon ?? this.pinLon,
    distanceM: distanceM ?? this.distanceM,
    tier: tier ?? this.tier,
    xp: xp ?? this.xp,
    packVersion: packVersion ?? this.packVersion,
    createdAt: createdAt ?? this.createdAt,
  );
  Answer copyWithCompanion(AnswersCompanion data) {
    return Answer(
      id: data.id.present ? data.id.value : this.id,
      roundId: data.roundId.present ? data.roundId.value : this.roundId,
      streetId: data.streetId.present ? data.streetId.value : this.streetId,
      pinLat: data.pinLat.present ? data.pinLat.value : this.pinLat,
      pinLon: data.pinLon.present ? data.pinLon.value : this.pinLon,
      distanceM: data.distanceM.present ? data.distanceM.value : this.distanceM,
      tier: data.tier.present ? data.tier.value : this.tier,
      xp: data.xp.present ? data.xp.value : this.xp,
      packVersion: data.packVersion.present
          ? data.packVersion.value
          : this.packVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Answer(')
          ..write('id: $id, ')
          ..write('roundId: $roundId, ')
          ..write('streetId: $streetId, ')
          ..write('pinLat: $pinLat, ')
          ..write('pinLon: $pinLon, ')
          ..write('distanceM: $distanceM, ')
          ..write('tier: $tier, ')
          ..write('xp: $xp, ')
          ..write('packVersion: $packVersion, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    roundId,
    streetId,
    pinLat,
    pinLon,
    distanceM,
    tier,
    xp,
    packVersion,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Answer &&
          other.id == this.id &&
          other.roundId == this.roundId &&
          other.streetId == this.streetId &&
          other.pinLat == this.pinLat &&
          other.pinLon == this.pinLon &&
          other.distanceM == this.distanceM &&
          other.tier == this.tier &&
          other.xp == this.xp &&
          other.packVersion == this.packVersion &&
          other.createdAt == this.createdAt);
}

class AnswersCompanion extends UpdateCompanion<Answer> {
  final Value<String> id;
  final Value<String> roundId;
  final Value<String> streetId;
  final Value<double> pinLat;
  final Value<double> pinLon;
  final Value<double> distanceM;
  final Value<Tier> tier;
  final Value<int> xp;
  final Value<String> packVersion;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const AnswersCompanion({
    this.id = const Value.absent(),
    this.roundId = const Value.absent(),
    this.streetId = const Value.absent(),
    this.pinLat = const Value.absent(),
    this.pinLon = const Value.absent(),
    this.distanceM = const Value.absent(),
    this.tier = const Value.absent(),
    this.xp = const Value.absent(),
    this.packVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnswersCompanion.insert({
    this.id = const Value.absent(),
    required String roundId,
    required String streetId,
    required double pinLat,
    required double pinLon,
    required double distanceM,
    required Tier tier,
    required int xp,
    required String packVersion,
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : roundId = Value(roundId),
       streetId = Value(streetId),
       pinLat = Value(pinLat),
       pinLon = Value(pinLon),
       distanceM = Value(distanceM),
       tier = Value(tier),
       xp = Value(xp),
       packVersion = Value(packVersion);
  static Insertable<Answer> custom({
    Expression<String>? id,
    Expression<String>? roundId,
    Expression<String>? streetId,
    Expression<double>? pinLat,
    Expression<double>? pinLon,
    Expression<double>? distanceM,
    Expression<String>? tier,
    Expression<int>? xp,
    Expression<String>? packVersion,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (roundId != null) 'round_id': roundId,
      if (streetId != null) 'street_id': streetId,
      if (pinLat != null) 'pin_lat': pinLat,
      if (pinLon != null) 'pin_lon': pinLon,
      if (distanceM != null) 'distance_m': distanceM,
      if (tier != null) 'tier': tier,
      if (xp != null) 'xp': xp,
      if (packVersion != null) 'pack_version': packVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnswersCompanion copyWith({
    Value<String>? id,
    Value<String>? roundId,
    Value<String>? streetId,
    Value<double>? pinLat,
    Value<double>? pinLon,
    Value<double>? distanceM,
    Value<Tier>? tier,
    Value<int>? xp,
    Value<String>? packVersion,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return AnswersCompanion(
      id: id ?? this.id,
      roundId: roundId ?? this.roundId,
      streetId: streetId ?? this.streetId,
      pinLat: pinLat ?? this.pinLat,
      pinLon: pinLon ?? this.pinLon,
      distanceM: distanceM ?? this.distanceM,
      tier: tier ?? this.tier,
      xp: xp ?? this.xp,
      packVersion: packVersion ?? this.packVersion,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (roundId.present) {
      map['round_id'] = Variable<String>(roundId.value);
    }
    if (streetId.present) {
      map['street_id'] = Variable<String>(streetId.value);
    }
    if (pinLat.present) {
      map['pin_lat'] = Variable<double>(pinLat.value);
    }
    if (pinLon.present) {
      map['pin_lon'] = Variable<double>(pinLon.value);
    }
    if (distanceM.present) {
      map['distance_m'] = Variable<double>(distanceM.value);
    }
    if (tier.present) {
      map['tier'] = Variable<String>(
        $AnswersTable.$convertertier.toSql(tier.value),
      );
    }
    if (xp.present) {
      map['xp'] = Variable<int>(xp.value);
    }
    if (packVersion.present) {
      map['pack_version'] = Variable<String>(packVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnswersCompanion(')
          ..write('id: $id, ')
          ..write('roundId: $roundId, ')
          ..write('streetId: $streetId, ')
          ..write('pinLat: $pinLat, ')
          ..write('pinLon: $pinLon, ')
          ..write('distanceM: $distanceM, ')
          ..write('tier: $tier, ')
          ..write('xp: $xp, ')
          ..write('packVersion: $packVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $UserSettingsTable extends UserSettings
    with TableInfo<$UserSettingsTable, Settings> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $UserSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _lastCityMeta = const VerificationMeta(
    'lastCity',
  );
  @override
  late final GeneratedColumn<String> lastCity = GeneratedColumn<String>(
    'last_city',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastAreaJsonMeta = const VerificationMeta(
    'lastAreaJson',
  );
  @override
  late final GeneratedColumn<String> lastAreaJson = GeneratedColumn<String>(
    'last_area_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  late final GeneratedColumnWithTypeConverter<Difficulty?, String>
  lastDifficulty = GeneratedColumn<String>(
    'last_difficulty',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<Difficulty?>($UserSettingsTable.$converterlastDifficultyn);
  @override
  late final GeneratedColumnWithTypeConverter<AppLanguage?, String>
  appLanguage = GeneratedColumn<String>(
    'app_language',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  ).withConverter<AppLanguage?>($UserSettingsTable.$converterappLanguagen);
  @override
  late final GeneratedColumnWithTypeConverter<StreetNameMode, String>
  streetNames = GeneratedColumn<String>(
    'street_names',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('local'),
  ).withConverter<StreetNameMode>($UserSettingsTable.$converterstreetNames);
  @override
  late final GeneratedColumnWithTypeConverter<ThemePreference, String> theme =
      GeneratedColumn<String>(
        'theme',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
        defaultValue: const Constant('system'),
      ).withConverter<ThemePreference>($UserSettingsTable.$convertertheme);
  static const VerificationMeta _soundMeta = const VerificationMeta('sound');
  @override
  late final GeneratedColumn<bool> sound = GeneratedColumn<bool>(
    'sound',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("sound" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _hapticsMeta = const VerificationMeta(
    'haptics',
  );
  @override
  late final GeneratedColumn<bool> haptics = GeneratedColumn<bool>(
    'haptics',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("haptics" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _homeCoachSeenMeta = const VerificationMeta(
    'homeCoachSeen',
  );
  @override
  late final GeneratedColumn<bool> homeCoachSeen = GeneratedColumn<bool>(
    'home_coach_seen',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("home_coach_seen" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    lastCity,
    lastAreaJson,
    lastDifficulty,
    appLanguage,
    streetNames,
    theme,
    sound,
    haptics,
    homeCoachSeen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'user_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Settings> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('last_city')) {
      context.handle(
        _lastCityMeta,
        lastCity.isAcceptableOrUnknown(data['last_city']!, _lastCityMeta),
      );
    }
    if (data.containsKey('last_area_json')) {
      context.handle(
        _lastAreaJsonMeta,
        lastAreaJson.isAcceptableOrUnknown(
          data['last_area_json']!,
          _lastAreaJsonMeta,
        ),
      );
    }
    if (data.containsKey('sound')) {
      context.handle(
        _soundMeta,
        sound.isAcceptableOrUnknown(data['sound']!, _soundMeta),
      );
    }
    if (data.containsKey('haptics')) {
      context.handle(
        _hapticsMeta,
        haptics.isAcceptableOrUnknown(data['haptics']!, _hapticsMeta),
      );
    }
    if (data.containsKey('home_coach_seen')) {
      context.handle(
        _homeCoachSeenMeta,
        homeCoachSeen.isAcceptableOrUnknown(
          data['home_coach_seen']!,
          _homeCoachSeenMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Settings map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Settings(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      lastCity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_city'],
      ),
      lastAreaJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_area_json'],
      ),
      lastDifficulty: $UserSettingsTable.$converterlastDifficultyn.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}last_difficulty'],
        ),
      ),
      appLanguage: $UserSettingsTable.$converterappLanguagen.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}app_language'],
        ),
      ),
      streetNames: $UserSettingsTable.$converterstreetNames.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}street_names'],
        )!,
      ),
      theme: $UserSettingsTable.$convertertheme.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}theme'],
        )!,
      ),
      sound: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}sound'],
      )!,
      haptics: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}haptics'],
      )!,
      homeCoachSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}home_coach_seen'],
      )!,
    );
  }

  @override
  $UserSettingsTable createAlias(String alias) {
    return $UserSettingsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<Difficulty, String, String>
  $converterlastDifficulty = const EnumNameConverter<Difficulty>(
    Difficulty.values,
  );
  static JsonTypeConverter2<Difficulty?, String?, String?>
  $converterlastDifficultyn = JsonTypeConverter2.asNullable(
    $converterlastDifficulty,
  );
  static JsonTypeConverter2<AppLanguage, String, String> $converterappLanguage =
      const EnumNameConverter<AppLanguage>(AppLanguage.values);
  static JsonTypeConverter2<AppLanguage?, String?, String?>
  $converterappLanguagen = JsonTypeConverter2.asNullable($converterappLanguage);
  static JsonTypeConverter2<StreetNameMode, String, String>
  $converterstreetNames = const EnumNameConverter<StreetNameMode>(
    StreetNameMode.values,
  );
  static JsonTypeConverter2<ThemePreference, String, String> $convertertheme =
      const EnumNameConverter<ThemePreference>(ThemePreference.values);
}

class Settings extends DataClass implements Insertable<Settings> {
  final int id;
  final String? lastCity;
  final String? lastAreaJson;
  final Difficulty? lastDifficulty;

  /// Null follows the device language.
  final AppLanguage? appLanguage;
  final StreetNameMode streetNames;
  final ThemePreference theme;
  final bool sound;
  final bool haptics;

  /// The first Home's coach mark was closed.
  final bool homeCoachSeen;
  const Settings({
    required this.id,
    this.lastCity,
    this.lastAreaJson,
    this.lastDifficulty,
    this.appLanguage,
    required this.streetNames,
    required this.theme,
    required this.sound,
    required this.haptics,
    required this.homeCoachSeen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || lastCity != null) {
      map['last_city'] = Variable<String>(lastCity);
    }
    if (!nullToAbsent || lastAreaJson != null) {
      map['last_area_json'] = Variable<String>(lastAreaJson);
    }
    if (!nullToAbsent || lastDifficulty != null) {
      map['last_difficulty'] = Variable<String>(
        $UserSettingsTable.$converterlastDifficultyn.toSql(lastDifficulty),
      );
    }
    if (!nullToAbsent || appLanguage != null) {
      map['app_language'] = Variable<String>(
        $UserSettingsTable.$converterappLanguagen.toSql(appLanguage),
      );
    }
    {
      map['street_names'] = Variable<String>(
        $UserSettingsTable.$converterstreetNames.toSql(streetNames),
      );
    }
    {
      map['theme'] = Variable<String>(
        $UserSettingsTable.$convertertheme.toSql(theme),
      );
    }
    map['sound'] = Variable<bool>(sound);
    map['haptics'] = Variable<bool>(haptics);
    map['home_coach_seen'] = Variable<bool>(homeCoachSeen);
    return map;
  }

  UserSettingsCompanion toCompanion(bool nullToAbsent) {
    return UserSettingsCompanion(
      id: Value(id),
      lastCity: lastCity == null && nullToAbsent
          ? const Value.absent()
          : Value(lastCity),
      lastAreaJson: lastAreaJson == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAreaJson),
      lastDifficulty: lastDifficulty == null && nullToAbsent
          ? const Value.absent()
          : Value(lastDifficulty),
      appLanguage: appLanguage == null && nullToAbsent
          ? const Value.absent()
          : Value(appLanguage),
      streetNames: Value(streetNames),
      theme: Value(theme),
      sound: Value(sound),
      haptics: Value(haptics),
      homeCoachSeen: Value(homeCoachSeen),
    );
  }

  factory Settings.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Settings(
      id: serializer.fromJson<int>(json['id']),
      lastCity: serializer.fromJson<String?>(json['lastCity']),
      lastAreaJson: serializer.fromJson<String?>(json['lastAreaJson']),
      lastDifficulty: $UserSettingsTable.$converterlastDifficultyn.fromJson(
        serializer.fromJson<String?>(json['lastDifficulty']),
      ),
      appLanguage: $UserSettingsTable.$converterappLanguagen.fromJson(
        serializer.fromJson<String?>(json['appLanguage']),
      ),
      streetNames: $UserSettingsTable.$converterstreetNames.fromJson(
        serializer.fromJson<String>(json['streetNames']),
      ),
      theme: $UserSettingsTable.$convertertheme.fromJson(
        serializer.fromJson<String>(json['theme']),
      ),
      sound: serializer.fromJson<bool>(json['sound']),
      haptics: serializer.fromJson<bool>(json['haptics']),
      homeCoachSeen: serializer.fromJson<bool>(json['homeCoachSeen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lastCity': serializer.toJson<String?>(lastCity),
      'lastAreaJson': serializer.toJson<String?>(lastAreaJson),
      'lastDifficulty': serializer.toJson<String?>(
        $UserSettingsTable.$converterlastDifficultyn.toJson(lastDifficulty),
      ),
      'appLanguage': serializer.toJson<String?>(
        $UserSettingsTable.$converterappLanguagen.toJson(appLanguage),
      ),
      'streetNames': serializer.toJson<String>(
        $UserSettingsTable.$converterstreetNames.toJson(streetNames),
      ),
      'theme': serializer.toJson<String>(
        $UserSettingsTable.$convertertheme.toJson(theme),
      ),
      'sound': serializer.toJson<bool>(sound),
      'haptics': serializer.toJson<bool>(haptics),
      'homeCoachSeen': serializer.toJson<bool>(homeCoachSeen),
    };
  }

  Settings copyWith({
    int? id,
    Value<String?> lastCity = const Value.absent(),
    Value<String?> lastAreaJson = const Value.absent(),
    Value<Difficulty?> lastDifficulty = const Value.absent(),
    Value<AppLanguage?> appLanguage = const Value.absent(),
    StreetNameMode? streetNames,
    ThemePreference? theme,
    bool? sound,
    bool? haptics,
    bool? homeCoachSeen,
  }) => Settings(
    id: id ?? this.id,
    lastCity: lastCity.present ? lastCity.value : this.lastCity,
    lastAreaJson: lastAreaJson.present ? lastAreaJson.value : this.lastAreaJson,
    lastDifficulty: lastDifficulty.present
        ? lastDifficulty.value
        : this.lastDifficulty,
    appLanguage: appLanguage.present ? appLanguage.value : this.appLanguage,
    streetNames: streetNames ?? this.streetNames,
    theme: theme ?? this.theme,
    sound: sound ?? this.sound,
    haptics: haptics ?? this.haptics,
    homeCoachSeen: homeCoachSeen ?? this.homeCoachSeen,
  );
  Settings copyWithCompanion(UserSettingsCompanion data) {
    return Settings(
      id: data.id.present ? data.id.value : this.id,
      lastCity: data.lastCity.present ? data.lastCity.value : this.lastCity,
      lastAreaJson: data.lastAreaJson.present
          ? data.lastAreaJson.value
          : this.lastAreaJson,
      lastDifficulty: data.lastDifficulty.present
          ? data.lastDifficulty.value
          : this.lastDifficulty,
      appLanguage: data.appLanguage.present
          ? data.appLanguage.value
          : this.appLanguage,
      streetNames: data.streetNames.present
          ? data.streetNames.value
          : this.streetNames,
      theme: data.theme.present ? data.theme.value : this.theme,
      sound: data.sound.present ? data.sound.value : this.sound,
      haptics: data.haptics.present ? data.haptics.value : this.haptics,
      homeCoachSeen: data.homeCoachSeen.present
          ? data.homeCoachSeen.value
          : this.homeCoachSeen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Settings(')
          ..write('id: $id, ')
          ..write('lastCity: $lastCity, ')
          ..write('lastAreaJson: $lastAreaJson, ')
          ..write('lastDifficulty: $lastDifficulty, ')
          ..write('appLanguage: $appLanguage, ')
          ..write('streetNames: $streetNames, ')
          ..write('theme: $theme, ')
          ..write('sound: $sound, ')
          ..write('haptics: $haptics, ')
          ..write('homeCoachSeen: $homeCoachSeen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    lastCity,
    lastAreaJson,
    lastDifficulty,
    appLanguage,
    streetNames,
    theme,
    sound,
    haptics,
    homeCoachSeen,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Settings &&
          other.id == this.id &&
          other.lastCity == this.lastCity &&
          other.lastAreaJson == this.lastAreaJson &&
          other.lastDifficulty == this.lastDifficulty &&
          other.appLanguage == this.appLanguage &&
          other.streetNames == this.streetNames &&
          other.theme == this.theme &&
          other.sound == this.sound &&
          other.haptics == this.haptics &&
          other.homeCoachSeen == this.homeCoachSeen);
}

class UserSettingsCompanion extends UpdateCompanion<Settings> {
  final Value<int> id;
  final Value<String?> lastCity;
  final Value<String?> lastAreaJson;
  final Value<Difficulty?> lastDifficulty;
  final Value<AppLanguage?> appLanguage;
  final Value<StreetNameMode> streetNames;
  final Value<ThemePreference> theme;
  final Value<bool> sound;
  final Value<bool> haptics;
  final Value<bool> homeCoachSeen;
  const UserSettingsCompanion({
    this.id = const Value.absent(),
    this.lastCity = const Value.absent(),
    this.lastAreaJson = const Value.absent(),
    this.lastDifficulty = const Value.absent(),
    this.appLanguage = const Value.absent(),
    this.streetNames = const Value.absent(),
    this.theme = const Value.absent(),
    this.sound = const Value.absent(),
    this.haptics = const Value.absent(),
    this.homeCoachSeen = const Value.absent(),
  });
  UserSettingsCompanion.insert({
    this.id = const Value.absent(),
    this.lastCity = const Value.absent(),
    this.lastAreaJson = const Value.absent(),
    this.lastDifficulty = const Value.absent(),
    this.appLanguage = const Value.absent(),
    this.streetNames = const Value.absent(),
    this.theme = const Value.absent(),
    this.sound = const Value.absent(),
    this.haptics = const Value.absent(),
    this.homeCoachSeen = const Value.absent(),
  });
  static Insertable<Settings> custom({
    Expression<int>? id,
    Expression<String>? lastCity,
    Expression<String>? lastAreaJson,
    Expression<String>? lastDifficulty,
    Expression<String>? appLanguage,
    Expression<String>? streetNames,
    Expression<String>? theme,
    Expression<bool>? sound,
    Expression<bool>? haptics,
    Expression<bool>? homeCoachSeen,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lastCity != null) 'last_city': lastCity,
      if (lastAreaJson != null) 'last_area_json': lastAreaJson,
      if (lastDifficulty != null) 'last_difficulty': lastDifficulty,
      if (appLanguage != null) 'app_language': appLanguage,
      if (streetNames != null) 'street_names': streetNames,
      if (theme != null) 'theme': theme,
      if (sound != null) 'sound': sound,
      if (haptics != null) 'haptics': haptics,
      if (homeCoachSeen != null) 'home_coach_seen': homeCoachSeen,
    });
  }

  UserSettingsCompanion copyWith({
    Value<int>? id,
    Value<String?>? lastCity,
    Value<String?>? lastAreaJson,
    Value<Difficulty?>? lastDifficulty,
    Value<AppLanguage?>? appLanguage,
    Value<StreetNameMode>? streetNames,
    Value<ThemePreference>? theme,
    Value<bool>? sound,
    Value<bool>? haptics,
    Value<bool>? homeCoachSeen,
  }) {
    return UserSettingsCompanion(
      id: id ?? this.id,
      lastCity: lastCity ?? this.lastCity,
      lastAreaJson: lastAreaJson ?? this.lastAreaJson,
      lastDifficulty: lastDifficulty ?? this.lastDifficulty,
      appLanguage: appLanguage ?? this.appLanguage,
      streetNames: streetNames ?? this.streetNames,
      theme: theme ?? this.theme,
      sound: sound ?? this.sound,
      haptics: haptics ?? this.haptics,
      homeCoachSeen: homeCoachSeen ?? this.homeCoachSeen,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lastCity.present) {
      map['last_city'] = Variable<String>(lastCity.value);
    }
    if (lastAreaJson.present) {
      map['last_area_json'] = Variable<String>(lastAreaJson.value);
    }
    if (lastDifficulty.present) {
      map['last_difficulty'] = Variable<String>(
        $UserSettingsTable.$converterlastDifficultyn.toSql(
          lastDifficulty.value,
        ),
      );
    }
    if (appLanguage.present) {
      map['app_language'] = Variable<String>(
        $UserSettingsTable.$converterappLanguagen.toSql(appLanguage.value),
      );
    }
    if (streetNames.present) {
      map['street_names'] = Variable<String>(
        $UserSettingsTable.$converterstreetNames.toSql(streetNames.value),
      );
    }
    if (theme.present) {
      map['theme'] = Variable<String>(
        $UserSettingsTable.$convertertheme.toSql(theme.value),
      );
    }
    if (sound.present) {
      map['sound'] = Variable<bool>(sound.value);
    }
    if (haptics.present) {
      map['haptics'] = Variable<bool>(haptics.value);
    }
    if (homeCoachSeen.present) {
      map['home_coach_seen'] = Variable<bool>(homeCoachSeen.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('UserSettingsCompanion(')
          ..write('id: $id, ')
          ..write('lastCity: $lastCity, ')
          ..write('lastAreaJson: $lastAreaJson, ')
          ..write('lastDifficulty: $lastDifficulty, ')
          ..write('appLanguage: $appLanguage, ')
          ..write('streetNames: $streetNames, ')
          ..write('theme: $theme, ')
          ..write('sound: $sound, ')
          ..write('haptics: $haptics, ')
          ..write('homeCoachSeen: $homeCoachSeen')
          ..write(')'))
        .toString();
  }
}

class $RoundQuestionsTable extends RoundQuestions
    with TableInfo<$RoundQuestionsTable, RoundQuestion> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoundQuestionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _roundIdMeta = const VerificationMeta(
    'roundId',
  );
  @override
  late final GeneratedColumn<String> roundId = GeneratedColumn<String>(
    'round_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES round (id)',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _streetIdMeta = const VerificationMeta(
    'streetId',
  );
  @override
  late final GeneratedColumn<String> streetId = GeneratedColumn<String>(
    'street_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [roundId, position, streetId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'round_question';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoundQuestion> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('round_id')) {
      context.handle(
        _roundIdMeta,
        roundId.isAcceptableOrUnknown(data['round_id']!, _roundIdMeta),
      );
    } else if (isInserting) {
      context.missing(_roundIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('street_id')) {
      context.handle(
        _streetIdMeta,
        streetId.isAcceptableOrUnknown(data['street_id']!, _streetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_streetIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {roundId, position};
  @override
  RoundQuestion map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoundQuestion(
      roundId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}round_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      streetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}street_id'],
      )!,
    );
  }

  @override
  $RoundQuestionsTable createAlias(String alias) {
    return $RoundQuestionsTable(attachedDatabase, alias);
  }
}

class RoundQuestion extends DataClass implements Insertable<RoundQuestion> {
  final String roundId;
  final int position;
  final String streetId;
  const RoundQuestion({
    required this.roundId,
    required this.position,
    required this.streetId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['round_id'] = Variable<String>(roundId);
    map['position'] = Variable<int>(position);
    map['street_id'] = Variable<String>(streetId);
    return map;
  }

  RoundQuestionsCompanion toCompanion(bool nullToAbsent) {
    return RoundQuestionsCompanion(
      roundId: Value(roundId),
      position: Value(position),
      streetId: Value(streetId),
    );
  }

  factory RoundQuestion.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoundQuestion(
      roundId: serializer.fromJson<String>(json['roundId']),
      position: serializer.fromJson<int>(json['position']),
      streetId: serializer.fromJson<String>(json['streetId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'roundId': serializer.toJson<String>(roundId),
      'position': serializer.toJson<int>(position),
      'streetId': serializer.toJson<String>(streetId),
    };
  }

  RoundQuestion copyWith({String? roundId, int? position, String? streetId}) =>
      RoundQuestion(
        roundId: roundId ?? this.roundId,
        position: position ?? this.position,
        streetId: streetId ?? this.streetId,
      );
  RoundQuestion copyWithCompanion(RoundQuestionsCompanion data) {
    return RoundQuestion(
      roundId: data.roundId.present ? data.roundId.value : this.roundId,
      position: data.position.present ? data.position.value : this.position,
      streetId: data.streetId.present ? data.streetId.value : this.streetId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoundQuestion(')
          ..write('roundId: $roundId, ')
          ..write('position: $position, ')
          ..write('streetId: $streetId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(roundId, position, streetId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoundQuestion &&
          other.roundId == this.roundId &&
          other.position == this.position &&
          other.streetId == this.streetId);
}

class RoundQuestionsCompanion extends UpdateCompanion<RoundQuestion> {
  final Value<String> roundId;
  final Value<int> position;
  final Value<String> streetId;
  final Value<int> rowid;
  const RoundQuestionsCompanion({
    this.roundId = const Value.absent(),
    this.position = const Value.absent(),
    this.streetId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RoundQuestionsCompanion.insert({
    required String roundId,
    required int position,
    required String streetId,
    this.rowid = const Value.absent(),
  }) : roundId = Value(roundId),
       position = Value(position),
       streetId = Value(streetId);
  static Insertable<RoundQuestion> custom({
    Expression<String>? roundId,
    Expression<int>? position,
    Expression<String>? streetId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (roundId != null) 'round_id': roundId,
      if (position != null) 'position': position,
      if (streetId != null) 'street_id': streetId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RoundQuestionsCompanion copyWith({
    Value<String>? roundId,
    Value<int>? position,
    Value<String>? streetId,
    Value<int>? rowid,
  }) {
    return RoundQuestionsCompanion(
      roundId: roundId ?? this.roundId,
      position: position ?? this.position,
      streetId: streetId ?? this.streetId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (roundId.present) {
      map['round_id'] = Variable<String>(roundId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (streetId.present) {
      map['street_id'] = Variable<String>(streetId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoundQuestionsCompanion(')
          ..write('roundId: $roundId, ')
          ..write('position: $position, ')
          ..write('streetId: $streetId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $RoundsTable rounds = $RoundsTable(this);
  late final $AnswersTable answers = $AnswersTable(this);
  late final Trigger answerImmutable = Trigger(
    'CREATE TRIGGER answer_immutable BEFORE UPDATE ON answer BEGIN SELECT RAISE (ABORT, \'answer rows are immutable\');END',
    'answer_immutable',
  );
  late final $UserSettingsTable userSettings = $UserSettingsTable(this);
  late final $RoundQuestionsTable roundQuestions = $RoundQuestionsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    rounds,
    answers,
    answerImmutable,
    userSettings,
    roundQuestions,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'answer',
        limitUpdateKind: UpdateKind.update,
      ),
      result: [],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$RoundsTableCreateCompanionBuilder =
    RoundsCompanion Function({
      Value<String> id,
      required String cityId,
      required String areaJson,
      required Difficulty difficulty,
      required String packVersion,
      Value<DateTime> startedAt,
      Value<DateTime?> finishedAt,
      Value<String?> retryOf,
      Value<int> rowid,
    });
typedef $$RoundsTableUpdateCompanionBuilder =
    RoundsCompanion Function({
      Value<String> id,
      Value<String> cityId,
      Value<String> areaJson,
      Value<Difficulty> difficulty,
      Value<String> packVersion,
      Value<DateTime> startedAt,
      Value<DateTime?> finishedAt,
      Value<String?> retryOf,
      Value<int> rowid,
    });

final class $$RoundsTableReferences
    extends BaseReferences<_$AppDatabase, $RoundsTable, Round> {
  $$RoundsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $RoundsTable _retryOfTable(_$AppDatabase db) =>
      db.rounds.createAlias('round__retry_of__round__id');

  $$RoundsTableProcessedTableManager? get retryOf {
    final $_column = $_itemColumn<String>('retry_of');
    if ($_column == null) return null;
    final manager = $$RoundsTableTableManager(
      $_db,
      $_db.rounds,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_retryOfTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$AnswersTable, List<Answer>> _answersRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.answers,
    aliasName: 'round__id__answer__round_id',
  );

  $$AnswersTableProcessedTableManager get answersRefs {
    final manager = $$AnswersTableTableManager(
      $_db,
      $_db.answers,
    ).filter((f) => f.roundId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_answersRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$RoundQuestionsTable, List<RoundQuestion>>
  _roundQuestionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.roundQuestions,
    aliasName: 'round__id__round_question__round_id',
  );

  $$RoundQuestionsTableProcessedTableManager get roundQuestionsRefs {
    final manager = $$RoundQuestionsTableTableManager(
      $_db,
      $_db.roundQuestions,
    ).filter((f) => f.roundId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_roundQuestionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RoundsTableFilterComposer
    extends Composer<_$AppDatabase, $RoundsTable> {
  $$RoundsTableFilterComposer({
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

  ColumnFilters<String> get cityId => $composableBuilder(
    column: $table.cityId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get areaJson => $composableBuilder(
    column: $table.areaJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Difficulty, Difficulty, String>
  get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$RoundsTableFilterComposer get retryOf {
    final $$RoundsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.retryOf,
      referencedTable: $db.rounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoundsTableFilterComposer(
            $db: $db,
            $table: $db.rounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> answersRefs(
    Expression<bool> Function($$AnswersTableFilterComposer f) f,
  ) {
    final $$AnswersTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.answers,
      getReferencedColumn: (t) => t.roundId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnswersTableFilterComposer(
            $db: $db,
            $table: $db.answers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> roundQuestionsRefs(
    Expression<bool> Function($$RoundQuestionsTableFilterComposer f) f,
  ) {
    final $$RoundQuestionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.roundQuestions,
      getReferencedColumn: (t) => t.roundId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoundQuestionsTableFilterComposer(
            $db: $db,
            $table: $db.roundQuestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RoundsTableOrderingComposer
    extends Composer<_$AppDatabase, $RoundsTable> {
  $$RoundsTableOrderingComposer({
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

  ColumnOrderings<String> get cityId => $composableBuilder(
    column: $table.cityId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get areaJson => $composableBuilder(
    column: $table.areaJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$RoundsTableOrderingComposer get retryOf {
    final $$RoundsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.retryOf,
      referencedTable: $db.rounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoundsTableOrderingComposer(
            $db: $db,
            $table: $db.rounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RoundsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoundsTable> {
  $$RoundsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cityId =>
      $composableBuilder(column: $table.cityId, builder: (column) => column);

  GeneratedColumn<String> get areaJson =>
      $composableBuilder(column: $table.areaJson, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Difficulty, String> get difficulty =>
      $composableBuilder(
        column: $table.difficulty,
        builder: (column) => column,
      );

  GeneratedColumn<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get finishedAt => $composableBuilder(
    column: $table.finishedAt,
    builder: (column) => column,
  );

  $$RoundsTableAnnotationComposer get retryOf {
    final $$RoundsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.retryOf,
      referencedTable: $db.rounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoundsTableAnnotationComposer(
            $db: $db,
            $table: $db.rounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> answersRefs<T extends Object>(
    Expression<T> Function($$AnswersTableAnnotationComposer a) f,
  ) {
    final $$AnswersTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.answers,
      getReferencedColumn: (t) => t.roundId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AnswersTableAnnotationComposer(
            $db: $db,
            $table: $db.answers,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> roundQuestionsRefs<T extends Object>(
    Expression<T> Function($$RoundQuestionsTableAnnotationComposer a) f,
  ) {
    final $$RoundQuestionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.roundQuestions,
      getReferencedColumn: (t) => t.roundId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoundQuestionsTableAnnotationComposer(
            $db: $db,
            $table: $db.roundQuestions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RoundsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoundsTable,
          Round,
          $$RoundsTableFilterComposer,
          $$RoundsTableOrderingComposer,
          $$RoundsTableAnnotationComposer,
          $$RoundsTableCreateCompanionBuilder,
          $$RoundsTableUpdateCompanionBuilder,
          (Round, $$RoundsTableReferences),
          Round,
          PrefetchHooks Function({
            bool retryOf,
            bool answersRefs,
            bool roundQuestionsRefs,
          })
        > {
  $$RoundsTableTableManager(_$AppDatabase db, $RoundsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoundsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoundsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoundsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> cityId = const Value.absent(),
                Value<String> areaJson = const Value.absent(),
                Value<Difficulty> difficulty = const Value.absent(),
                Value<String> packVersion = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<String?> retryOf = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoundsCompanion(
                id: id,
                cityId: cityId,
                areaJson: areaJson,
                difficulty: difficulty,
                packVersion: packVersion,
                startedAt: startedAt,
                finishedAt: finishedAt,
                retryOf: retryOf,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String cityId,
                required String areaJson,
                required Difficulty difficulty,
                required String packVersion,
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> finishedAt = const Value.absent(),
                Value<String?> retryOf = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoundsCompanion.insert(
                id: id,
                cityId: cityId,
                areaJson: areaJson,
                difficulty: difficulty,
                packVersion: packVersion,
                startedAt: startedAt,
                finishedAt: finishedAt,
                retryOf: retryOf,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RoundsTable, Round>(table),
                  $$RoundsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                retryOf = false,
                answersRefs = false,
                roundQuestionsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (answersRefs) db.answers,
                    if (roundQuestionsRefs) db.roundQuestions,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (retryOf) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.retryOf,
                                    referencedTable: $$RoundsTableReferences
                                        ._retryOfTable(db),
                                    referencedColumn: $$RoundsTableReferences
                                        ._retryOfTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (answersRefs)
                        await $_getPrefetchedDataByColumns<
                          Round,
                          $RoundsTable,
                          Answer,
                          $AnswersTable
                        >(
                          currentTable: table,
                          referencedTable: $$RoundsTableReferences
                              ._answersRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RoundsTableReferences(
                                db,
                                table,
                                p0,
                              ).answersRefs,
                          currentColumn: 'id',
                          referencedColumn: 'round_id',
                          typedResults: items,
                        ),
                      if (roundQuestionsRefs)
                        await $_getPrefetchedDataByColumns<
                          Round,
                          $RoundsTable,
                          RoundQuestion,
                          $RoundQuestionsTable
                        >(
                          currentTable: table,
                          referencedTable: $$RoundsTableReferences
                              ._roundQuestionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$RoundsTableReferences(
                                db,
                                table,
                                p0,
                              ).roundQuestionsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'round_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$RoundsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoundsTable,
      Round,
      $$RoundsTableFilterComposer,
      $$RoundsTableOrderingComposer,
      $$RoundsTableAnnotationComposer,
      $$RoundsTableCreateCompanionBuilder,
      $$RoundsTableUpdateCompanionBuilder,
      (Round, $$RoundsTableReferences),
      Round,
      PrefetchHooks Function({
        bool retryOf,
        bool answersRefs,
        bool roundQuestionsRefs,
      })
    >;
typedef $$AnswersTableCreateCompanionBuilder =
    AnswersCompanion Function({
      Value<String> id,
      required String roundId,
      required String streetId,
      required double pinLat,
      required double pinLon,
      required double distanceM,
      required Tier tier,
      required int xp,
      required String packVersion,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });
typedef $$AnswersTableUpdateCompanionBuilder =
    AnswersCompanion Function({
      Value<String> id,
      Value<String> roundId,
      Value<String> streetId,
      Value<double> pinLat,
      Value<double> pinLon,
      Value<double> distanceM,
      Value<Tier> tier,
      Value<int> xp,
      Value<String> packVersion,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

final class $$AnswersTableReferences
    extends BaseReferences<_$AppDatabase, $AnswersTable, Answer> {
  $$AnswersTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $RoundsTable _roundIdTable(_$AppDatabase db) =>
      db.rounds.createAlias('answer__round_id__round__id');

  $$RoundsTableProcessedTableManager get roundId {
    final $_column = $_itemColumn<String>('round_id')!;

    final manager = $$RoundsTableTableManager(
      $_db,
      $_db.rounds,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_roundIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$AnswersTableFilterComposer
    extends Composer<_$AppDatabase, $AnswersTable> {
  $$AnswersTableFilterComposer({
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

  ColumnFilters<String> get streetId => $composableBuilder(
    column: $table.streetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pinLat => $composableBuilder(
    column: $table.pinLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pinLon => $composableBuilder(
    column: $table.pinLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Tier, Tier, String> get tier =>
      $composableBuilder(
        column: $table.tier,
        builder: (column) => ColumnWithTypeConverterFilters(column),
      );

  ColumnFilters<int> get xp => $composableBuilder(
    column: $table.xp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  $$RoundsTableFilterComposer get roundId {
    final $$RoundsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roundId,
      referencedTable: $db.rounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoundsTableFilterComposer(
            $db: $db,
            $table: $db.rounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnswersTableOrderingComposer
    extends Composer<_$AppDatabase, $AnswersTable> {
  $$AnswersTableOrderingComposer({
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

  ColumnOrderings<String> get streetId => $composableBuilder(
    column: $table.streetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pinLat => $composableBuilder(
    column: $table.pinLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pinLon => $composableBuilder(
    column: $table.pinLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceM => $composableBuilder(
    column: $table.distanceM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tier => $composableBuilder(
    column: $table.tier,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get xp => $composableBuilder(
    column: $table.xp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$RoundsTableOrderingComposer get roundId {
    final $$RoundsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roundId,
      referencedTable: $db.rounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoundsTableOrderingComposer(
            $db: $db,
            $table: $db.rounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnswersTableAnnotationComposer
    extends Composer<_$AppDatabase, $AnswersTable> {
  $$AnswersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get streetId =>
      $composableBuilder(column: $table.streetId, builder: (column) => column);

  GeneratedColumn<double> get pinLat =>
      $composableBuilder(column: $table.pinLat, builder: (column) => column);

  GeneratedColumn<double> get pinLon =>
      $composableBuilder(column: $table.pinLon, builder: (column) => column);

  GeneratedColumn<double> get distanceM =>
      $composableBuilder(column: $table.distanceM, builder: (column) => column);

  GeneratedColumnWithTypeConverter<Tier, String> get tier =>
      $composableBuilder(column: $table.tier, builder: (column) => column);

  GeneratedColumn<int> get xp =>
      $composableBuilder(column: $table.xp, builder: (column) => column);

  GeneratedColumn<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  $$RoundsTableAnnotationComposer get roundId {
    final $$RoundsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roundId,
      referencedTable: $db.rounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoundsTableAnnotationComposer(
            $db: $db,
            $table: $db.rounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$AnswersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AnswersTable,
          Answer,
          $$AnswersTableFilterComposer,
          $$AnswersTableOrderingComposer,
          $$AnswersTableAnnotationComposer,
          $$AnswersTableCreateCompanionBuilder,
          $$AnswersTableUpdateCompanionBuilder,
          (Answer, $$AnswersTableReferences),
          Answer,
          PrefetchHooks Function({bool roundId})
        > {
  $$AnswersTableTableManager(_$AppDatabase db, $AnswersTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnswersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AnswersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnswersTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> roundId = const Value.absent(),
                Value<String> streetId = const Value.absent(),
                Value<double> pinLat = const Value.absent(),
                Value<double> pinLon = const Value.absent(),
                Value<double> distanceM = const Value.absent(),
                Value<Tier> tier = const Value.absent(),
                Value<int> xp = const Value.absent(),
                Value<String> packVersion = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnswersCompanion(
                id: id,
                roundId: roundId,
                streetId: streetId,
                pinLat: pinLat,
                pinLon: pinLon,
                distanceM: distanceM,
                tier: tier,
                xp: xp,
                packVersion: packVersion,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                required String roundId,
                required String streetId,
                required double pinLat,
                required double pinLon,
                required double distanceM,
                required Tier tier,
                required int xp,
                required String packVersion,
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AnswersCompanion.insert(
                id: id,
                roundId: roundId,
                streetId: streetId,
                pinLat: pinLat,
                pinLon: pinLon,
                distanceM: distanceM,
                tier: tier,
                xp: xp,
                packVersion: packVersion,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AnswersTable, Answer>(table),
                  $$AnswersTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({roundId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (roundId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.roundId,
                                referencedTable: $$AnswersTableReferences
                                    ._roundIdTable(db),
                                referencedColumn: $$AnswersTableReferences
                                    ._roundIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$AnswersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AnswersTable,
      Answer,
      $$AnswersTableFilterComposer,
      $$AnswersTableOrderingComposer,
      $$AnswersTableAnnotationComposer,
      $$AnswersTableCreateCompanionBuilder,
      $$AnswersTableUpdateCompanionBuilder,
      (Answer, $$AnswersTableReferences),
      Answer,
      PrefetchHooks Function({bool roundId})
    >;
typedef $$UserSettingsTableCreateCompanionBuilder =
    UserSettingsCompanion Function({
      Value<int> id,
      Value<String?> lastCity,
      Value<String?> lastAreaJson,
      Value<Difficulty?> lastDifficulty,
      Value<AppLanguage?> appLanguage,
      Value<StreetNameMode> streetNames,
      Value<ThemePreference> theme,
      Value<bool> sound,
      Value<bool> haptics,
      Value<bool> homeCoachSeen,
    });
typedef $$UserSettingsTableUpdateCompanionBuilder =
    UserSettingsCompanion Function({
      Value<int> id,
      Value<String?> lastCity,
      Value<String?> lastAreaJson,
      Value<Difficulty?> lastDifficulty,
      Value<AppLanguage?> appLanguage,
      Value<StreetNameMode> streetNames,
      Value<ThemePreference> theme,
      Value<bool> sound,
      Value<bool> haptics,
      Value<bool> homeCoachSeen,
    });

class $$UserSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableFilterComposer({
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

  ColumnFilters<String> get lastCity => $composableBuilder(
    column: $table.lastCity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastAreaJson => $composableBuilder(
    column: $table.lastAreaJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<Difficulty?, Difficulty, String>
  get lastDifficulty => $composableBuilder(
    column: $table.lastDifficulty,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<AppLanguage?, AppLanguage, String>
  get appLanguage => $composableBuilder(
    column: $table.appLanguage,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<StreetNameMode, StreetNameMode, String>
  get streetNames => $composableBuilder(
    column: $table.streetNames,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnWithTypeConverterFilters<ThemePreference, ThemePreference, String>
  get theme => $composableBuilder(
    column: $table.theme,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get sound => $composableBuilder(
    column: $table.sound,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get haptics => $composableBuilder(
    column: $table.haptics,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get homeCoachSeen => $composableBuilder(
    column: $table.homeCoachSeen,
    builder: (column) => ColumnFilters(column),
  );
}

class $$UserSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableOrderingComposer({
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

  ColumnOrderings<String> get lastCity => $composableBuilder(
    column: $table.lastCity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastAreaJson => $composableBuilder(
    column: $table.lastAreaJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastDifficulty => $composableBuilder(
    column: $table.lastDifficulty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appLanguage => $composableBuilder(
    column: $table.appLanguage,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streetNames => $composableBuilder(
    column: $table.streetNames,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get theme => $composableBuilder(
    column: $table.theme,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get sound => $composableBuilder(
    column: $table.sound,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get haptics => $composableBuilder(
    column: $table.haptics,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get homeCoachSeen => $composableBuilder(
    column: $table.homeCoachSeen,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$UserSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $UserSettingsTable> {
  $$UserSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get lastCity =>
      $composableBuilder(column: $table.lastCity, builder: (column) => column);

  GeneratedColumn<String> get lastAreaJson => $composableBuilder(
    column: $table.lastAreaJson,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<Difficulty?, String> get lastDifficulty =>
      $composableBuilder(
        column: $table.lastDifficulty,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<AppLanguage?, String> get appLanguage =>
      $composableBuilder(
        column: $table.appLanguage,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<StreetNameMode, String> get streetNames =>
      $composableBuilder(
        column: $table.streetNames,
        builder: (column) => column,
      );

  GeneratedColumnWithTypeConverter<ThemePreference, String> get theme =>
      $composableBuilder(column: $table.theme, builder: (column) => column);

  GeneratedColumn<bool> get sound =>
      $composableBuilder(column: $table.sound, builder: (column) => column);

  GeneratedColumn<bool> get haptics =>
      $composableBuilder(column: $table.haptics, builder: (column) => column);

  GeneratedColumn<bool> get homeCoachSeen => $composableBuilder(
    column: $table.homeCoachSeen,
    builder: (column) => column,
  );
}

class $$UserSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $UserSettingsTable,
          Settings,
          $$UserSettingsTableFilterComposer,
          $$UserSettingsTableOrderingComposer,
          $$UserSettingsTableAnnotationComposer,
          $$UserSettingsTableCreateCompanionBuilder,
          $$UserSettingsTableUpdateCompanionBuilder,
          (
            Settings,
            BaseReferences<_$AppDatabase, $UserSettingsTable, Settings>,
          ),
          Settings,
          PrefetchHooks Function()
        > {
  $$UserSettingsTableTableManager(_$AppDatabase db, $UserSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$UserSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$UserSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$UserSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> lastCity = const Value.absent(),
                Value<String?> lastAreaJson = const Value.absent(),
                Value<Difficulty?> lastDifficulty = const Value.absent(),
                Value<AppLanguage?> appLanguage = const Value.absent(),
                Value<StreetNameMode> streetNames = const Value.absent(),
                Value<ThemePreference> theme = const Value.absent(),
                Value<bool> sound = const Value.absent(),
                Value<bool> haptics = const Value.absent(),
                Value<bool> homeCoachSeen = const Value.absent(),
              }) => UserSettingsCompanion(
                id: id,
                lastCity: lastCity,
                lastAreaJson: lastAreaJson,
                lastDifficulty: lastDifficulty,
                appLanguage: appLanguage,
                streetNames: streetNames,
                theme: theme,
                sound: sound,
                haptics: haptics,
                homeCoachSeen: homeCoachSeen,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> lastCity = const Value.absent(),
                Value<String?> lastAreaJson = const Value.absent(),
                Value<Difficulty?> lastDifficulty = const Value.absent(),
                Value<AppLanguage?> appLanguage = const Value.absent(),
                Value<StreetNameMode> streetNames = const Value.absent(),
                Value<ThemePreference> theme = const Value.absent(),
                Value<bool> sound = const Value.absent(),
                Value<bool> haptics = const Value.absent(),
                Value<bool> homeCoachSeen = const Value.absent(),
              }) => UserSettingsCompanion.insert(
                id: id,
                lastCity: lastCity,
                lastAreaJson: lastAreaJson,
                lastDifficulty: lastDifficulty,
                appLanguage: appLanguage,
                streetNames: streetNames,
                theme: theme,
                sound: sound,
                haptics: haptics,
                homeCoachSeen: homeCoachSeen,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$UserSettingsTable, Settings>(table),
                  BaseReferences<_$AppDatabase, $UserSettingsTable, Settings>(
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

typedef $$UserSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $UserSettingsTable,
      Settings,
      $$UserSettingsTableFilterComposer,
      $$UserSettingsTableOrderingComposer,
      $$UserSettingsTableAnnotationComposer,
      $$UserSettingsTableCreateCompanionBuilder,
      $$UserSettingsTableUpdateCompanionBuilder,
      (Settings, BaseReferences<_$AppDatabase, $UserSettingsTable, Settings>),
      Settings,
      PrefetchHooks Function()
    >;
typedef $$RoundQuestionsTableCreateCompanionBuilder =
    RoundQuestionsCompanion Function({
      required String roundId,
      required int position,
      required String streetId,
      Value<int> rowid,
    });
typedef $$RoundQuestionsTableUpdateCompanionBuilder =
    RoundQuestionsCompanion Function({
      Value<String> roundId,
      Value<int> position,
      Value<String> streetId,
      Value<int> rowid,
    });

final class $$RoundQuestionsTableReferences
    extends BaseReferences<_$AppDatabase, $RoundQuestionsTable, RoundQuestion> {
  $$RoundQuestionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $RoundsTable _roundIdTable(_$AppDatabase db) =>
      db.rounds.createAlias('round_question__round_id__round__id');

  $$RoundsTableProcessedTableManager get roundId {
    final $_column = $_itemColumn<String>('round_id')!;

    final manager = $$RoundsTableTableManager(
      $_db,
      $_db.rounds,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_roundIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$RoundQuestionsTableFilterComposer
    extends Composer<_$AppDatabase, $RoundQuestionsTable> {
  $$RoundQuestionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get streetId => $composableBuilder(
    column: $table.streetId,
    builder: (column) => ColumnFilters(column),
  );

  $$RoundsTableFilterComposer get roundId {
    final $$RoundsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roundId,
      referencedTable: $db.rounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoundsTableFilterComposer(
            $db: $db,
            $table: $db.rounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RoundQuestionsTableOrderingComposer
    extends Composer<_$AppDatabase, $RoundQuestionsTable> {
  $$RoundQuestionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get streetId => $composableBuilder(
    column: $table.streetId,
    builder: (column) => ColumnOrderings(column),
  );

  $$RoundsTableOrderingComposer get roundId {
    final $$RoundsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roundId,
      referencedTable: $db.rounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoundsTableOrderingComposer(
            $db: $db,
            $table: $db.rounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RoundQuestionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoundQuestionsTable> {
  $$RoundQuestionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get streetId =>
      $composableBuilder(column: $table.streetId, builder: (column) => column);

  $$RoundsTableAnnotationComposer get roundId {
    final $$RoundsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roundId,
      referencedTable: $db.rounds,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoundsTableAnnotationComposer(
            $db: $db,
            $table: $db.rounds,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$RoundQuestionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoundQuestionsTable,
          RoundQuestion,
          $$RoundQuestionsTableFilterComposer,
          $$RoundQuestionsTableOrderingComposer,
          $$RoundQuestionsTableAnnotationComposer,
          $$RoundQuestionsTableCreateCompanionBuilder,
          $$RoundQuestionsTableUpdateCompanionBuilder,
          (RoundQuestion, $$RoundQuestionsTableReferences),
          RoundQuestion,
          PrefetchHooks Function({bool roundId})
        > {
  $$RoundQuestionsTableTableManager(
    _$AppDatabase db,
    $RoundQuestionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoundQuestionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoundQuestionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoundQuestionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> roundId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> streetId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RoundQuestionsCompanion(
                roundId: roundId,
                position: position,
                streetId: streetId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String roundId,
                required int position,
                required String streetId,
                Value<int> rowid = const Value.absent(),
              }) => RoundQuestionsCompanion.insert(
                roundId: roundId,
                position: position,
                streetId: streetId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RoundQuestionsTable, RoundQuestion>(table),
                  $$RoundQuestionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({roundId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (roundId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.roundId,
                                referencedTable: $$RoundQuestionsTableReferences
                                    ._roundIdTable(db),
                                referencedColumn:
                                    $$RoundQuestionsTableReferences
                                        ._roundIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$RoundQuestionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoundQuestionsTable,
      RoundQuestion,
      $$RoundQuestionsTableFilterComposer,
      $$RoundQuestionsTableOrderingComposer,
      $$RoundQuestionsTableAnnotationComposer,
      $$RoundQuestionsTableCreateCompanionBuilder,
      $$RoundQuestionsTableUpdateCompanionBuilder,
      (RoundQuestion, $$RoundQuestionsTableReferences),
      RoundQuestion,
      PrefetchHooks Function({bool roundId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$RoundsTableTableManager get rounds =>
      $$RoundsTableTableManager(_db, _db.rounds);
  $$AnswersTableTableManager get answers =>
      $$AnswersTableTableManager(_db, _db.answers);
  $$UserSettingsTableTableManager get userSettings =>
      $$UserSettingsTableTableManager(_db, _db.userSettings);
  $$RoundQuestionsTableTableManager get roundQuestions =>
      $$RoundQuestionsTableTableManager(_db, _db.roundQuestions);
}
