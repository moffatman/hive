import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:hive/hive.dart';
import 'package:source_gen/source_gen.dart';

final _hiveFieldChecker = const TypeChecker.typeNamed(HiveField);

class HiveFieldInfo {
  HiveFieldInfo(
    this.index,
    this.defaultValue,
    this.merger,
    this.isDeprecated,
    this.isOptimized,
  );

  final int index;
  final DartObject? defaultValue;
  final String? merger;
  final bool isDeprecated;
  final bool isOptimized;
}

HiveFieldInfo? getHiveFieldAnn(Element element) {
  var obj = _hiveFieldChecker.firstAnnotationOfExact(element);
  if (obj == null) return null;

  /// This trick is needed because I need merger to be able to refer to
  /// generated variables, which will be Null at generation time here if using
  /// normal ConstReader method.
  String? merger;
  for (final metadata in element.metadata.annotations) {
    final source = metadata.toSource();
    if (!source.startsWith('@HiveField')) {
      continue;
    }
    final mergerParameterStart = source.indexOf('merger:');
    if (mergerParameterStart == -1) {
      continue;
    }
    final mergerStart = mergerParameterStart + 'merger:'.length;
    var mergerEnd = mergerStart;
    final bracketStack = <int>[];
    final closeNormalBracket = ')'.codeUnits.first;
    final bracketPairs = {
      '['.codeUnits.first: ']'.codeUnits.first,
      '('.codeUnits.first: closeNormalBracket,
      '{'.codeUnits.first: '}'.codeUnits.first,
      '<'.codeUnits.first: '>'.codeUnits.first,
    };
    final afterEnds = {closeNormalBracket, ','.codeUnits.first};
    while (mergerEnd < source.length) {
      final c = source.codeUnitAt(mergerEnd);
      if (bracketStack.isNotEmpty && c == bracketPairs[bracketStack.last]) {
        bracketStack.removeLast();
      }
      else if (afterEnds.contains(c) && bracketStack.isEmpty) {
        break;
      }
      else if (bracketPairs.containsKey(c)) {
        bracketStack.add(c);
      }
      mergerEnd++;
    }
    merger = source.substring(mergerStart, mergerEnd).trim();
  }

  return HiveFieldInfo(
    obj.getField('index')!.toIntValue()!,
    obj.getField('defaultValue'),
    merger,
    obj.getField('isDeprecated')!.toBoolValue()!,
    obj.getField('isOptimized')!.toBoolValue()!,
  );
}

bool isLibraryNNBD(Element element) {
  final dartVersion = element.library!.languageVersion.effective;
  // Libraries with the dart version >= 2.12 are nnbd
  if (dartVersion.major >= 2 && dartVersion.minor >= 12) {
    return true;
  } else {
    return false;
  }
}

void check(bool condition, Object error) {
  if (!condition) {
    // ignore: only_throw_errors
    throw error;
  }
}
