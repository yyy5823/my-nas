import 'dart:convert';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:my_nas/core/utils/logger.dart';

/// NCM 文件解密服务
/// 用于解密网易云音乐的 .ncm 加密文件
class NcmDecryptService {
  factory NcmDecryptService() => _instance ??= NcmDecryptService._();
  NcmDecryptService._();

  static NcmDecryptService? _instance;

  // NCM 文件魔数 "CTENFDAM"
  static const _magicHeader = [0x43, 0x54, 0x45, 0x4E, 0x46, 0x44, 0x41, 0x4D];

  // AES 密钥（用于解密 RC4 密钥）
  static final _coreKey = Uint8List.fromList([
    0x68, 0x7A, 0x48, 0x52, 0x41, 0x6D, 0x73, 0x6F,
    0x35, 0x6B, 0x49, 0x6E, 0x62, 0x61, 0x78, 0x57,
  ]);

  // AES 密钥（用于解密元数据）
  static final _metaKey = Uint8List.fromList([
    0x23, 0x31, 0x34, 0x6C, 0x6A, 0x6B, 0x5F, 0x21,
    0x5C, 0x5D, 0x26, 0x30, 0x55, 0x3C, 0x27, 0x28,
  ]);

  /// 检查是否为有效的 NCM 文件
  bool isValidNcmFile(Uint8List data) {
    if (data.length < 8) return false;
    for (var i = 0; i < 8; i++) {
      if (data[i] != _magicHeader[i]) return false;
    }
    return true;
  }

  /// 解密 NCM 文件
  /// 返回解密后的音频数据和元数据
  NcmDecryptResult? decrypt(Uint8List data) {
    try {
      if (!isValidNcmFile(data)) {
        logger.w('NcmDecryptService: 无效的 NCM 文件头');
        return null;
      }

      var offset = 10; // 跳过魔数(8) + 2字节

      // 读取并解密 RC4 密钥
      final keyLength = _readUint32LE(data, offset);
      offset += 4;

      final keyData = Uint8List(keyLength);
      for (var i = 0; i < keyLength; i++) {
        keyData[i] = data[offset + i] ^ 0x64;
      }
      offset += keyLength;

      // AES ECB 解密 RC4 密钥
      final aesCore = encrypt.Encrypter(
        encrypt.AES(encrypt.Key(_coreKey), mode: encrypt.AESMode.ecb, padding: null),
      );
      final decryptedKey = aesCore.decryptBytes(encrypt.Encrypted(keyData));
      final unpadded = _unpad(Uint8List.fromList(decryptedKey));

      // 跳过前 17 字节 "neteasecloudmusic"
      final rc4Key = unpadded.sublist(17);

      // 生成 RC4 密钥盒
      final keyBox = _generateKeyBox(rc4Key);

      // 读取并解密元数据
      final metaLength = _readUint32LE(data, offset);
      offset += 4;

      NcmMetadata? metadata;
      if (metaLength > 0) {
        final metaData = Uint8List(metaLength);
        for (var i = 0; i < metaLength; i++) {
          metaData[i] = data[offset + i] ^ 0x63;
        }
        offset += metaLength;

        try {
          // Base64 解码（跳过前 22 字节 "163 key(Don't modify):"）
          final metaBase64 = String.fromCharCodes(metaData.sublist(22));
          final metaEncrypted = base64.decode(metaBase64);

          // AES ECB 解密元数据
          final aesMeta = encrypt.Encrypter(
            encrypt.AES(encrypt.Key(_metaKey), mode: encrypt.AESMode.ecb, padding: null),
          );
          final decryptedMeta = aesMeta.decryptBytes(encrypt.Encrypted(Uint8List.fromList(metaEncrypted)));
          final unpaddedMeta = _unpad(Uint8List.fromList(decryptedMeta));

          // 跳过前 6 字节 "music:"
          final metaJson = utf8.decode(unpaddedMeta.sublist(6));
          final metaMap = json.decode(metaJson) as Map<String, dynamic>;

          metadata = NcmMetadata(
            musicName: metaMap['musicName'] as String? ?? '',
            artist: _parseArtist(metaMap['artist']),
            album: metaMap['album'] as String? ?? '',
            format: metaMap['format'] as String? ?? 'mp3',
            duration: metaMap['duration'] as int? ?? 0,
            bitrate: metaMap['bitrate'] as int? ?? 0,
          );

          logger.d('NcmDecryptService: 元数据解析成功 - ${metadata.musicName}');
        } on Exception catch (e) {
          logger.w('NcmDecryptService: 元数据解析失败: $e');
        }
      }

      // 跳过 CRC32 (4字节) + 5字节
      offset += 4 + 5;

      // 读取封面图片
      Uint8List? coverData;
      if (offset + 4 <= data.length) {
        final imageSize = _readUint32LE(data, offset);
        offset += 4;

        if (imageSize > 0 && offset + imageSize <= data.length) {
          coverData = data.sublist(offset, offset + imageSize);
          offset += imageSize;
          logger.d('NcmDecryptService: 封面图片大小: $imageSize bytes');
        }
      }

      // 解密音频数据
      final audioData = <int>[];
      var chunkIndex = 1;

      while (offset < data.length) {
        final chunkEnd = (offset + 0x8000 <= data.length) ? offset + 0x8000 : data.length;
        final chunk = data.sublist(offset, chunkEnd);

        for (var i = 0; i < chunk.length; i++) {
          final j = chunkIndex & 0xff;
          final boxIndex = (keyBox[j] + keyBox[(keyBox[j] + j) & 0xff]) & 0xff;
          audioData.add(chunk[i] ^ keyBox[boxIndex]);
          chunkIndex++;
        }

        offset = chunkEnd;
      }

      logger.i('NcmDecryptService: 解密成功，音频大小: ${audioData.length} bytes');

      return NcmDecryptResult(
        audioData: Uint8List.fromList(audioData),
        metadata: metadata,
        coverData: coverData,
      );
    } on Exception catch (e, stackTrace) {
      logger.e('NcmDecryptService: 解密失败', e, stackTrace);
      return null;
    }
  }

