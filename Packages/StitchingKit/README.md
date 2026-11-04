# StitchingKit

iOS 17 / macOS 14 本地图像配准模块。四个引擎通过相同接口供 UIKit 应用和 macOS 评测工具调用。没有网络运行时依赖。

## 模块边界

```text
UIImage / HEIC → RasterImage (RGBA8, original pixels)
                      ↓
             ScreenshotStitchingEngine
        ┌─────────┬──────────┬────────┬────────┐
        Ekibun    LongStitch ZoomIt  Seamly
        └─────────┴──────────┴────────┴────────┘
                      ↓
             StitchPlan (bounds + adjacent offsets)
                      ↓
       StitchCompositor → RasterImage → PNG / UIKit preview
```

* `StitchingCore`: 像素契约、ImageIO 解码、统一硬切合成器。无 UIKit、无算法选择。
* 四个算法 target：只依赖 Core，彼此不依赖。来源、固定 commit、许可证、改动范围、单独回归工具在 `Ports/`。
* `StitchingEngines`: 唯一注册表、工厂和显示名称。添加算法无需修改合成器。
* `StitchBenchmark`: macOS 可执行工具，直接读取同一批原图，生成图片、逐接缝 JSON 和 HTML 对比页。
* App 的 `PortedImageStitcher`：UIImage 方向、后台执行、临时文件和预览生命周期；不实现匹配算法。

坐标约定：图像行 0 在顶部。`next(x,y)` 对应 `previous(x+offsetX,y+offsetY)`，偏移始终用原图像素表示。`FrameBounds.bottom` 不包含该行。相邻图片的顺序由用户决定；当前合成器支持自上而下的截图，负向/不可用几何会作为未匹配完整保留。所有输入均须产生一个 bound 和相邻 pair 结果，不允许静默丢帧。

匹配失败只中断当前接缝，不撤销此前成功接缝。成功接缝在重叠内选择低差异的水平硬切，拷贝原像素，不做混合、补洞或生成内容。水平位移只保留公共宽度。输出限制 4500 万像素。重复判定依赖引擎；LongStitch 的零位移只有全图相同才可变成 duplicate。

## 移植范围

| 引擎 | 本项目实现 | 明确未移植 |
|---|---|---|
| Ekibun | 默认自动模式：diff mask + Laplacian + FFT phase correlation；Swift 数值适配和局部原像素验证 | 可选 SIFT / FLANN / homography 特征分支，原应用手动编辑 UI |
| LongStitch | Rust session 的精确/粗行指纹、公共连续段、唯一行证据、亮度回退；Swift 相邻帧适配 | 累积长图的回滚搜索、内容刷新和原 commit 合成过程 |
| ZoomIt | Microsoft **Zoomit-Mac** 原始分辨率 matcher，保留上游搜索路径和固定头尾检测 | Windows C++ 的完整实现与五帧悬浮组件 mask，连续采集丢帧/动量状态 |
| Seamly | 实际 StitchKit 源码，input-order 离线规划、tile consensus、独立 chrome、原分辨率 refinement | 自动重排序、录屏/采样、repair UI、原生最终合成与 PDF |

这些是用于统一对照的算法适配器，不能将结果直接等同于四个原应用的整体产品效果。此次允许其他语言库，但现有 Swift 来源和小型匹配器移植已能满足双平台构建；Rust 原实现仍通过 parity harness 做了独立对照。

## 来源和许可记录

* Ekibun `07c61d250824cddcaa84af38042334efe2ad0070`，LGPL-2.1，见 `Ports/Ekibun/`。
* jietuba `5eb635bd88eab96c1a3bd4273478ce15e161541b`，MIT，见 `Ports/LongStitch/`。
* Zoomit-Mac `45e15ac00c578fa9b6ca68d5e474b01dbc5d50ef`，MIT，见 `Ports/ZoomIt/`。
* Seamly `ed371adfc13151f95c95b6e3e8e3ff8790075d8d`，上游许可证 **TBD**，本地实验用途，未将其标成可发布的许可依赖。见 `Ports/Seamly/`。

## 验证

在仓库根目录：

```sh
swift test --package-path Packages/StitchingKit -c release
sh Scripts/benchmark-stitching.sh
sh Scripts/benchmark-stitching.sh --engine ekibun --group 2
```

评测输出为 `build/stitch-benchmark/index.html`、`results.json` 和每组/每算法的 `output.png`、`preview.png`、`seam-N.png`、`result.json`。原图 SHA-256、原始尺寸、对齐结果、独立的配准/合成耗时均有记录；图像解码和 PNG 写出不计入配准耗时。置信度是各自算法分数，不可跨算法直接比较。

HEIC 需要系统解码服务；受限沙箱可能无法使用它。解码器检查未写入的透明缓冲区并报错，不能把空白解码当成重复截图。必要时在可访问系统 HEIC 服务的终端运行上述脚本。测试原图与生成图留在 git 忽略的本地目录，报告只保存元数据。
