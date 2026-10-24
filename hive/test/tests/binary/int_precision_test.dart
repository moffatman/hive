@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:hive/src/binary/binary_reader_impl.dart';
import 'package:hive/src/binary/binary_writer_impl.dart';
import 'package:hive/src/binary/frame.dart';
import 'package:hive/src/hive_impl.dart';
import 'package:hive/src/registry/type_registry_impl.dart';
import 'package:test/test.dart';

import '../common.dart' show getTempDir;

const values = <int>[
  0,
  1,
  -1,
  0x1fffffffffffff,
  0x20000000000000,
  0x20000000000001,
  -0x20000000000001,
  6023364273353477121,
  6023364273353477122,
  -6023364273353477121,
  0x7ffffffffffffffe,
  0x7fffffffffffffff,
  -0x7fffffffffffffff,
  -0x8000000000000000,
];

void main() {
  test('tagged large integers use nine bytes with exact int64 payloads', () {
    final registry = TypeRegistryImpl();
    for (final value in values.where(
        (value) => value < -0x1fffffffffffff || value > 0x1fffffffffffff)) {
      final writer = BinaryWriterImpl(registry)..write(value);
      final expected = ByteData(9)
        ..setUint8(0, FrameValueType.int64T)
        ..setInt64(1, value, Endian.little);
      expect(writer.toBytes(), expected.buffer.asUint8List());
    }
  });

  test('tagged large integer lists use eight bytes per element', () {
    final registry = TypeRegistryImpl();
    final writer = BinaryWriterImpl(registry)..write(values);
    final bytes = writer.toBytes();
    expect(bytes.length, 1 + 4 + 8 * values.length);
    expect(bytes.first, FrameValueType.int64ListT);
    final expected = ByteData(4 + 8 * values.length)
      ..setUint32(0, values.length, Endian.little);
    for (var i = 0; i < values.length; i++) {
      expected.setInt64(4 + i * 8, values[i], Endian.little);
    }
    expect(bytes.sublist(1), expected.buffer.asUint8List());
  });

  test('type-less generic writes retain the raw adapter encoding', () {
    final registry = TypeRegistryImpl();
    final writer = BinaryWriterImpl(registry)
      ..write(123, writeTypeId: false)
      ..write(<int>[1, 2, 3], writeTypeId: false);
    final reader = BinaryReaderImpl(writer.toBytes(), registry);
    expect(reader.readInt(), 123);
    expect(reader.readIntList(), [1, 2, 3]);
    expect(reader.availableBytes, 0);
  });

  test('new integer tags do not collide with built-in adapter IDs', () {
    final hive = HiveImpl();
    final value = <dynamic>[
      DateTime.utc(2026, 10, 23),
      BigInt.parse('60233642733534771216023364273353477121'),
      6023364273353477121,
      values,
    ];
    expect(hive.decode(hive.encode(value)), value);
  });

  for (final encrypted in [false, true]) {
    test('large IDs survive compaction and lazy reopen (encrypted: $encrypted)',
        () async {
      final directory = await getTempDir();
      final hive = HiveImpl()..init(directory.path);
      addTearDown(() async {
        await hive.close();
        await directory.delete(recursive: true);
      });
      final cipher = encrypted ? HiveAesCipher(List.filled(32, 1)) : null;
      final box = await hive.openBox<dynamic>('ids', encryptionCipher: cipher);
      await box.put('ids', values);
      await box.put('id', 6023364273353477121);
      await box.put('id', 6023364273353477122);
      await box.compact();
      await box.close();
      final restored =
          await hive.openLazyBox<dynamic>('ids', encryptionCipher: cipher);
      expect(await restored.get('ids'), values);
      expect(await restored.get('id'), 6023364273353477122);
    });
  }

  for (final value in values) {
    test('integer $value round trips exactly', () {
      final registry = TypeRegistryImpl();
      final writer = BinaryWriterImpl(registry)..write(value);
      final reader = BinaryReaderImpl(writer.toBytes(), registry);
      expect(reader.read(), value);
      expect(reader.availableBytes, 0);
    });
  }

  test('raw adapter integers preserve the following fields', () {
    final registry = TypeRegistryImpl();
    final writer = BinaryWriterImpl(registry);
    for (final value in values) {
      writer.writeInt64(value);
    }
    writer.writeString('following field');
    final reader = BinaryReaderImpl(writer.toBytes(), registry);
    for (final value in values) {
      expect(reader.readInt64(), value);
    }
    expect(reader.readString(), 'following field');
    expect(reader.availableBytes, 0);
  });

  test('typed integer lists preserve large values and the next value', () {
    final registry = TypeRegistryImpl();
    final writer = BinaryWriterImpl(registry)
      ..write(values)
      ..write(123);
    final reader = BinaryReaderImpl(writer.toBytes(), registry);
    final restored = reader.read();
    expect(restored, isA<List<int>>());
    expect(restored, values);
    expect(reader.read(), 123);
    expect(reader.availableBytes, 0);
  });

  test('raw integer lists support externally supplied lengths', () {
    final registry = TypeRegistryImpl();
    final writer = BinaryWriterImpl(registry)
      ..writeInt64List(values, writeLength: false)
      ..writeString('next');
    final reader = BinaryReaderImpl(writer.toBytes(), registry);
    expect(reader.readInt64List(values.length), values);
    expect(reader.readString(), 'next');
  });

  test('nested maps, sets and lists retain distinct large IDs', () {
    final registry = TypeRegistryImpl();
    final value = {
      6023364273353477121: <dynamic>[
        6023364273353477122,
        {6023364273353477121, 6023364273353477122},
        values,
      ],
    };
    final writer = BinaryWriterImpl(registry)..write(value);
    expect(BinaryReaderImpl(writer.toBytes(), registry).read(), value);
  });

  test('exactly representable integers keep their legacy bytes', () {
    final registry = TypeRegistryImpl();
    for (final value in [0, -1, 0x20000000000000, 6023364273353477120]) {
      final legacy = ByteData(8)
        ..setFloat64(0, value.toDouble(), Endian.little);
      final writer = BinaryWriterImpl(registry)..writeInt(value);
      expect(writer.toBytes(), legacy.buffer.asUint8List());
    }
  });

  test('legacy integer and integer list data still decodes', () {
    final registry = TypeRegistryImpl();
    final bytes = ByteData(1 + 8 + 1 + 4 + 16)
      ..setUint8(0, FrameValueType.intT)
      ..setFloat64(1, 42, Endian.little)
      ..setUint8(9, FrameValueType.intListT)
      ..setUint32(10, 2, Endian.little)
      ..setFloat64(14, -1, Endian.little)
      ..setFloat64(22, 6023364273353477120.0, Endian.little);
    final reader = BinaryReaderImpl(bytes.buffer.asUint8List(), registry);
    expect(reader.read(), 42);
    expect(reader.read(), [-1, 6023364273353477120]);
    expect(reader.availableBytes, 0);
  });

  test('double NaN still round trips as a double', () {
    final registry = TypeRegistryImpl();
    final writer = BinaryWriterImpl(registry)..write(double.nan);
    expect(BinaryReaderImpl(writer.toBytes(), registry).read(), isNaN);
  });

  test('large integer lists survive buffer growth', () {
    final registry = TypeRegistryImpl();
    final largeList =
        List.generate(2000, (index) => values[index % values.length]);
    final writer = BinaryWriterImpl(registry)..write(largeList);
    expect(BinaryReaderImpl(writer.toBytes(), registry).read(), largeList);
  });

  test('truncated raw int64 values are rejected', () {
    final registry = TypeRegistryImpl();
    final writer = BinaryWriterImpl(registry)..writeInt64(6023364273353477121);
    for (var length = 0; length < 8; length++) {
      final reader =
          BinaryReaderImpl(writer.toBytes().sublist(0, length), registry);
      expect(reader.readInt64, throwsRangeError);
    }
  });
}
