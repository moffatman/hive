part of hive;

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) {
    return b == null;
  }
  if (b == null || a.length != b.length) {
    return false;
  }
  if (identical(a, b)) {
    return true;
  }
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

abstract class FieldMerger<T> {
  bool merge(
    MergerController<T> merger,
    T yours,
    T theirs,
    T? base
  );

  const FieldMerger();
}

// Dummy for generator
class NotDefinedListMerger {
  const NotDefinedListMerger();
}

abstract class _ValueFieldMerger<T> extends FieldMerger<T> {
  const _ValueFieldMerger();

  @protected
  bool valueEquals(T a, T b);

  @override
  bool merge(
    MergerController<T> merger,
    T yours,
    T theirs,
    T? base
  ) {
    if (valueEquals(yours, theirs)) {
      return true;
    }
    if (!merger.canWrite) {
      // No match but also no ability to write
      return false;
    }
    if (base != null && valueEquals(theirs, base)) {
      // You changed yours
      merger.writeTheirs(yours);
      return true;
    }
    if (base != null && valueEquals(yours, base)) {
      // They changed theirs
      merger.writeYours(theirs);
      return true;
    }
    // yours != base != theirs
    merger.reportSelfConflict();
    return true;
  }
}

class PrimitiveMerger<T> extends _ValueFieldMerger<T> {
  const PrimitiveMerger();

  @override
  bool valueEquals(T a, T b) => a == b;
}

class MapEqualsMerger<K, V> extends _ValueFieldMerger<Map<K, V>> {
  const MapEqualsMerger();

  @override
  bool valueEquals(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) {
      return false;
    }
    if (identical(a, b)) {
      return true;
    }
    for (final K key in a.keys) {
      if (!b.containsKey(key) || b[key] != a[key]) {
        return false;
      }
    }
    return true;
  }
}

class DeepCollectionEqualityMerger<T> extends _ValueFieldMerger<T> {
  const DeepCollectionEqualityMerger();

  @override
  bool valueEquals(T a, T b) {
    return DeepCollectionEquality().equals(a, b);
  }
} 

class ListEqualsMerger<T> extends _ValueFieldMerger<List<T>> {
  const ListEqualsMerger();

  @override
  bool valueEquals(List<T> a, List<T> b) => _listEquals(a, b);
}

class NullableListEqualsMerger<T> extends _ValueFieldMerger<List<T>?> {
  const NullableListEqualsMerger();

  @override
  bool valueEquals(List<T>? a, List<T>? b) => _listEquals(a, b);
}

mixin _OptimizedListMerger<T> on FieldMerger<List<T>> {
  bool? _optimizedMerge(
    MergerController<List<T>> merger,
    List<T> yours,
    List<T> theirs,
    List<T>? base,
    {
      required bool unmodifiable
    }
  ) {
    if (yours.isEmpty && theirs.isEmpty) {
      // Nothing to do here
      return true;
    }
    if (yours.isEmpty) {
      if (unmodifiable) {
        if (!merger.canWrite) {
          return false;
        }
        merger.writeYours(theirs.toList());
      }
      else {
        yours.clear();
        yours.addAll(theirs);
        merger.didWriteYours();
      }
      return true;
    }
    if (theirs.isEmpty) {
      if (unmodifiable) {
        if (!merger.canWrite) {
          return false;
        }
        merger.writeTheirs(yours.toList());
      }
      else {
        theirs.clear();
        theirs.addAll(yours);
        merger.didWriteTheirs();
      }
      return true;
    }
    // More complex situation
    return null;
  }
}

