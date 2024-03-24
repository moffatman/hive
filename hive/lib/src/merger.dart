import 'package:hive/hive.dart';
import 'package:hive/src/registry/type_registry_impl.dart';

class MergeResult<T> {
	final bool wroteYours;
	final bool wroteTheirs;
	final List<MergeConflict<T, dynamic>> conflicts;

	const MergeResult({
		required this.wroteYours,
		required this.wroteTheirs,
		required this.conflicts
	});

	@override
	String toString() => 'MergeResult<$T>(wroteYours: $wroteYours, wroteTheirs: '
	                     '$wroteTheirs, conflicts: $conflicts)';
}

class MergeException implements Exception {
	final String message;

	const MergeException(this.message);

	@override
	String toString() => 'MergeException: $message';
}

class MergePath<Ancestor, T> {
	final List<FieldReader<dynamic, dynamic>> stack;

	const MergePath({
		required this.stack
	});

	T get(Ancestor a) {
		dynamic p = a;
		for (final field in stack) {
			p = field.dynamicGetter(p);
		}
		return p as T;
	}
}

class MergeConflict<Ancestor, T> extends MergePath<Ancestor, T> {
	const MergeConflict({
		required super.stack
	});

	void set(Ancestor a, T value) {
		dynamic p = a;
		for (int i = 0; i < stack.length - 1; i++) {
			p = stack[i].dynamicGetter(p);
		}
		final void Function(dynamic, T) setter = switch (stack.last) {
			(WritableFieldAdapter<dynamic, T> x) => x.dynamicSetter,
			_ => throw MergeException('Tried to modify a read-only field: $this')
		};
		setter(p, value);
	}

	MergeConflict<NewAncestor, T>
		hoist<NewAncestor>(FieldReader<NewAncestor, Ancestor> field) {
		return MergeConflict<NewAncestor, T>(
			stack: [field, ...stack]
		);
	}

	String get path => stack.map((s) => s.fieldName).where((n) => n.isNotEmpty).join('/');

	@override
	String toString() {
		return
			'MergeConflict<$Ancestor, $T>($path)';
	}
}

abstract class MergerController<T> {
	final TypeRegistryImpl typeRegistry;
	final List<List<String>> skips;
	final List<MergeConflict<T, dynamic>> conflicts = [];
	bool _wroteYours = false;
	bool get wroteYours => _wroteYours;
	void didWriteYours() {

		_wroteYours = true;
	}
	bool _wroteTheirs = false;
	bool get wroteTheirs => _wroteTheirs;
	void didWriteTheirs() {
		_wroteTheirs = true;
	}

	MergerController({
		required this.typeRegistry,
		required this.skips
	});

	bool pushField<Child>(
		FieldAdapter<T, Child> field,
		T yourParent,
		T theirParent,
		T? baseParent
	) {
		if (skips.any((s) => s.length == 1 && s.first == field.fieldName)) {
			// Skip it
			return true;
		}
		final childSkips = skips
			.where((s) => s.first == field.fieldName)
			.map((s) => s.sublist(1))
			.toList();
		final merger = switch (field) {
			(WritableFieldAdapter<T, Child> x) =>
				WritableFieldMergerController<T, Child>(
					typeRegistry: typeRegistry,
					skips: childSkips,
					field: x,
					yourParent: yourParent,
					theirParent: theirParent,
					baseParent: baseParent
				),
			(FieldAdapter<T, Child> x) =>
				FieldMergerController<T, Child>(
					typeRegistry: typeRegistry,
					skips: childSkips,
					field: x,
					yourParent: yourParent,
					theirParent: theirParent,
					baseParent: baseParent
				)
		};
		final ret = merger.merge();
		conflicts.addAll(merger.conflicts.map((m) => m.hoist(field)));
		_wroteYours |= merger.wroteYours;
		_wroteTheirs |= merger.wroteTheirs;
		return ret;
	}

	void reportSelfConflict() {
		if (!canWrite) {
			throw ArgumentError('Tried to report conflict to non-writable merger $this');
		}
		conflicts.add(MergeConflict<T, T>(
			stack: []
		));
	}

	bool get canWrite => false;
	void writeYours(T newValue) {
		throw ArgumentError('Tried to write yours to non-writable merger $this');
	}
	void writeTheirs(T newValue) {
		throw ArgumentError('Tried to write theirs to non-writable merger $this');
	}

	bool merge();
}

class BaseMergerController<T> extends MergerController<T> {
	final T yours;
	final T theirs;
	final T? base;
	final FieldMerger<T> merger;
	
