# GitStatX 2.0 - Swift Rewrite

GitStatX 2.0 是一个完全用 Swift 重写的 Git 统计分析工具，不再依赖任何外部命令行工具。

## 新特性

- ✅ **纯 Swift 实现** - 不再依赖 gitstats、gnuplot、git 命令行工具
- ✅ **SwiftData** - 使用原生数据持久化框架
- ✅ **SwiftUI** - 现代化的用户界面
- ✅ **原生 Git 解析** - 直接读取 Git 对象文件，无需外部依赖
- ✅ **WKWebView** - 现代化的 Web 内容显示
- ✅ **拖拽支持** - 从 Finder 拖拽添加 Git 仓库
- ✅ **分组管理** - 支持文件夹分组
- ✅ **导出功能** - 导出统计报告
- ✅ **多标签页** - 概览、活动、作者、提交、文件

## 项目结构

```
Sources/
├── GitStatXApp.swift          # 应用入口
├── Models/
│   ├── Project.swift         # 项目数据模型
│   ├── GitModels.swift       # Git 相关数据模型
│   └── DataController.swift   # 数据控制器
├── Services/
│   ├── GitRepository.swift   # Git 仓库解析（原生实现）
│   ├── GitStatsEngine.swift   # 统计引擎
│   └── HTMLReportGenerator.swift # HTML 报告生成器
└── Views/
    ├── MainWindowView.swift   # 主窗口
    ├── ProjectListView.swift  # 项目列表
    ├── ReportView.swift       # 报告视图
    ├── AddProjectSheet.swift  # 添加项目弹窗
    ├── ExportDocument.swift   # 导出文档
    └── SettingsView.swift     # 设置视图
```

## 技术栈

- **Swift 5.9+**
- **SwiftUI** - 用户界面
- **SwiftData** - 数据持久化
- **WebKit** - HTML 报告显示
- **zlib** - Git 对象解压缩

## 核心实现

### Git 解析引擎

`GitRepository.swift` 实现了原生的 Git 对象解析：
- 读取 `.git` 目录结构
- 解析 commit、tree、blob 对象
- 计算提交差异统计
- 支持压缩对象的解压

### 统计引擎

`GitStatsEngine.swift` 负责生成统计数据：
- 遍历所有提交
- 统计作者贡献
- 统计文件变更
- 计算代码行数变化
- 生成 HTML 报告

### 报告生成

`HTMLReportGenerator.swift` 生成美观的 HTML 报告：
- 概览页面
- 活动图表
- 作者统计
- 提交历史
- 文件统计

## 构建和运行

```bash
# 使用 Swift Package Manager
swift build

# 运行
swift run GitStatX
```

## 系统要求

- macOS 14.0+
- Xcode 15.0+ 或 Swift 5.9+

## 与原版本的区别

| 特性 | 原版本 (Objective-C) | 新版本 (Swift) |
|------|---------------------|----------------|
| 语言 | Objective-C | Swift |
| UI 框架 | AppKit + WebView | SwiftUI + WKWebView |
| 数据存储 | SQLitePersistentObjects | SwiftData |
| Git 操作 | git 命令行 + ObjectiveGit | 原生解析 |
| 统计生成 | gitstats + gnuplot | 原生实现 |
| 依赖 | 多个外部工具 | 无外部依赖 |

## 许可证

GPLv3 - 与原版本保持一致
