import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:source_gen/source_gen.dart';

class AdapterField {
  final int index;
  final String name;
  final DartType type;
  final DartObject? defaultValue;
  final String? merger;
  final bool isReadOnly;
  final bool isDeprecated;
  final bool isOptimized;

  AdapterField(
    this.index,
    this.name,
    this.type,
    this.defaultValue,
    this.merger,
    this.isReadOnly,
    this.isDeprecated,
    this.isOptimized,
  );


  static final _stringChecker = const TypeChecker.fromRuntime(String);
  static final _numChecker = const TypeChecker.fromRuntime(num);
  static final _boolChecker = const TypeChecker.fromRuntime(bool);
  static final _enumChecker = const TypeChecker.fromRuntime(Enum);
  static final _dateTimeChecker = const TypeChecker.fromRuntime(DateTime);
  static final _listChecker = const TypeChecker.fromRuntime(List);
  static final _mapChecker = const TypeChecker.fromRuntime(Map);
  static final _setChecker = const TypeChecker.fromRuntime(Set);

  static bool _isPrimitive(DartType type) =>
    _stringChecker.isAssignableFromType(type)
    || _numChecker.isAssignableFromType(type)
    || _boolChecker.isAssignableFromType(type)
    || _enumChecker.isAssignableFromType(type)
    || _dateTimeChecker.isAssignableFromType(type);

  bool get isPrimitive => _isPrimitive(type);

  static String _makeMergerConstructor(DartType type, {bool checkNull = true}) {
    if (_isPrimitive(type)) {
      return 'PrimitiveMerger()';
    }
    if (checkNull && type.nullabilitySuffix == NullabilitySuffix.question) {
      return
        'NullableMerger(${_makeMergerConstructor(type, checkNull: false)})';
    }
    if (_listChecker.isAssignableFromType(type)) {
      return 'NotDefinedListMerger()';
    }
    if (_mapChecker.isAssignableFromType(type)) {
      final childType = (type as ParameterizedType).typeArguments.last;
      return 'MapMerger(${_makeMergerConstructor(childType)})';
    }
    if (_setChecker.isAssignableFromType(type)) {
      final childType = (type as ParameterizedType).typeArguments.last;
      if (_isPrimitive(childType)) {
        return 'PrimitiveSetMerger()';
      }
      return 'SetMerger(${_makeMergerConstructor(childType)})';
    }
    final typeName = type.getDisplayString(withNullability: false);
    return 'AdaptedMerger(${typeName}Adapter.kTypeId)';
  }

  String get mergerConstructor {
    return merger ?? _makeMergerConstructor(type);
  }
}

abstract class Builder {
  final InterfaceElement interface;
  final List<AdapterField> getters;
  final List<AdapterField> setters;

  Builder(this.interface, this.getters,
      [this.setters = const <AdapterField>[]]);

  String buildRead();

  String buildWrite();
}
