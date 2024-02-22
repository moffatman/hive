part of hive;

/// Annotate all fields you want to persist with [HiveField].
class HiveField {
  /// The index of this field.
  final int index;

  /// The default value of this field for class hive types.
  ///
  /// In enum hive types set `true` to use this enum value as default value
  /// instead of null in null-safety.
  ///
  /// ```dart
  /// @HiveType(typeId: 1)
  /// enum MyEnum {
  ///   @HiveField(0)
  ///   apple,
  ///
  ///   @HiveField(1, defaultValue: true)
  ///   pear
  /// }
  /// ```
  final dynamic defaultValue;

  final FieldMerger<dynamic>? merger;

  // Whether it should be read only and not written to disk
  final bool isDeprecated;

  // Whether it should not be written to disk if null
  final bool isOptimized;

  const HiveField(this.index, {
    this.defaultValue,
    this.merger,
    this.isDeprecated = false,
    this.isOptimized = false,
  });
}
