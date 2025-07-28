enum SqliteColumnType {
  integer(1),
  double(2),
  text(3),
  blob(4),
  nullType(5);// `null` is a reserved word, so use a different name

  final int value;
  const SqliteColumnType(this.value);

  static SqliteColumnType fromInt(int value) {
    return SqliteColumnType.values.firstWhere(
          (e) => e.value == value,
      orElse: () => SqliteColumnType.nullType,
    );
  }
}