class SetLikePrimitiveListMerger<T>
  extends FieldMerger<List<T>> with _OptimizedListMerger<T> {
  const SetLikePrimitiveListMerger();

  @override
  bool merge(
    MergerController<List<T>> merger,
    List<T> yours,
    List<T> theirs,
    List<T>? base
  ) {
    if (_listEquals(yours, theirs)) {
      // Fast path
      return true;
    }
    final optimized = _optimizedMerge(
      merger, yours, theirs, base, unmodifiable: false);
    if (optimized != null) {
      return optimized;
    }
    final theirsCopy = theirs.toSet();
    for (final yourEntry in yours.toList()) {
      if (theirsCopy.contains(yourEntry)) {
        // you both have it
        theirsCopy.remove(yourEntry);
        merger.didWriteTheirs();
      }
      else if (base?.contains(yourEntry) ?? false) {
        // they deleted it
        yours.remove(yourEntry);
        merger.didWriteYours();
      }
      else {
        // you added it
        theirs.add(yourEntry);
        merger.didWriteTheirs();
      }
    }
    for (final theirEntry in theirsCopy) {
      // you don't have this value
      if (base?.contains(theirEntry) ?? false) {
        // you deleted it from the base
        theirs.remove(theirEntry);
        merger.didWriteTheirs();
      }
      else {
        // they added it to the base
        yours.add(theirEntry);
        merger.didWriteYours();
      }
    }
    return true;
  }
}

class OrderedSetLikePrimitiveListMerger<T>
  extends FieldMerger<List<T>> with _OptimizedListMerger<T> {
  const OrderedSetLikePrimitiveListMerger();

  @override
  bool merge(
    MergerController<List<T>> merger,
    List<T> yours,
    List<T> theirs,
    List<T>? base
  ) {
    if (_listEquals(yours, theirs)) {
      // Fast path
      return true;
    }
    final optimized = _optimizedMerge(
      merger, yours, theirs, base, unmodifiable: false);
    if (optimized != null) {
      return optimized;
    }
    final theirOperations = calculateListDiff<T>(base ?? [], theirs);
    for (final update in theirOperations.getUpdatesWithData()) {
      update.when(
        insert: (index, item) {
          if (!yours.contains(item)) {
            merger.didWriteYours();
            yours.insert(index, item);
          }
        },
        remove: (index, item) {
          merger.didWriteYours();
          yours.remove(item);
        },
        move: (before, after, item) {
          merger.didWriteYours();
          yours.remove(item);
          yours.insert(after, item);
        },
        change: (index, before, after) {
          final indexToChange = yours.indexOf(before);
          if (indexToChange == -1) {
            if (!yours.contains(after)) {
              merger.didWriteYours();
              yours.insert(index, after);
            }
          }
        }
      );
    }
    // Lazy but it works, these are primitives
    if (!_listEquals(yours, theirs)) {
      theirs.clear();
      theirs.addAll(yours);
      merger.didWriteTheirs();
    }
    return true;
  }
}

class ExactPrimitiveListMerger<T>
  extends FieldMerger<List<T>> with _OptimizedListMerger<T> {
  const ExactPrimitiveListMerger();

  @override
  bool merge(
    MergerController<List<T>> merger,
    List<T> yours,
    List<T> theirs,
    List<T>? base
  ) {
    if (_listEquals(yours, theirs)) {
      // Fast path
      return true;
    }
    final optimized = _optimizedMerge(
      merger, yours, theirs, base, unmodifiable: false);
    if (optimized != null) {
      return optimized;
    }
    // TODO: Just bailing for now, maybe something to do?
    merger.reportSelfConflict();
    return true;
  }
}

