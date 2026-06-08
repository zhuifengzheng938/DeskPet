# DeskPet

DeskPet 是一个用 SwiftUI 和 Swift Package Manager 写的 macOS 桌面宠物。它会悬浮在桌面上，对点击和悬停做出反应，带一个轻量聊天面板，并能执行一些本地 macOS 操作，比如打开 App、打开常用文件夹、截图、查看电量/磁盘状态、切换程序坞显示方式等。

这个仓库已经按“以后可能有更多桌宠”的方向整理过：当前桌宠是第一个可执行应用，共享模型、命令解析和 UI 放在 `DeskPetKit`，后续可以继续加新的桌宠 target。

## 运行环境

- macOS 14 或更新版本
- Xcode Command Line Tools
- Swift 6 工具链

## 仓库结构

```text
DeskPet/
|-- Package.swift
|-- Sources/
|   |-- DeskPet/
|   |   `-- main.swift              # 当前桌宠的可执行入口
|   |-- DeskPetKit/
|   |   `-- DeskPetKit.swift        # 共享模型、助手逻辑和 SwiftUI 组件
|   `-- DeskPetLauncher/
|       `-- main.swift              # 后台快捷键启动器
`-- Scripts/
    |-- build_and_run.sh            # 构建 .app 到 dist/
    |-- install_launcher.sh         # 安装快捷键启动器 LaunchAgent
    `-- uninstall_launcher.sh       # 卸载 LaunchAgent
```

后续新增桌宠时，可以在 `Sources/` 下新增可执行 target，复用 `DeskPetKit` 里的通用能力。

## 构建

```bash
swift build
```

生成 app bundle 到 `dist/`：

```bash
./Scripts/build_and_run.sh --stage
```

## 运行

运行快捷键启动器：

```bash
./Scripts/build_and_run.sh
```

按 `Control + Option + D` 启动或显示/隐藏 DeskPet。

只运行桌宠窗口：

```bash
./Scripts/build_and_run.sh --pet
```

## 安装启动器

安装用户级 LaunchAgent，让启动器常驻：

```bash
./Scripts/install_launcher.sh
```

卸载：

```bash
./Scripts/uninstall_launcher.sh
```

## 当前功能

- 透明悬浮 SwiftUI 桌宠窗口
- 点击、悬停、眨眼和跳动反馈
- 轻量聊天面板
- 文件夹选择和快速打开
- 打开 App、截图、查看电量、磁盘、IP、内存、锁屏、重启 Finder、显示隐藏文件、清空废纸篓、切换程序坞自动隐藏等本地命令
- 每日民谣推荐和哲学名言回复
- `Control + Option + D` 后台快捷键启动器

## 新增其他桌宠

1. 在 `Package.swift` 里新增 executable target。
2. 在 `Sources/<NewPetName>/` 下添加入口文件。
3. 复用 `DeskPetKit` 中的共享模型、命令处理和 UI 组件。
4. 将新桌宠自己的外观、人格、资源和专属命令放在新 target 中；如果规模变大，再拆成独立 library target。
