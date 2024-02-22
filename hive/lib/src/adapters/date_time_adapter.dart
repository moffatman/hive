import 'package:hive/hive.dart';

/// Adapter for DateTime
class DateTimeAdapter<T extends DateTime> extends TypeAdapter<T> {
  @override
  final typeId = 16;

  @override
  T read(BinaryReader reader) {
    var millis = reader.readInt();
    return DateTimeWithoutTZ.fromMillisecondsSinceEpoch(millis) as T;
  }

  @override
  void write(BinaryWriter writer, DateTime obj) {
    writer.writeInt(obj.millisecondsSinceEpoch);
  }

  @override
  /// This can't be const because the adapter is generic
  final fields = {
    0: ReadOnlyHiveFieldAdapter<T, int>(
      getter: (T x) => x.millisecondsSinceEpoch,
      fieldNumber: 0,
      fieldName: 'millisecondsSinceEpoch',
      merger: PrimitiveMerger()
    )
  };
}

class DateTimeWithoutTZ extends DateTime {
  DateTimeWithoutTZ.fromMillisecondsSinceEpoch(int millisecondsSinceEpoch)
      : super.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
}

class DateTimeWithTimezoneFields {
  static int getMillisecondsSinceEpoch(DateTime x) => x.millisecondsSinceEpoch;
  static const millisecondsSinceEpoch = ReadOnlyHiveFieldAdapter<DateTime, int>(
    getter: getMillisecondsSinceEpoch,
    fieldNumber: 0,
    fieldName: 'millisecondsSinceEpoch',
    merger: PrimitiveMerger()
  );
  static bool getIsUtc(DateTime x) => x.isUtc;
  static const isUtc = ReadOnlyHiveFieldAdapter<DateTime, bool>(
    getter: getIsUtc,
    fieldNumber: 1,
    fieldName: 'isUtc',
    merger: PrimitiveMerger()
  );
}

/// Alternative adapter for DateTime with time zone info
class DateTimeWithTimezoneAdapter extends TypeAdapter<DateTime> {
  @override
  final typeId = 18;

  @override
  DateTime read(BinaryReader reader) {
    var millis = reader.readInt();
    var isUtc = reader.readBool();
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: isUtc);
  }

  @override
  void write(BinaryWriter writer, DateTime obj) {
    writer.writeInt(obj.millisecondsSinceEpoch);
    writer.writeBool(obj.isUtc);
  }

  @override
  final fields = const {
    0: DateTimeWithTimezoneFields.millisecondsSinceEpoch,
    1: DateTimeWithTimezoneFields.isUtc
  };
}
