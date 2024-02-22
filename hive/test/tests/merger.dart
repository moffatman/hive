import 'package:hive/hive.dart';
import 'package:test/test.dart';

class TestType {
	final String name;
	String value1;
	String value2;

	TestType({
		required this.name,
		required this.value1,
		required this.value2
	});

	@override
	String toString() => 'TestType(name: $name, value1: $value1, value2: $value2)';
}

class TestTypeFields {
	static String _getNameOnTestType(TestType x) => x.name;
	static const name = ReadOnlyHiveFieldAdapter<TestType, String>(
		fieldName: 'name',
		fieldNumber: 0,
		getter: _getNameOnTestType,
		merger: PrimitiveMerger()
	);
	static String _getValue1OnTestType(TestType x) => x.value1;
	static String _setValue1OnTestType(TestType x, String v) => x.value1 = v;
	static const value1 = HiveFieldAdapter<TestType, String>(
		fieldName: 'value1',
		fieldNumber: 1,
		getter: _getValue1OnTestType,
		setter: _setValue1OnTestType,
		merger: PrimitiveMerger()
	);
	static String _getValue2OnTestType(TestType x) => x.value2;
	static String _setValue2OnTestType(TestType x, String v) => x.value2 = v;
	static const value2 = HiveFieldAdapter<TestType, String>(
		fieldName: 'value2',
		fieldNumber: 2,
		getter: _getValue2OnTestType,
		setter: _setValue2OnTestType,
		merger: PrimitiveMerger()
	);
}

class TestTypeAdapter extends TypeAdapter<TestType> {
	@override
	TestType read(BinaryReader reader) {
		throw UnimplementedError();
	}

	@override
	final int typeId = 0;

	@override
	void write(BinaryWriter writer, TestType obj) {
		throw UnimplementedError();
	}
	
	@override
	final fields = const {
		0: TestTypeFields.name,
		1: TestTypeFields.value1,
		2: TestTypeFields.value2
	};
}

