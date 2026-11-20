# Android 固定签名配置

Release 工作流不生成临时密钥，也不使用 debug 签名。普通 CI 仍构建 debug APK；Pull Request 不接触发布密钥。未配置签名时，Release 明确失败。

## GitHub Secrets

在仓库 **Settings → Secrets and variables → Actions** 添加以下 Repository secrets：

| Secret | 内容 |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | 现有 JKS 文件的 Base64 内容 |
| `ANDROID_KEYSTORE_PASSWORD` | JKS 存储密码 |
| `ANDROID_KEY_ALIAS` | 签名密钥别名 |
| `ANDROID_KEY_PASSWORD` | 此别名的私钥密码 |

Windows 将 JKS 转成 Base64 并复制到剪贴板（不要提交或发送密钥内容）：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes('D:\Keys\release.jks')) | Set-Clipboard
```

Linux/macOS：

```sh
base64 < release.jks | tr -d '\n'
```

查看别名：`keytool -list -keystore release.jks`（密码通过交互输入）。

工作流将密钥恢复到 runner 临时目录，检查必填项与别名，构建后验证 APK 签名，并始终清理密钥；密码仅通过环境变量传递，不写入构建产物。签名密钥不进入缓存或上传文件。所有发布必须持续使用同一密钥，请自行安全备份 JKS。

## 本地 Release

复制 `android/key.properties.example` 为 `android/key.properties`，填入 JKS 路径、密码和别名，再执行 `flutter build apk --release`。这些文件已加入忽略规则。也可使用 `ANDROID_KEYSTORE_PATH`、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD` 环境变量。

## 已安装旧版本

旧 CI APK 使用各 runner 生成的 debug 签名。切换到固定 JKS 后，通常不能直接覆盖旧 APK，需要卸载旧版后重新安装；卸载前请备份应用设置，音乐文件应存放在用户选定的共享目录中。之后使用同一个 JKS 发布即可正常覆盖升级。
