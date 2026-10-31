import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import '../../models/song.dart';

/// 音频元数据与 ID3 标签写入器
/// 负责向已下载的音频文件写入歌曲名、歌手、专辑及封面等元数据
class Id3Tagger {
  /// 向目标音频文件注入歌曲元数据
  ///
  /// [filePath] 音频文件绝对路径
  /// [song] 歌曲对象
  /// [coverBytes] 封面图片二进制数据（可选）
  static Future<void> writeTags({
    required String filePath,
    required Song song,
    Uint8List? coverBytes,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    try {
      final ext = filePath.toLowerCase();
      if (ext.endsWith('.mp3')) {
        await _writeMp3Id3v2(file, song, coverBytes);
      }
    } catch (_) {
      // 容错：标签写入失败不影响音频本身正常收听
    }
  }

  /// 针对 MP3 封装 ID3v2.3 标签块并写入文件头部（采用原子写入以防损坏原始音频）
  static Future<void> _writeMp3Id3v2(
    File file,
    Song song,
    Uint8List? coverBytes,
  ) async {
    final originalBytes = await file.readAsBytes();
    if (originalBytes.isEmpty) return;

    int audioDataOffset = 0;

    // 检查原有文件是否已有 ID3v2 头部
    if (originalBytes.length >= 10 &&
        originalBytes[0] == 0x49 &&
        originalBytes[1] == 0x44 &&
        originalBytes[2] == 0x33) {
      // 读取 synchsafe 长度
      final tagSize = (originalBytes[6] & 0x7F) << 21 |
          (originalBytes[7] & 0x7F) << 14 |
          (originalBytes[8] & 0x7F) << 7 |
          (originalBytes[9] & 0x7F);
      audioDataOffset = 10 + tagSize;
      if (audioDataOffset > originalBytes.length) {
        audioDataOffset = 0;
      }
    }

    // 组装各个 ID3v2 Frame
    final framesBytes = BytesBuilder();
    _appendFrame(framesBytes, 'TIT2', song.name);
    _appendFrame(framesBytes, 'TPE1', song.artistString);
    _appendFrame(framesBytes, 'TALB', song.albumName);
    _appendFrame(framesBytes, 'TRCK', song.trackNumber.toString());

    // 组装 APIC 封面图片 Frame（若提供且小于 10MB）
    if (coverBytes != null && coverBytes.isNotEmpty && coverBytes.length < 10 * 1024 * 1024) {
      _appendPictureFrame(framesBytes, coverBytes);
    }

    final framesPayload = framesBytes.takeBytes();
    final framesLength = framesPayload.length;

    // 组装 ID3 头部 (10 字节)
    final header = Uint8List(10);
    header[0] = 0x49; // 'I'
    header[1] = 0x44; // 'D'
    header[2] = 0x33; // '3'
    header[3] = 0x03; // ID3v2.3
    header[4] = 0x00; // revision
    header[5] = 0x00; // flags

    // 4 字节 Synchsafe 格式存储标签总长度 (不含 10 字节头)
    header[6] = (framesLength >> 21) & 0x7F;
    header[7] = (framesLength >> 14) & 0x7F;
    header[8] = (framesLength >> 7) & 0x7F;
    header[9] = framesLength & 0x7F;

    // 重新拼接文件：新 ID3 + 纯音频数据
    final finalBuilder = BytesBuilder();
    finalBuilder.add(header);
    finalBuilder.add(framesPayload);
    if (audioDataOffset > 0 && audioDataOffset < originalBytes.length) {
      finalBuilder.add(originalBytes.sublist(audioDataOffset));
    } else {
      finalBuilder.add(originalBytes);
    }

    // 先写入临时文件，确保成功后再替换原文件，杜绝写入中断损坏文件
    final tempFile = File('${file.path}.tag.tmp');
    await tempFile.writeAsBytes(finalBuilder.takeBytes(), flush: true);
    if (await tempFile.exists() && await tempFile.length() > originalBytes.length / 2) {
      await tempFile.rename(file.path);
    } else {
      try { await tempFile.delete(); } catch (_) {}
    }
  }

  /// 组装文本类 ID3v2 Frame
  static void _appendFrame(BytesBuilder builder, String frameId, String text) {
    if (text.isEmpty) return;

    final textBytes = utf8.encode(text);
    // Frame Content: 1 字节编码标识(0x03 为 UTF-8) + 文本内容
    final frameData = Uint8List(1 + textBytes.length);
    frameData[0] = 0x03; // UTF-8
    frameData.setRange(1, frameData.length, textBytes);

    // Frame Header (10 字节): FrameID(4) + Size(4) + Flags(2)
    builder.add(utf8.encode(frameId));
    final size = frameData.length;
    builder.add([
      (size >> 24) & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 8) & 0xFF,
      size & 0xFF,
    ]);
    builder.add([0x00, 0x00]); // flags
    builder.add(frameData);
  }

  /// 组装封面图片 APIC Frame
  static void _appendPictureFrame(BytesBuilder builder, Uint8List pictureBytes) {
    const mimeType = 'image/jpeg';
    final mimeBytes = utf8.encode(mimeType);

    // APIC 结构: 编码(1) + MIME(\0结尾) + PictureType(1, 0x03为封面) + 描述(\0结尾) + 图片数据
    final apicBuilder = BytesBuilder();
    apicBuilder.addByte(0x00); // ISO-8859-1
    apicBuilder.add(mimeBytes);
    apicBuilder.addByte(0x00); // MIME 字符串终止符
    apicBuilder.addByte(0x03); // PictureType: 3 = Cover (front)
    apicBuilder.addByte(0x00); // 描述终止符
    apicBuilder.add(pictureBytes);

    final payload = apicBuilder.takeBytes();
    builder.add(utf8.encode('APIC'));
    final size = payload.length;
    builder.add([
      (size >> 24) & 0xFF,
      (size >> 16) & 0xFF,
      (size >> 8) & 0xFF,
      size & 0xFF,
    ]);
    builder.add([0x00, 0x00]);
    builder.add(payload);
  }
}