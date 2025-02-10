import 'dart:convert';

import 'package:hive/hive.dart';
import 'package:hive/src/registry/type_registry_impl.dart';

class JsonWriter {
  final TypeRegistryImpl _typeRegistry;

  /// Not part of public API
  JsonWriter(TypeRegistry typeRegistry)
      : _typeRegistry = typeRegistry as TypeRegistryImpl;

  

	Object? _toEncodable(Object? object) {
    if (object is num) {
      return object;
    } else if (identical(object, true)) {
      return object;
    } else if (identical(object, false)) {
      return object;
    } else if (object == null) {
      return object;
    } else if (object is String) {
      return object;
    } else if (object is List) {
      return object;
    } else if (object is Map) {
			if (object.keys.every((k) => k is String)) {
				return object;
			}
      return {
				for (final entry in object.entries)
					_toEncodable(entry.key).toString(): _toEncodable(entry.value)
			};
    } else if (object is MapEntry) {
			return {
				'_type': object.runtimeType.toString(),
				'key': _toEncodable(object.key),
				'value': _toEncodable(object.value)
			};
		} else if (object is Set) {
			// Who cares, just throw away set-ness
			return {
				'_type': object.runtimeType.toString(),
				'elements': object.toList()
			};
		}
		final resolved = _typeRegistry.findAdapterForValue(object);
		if (resolved == null) {
			throw HiveError('Cannot write, unknown type: ${object.runtimeType}. '
					'Did you forget to register an adapter?');
		}
		if (resolved.adapter.fields.isEmpty) {
			// Enum or dummy?
			return object.toString();
		}
		return {
			'_type': resolved.runtimeType.toString(),
			for (final field in resolved.adapter.fields.values)
				field.fieldName: _toEncodable(field.dynamicGetter(object))
		};
	}

	void _dumpJsonError(Object? error) {
		final e = error;
		if (e is JsonUnsupportedObjectError) {
			print(e);
			print(e.unsupportedObject);
			_dumpJsonError(e.cause);
		}
		else {
			print(e);
		}
	}

  String write<T>(T value) {
		try {
			return jsonEncode(value, toEncodable: _toEncodable);
		}
		catch (error) {
			_dumpJsonError(error);
			rethrow;
		}
  }
}
