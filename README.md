# HyDownloader

<div align="center">
  <img src="assets/icon.png" width="128" height="128" alt="HyDownloader Logo" />
  <p>专业的跨平台网易云音乐与歌单同步下载工具</p>
  <p>参照 <a href="https://github.com/HyPlayer/HyPlayer">HyPlayer</a> 原生逻辑架构精心打造</p>
</div>

---

## 📖 项目简介

**HyDownloader** 是一款专为音乐爱好者打造的跨平台下载与歌单管理应用。基于 Flutter 现代响应式架构开发，深度复用 HyPlayer 核心网络通信与加解密设计，并创新性引入了**本地音乐双向同步引擎**，帮助您轻松管理、下载和备份网易云音乐中的海量歌曲与播客。

> **免责声明**：本项目仅供技术学习与个人离线备份研究交流使用，音频版权均归网易云音乐及原版权方所有。请支持正版音乐。

---

## ✨ 核心功能

### 1. 多元化安全登录
- **虚拟令牌登录 (伪造令牌)**：模拟虚拟设备硬件指纹，向云端注册匿名设备凭证，无需输入账号密码即可安全检索与下载曲目。
- **抓包导入登录 (Packet Capture)**：支持直接导入由 mitmproxy 导出的 `capture.json` 抓包数据或原生 Cookie，无感继承官方客户端授权。
- **手机扫码登录**：生成网易云官方二维码，支持使用网易云音乐手机 App 扫码快捷授权。
- **Cookie 登录**：支持手动粘贴网页端 Cookie（如 `MUSIC_U`）完成登录。

### 2. 丰富的主页内容浏览
- **我的歌单**：直观展示登录用户的全部在线歌单，特型高亮呈现“**我喜欢的音乐**”。
- **收藏播客**：无缝同步与浏览您在网易云收藏的声音电台及各期音频节目。
- **全网综合检索**：支持单曲、歌单、播客三维度全网快速检索。

### 3. 专业级音乐下载引擎
- **单曲与批量下载**：进入歌单或播客后，支持一键“全部下载”或多选“批量下载”。
- **多档位音质自选**：完整支持超清母带 (Master)、沉浸环绕声 (Sky)、Hi-Res 高解析 (24bit)、无损音质 (FLAC 16bit)、极高音质 (320Kbps) 与标准音质 (128Kbps)。
- **自定义命名模板**：支持 `{$SINGER}`、`{$SONGNAME}`、`{$ALBUM}`、`{$INDEX}` 等占位符灵活定制文件名。
- **元数据标签注入**：下载完成后自动将歌曲名、艺术家、专辑及高清封面注入音频 ID3 标签。
- **歌词双向同步**：自动拉取时间轴歌词并生成标准 `.lrc` 文件，支持翻译歌词无缝合并。
- **后台并发队列**：支持多任务并发控制、实时下载速度监测、暂停/恢复/重试与目录变更。

### 4. 下载前在线试听
- 内置轻量试听播放器，在决定下载前轻点即可在线试听整首曲目，支持进度拖拽与状态保持。

### 5. 💡 歌单文件双向同步 (独家新增亮点)
针对多设备离线听歌痛点全新打造，支持：
- 选取任意一个**在线歌单**与**多个本地文件夹**。
- 智能对比在线歌单曲目与本地已有音频文件。
- 精准分类列出：
  - **云端新增 (本地缺失)**：在线歌单拥有但本地尚未下载的曲目。
  - **本地多余**：本地文件夹存在但在线歌单中已移除的过时曲目。
  - **已同步**：两端保持一致的曲目。
- 提供全选/部分勾选同步选项：一键将缺失歌曲批量加入下载队列，并可安全清理本地多余文件及关联歌词。

---

## 🛠️ 项目架构设计

HyDownloader 遵循分层、模块化与单一职责规范设计，代码架构清晰明了：

```
lib/
├── config/                  # 全局应用配置与色彩主题
│   ├── app_constants.dart   # 音质档位、占位符模板、存储键与端点常量
│   └── app_theme.dart       # Material 3 现代化自适应主题
├── models/                  # 强类型数据模型层
│   ├── auth_state.dart      # 认证状态与登录凭据
│   ├── song.dart            # 单曲信息模型
│   ├── playlist.dart        # 歌单数据模型
│   ├── podcast.dart         # 播客与声音节目模型
│   ├── search_result.dart   # 综合检索封装
│   ├── download_task.dart   # 下载任务生命周期模型
│   ├── sync_item.dart       # 同步差异比对实体
│   └── user_profile.dart    # 用户个人资料模型
├── services/                # 独立业务服务层
│   ├── netease/             # 网易云接口与协议核心
│   │   ├── crypto_utils.dart# EAPI (AES-128-ECB) 与 WEAPI (AES+RSA) 算法
│   │   ├── netease_client.dart # 底层 HTTP、Cookie 与抓包参数管理器
│   │   ├── auth_service.dart# 伪造令牌、抓包导入、扫码轮询认证
│   │   ├── music_service.dart # 歌单、详情、播客、搜索与高解析链接解析
│   │   └── lyric_service.dart # 时间轴歌词解析与翻译合并
│   ├── download/            # 下载引擎
│   │   ├── download_service.dart # 并发队列调度与流式下载
│   │   ├── id3_tagger.dart  # 音频 ID3v2 标签与封面写入器
│   │   └── lyric_writer.dart# 本地 .lrc 文件保存
│   ├── sync/                # 歌单文件比对与同步
│   │   └── playlist_sync_service.dart # 多文件夹比对算法与批量执行
│   ├── audio/               # 音频预览服务
│   │   └── preview_player_service.dart # 试听播放器单例封装
│   └── storage/             # 本地持久化
│       └── storage_service.dart # 偏好设置、路径与登录缓存
├── providers/               # 响应式状态管理层 (Provider)
│   ├── auth_provider.dart   # 登录状态管理
│   ├── home_provider.dart   # 主页数据管理
│   ├── player_provider.dart # 试听状态管理
│   ├── download_provider.dart # 下载队列管理
│   └── sync_provider.dart   # 歌单比对同步管理
├── ui/                      # 视图表现层
│   ├── home/                # 主页框架与 Tab 页面
│   ├── detail/              # 歌单与播客详情页
│   ├── sync/                # 歌单文件同步交互界面
│   ├── download/            # 下载管理中心
│   ├── login/               # 四合一登录认证弹窗
│   └── widgets/             # 可复用组件 (试听栏、歌曲项、空状态)
└── main.dart                # 应用入口与全局 Provider 注入
```

---

## 🚀 本地开发与构建

### 开发环境要求
- **Flutter SDK**：`3.44.1` 或兼容版本
- **Dart SDK**：`3.12.1` 或兼容版本
- 目标平台支持：Windows、macOS、Linux、Android、iOS（全平台桌面与移动端）

### 常用命令

```bash
# 获取项目依赖
flutter pub get

# 静态代码质量分析 (保证 0 warning / 0 error)
flutter analyze

# 运行自动化单元与组件测试
flutter test

# 本地调试运行 (Windows 桌面端)
flutter run -d windows

# 构建 Android 安装包
flutter build apk --release

# 构建 Windows 桌面便携版
flutter build windows --release
```

---

## 📄 开源许可证

本项目遵循开源规范开发，仅供技术研究交流使用。
