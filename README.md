# Avo Helper

一个使用 SwiftUI 构建的本地截图拼接工具，最低支持 iOS 17。

## 当前功能

- 从系统相册按顺序选择 2–10 张截图
- 拖动调整截图顺序、删除或继续添加
- 对内容区执行 NCC 匹配和多区域投票，自动识别滚动位移并仅追加新增内容
- 默认使用 Ekibun；右上角“更多选项”菜单可切换 LongStitch、ZoomIt、Seamly，保留原算法对照
- 对拼接结果进行四角自由裁剪
- 无损 PNG 保存到相册
- 单页长 PDF 系统分享
- 左上角菜单切换「多张截图拼接」与「视频转长截图」
- 从相册或文件导入录屏，在 Long Screen / hypr-longshot 两个独立引擎间切换
- 视频转换显示进度、支持取消；无法连接的片段分别预览、裁剪和导出，并显示不完整提示

## 开发

直接使用 Xcode 打开 `AvoHelper.xcodeproj`，选择 `AvoHelper` scheme 后运行。

默认 `AvoHelper` scheme 不采集代码覆盖率，Release 配置显式关闭覆盖率插桩。需要覆盖率报告时选择 `AvoHelper-Coverage` scheme，它以 Debug 配置运行测试。

工程文件由 `project.yml` 管理；修改工程配置后可运行：

```sh
xcodegen generate
```

图片、视频处理和导出均在设备本地完成。视频功能链接 Long Screen 的 Rust 静态库和 OpenCV；不内嵌 Python，也不上传录屏。

## 录屏转长截图

`Packages/VideoStitchingKit` 提供共用 AVFoundation 逐帧解码器与两个同步处理引擎，App 在后台工作任务运行算法。界面切到后台时取消转换，避免在后台被挂起后留下不明确的任务状态。

- **Long Screen**：保留原始 Rust 核心，通过 C ABI 调用；每一遍分析重新顺序解码，避免把整个视频展开为原始帧临时文件。当前限制每段最长 3 分钟。固定界面、回滚、二维移动由上游算法处理，不保证所有输入都能正确重建。
- **hypr-longshot**：将 Python 流程移植为 Swift，实际调用 OpenCV `phaseCorrelate`。约 10 fps 采样、固定栏校准后回放校准帧；保留完整输入边缘，逆向/不可信匹配分段报告。适合平稳向下滚动。

两种引擎不自动混用。输出预算为总计 4500 万像素；工作预算随设备内存取值、最高 512 MB，它不是进程 RSS 的严格上限。超出预算会报错或保留明确标记的不完整结果。选择其他片段时重置裁剪；「存到相册」和 PDF 导出只处理当前片段。

Long Screen 的固定版本源码、许可证、构建方法与限制见 [LongScreenBridge](Packages/LongScreenBridge/README.md)。仓库包含设备 arm64、模拟器 arm64/x86_64 和 macOS arm64 的 XCFramework。修改 Rust 桥接后运行：

```sh
Packages/LongScreenBridge/build.sh
```

OpenCV 通过 SwiftPM 固定为 `opencv-spm` 4.13.0，首次构建需要下载，之后复用 SwiftPM 共享缓存。Hypr 上游快照及移植差异见 [移植记录](Ports/HyprLongshot/PORT_NOTES.md)。

视频算法和真实编码视频的回归测试：

```sh
swift test --package-path Packages/VideoStitchingKit
```

四种移植算法使用本地 Swift package 封装，包含第三方来源代码；具体移植范围和许可记录见 [StitchingKit](Packages/StitchingKit/README.md)。Seamly 上游许可尚未确定，当前只作本地实验。

在仓库根目录运行 `sh Scripts/benchmark-stitching.sh`，使用 `LocalTestData/Screenshots/` 的四组原图生成 `build/stitch-benchmark/index.html`。实测结果与限制见 [评测报告](Benchmarks/Screenshots/REPORT.md)。截图和完整输出不会加入版本控制。
