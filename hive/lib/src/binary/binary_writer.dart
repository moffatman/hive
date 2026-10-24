part of hive;

/// The [BinaryWriter] is used to encode data to the binary format.
abstract class BinaryWriter {
  /// The UTF-8 encoder is used to encode Strings.
  static const utf8Encoder = Utf8Encoder();

  /// Write a single byte.
  void writeByte(int byte);

  /// Write a 16-bit unsigned integer as two bytes.
  void writeWord(int value);

  /// Write a 32-bit signed integer as four bytes.
  void writeInt32(int value);

  /// Write a 32-bit unsigned integer as four bytes.
  void writeUint32(int value);

  /// Write an integer using the legacy eight-byte double encoding.
  /// Use [writeInt64] for exact large integers in versioned adapter formats.
  void writeInt(int value);

  /// Write a signed 64-bit integer as eight bytes, without a type ID.
  /// Pair with [BinaryReader.readInt64], not the legacy `readInt` method.
  void writeInt64(int value);

  /// Write a 64-bit double as eight bytes.
  void writeDouble(double value);

  /// Write a boolean.
  void writeBool(bool value);

  /// Encode the UTF-8 String [value] and write its bytes.
  void writeString(
    String value, {
    bool writeByteCount = true,
    Converter<String, List<int>> encoder = utf8Encoder,
  });

  /// Write a list of [bytes].
  void writeByteList(List<int> bytes, {bool writeLength = true});

  /// Write a [list] of integers.
  void writeIntList(List<int> list, {bool writeLength = true});

  /// Write integers as exact signed 64-bit values, without a type ID.
  void writeInt64List(List<int> list, {bool writeLength = true});

  /// Write a [list] of doubles.
  void writeDoubleList(List<double> list, {bool writeLength = true});

  /// Write a [list] of booleans.
  void writeBoolList(List<bool> list, {bool writeLength = true});

  /// Write a [list] of Strings.
  void writeStringList(
    List<String> list, {
    bool writeLength = true,
    Converter<String, List<int>> encoder = utf8Encoder,
  });

  /// Write a [list].
  void writeList(List list, {bool writeLength = true});

  /// Write a [map].
  void writeMap(Map map, {bool writeLength = true});

  /// Write a [set].
  void writeSet(Set set, {bool writeLength = true});

  /// Write a [HiveList].
  void writeHiveList(HiveList list, {bool writeLength = true});

  /// Write any [value].
  void write<T>(T value, {bool writeTypeId = true});
}