class MapLikeListMerger<T, Proxy>
  extends FieldMerger<List<T>> with _OptimizedListMerger<T> {
  final FieldMerger<T> childMerger;
  final Proxy Function(T) keyer;
  final bool maintainOrder;
  final bool unmodifiable;

  const MapLikeListMerger({
    required this.childMerger,
    required this.keyer,
    this.maintainOrder = false,
    this.unmodifiable = false
  });

  @override
  bool merge(
    MergerController<List<T>> merger,
    List<T> yours,
    List<T> theirs,
    List<T>? base
  ) {
    final optimized = _optimizedMerge(
      merger, yours, theirs, base, unmodifiable: unmodifiable);
    if (optimized != null) {
      return optimized;
    }
    // TODO: keyCache?
    final yourMap = Map<Proxy, T>.fromEntries(
      yours.map((v) => MapEntry(keyer(v), v)));
    final yourProxy = yours.map(keyer).toList(growable: false);
    final theirMap = Map<Proxy, T>.fromEntries(
      theirs.map((v) => MapEntry(keyer(v), v)));
    final theirProxy = theirs.map(keyer).toList(growable: false);
    final baseMap = base == null ? null : Map<Proxy, T>.fromEntries(
      base.map((v) => MapEntry(keyer(v), v)));
    final baseProxy = base?.map(keyer).toList(growable: false);
    List<T>? modifiableYours;
    List<T>? modifiableTheirs;
    if (_listEquals(yourProxy, theirProxy)) {
      // Fast path - order and membership is the same
      for (final proxy in yourProxy) {
        final yourChild = yourMap[proxy];
        final theirChild = theirMap[proxy];
        if (yourChild != null && theirChild != null) {
          final baseChild = baseMap?[proxy];
          FieldAdapterImpl<List<T>, T>(
            getter: (list) {
              if (identical(list, yours)) {
                return yourChild;
              }
              if (identical(list, theirs)) {
                return theirChild;
              }
              if (identical(list, base)) {
                return baseChild!;
              }
              return list.firstWhere((l) => keyer(l) == proxy);
            },
            setter: (list, v) {
              final List<T> modifiableList;
              if (unmodifiable) {
                if (identical(list, yours)) {
                  modifiableList = modifiableYours ??= yours.toList();
                }
                else {
                  // Must be theirs
                  modifiableList = modifiableTheirs ??= theirs.toList();
                }
              }
              else {
                modifiableList = list;
              }
              final index = modifiableList.indexWhere((l) => keyer(l) == proxy);
              if (index != -1) {
                modifiableList[index] = v;
              }
            },
            merger: childMerger,
            fieldName: '[$proxy]'
          ).merge(merger, yours, theirs, baseChild == null ? null : base);
        }
      }
      final finalModifiableYours = modifiableYours;
      if (finalModifiableYours != null) {
        if (!merger.canWrite) {
          return false;
        }
        merger.writeYours(finalModifiableYours);
      }
      final finalModifiableTheirs = modifiableTheirs;
      if (finalModifiableTheirs != null) {
        if (!merger.canWrite) {
          return false;
        }
        merger.writeTheirs(finalModifiableTheirs);
      }
      return true;
    }
    if (unmodifiable) {
      if (!merger.canWrite) {
        // No way to resolve it, non-equal unmodifiable lists
        return false;
      }
      // Make copy
      yours = yours.toList();
      theirs = theirs.toList();
    }
    final yourOrder = maintainOrder ? {
      for (int i = 0; i < yours.length; i++)
        keyer(yours[i]): i
    } : <Proxy, int>{};
    final theirOrder = maintainOrder ? {
      for (int i = 0; i < theirs.length; i++)
        keyer(theirs[i]): i
    } : <Proxy, int>{};
    final theirsCopy = theirProxy.toSet();
    for (final yourEntry in yourProxy) {
      if (theirsCopy.contains(yourEntry)) {
        // you both have it
        FieldAdapterImpl<List<T>, T>(
          getter: (list) {
            if (identical(list, yours)) {
              return yourMap[yourEntry]!;
            }
            if (identical(list, theirs)) {
              return theirMap[yourEntry]!;
            }
            if (identical(list, base)) {
              return baseMap![yourEntry]!;
            }
            return list.firstWhere((l) => keyer(l) == yourEntry);
          },
          setter: (list, v) {
            final index = list.indexWhere((l) => keyer(l) == yourEntry);
            if (index != -1) {
              list[index] = v;
            }
          },
          fieldName: '[$yourEntry]',
          merger: childMerger
        ).merge(
          merger,
          yours,
          theirs,
          (baseMap?.containsKey(yourEntry) ?? false) ? base : null
        );
        theirsCopy.remove(yourEntry);
      }
      else if (baseProxy?.contains(yourEntry) ?? false) {
        // they deleted it
        yours.removeWhere((x) => keyer(x) == yourEntry);
        merger.didWriteYours();
      }
      else {
        // you added it
        final entry = yourMap[yourEntry];
        if (entry != null) {
          theirs.add(entry);
          merger.didWriteTheirs();
        }
      }
    }
    for (final theirEntry in theirsCopy) {
      // you don't have this value
      if (baseProxy?.contains(theirEntry) ?? false) {
        // you deleted it from the base
        theirs.removeWhere((x) => keyer(x) == theirEntry);
        merger.didWriteTheirs();
      }
      else {
        // they added it to the base
        final entry = theirMap[theirEntry];
        if (entry != null) {
          yours.add(entry);
          merger.didWriteYours();
        }
      }
    }
    assert(yours.length == theirs.length);
    if (maintainOrder) {
      int comparator(T a, T b) {
        final keyA = keyer(a);
        final keyB = keyer(b);
        final yourIndexA = yourOrder[keyA];
        final yourIndexB = yourOrder[keyB];
        if (yourIndexA != null && yourIndexB != null) {
          return yourIndexA.compareTo(yourIndexB);
        }
        final theirIndexA = theirOrder[keyA];
        final theirIndexB = theirOrder[keyB];
        if (theirIndexA != null && theirIndexB != null) {
          return theirIndexA.compareTo(theirIndexB);
        }
        // Some tiebreak for items which are only in one list
        if (yourIndexA != null) {
          return 1;
        }
        return -1;
      }
      yours.sort(comparator);
      theirs.sort(comparator);
      // Maybe only order changed
      if (!merger.wroteYours) {
        for (int i = 0; i < yours.length; i++) {
          if (yourOrder[keyer(yours[i])] != i) {
            merger.didWriteYours();
            break;
          }
        }
      }
      if (!merger.wroteTheirs) {
        for (int i = 0; i < theirs.length; i++) {
          if (theirOrder[keyer(theirs[i])] != i) {
            merger.didWriteTheirs();
            break;
          }
        }
      }
      assert(() {
        for (int i = 0; i < yours.length; i++) {
          if (keyer(yours[i]) != keyer(theirs[i])) {
            throw HiveError(
              'MapLikeListMerger<$T, $Proxy> failed!\n'
              '    yours(proxy): ${yours.map(keyer)}'
              '    theirs(proxy: ${theirs.map(keyer)})'
            );
          }
        }
        return true;
      }());
    }
    if (unmodifiable) {
      // Hack
      if (merger.wroteYours) {
        merger.writeYours(yours);
      }
      if (merger.wroteTheirs) {
        merger.writeTheirs(theirs);
      }
    }
    return true;
  }
}