	BaseMergerController({
		required super.typeRegistry,
		required super.skips,
		required this.yours,
		required this.theirs,
		required this.base,
		required this.merger
	});

	@override
	bool merge() {
		return merger.merge(this, yours, theirs, base);
	}
}

class _FieldMergerController<Parent, T, X extends FieldAdapter<Parent, T>>
	extends MergerController<T> {
	final X field;
	final Parent yourParent;
	final Parent theirParent;
	final Parent? baseParent;
	_FieldMergerController({
		required super.typeRegistry,
		required super.skips,
		required this.field,
		required this.yourParent,
		required this.theirParent,
		required this.baseParent
	});

	@override
	bool merge() {
		final baseParent = this.baseParent;
		return field.merger.merge(
			this,
			field.getter(yourParent),
			field.getter(theirParent),
			baseParent == null ? null : field.getter(baseParent)
		);
	}
}

class FieldMergerController<Parent, T> extends
	_FieldMergerController<Parent, T, FieldAdapter<Parent, T>> {
	FieldMergerController({
		required super.typeRegistry,
		required super.skips,
		required super.field,
		required super.yourParent,
		required super.theirParent,
		required super.baseParent
	});
}


class WritableFieldMergerController<Parent, T> extends
	_FieldMergerController<Parent, T, WritableFieldAdapter<Parent, T>> {

	WritableFieldMergerController({
		required super.typeRegistry,
		required super.skips,
		required super.field,
		required super.yourParent,
		required super.theirParent,
		required super.baseParent
	});

	@override
	bool get canWrite => true;

	@override
	void writeYours(T newValue) {
		_wroteYours = true;
		field.setter(yourParent, newValue);
	}
	@override
	void writeTheirs(T newValue) {
		_wroteTheirs = true;
		field.setter(theirParent, newValue);
	}
}

class UnwrappingMergerController<T extends Object>
	implements MergerController<T> {
	final MergerController<T?> parent;

	UnwrappingMergerController(this.parent);

	@override
	bool merge() {
		return parent.merge();
	}

	@override
	bool get canWrite => parent.canWrite;

	@override
	bool get wroteYours => parent.wroteYours;
	@override
	bool get _wroteYours => parent._wroteYours;
	@override
	set _wroteYours(bool v) => parent._wroteYours = v;
	@override
	void didWriteYours() => parent.didWriteYours();

	@override
	bool get wroteTheirs => parent.wroteTheirs;
	@override
	bool get _wroteTheirs => parent._wroteTheirs;
	@override
	set _wroteTheirs(bool v) => parent._wroteTheirs = v;
	@override
	void didWriteTheirs() => parent.didWriteTheirs();

	@override
	List<MergeConflict<T, dynamic>> get conflicts => parent.conflicts.map(
		(c) => c.hoist(NullUnwrapFieldReader())
	).toList();

	@override
	bool pushField<Child>(
		FieldAdapter<T, Child> field,
		T yourParent,
		T theirParent,
		T? baseParent
	) {
		if (skips.any((s) => s.length == 1 && s.first == field.fieldName)) {
			// Skip it
			return true;
		}
		final childSkips = skips
			.where((s) => s.first == field.fieldName)
			.map((s) => s.sublist(1))
			.toList();
		final merger = switch (field) {
			(WritableFieldAdapter<T, Child> x) =>
				WritableFieldMergerController<T, Child>(
					typeRegistry: typeRegistry,
					skips: childSkips,
					field: x,
					yourParent: yourParent,
					theirParent: theirParent,
					baseParent: baseParent
				),
			(FieldAdapter<T, Child> x) =>
				FieldMergerController<T, Child>(
					typeRegistry: typeRegistry,
					skips: childSkips,
					field: x,
					yourParent: yourParent,
					theirParent: theirParent,
					baseParent: baseParent
				)
		};
		final ret = merger.merge();
		parent.conflicts.addAll(merger.conflicts.map((m) => m.hoist(field)));
		parent._wroteYours |= merger.wroteYours;
		parent._wroteTheirs |= merger.wroteTheirs;
		return ret;
	}

	@override
	void reportSelfConflict() {
		parent.reportSelfConflict();
	}

	@override
	List<List<String>> get skips => parent.skips;

	@override
	TypeRegistryImpl get typeRegistry => parent.typeRegistry;

	@override
	void writeTheirs(T newValue) {
		parent.writeTheirs(newValue);
	}

	@override
	void writeYours(T newValue) {
		parent.writeYours(newValue);
	}
}
