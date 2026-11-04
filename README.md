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

## 开发

直接使用 Xcode 打开 `AvoHelper.xcodeproj`，选择 `AvoHelper` scheme 后运行。

工程文件由 `project.yml` 管理；修改工程配置后可运行：

```sh
xcodegen generate
```

应用不包含第三方运行时依赖，图片处理和导出均在设备本地完成。

四种移植算法使用本地 Swift package 封装，包含第三方来源代码；具体移植范围和许可记录见 [StitchingKit](Packages/StitchingKit/README.md)。Seamly 上游许可尚未确定，当前只作本地实验。

在仓库根目录运行 `sh Scripts/benchmark-stitching.sh`，使用 `LocalTestData/Screenshots/` 的四组原图生成 `build/stitch-benchmark/index.html`。实测结果与限制见 [评测报告](Benchmarks/Screenshots/REPORT.md)。截图和完整输出不会加入版本控制。