void main() {
  group('Merger', () {
    group('List', () {
			group('uniqueValuesPositionless', () {
				test('normal', () {
					final yours = [1, 2, 3, 4, 5];
					final theirs = [1, 2, 4];
					final base = [1, 2, 3, 4];
					final conflicts = Hive.merge<List<int>>(
						merger: SetLikePrimitiveListMerger(),
						yours: yours,
						theirs: theirs,
						base: base
					);
					expect(yours, [1, 2, 4, 5]);
					expect(theirs, [1, 2, 4, 5]);
					expect(conflicts, isEmpty);
				});
				test('no base', () {
					final yours = [1, 2, 3, 4, 5];
					final theirs = [1, 2, 4];
					final conflicts = Hive.merge<List<int>>(
						merger: SetLikePrimitiveListMerger(),
						yours: yours,
						theirs: theirs
					);
					expect(yours, [1, 2, 3, 4, 5]);
					expect(theirs, [1, 2, 4, 3, 5]);
					expect(conflicts, isEmpty);
				});
			});
			group('uniqueValuesPositioned', () {
				test('normal', () {
					final yours = [1, 2, 3, 4, 5];
					final theirs = [4, 1, 2];
					final base = [1, 2, 3, 4];
					final conflicts = Hive.merge<List<int>>(
						merger: OrderedSetLikePrimitiveListMerger(),
						yours: yours,
						theirs: theirs,
						base: base
					);
					expect(yours, [4, 1, 2, 5]);
					expect(theirs, [4, 1, 2, 5]);
					expect(conflicts, isEmpty);
				});
				test('no base', () {
					final yours = [1, 2, 3, 4, 5];
					final theirs = [4, 1, 2];
					final conflicts = Hive.merge<List<int>>(
						merger: OrderedSetLikePrimitiveListMerger(),
						yours: yours,
						theirs: theirs
					);
					expect(yours, [1, 2, 3, 4, 5]);
					expect(theirs, [1, 2, 3, 4, 5]);
					expect(conflicts, isEmpty);
				});
			});
		});
		group('Map', () {
			test('normal', () {
				final yours = {1: 'one', 2: 'two', 4: 'four'};
				final theirs = {1: 'one', 3: 'three'};
				final base = {1: 'one', 2: 'two'};
				final conflicts = Hive.merge(
					merger: MapMerger<int, String>(PrimitiveMerger()),
					yours: yours,
					theirs: theirs,
					base: base
				);
				expect(yours, {1: 'one', 3: 'three', 4: 'four'});
				expect(theirs, {1: 'one', 3: 'three', 4: 'four'});
				expect(conflicts, isEmpty);
			});
			test('no base', () {
				final yours = {1: 'one', 2: 'two', 4: 'four'};
				final theirs = {1: 'one', 3: 'three'};
				final conflicts = Hive.merge(
					merger: MapMerger<int, String>(PrimitiveMerger()),
					yours: yours,
					theirs: theirs
				);
				expect(yours, {1: 'one', 2: 'two', 3: 'three', 4: 'four'});
				expect(theirs, {1: 'one', 2: 'two', 3: 'three', 4: 'four'});
				expect(conflicts, isEmpty);
			});
			test('skip', () {
				final yours = {1: 'one', 2: 'NOT TWO', 3: 'three'};
				final theirs = {1: 'one', 2: 'two', 3: 'three'};
				final base = {1: 'one', 2: 'two', 3: 'three'};
				final conflicts = Hive.merge(
					merger: MapMerger<int, String>(PrimitiveMerger()),
					yours: yours,
					theirs: theirs,
					base: base,
					skipPaths: ['[2]']
				);
				expect(yours, {1: 'one', 2: 'NOT TWO', 3: 'three'});
				expect(theirs, {1: 'one', 2: 'two', 3: 'three'});
				expect(conflicts, isEmpty);
			});
		});
		group('Adapted', () {
			Hive.registerAdapter(TestTypeAdapter());
			test('normal', () {
				final yours = TestType(
					name: 'name1',
					value1: 'value1a',
					value2: 'value2'
				);
				final theirs = TestType(
					name: 'name1',
					value1: 'value1',
					value2: 'value2a'
				);
				final base = TestType(
					name: 'name1',
					value1: 'value1',
					value2: 'value2'
				);
				final conflicts = Hive.merge(
					merger: ResolvedAdaptedMerger(TestTypeAdapter()),
					yours: yours,
					theirs: theirs,
					base: base
				);
				expect(yours.name, equals('name1'));
				expect(yours.value1, equals('value1a'));
				expect(yours.value2, equals('value2a'));
				expect(theirs.name, equals('name1'));
				expect(theirs.value1, equals('value1a'));
				expect(theirs.value2, equals('value2a'));
				expect(conflicts, isEmpty);
			});
			test('no base', () {
				final yours = TestType(
					name: 'name1',
					value1: 'value1a',
					value2: 'value2'
				);
				final theirs = TestType(
					name: 'name1',
					value1: 'value1',
					value2: 'value2a'
				);
				final result = Hive.merge<TestType>(
					merger: ResolvedAdaptedMerger(TestTypeAdapter()),
					yours: yours,
					theirs: theirs
				);
				expect(yours.name, equals('name1'));
				expect(yours.value1, equals('value1a'));
				expect(yours.value2, equals('value2'));
				expect(theirs.name, equals('name1'));
				expect(theirs.value1, equals('value1'));
				expect(theirs.value2, equals('value2a'));
				for (final conflict in result.conflicts) {
					print(conflict);
					print(conflict.get(yours));
					print(conflict.get(theirs));
				}
				expect(result.conflicts.map((c) => c.path), containsAll([
					MergeConflict<TestType, String>(
						stack: [TestTypeFields.value1]
					).path,
					MergeConflict<TestType, String>(
						stack: [TestTypeFields.value2]
					).path,
				]));
			});
			test('incompatible conflict', () {
				try {
					final yours = TestType(
						name: 'name1',
						value1: 'value1a',
						value2: 'value2'
					);
					final theirs = TestType(
						name: 'name2',
						value1: 'value1',
						value2: 'value2a'
					);
					final base = TestType(
						name: 'name1',
						value1: 'value1',
						value2: 'value2'
					);
					Hive.merge(
						merger: ResolvedAdaptedMerger(TestTypeAdapter()),
						yours: yours,
						theirs: theirs,
						base: base
					);
					fail('No exception thrown with incompatible merge');
				}
				on ArgumentError {
					// Do nothing
				}
				on TestFailure {
					// Do nothing
				}
				catch (e) {
					fail('Wrong exception thrown with incompatible merge: $e');
				}
			});
		});
  });
}