class MapMerger<K, V> extends FieldMerger<Map<K, V>> {
  final FieldMerger<V> valueMerger;

  const MapMerger(this.valueMerger);

  bool? _optimizedMerge(
    MergerController<Map<K, V>> merger,
    Map<K, V> yours,
    Map<K, V> theirs,
    Map<K, V>? base,
  ) {
    if (yours.isEmpty && theirs.isEmpty) {
      // Nothing to do here
      return true;
    }
    if (yours.isEmpty) {
      yours.clear();
      yours.addAll(theirs);
      merger.didWriteYours();
      return true;
    }
    if (theirs.isEmpty) {
      theirs.clear();
      theirs.addAll(yours);
      merger.didWriteTheirs();
      return true;
    }
    // More complex situation
    return null;
  }

  @override
  bool merge(
    MergerController<Map<K, V>> merger,
    Map<K, V> yours,
    Map<K, V> theirs,
    Map<K, V>? base
  ) {
    final optimized = _optimizedMerge(merger, yours, theirs, base);
    if (optimized != null) {
      return optimized;
    }
    final theirsCopy = {
      ...theirs
    };
    for (final yourKey in yours.keys.toList()) {
      if (theirsCopy.containsKey(yourKey)) {
        // you both have this key
        MapFieldAdapter<K, V>(
          key: yourKey,
          merger: valueMerger
        ).merge(
          merger, yours, theirs,
          (base?.containsKey(yourKey) ?? false) ? base : null);
        theirsCopy.remove(yourKey);
      }
      else if (base?.containsKey(yourKey) ?? false) {
        // they deleted it
        yours.remove(yourKey);
        merger.didWriteYours();
      }
      else {
        // you added it
        theirs[yourKey] = yours[yourKey]!;
        merger.didWriteTheirs();
      }
    }
    for (final theirEntry in theirsCopy.entries) {
      // you don't have this key
      if (base?.containsKey(theirEntry.key) ?? false) {
        // you deleted it from the base
        theirs.remove(theirEntry.key);
        merger.didWriteTheirs();
      }
      else {
        // they added it to the base
        yours[theirEntry.key] = theirEntry.value;
        merger.didWriteYours();
      }
    }
    return true;
  }
}

