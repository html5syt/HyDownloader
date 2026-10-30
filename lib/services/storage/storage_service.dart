import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/app_constants.dart';

/// 本地存储与用户偏好持久化服务
/// 负责保存会话凭据、抓包参数、下载偏好设置与本地同步目录历史
class StorageService {
  late final SharedPreferences _prefs;

  /// 单例实例
  static final StorageService instance = StorageService._internal();
  StorageService._internal();

  /// 初始化 SharedPreferences 实例
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 获取持久化保存的 Cookies 映射表
  Map<String, String> getSavedCookies() {
    final raw = _prefs.getString(AppConstants.prefKeyCookies);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    } catch (_) {}
    return {};
  }

  /// 保存 Cookies 映射表
  Future<void> saveCookies(Map<String, String> cookies) async {
    await _prefs.setString(AppConstants.prefKeyCookies, json.encode(cookies));
  }

  /// 清除保存的 Cookies
  Future<void> clearCookies() async {
    await _prefs.remove(AppConstants.prefKeyCookies);
  }

  /// 获取抓包导入的附加参数 (AdditionalParameters)
  Map<String, dynamic> getSavedAdditionalParameters() {
    final raw = _prefs.getString(AppConstants.prefKeyAdditionalParameters);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return {};
  }

  /// 保存附加参数
  Future<void> saveAdditionalParameters(Map<String, dynamic> params) async {
    await _prefs.setString(
      AppConstants.prefKeyAdditionalParameters,
      json.encode(params),
    );
  }

  /// 清除保存的附加参数
  Future<void> clearAdditionalParameters() async {
    await _prefs.remove(AppConstants.prefKeyAdditionalParameters);
  }

  /// 获取配置的下载存储根目录
  /// 若用户尚未配置，则自动选择系统标准的音乐目录或文档目录
  Future<String> getDownloadDirectory() async {
    final savedPath = _prefs.getString(AppConstants.prefKeyDownloadPath);
    if (savedPath != null && savedPath.isNotEmpty) {
      final dir = Directory(savedPath);
      if (await dir.exists()) return savedPath;
    }

    try {
      // 优先系统标准音乐目录 (Music)
      final musicDir = await getDownloadsDirectory() ??
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux
              ? await getApplicationDocumentsDirectory()
              : await getApplicationDocumentsDirectory());

      final defaultFolder = Directory('${musicDir.path}/${AppConstants.defaultDownloadFolderName}');
      if (!await defaultFolder.exists()) {
        await defaultFolder.create(recursive: true);
      }
      return defaultFolder.path;
    } catch (_) {
      final temp = await getTemporaryDirectory();
      return temp.path;
    }
  }

  /// 保存下载存储根目录配置
  Future<void> saveDownloadDirectory(String path) async {
    await _prefs.setString(AppConstants.prefKeyDownloadPath, path);
  }

  /// 获取当前配置的下载音质 (默认 lossless)
  String getAudioRate() {
    return _prefs.getString(AppConstants.prefKeyAudioRate) ??
        AppConstants.defaultAudioRate;
  }

  /// 保存下载音质配置
  Future<void> saveAudioRate(String rate) async {
    await _prefs.setString(AppConstants.prefKeyAudioRate, rate);
  }

  /// 获取下载文件名命名模板 (默认 {$SINGER} - {$SONGNAME})
  String getFileNameTemplate() {
    return _prefs.getString(AppConstants.prefKeyFileNameTemplate) ??
        AppConstants.defaultFileNameTemplate;
  }

  /// 保存下载文件名模板
  Future<void> saveFileNameTemplate(String template) async {
    await _prefs.setString(AppConstants.prefKeyFileNameTemplate, template);
  }

  /// 是否同步下载歌词文件
  bool getDownloadLyrics() {
    return _prefs.getBool(AppConstants.prefKeyDownloadLyrics) ?? true;
  }

  /// 保存是否下载歌词配置
  Future<void> saveDownloadLyrics(bool value) async {
    await _prefs.setBool(AppConstants.prefKeyDownloadLyrics, value);
  }

  /// 是否合并歌词翻译
  bool getDownloadTranslation() {
    return _prefs.getBool(AppConstants.prefKeyDownloadTranslation) ?? true;
  }

  /// 保存是否下载翻译配置
  Future<void> saveDownloadTranslation(bool value) async {
    await _prefs.setBool(AppConstants.prefKeyDownloadTranslation, value);
  }

  /// 是否写入歌曲 ID3 / 元数据标签
  bool getWriteMetadata() {
    return _prefs.getBool(AppConstants.prefKeyWriteMetadata) ?? true;
  }

  /// 保存是否写入标签配置
  Future<void> saveWriteMetadata(bool value) async {
    await _prefs.setBool(AppConstants.prefKeyWriteMetadata, value);
  }

  /// 获取最大并发下载数 (默认 3)
  int getMaxConcurrentDownloads() {
    return _prefs.getInt(AppConstants.prefKeyMaxConcurrent) ??
        AppConstants.defaultMaxConcurrentDownloads;
  }

  /// 保存最大并发数
  Future<void> saveMaxConcurrentDownloads(int value) async {
    await _prefs.setInt(AppConstants.prefKeyMaxConcurrent, value);
  }

  /// 获取记忆的用于歌曲文件同步的本地文件夹路径列表
  List<String> getSyncFolders() {
    return _prefs.getStringList(AppConstants.prefKeySyncFolders) ?? [];
  }

  /// 保存同步本地文件夹列表
  Future<void> saveSyncFolders(List<String> folders) async {
    await _prefs.setStringList(AppConstants.prefKeySyncFolders, folders);
  }

  /// 获取是否深色主题
  bool? getDarkMode() {
    return _prefs.getBool(AppConstants.prefKeyDarkMode);
  }

  /// 保存深色模式
  Future<void> saveDarkMode(bool isDark) async {
    await _prefs.setBool(AppConstants.prefKeyDarkMode, isDark);
  }
}
