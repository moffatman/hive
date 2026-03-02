import 'dart:io';
import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:hive/src/binary/frame.dart';
import 'package:hive/src/binary/frame_helper.dart';
import 'package:hive/src/box/keystore.dart';
import 'package:meta/meta.dart';

/// Not part of public API
class FrameIoHelper extends FrameHelper {
  /// Not part of public API
  @visibleForTesting
  Future<RandomAccessFile> openFile(String path) {
    return File(path).open();
  }

  /// Not part of public API
  @visibleForTesting
  Future<Uint8List> readFile(String path) {
    return File(path).readAsBytes();
  }

  /// Not part of public API
  Uint8List readFileSync(String path) {
    return File(path).readAsBytesSync();
  }

  /// Not part of public API
  Future<int> keysFromFile(String path, Keystore keystore,
                           {bool syncIO = false}) async {
    final file = syncIO ? File(path).openSync() : await File(path).open();
    try {
      return await _KeyReader(file).readKeys(keystore, syncIO: syncIO);
    } finally {
      syncIO ? file.closeSync() : await file.close();
    }
  }

  /// Not part of public API
  Future<int> framesFromFile(String path, Keystore keystore,
      TypeRegistry registry, HiveCipher? cipher, {bool syncIO = false}) async {
    var bytes = syncIO ? readFileSync(path) : await readFile(path);
    return framesFromBytes(bytes, keystore, registry, cipher);
  }
}

class _KeyReader {
  final RandomAccessFile file;

  _KeyReader(this.file);

  Future<int> readKeys(Keystore keystore, {bool syncIO = false}) async {
    int position = 0;
    final length = syncIO ? file.lengthSync() : await file.length();
    while (true) {
      var frameOffset = position;

      final bytes = syncIO ? file.readSync(4) : await file.read(4);
      if (bytes.isEmpty) {
        // End of file
        break;
      }
      if (bytes.length < 4) {
        return frameOffset;
      }

      
      final frameLength =
          bytes[0] | bytes[1] << 8 | bytes[2] << 16 | bytes[3] << 24;
      if (length < (frameOffset + frameLength)) {
        return frameOffset;
      }

      dynamic key;
      // Key can be at max string length 255
      final len = frameLength.clamp(0, 257);
      final lookahead = syncIO ? file.readSync(len) : await file.read(len);
      final keyType = lookahead[0];
      if (keyType == FrameKeyType.uintT) {
        key = lookahead[1]
            | lookahead[2] << 8
            | lookahead[3] << 16
            | lookahead[4] << 24;
      }
      else if (keyType == FrameKeyType.utf8StringT) {
        final length = lookahead[1];
        key = BinaryReader.utf8Decoder.convert(lookahead, 2, 2 + length);
      }
      else {
        print('Unsupported key type $keyType. Frame might be corrupted.');
        return frameOffset;
      }

      keystore.insert(Frame.lazy(
        key, length: frameLength, offset: frameOffset
      ), notify: false);

      position = frameOffset + frameLength;
      syncIO ? file.setPositionSync(position)
             : await file.setPosition(position);
    }

    return -1;
  }
}