class NullableMerger<T extends Object> extends FieldMerger<T?> {
  final FieldMerger<T> childMerger;

  const NullableMerger(this.childMerger);

  @override
  bool merge(
    MergerController<T?> merger,
    T? yours,
    T? theirs,
    T? base
  ) {
    if (yours == null || theirs == null) {
      return PrimitiveMerger<T?>().merge(merger, yours, theirs, base);
    }
    final unwrappingMerger = UnwrappingMergerController(merger);
    return childMerger.merge(unwrappingMerger, yours, theirs, base);
  }
}

mixin _OptimizedSetMerger<T> on FieldMerger<Set<T>> {
  bool? _optimizedMerge(
    MergerController<Set<T>> merger,
    Set<T> yours,
    Set<T> theirs,
    Set<T>? base
  ) {
    if (yours.isEmpty && theirs.isEmpty) {
      // Nothing to do here
      return true;
    }
    if (yours.isEmpty) {
      yours.clear();
      yours.addAll(theirs);
      merger.didWriteYours();
      return true;
    }
    if (theirs.isEmpty) {
      theirs.clear();
      theirs.addAll(yours);
      merger.didWriteTheirs();
      return true;
    }
    // More complex situation
    return null;
  }
}

class PrimitiveSetMerger<T>
  extends FieldMerger<Set<T>> with _OptimizedSetMerger<T> {
  const PrimitiveSetMerger();

  @override
  bool merge(
    MergerController<Set<T>> merger,
    Set<T> yours,
    Set<T> theirs,
    Set<T>? base
  ) {
    final optimized = _optimizedMerge(merger, yours, theirs, base);
    if (optimized != null) {
      return optimized;
    }
    final theirsCopy = {
      ...theirs
    };
    for (final your in yours.toList()) {
      if (theirsCopy.contains(your)) {
        // you both have this value
        theirsCopy.remove(your);
      }
      else if (base?.contains(your) ?? false) {
        // they deleted it
        yours.remove(your);
        merger.didWriteYours();
      }
      else {
        // you added it
        theirs.add(your);
        merger.didWriteTheirs();
      }
    }
    for (final their in theirsCopy) {
      // you don't have this value
      if (base?.contains(their) ?? false) {
        // you deleted it from the base
        theirs.remove(their);
        merger.didWriteTheirs();
      }
      else {
        // they added it to the base
        yours.add(their);
        merger.didWriteYours();
      }
    }
    return true;
  }
}

class SetMerger<T>
  extends FieldMerger<Set<T>> with _OptimizedSetMerger<T> {
  final FieldMerger<T> childMerger;

  const SetMerger(this.childMerger);

  @override
  bool merge(
    MergerController<Set<T>> merger,
    Set<T> yours,
    Set<T> theirs,
    Set<T>? base
  ) {
    final optimized = _optimizedMerge(merger, yours, theirs, base);
    if (optimized != null) {
      return optimized;
    }
    final theirsCopy = {
      ...theirs
    };
    for (final your in yours.toList()) {
      if (theirsCopy.contains(your)) {
        // you both have this key
        FieldAdapterImpl<Set<T>, T>(
          getter: (s) => s.lookup(your)!,
          setter: (s, v) {
            s.remove(v);
            s.add(v);
          },
          fieldName: '[$your]',
          merger: childMerger
        ).merge(
          merger, yours, theirs,
          (base?.contains(your) ?? false) ? base : null);
        theirsCopy.remove(your);
      }
      else if (base?.contains(your) ?? false) {
        // they deleted it
        yours.remove(your);
        merger.didWriteYours();
      }
      else {
        // you added it
        theirs.add(your);
        merger.didWriteTheirs();
      }
    }
    for (final their in theirsCopy) {
      // you don't have this key
      if (base?.contains(their) ?? false) {
        // you deleted it from the base
        theirs.remove(their);
        merger.didWriteTheirs();
      }
      else {
        // they added it to the base
        yours.add(their);
        merger.didWriteYours();
      }
    }
    return true;
  }
}

