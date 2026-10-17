# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 项目定位

本仓库是 [niri](https://github.com/niri-wm/niri)（滚动平铺 Wayland 合成器，基于 Smithay）的分支，基线为上游 **v26.04**（提交 `8ed0da44`）。分支只改了移动动画：

- 左右移动列（`move-column-left/right/to-first/to-last/to-index`）
- 列内上下移动窗口（`move-window-up/down`）、浮动窗口换位
- 把窗口或列移到上下 / 指定序号的工作区

其余行为（配置、IPC、多显示器、截图、投屏等）应与上游 v26.04 保持一致，不要顺手改动。查看本分支的全部改动：`git diff 8ed0da44 -- src/`。README.md 有动画行为的完整中英文说明，修改动画后需要同步更新它。

## 常用命令

```sh
cargo build                     # 调试构建
cargo build --release
cargo test --all                # 含子 crate（niri-config、niri-ipc）
cargo test --all --exclude niri-visual-tests   # CI 的用法，不需要 GTK
cargo test --all <测试名>        # 运行单个测试，例如 repeated_moves_to_workspace_settle
env RUN_SLOW_TESTS=1 cargo test --all          # 包括较慢的随机化（proptest）布局测试
env RUN_SLOW_TESTS=1 PROPTEST_CASES=200000 PROPTEST_MAX_GLOBAL_REJECTS=200000 RUST_BACKTRACE=1 cargo test --release --all   # 推送前的完整测试
cargo clippy --all --all-targets
cargo +nightly fmt --all        # 格式化必须用 nightly（rustfmt.toml 用了 nightly 选项）
cargo check --no-default-features   # CI 也会检查各 feature 组合：dbus / systemd / dinit / xdp-gnome-screencast
```

嵌套运行预览（在现有桌面里以窗口方式启动）：

```sh
cargo run -- -c resources/preview-config.kdl
```

`preview-config.kdl` 是本分支新增的：它 include 默认配置，把嵌套时的 Mod 键设为 Alt（宿主合成器占用了 Super），并启动三个 alacritty。所以列移动是 `Alt+Ctrl+Left/Right` 或 `Alt+Ctrl+H/L`。

`niri-visual-tests` 是 GTK 程序，用 mock 窗口和真实布局/渲染代码跑固定用例，调动画时有用：`cargo run -p niri-visual-tests`。

## 架构概览

- `src/main.rs` / `src/niri.rs`：入口和全局状态 `Niri`/`State`，事件循环基于 calloop。
- `src/backend/`：`tty.rs`（DRM/KMS，真机）、`winit.rs`（嵌套窗口）、`headless.rs`（测试）。
- `src/input/`：输入处理，键绑定动作在 `input/mod.rs` 中分派到 `Layout` 的方法。
- `src/handlers/`、`src/protocols/`：Wayland 协议实现。
- `src/animation/`：`Animation`（缓动/弹簧）与 `Clock`。测试中通过 `Op::AdvanceAnimations` 手动推进时钟。
- `niri-config/`：KDL 配置解析（knuffel）。`niri-ipc/`：IPC 类型，公开 crate。

### 布局层次（本分支改动集中在这里）

`src/layout/` 对窗口类型泛型化（`W: LayoutElement`），因此可以在没有 Wayland 的情况下单元测试。层次自上而下：

`Layout`（mod.rs）→ `Monitor`（monitor.rs，持有工作区列表和工作区切换动画）→ `Workspace`（workspace.rs）→ `ScrollingSpace`（scrolling.rs，列带与视角偏移）/ `FloatingSpace`（floating.rs）→ `Column`（scrolling.rs）→ `Tile`（tile.rs，单窗口外框、边框、阴影和各类动画）。

每层都有 `verify_invariants()`，测试在每个操作后调用它。

### 本分支的"travel"动画

相关标识符都带 `travel` / `lift` 字样，可以直接 grep：

- `tile.rs`：`travel_enabled()`（`animations.off`、`window-movement.off` 或 `window-travel.off` 任一开启时返回 false，各入口据此退回上游动画）和 `travel_min_scale()`（读配置 `animations.window-travel.scale`，默认 0.88，定义在 `niri-config/src/animations.rs` 的 `WindowTravelAnim`）；`travel_settle_spring()`（缩小与位移，420ms ease-out cubic）和 `travel_spring()`（恢复到 100%，480ms ease-out cubic）。函数名带 spring，实际都是缓动曲线，不是弹簧。`advance_travel_scale` 负责在缩小结束后切换到恢复阶段。
- `scrolling.rs`：`ColumnTravel`（当前正在移动的列）、`travel_pivot()`（被移动的列绕被移动窗口的中心缩放）、`TravelGather` / `travel_gather()`（只有被移动的窗口缩放，四周窗口保持原尺寸、按它的缩放算出平移量向中间聚拢）、`gather_snapshot()` / `bake_gather()`（连按、移除列、浮起时把聚拢量的变化折进移动动画，避免跳动）、连按时冻结当前屏幕位置再继续，以及跨工作区时的浮起（lifted）状态。
- `monitor.rs`：`move_tile_to_workspace_with_travel` / `move_column_to_workspace_with_travel` 计算跨工作区移动的起点；渲染时调用各工作区的 `render_lifted`，把浮起的列绘制在所有工作区之上（即使它所在工作区不在屏幕内）。
- `workspace.rs`：`begin_lift` / `has_lifted` / `render_lifted` 把浮起状态转交给 `ScrollingSpace` 中的同名方法。
- `floating.rs`：浮动窗口绘制同样的缩放。

缩放只作用于绘制：布局尺寸、焦点和点击区域都按未缩放的窗口计算，改动时要保持这一点。浮动窗口和移到其他显示器的操作保持上游行为。

## 测试约定

- 布局测试在 `src/layout/tests.rs`。新增布局操作时，加入该文件中的 `Op` 枚举（自动进入随机化测试），适用的话也加入 `every_op` 数组。注意上游 wiki 说 `Op` 在 `mod.rs` 底部，实际已移到 `tests.rs`。
- 动画类测试的写法可参考 `repeated_moves_to_workspace_settle`：用 `check_ops_with_options` 构造布局，穿插 `Op::AdvanceAnimations`，最后断言 `are_animations_ongoing` 结束。
- `src/tests/` 是客户端-服务端集成测试（使用 insta 快照，快照在 `src/tests/snapshots/`）。
- 新配置项要加入 niri-config 的解析测试，并在 `docs/wiki/` 中写文档（带 `Since` 标注）。

## 代码风格

- `rustfmt.toml`：`imports_granularity = "Module"`、`group_imports = "StdExternalCrate"`、注释按 100 列换行。
- 合成器崩溃会带走整个会话，能恢复的编程错误用 `error!` 记录而不是 `unwrap()`；`warn!` 用于用户或硬件导致的问题；`trace!` 在 release 构建中会被编译掉。
- 参考周边代码和同类模块的结构写法，保持与上游一致，方便日后 rebase 到新的上游版本。
