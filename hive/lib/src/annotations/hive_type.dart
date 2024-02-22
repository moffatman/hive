part of hive;

/// Annotate classes with [HiveType] to generate a `TypeAdapter`.
class HiveType {
  /// The typeId of the annotated class.
  final int typeId;

  /// The name of the generated adapter.
  final String? adapterName;

  /// Whether to apply various tricks for optimized storage
  final bool isOptimized;

  /// Something to run during read
  final void Function(Map<int, dynamic> fields)? readHook;

  /// This parameter can be used to keep track of old fieldIds which must not
  /// be reused. The generator will throw an error if a legacy fieldId is
  /// used again.
  // final List<int> legacyFieldIds;

  /// If [adapterName] is not set, it'll be `"YourClass" + "Adapter"`.
  const HiveType({
    required this.typeId,
    this.adapterName,
    this.isOptimized = false,
    this.readHook,
    //this.legacyFieldIds,
  });
}