abstract class _AdaptedMerger<T extends Object> extends FieldMerger<T> {
  const _AdaptedMerger();

  @protected
  TypeAdapter<T> _getAdapter(MergerController<T> merger);

  @override
  bool merge(
    MergerController<T> merger,
    T yours,
    T theirs,
    T? base
  ) {
    final adapter = _getAdapter(merger);
    if (adapter.fields.isEmpty) {
      return PrimitiveMerger<T>().merge(
        merger,
        yours,
        theirs,
        base
      );
    }
    for (final field in adapter.fields.values) {
      if (!field.merge(merger, yours, theirs, base)) {
        // Unresolveable submerge
        if (merger.canWrite) {
          merger.reportSelfConflict();
        }
        else {
          // Non-writable field, propagate upwards
          return false;
        }
      }
    }
    return true;
  }
}

class AdaptedMerger<T extends Object> extends _AdaptedMerger<T> {
  /// For optimization, avoid slow type lookup
  final int typeId;

  const AdaptedMerger(this.typeId);

  @override
  _getAdapter(merger) {
    final found = merger.typeRegistry.findAdapterForPublicTypeId(typeId);
    if (found == null) {
      throw HiveError('AdaptedMerger<$T>($typeId) found no such adapter!');
    }
    return found.adapter as TypeAdapter<T>;
  }
}

class ResolvedAdaptedMerger<T extends Object> extends _AdaptedMerger<T> {
  final TypeAdapter<T> adapter;

  const ResolvedAdaptedMerger(this.adapter);

  @override
  _getAdapter(merger) => adapter;
}

class NullUnwrapMerger<T extends Object> extends FieldMerger<T> {
  final FieldMerger<T?> parent;

  const NullUnwrapMerger(this.parent);

  @override
  bool merge(
    MergerController<T> merger,
    T yours,
    T theirs,
    T? base
  ) {
    return parent.merge(merger, yours, theirs, base);
  }
}

abstract class FieldReader<Parent, T> {
  T Function(Parent) get getter;
  String get fieldName;

  T dynamicGetter(dynamic parent) {
    if (parent is! Parent) {
      throw ArgumentError.value(
        parent, 'parent', 'Wrong parent passed to $this');
    }
    return getter(parent);
  }

  const FieldReader();

  @override
  String toString() => 'FieldReader<$Parent, $T>(fieldName: $fieldName)';
}

class NullUnwrapFieldReader<T extends Object>
  extends FieldReader<T, T?> {
  const NullUnwrapFieldReader();
  
  @override
  String get fieldName => '';
  
  @override
  T Function(T?) get getter => (x) => x!;
}


abstract class FieldWriter<Parent, T> extends FieldReader<Parent, T> {
  void Function(Parent, T) get setter;

  void Function(dynamic, T) get dynamicSetter {
    return (dynamic parent, T v) => setter(parent as Parent, v);
  }

  const FieldWriter();

  @override
  String toString() => 'FieldWriter<$Parent, $T>(fieldName: $fieldName)';
}

abstract class FieldAdapter<Parent, T> extends FieldReader<Parent, T> {
  FieldMerger<T> get merger;

  const FieldAdapter();

  bool merge(
    MergerController<Parent> merger,
    Parent yourParent,
    Parent theirParent,
    Parent? baseParent
  ) {
    return merger.pushField(this, yourParent, theirParent, baseParent);
  }

  @override
  String toString() => 'FieldAdapter<$Parent, $T>(fieldName: $fieldName)';
}

mixin WritableFieldAdapter<Parent, T> on FieldAdapter<Parent, T>
  implements FieldWriter<Parent, T> {
  @override
  void Function(Parent, T) get setter;

  @override
  void Function(dynamic, T) get dynamicSetter {
    return (dynamic parent, T v) => setter(parent as Parent, v);
  }
}