  /// 生成 RC4 密钥盒
  Uint8List _generateKeyBox(Uint8List key) {
    final keyBox = Uint8List(256);
    for (var i = 0; i < 256; i++) {
      keyBox[i] = i;
    }

    var c = 0;
    var lastByte = 0;
    var keyOffset = 0;
    final keyLength = key.length;

    for (var i = 0; i < 256; i++) {
      final swap = keyBox[i];
      c = (swap + lastByte + key[keyOffset]) & 0xff;
      keyOffset++;
      if (keyOffset >= keyLength) keyOffset = 0;
      keyBox[i] = keyBox[c];
      keyBox[c] = swap;
      lastByte = c;
    }

    return keyBox;
  }

  /// 读取小端序 32 位无符号整数
  int _readUint32LE(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  /// PKCS7 去除填充
  Uint8List _unpad(Uint8List data) {
    if (data.isEmpty) return data;
    final padLength = data[data.length - 1];
    if (padLength > 16 || padLength > data.length) return data;
    return data.sublist(0, data.length - padLength);
  }

  /// 解析艺术家信息
  String _parseArtist(dynamic artist) {
    if (artist == null) return '';
    if (artist is String) return artist;
    if (artist is List) {
      // 格式: [[name, id], [name, id], ...]
      final names = <String>[];
      for (final item in artist) {
        if (item is List && item.isNotEmpty) {
          names.add(item[0].toString());
        }
      }
      return names.join(' / ');
    }
    return '';
  }
}

/// NCM 解密结果
class NcmDecryptResult {
  const NcmDecryptResult({
    required this.audioData,
    this.metadata,
    this.coverData,
  });

  /// 解密后的音频数据
  final Uint8List audioData;

  /// 元数据
  final NcmMetadata? metadata;

  /// 封面图片数据
  final Uint8List? coverData;
}

/// NCM 元数据
class NcmMetadata {
  const NcmMetadata({
    required this.musicName,
    required this.artist,
    required this.album,
    required this.format,
    this.duration = 0,
    this.bitrate = 0,
  });

  /// 歌曲名称
  final String musicName;

  /// 艺术家
  final String artist;

  /// 专辑
  final String album;

  /// 格式 (mp3/flac)
  final String format;

  /// 时长（毫秒）
  final int duration;

  /// 比特率
  final int bitrate;
}
