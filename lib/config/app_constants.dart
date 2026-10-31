/// HyDownloader 全局应用常量定义
/// 包含 API 地址、音质档位、下载命名通配符、存储键等配置
class AppConstants {
  /// 应用显示名称
  static const String appName = 'HyDownloader';

  /// 应用版本号
  static const String appVersion = '1.0.0';

  /// 默认音乐下载目录名
  static const String defaultDownloadFolderName = 'HyDownloader';

  /// 默认下载文件名模板
  static const String defaultFileNameTemplate = r'{$SINGER} - {$SONGNAME}';

  /// 默认下载音质档位
  static const String defaultAudioRate = 'lossless';

  /// 默认试听音质档位 (极高 320k，兼顾音质与秒开)
  static const String defaultPreviewAudioRate = 'exhigh';

  /// 默认最大并发同时下载歌曲任务数
  static const int defaultMaxConcurrentDownloads = 3;

  /// 默认单首歌曲多线程分块下载数 (1 为单线程原生流式，大于 1 为多线程 Range 分块加速)
  static const int defaultSingleSongThreads = 4;

  /// 文件名通配符：歌手
  static const String placeholderSinger = r'{$SINGER}';

  /// 文件名通配符：歌名
  static const String placeholderSongName = r'{$SONGNAME}';

  /// 文件名通配符：专辑
  static const String placeholderAlbum = r'{$ALBUM}';

  /// 文件名通配符：音轨序号
  static const String placeholderIndex = r'{$INDEX}';

  /// 文件名通配符：歌曲ID
  static const String placeholderSongId = r'{$SONGID}';

  /// 网易云音乐 PC 网页基地址
  static const String musicBaseUrl = 'https://music.163.com';

  /// 网易云音乐接口基地址 (用于 EAPI 接口)
  static const String interfaceBaseUrl = 'https://interface.music.163.com';

  /// 网易云音乐图片防盗链与反爬验证所需的统一请求头
  static const Map<String, String> neteaseImageHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36',
    'Referer': 'https://music.163.com/',
  };

  /// SharedPreferences 键定义
  static const String prefKeyCookies = 'hydownloader_cookies';
  static const String prefKeyAdditionalParameters = 'hydownloader_additional_parameters';
  static const String prefKeyDownloadPath = 'hydownloader_download_path';
  static const String prefKeyAudioRate = 'hydownloader_audio_rate';
  static const String prefKeyPreviewAudioRate = 'hydownloader_preview_audio_rate';
  static const String prefKeyFileNameTemplate = 'hydownloader_filename_template';
  static const String prefKeyDownloadLyrics = 'hydownloader_download_lyrics';
  static const String prefKeyDownloadTranslation = 'hydownloader_download_translation';
  static const String prefKeyWriteMetadata = 'hydownloader_write_metadata';
  static const String prefKeyMaxConcurrent = 'hydownloader_max_concurrent';
  static const String prefKeySingleSongThreads = 'hydownloader_single_song_threads';
  static const String prefKeySyncFolders = 'hydownloader_sync_folders';
  static const String prefKeyDarkMode = 'hydownloader_dark_mode';
}

/// 音质档位定义与描述
class AudioQuality {
  /// 档位标识符（传给网易云 API 的 level 字段）
  final String level;

  /// 档位显示名称（如：无损音质、标准音质）
  final String label;

  /// 档位简要描述
  final String description;

  /// 格式预估后缀
  final String defaultExtension;

  const AudioQuality({
    required this.level,
    required this.label,
    required this.description,
    required this.defaultExtension,
  });

  /// 支持的所有音质档位列表（从高到低排列）
  static const List<AudioQuality> availableQualities = [
    AudioQuality(
      level: 'jymaster',
      label: '超清母带',
      description: 'Master 级至臻无损声音细节，码率最高',
      defaultExtension: 'flac',
    ),
    AudioQuality(
      level: 'sky',
      label: '沉浸环绕声',
      description: '全景声空间音频沉浸体验',
      defaultExtension: 'flac',
    ),
    AudioQuality(
      level: 'hires',
      label: 'Hi-Res 高解析',
      description: '高于 CD 的高解析度无损数字音频 (24bit/96kHz及以上)',
      defaultExtension: 'flac',
    ),
    AudioQuality(
      level: 'lossless',
      label: '无损音质 (FLAC)',
      description: 'CD 级无损音质，还原真实听感 (16bit/44.1kHz)',
      defaultExtension: 'flac',
    ),
    AudioQuality(
      level: 'exhigh',
      label: '极高品质 (320Kbps)',
      description: 'MP3 极高质量音频，文件适中音质佳',
      defaultExtension: 'mp3',
    ),
    AudioQuality(
      level: 'higher',
      label: '较高品质 (192Kbps)',
      description: '高品质音频',
      defaultExtension: 'mp3',
    ),
    AudioQuality(
      level: 'standard',
      label: '标准品质 (128Kbps)',
      description: '常规音质，文件体积最小',
      defaultExtension: 'mp3',
    ),
  ];

  /// 根据 level 标识查找音质配置，若未匹配则默认返回无损
  static AudioQuality fromLevel(String level) {
    return availableQualities.firstWhere(
      (q) => q.level.toLowerCase() == level.toLowerCase(),
      orElse: () => availableQualities[3], // lossless
    );
  }
}