class ReadOnlyFieldAdapterImpl<Parent, T> extends FieldAdapter<Parent, T> {
  @override
  final T Function(Parent) getter;
  @override
  final String fieldName;
  @override
  final FieldMerger<T> merger;

  const ReadOnlyFieldAdapterImpl({
    required this.getter,
    required this.fieldName,
    required this.merger
  });
}

class FieldAdapterImpl<Parent, T> extends ReadOnlyFieldAdapterImpl<Parent, T>
  with WritableFieldAdapter<Parent, T> {
  @override
  final void Function(Parent, T) setter;

  const FieldAdapterImpl({
    required super.getter,
    required this.setter,
    required super.fieldName,
    required super.merger
  });
}

// TODO: FieldAdapter classes for all uses of FieldAdapterImpl in this file

class NullUnwrapFieldAdapter<Parent, T extends Object>
  extends FieldAdapter<Parent, T> {
  final FieldAdapter<Parent, T?> parent;

  const NullUnwrapFieldAdapter(this.parent);
  
  @override
  String get fieldName => parent.fieldName;
  
  @override
  T Function(Parent) get getter => (x) => parent.getter(x)!;
  
  @override
  FieldMerger<T> get merger => NullUnwrapMerger(parent.merger);
}

class ReadOnlyHiveFieldAdapter<Parent, T> extends
  ReadOnlyFieldAdapterImpl<Parent, T> {
  final int fieldNumber;

  const ReadOnlyHiveFieldAdapter({
    required super.getter,
    required super.fieldName,
    required this.fieldNumber,
    required super.merger
  });

  @override
  String toString() => 'ReadOnlyHiveFieldAdapter<$Parent, $T>('
                       'fieldName: $fieldName, fieldNumber: $fieldNumber)';
}

class HiveFieldAdapter<Parent, T> extends ReadOnlyHiveFieldAdapter<Parent, T>
  with WritableFieldAdapter {
  @override
  final void Function(Parent, T) setter;

  const HiveFieldAdapter({
    required super.getter,
    required this.setter,
    required super.fieldName,
    required super.fieldNumber,
    required super.merger
  });

  @override
  String toString() => 'HiveFieldAdapter<$Parent, $T>(fieldName: $fieldName, '
                       'fieldNumber: $fieldNumber)';
}

class MapFieldWriter<K, V> extends FieldWriter<Map<K, V>, V> {
  final K key;

  const MapFieldWriter({
    required this.key
  });

  @override
  String get fieldName => '[$key]';

  @override
  V Function(Map<K, V> parent) get getter => (parent) => parent[key]!;

  @override
  void Function(Map<K, V> parent, V v) get setter =>
    (parent, v) => parent[key] = v; 
}


class MapFieldAdapter<K, V> extends FieldAdapter<Map<K, V>, V>
  with WritableFieldAdapter {
  @override
  final FieldMerger<V> merger;
  final K key;

  const MapFieldAdapter({
    required this.merger,
    required this.key
  });

  @override
  String get fieldName => '[$key]';

  @override
  V Function(Map<K, V> parent) get getter => (parent) => parent[key]!;

  @override
  void Function(Map<K, V> parent, V v) get setter =>
    (parent, v) => parent[key] = v;
  
}

class ChainedFieldReader<T1, T2, T3> extends FieldReader<T1, T3> {
  final FieldReader<T1, T2> parent;
  final FieldReader<T2, T3> child;

  const ChainedFieldReader(this.parent, this.child);

  @override
  String get fieldName => '${parent.fieldName}/${child.fieldName}';
  
  @override
  T3 Function(T1 parent) get getter => (x) => child.getter(parent.getter(x));
}

class ChainedFieldWriter<T1, T2, T3> extends FieldWriter<T1, T3> {
  final FieldReader<T1, T2> parent;
  final FieldWriter<T2, T3> child;

  const ChainedFieldWriter(this.parent, this.child);

  @override
  String get fieldName => '${parent.fieldName}/${child.fieldName}';
  
  @override
  T3 Function(T1 parent) get getter => (x) => child.getter(parent.getter(x));
  
  @override
  void Function(T1 parent, T3 v) get setter =>
    (p, v) => child.setter(parent.getter(p), v);
}
