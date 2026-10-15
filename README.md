<h1 align="center">niri-better-action</h1>

<p align="center">基于 niri 的滚动平铺 Wayland 合成器。左右移动列时，窗口会先一起缩小、错开，再缓回原尺寸；连按从当前画面继续，而不是跳回静止布局。</p>
<p align="center">A scrollable-tiling Wayland compositor based on niri. Moving a column left or right shrinks the windows together, slides them apart, then eases them back to full size. Another press continues from the picture on screen.</p>

<p align="center">
    <a href="https://github.com/niri-wm/niri"><img alt="Upstream" src="https://img.shields.io/badge/upstream-niri--wm%2Fniri-blue"></a>
    <a href="https://github.com/niri-wm/niri/blob/v26.04/LICENSE"><img alt="License" src="https://img.shields.io/badge/license-GPL--3.0--or--later-blue"></a>
    <a href="https://github.com/niri-wm/niri/releases/tag/v26.04"><img alt="Base" src="https://img.shields.io/badge/base-niri%20v26.04-green"></a>
</p>

<p align="center">
    <a href="#中文">中文</a> · <a href="#english">English</a> · <a href="https://niri-wm.github.io/niri/Getting-Started.html">上游入门 / Upstream getting started</a>
</p>

<img width="1280" height="720" alt="niri with a few windows open" src="https://github.com/user-attachments/assets/dea5909e-1859-4aaa-9d88-d37f9663e00b" />

这是上游 niri 的静态截图，用来说明布局。本仓库改的是移动过程中的动画。

---

## 中文

### 这是什么

[niri](https://github.com/niri-wm/niri) 是一个滚动平铺的 Wayland 合成器：窗口排成向右延伸的列，新窗口不会把已有窗口挤变形；每个显示器有自己的列带和工作区。

**niri-better-action** 从 niri **v26.04**（`8ed0da4`）分出。配置、快捷键、IPC、多显示器、浮动窗口、标签、截图和门户投屏都与这一版上游相同。本仓库只改了移动列、以及在列内上下移动窗口时的过渡。

### 和原项目的区别

上游在 `move-column-left` / `move-column-right` 时，按新顺序重排列，再用配置项 `animations.window-movement`（默认是弹簧）把列滑到新位置。窗口在移动过程中保持原尺寸。动画尚未结束就再按一次时，偏移从静止布局重算，画面会先回到排好的位置，再开始下一次滑动。

这一支把左右移动列做成三段，并让连按沿着当前画面继续：

1. **缩小。** 被移动的列以 420ms 的 ease-out cubic 收到自身的 92%（`TRAVEL_SCALE_MIN`）。这一段里，该工作区上的每一列都按这个比例绘制，所以左右的列会一起变小。各列先停在按键之前的屏幕坐标上。
2. **错开。** 缩放到约 94%（0.92 + 0.02），或缩小动画已经结束时，邻居列和视角用同一条 420ms ease-out cubic 滑向新的列顺序。被移动的列保持缩小。视角和列位移用同一条曲线，避免列先漂开再突然对齐。
3. **恢复。** 列的位置和视角都停稳之后，被移动的列再以 480ms 的 ease-out cubic 回到 100%。恢复阶段没有弹簧过冲。

在缩小、错开或恢复的过程中再按一次左/右，或使用「移到第一列 / 最后一列 / 指定序号」，会先记下每一列当时的屏幕位置和当前缩放，再从那里进入下一次缩小。若已经足够小，则直接开始错开。画面保持在你看到的位置上，再走向新顺序。

列内上下交换窗口（`move-window-up` / `move-window-down`）时，被你移动的那个窗口会缩到 92% 再回到原尺寸；与它对调的窗口只做普通滑动。浮动窗口换位时，被移动的窗口同样先缩小再恢复。

缩放只加在绘制上，绕每个窗口的中心。布局尺寸、焦点和点击区域仍按未缩放的窗口计算。

默认快捷键没有改动：

| 动作 | 默认快捷键 |
| --- | --- |
| `move-column-left` | `Mod+Ctrl+Left`、`Mod+Ctrl+H` |
| `move-column-right` | `Mod+Ctrl+Right`、`Mod+Ctrl+L` |
| `move-window-up` / `move-window-down` | `Mod+Ctrl+Up` / `Down`，以及 `K` / `J` |
| `move-column-to-first` / `move-column-to-last` | `Mod+Ctrl+Home` / `End` |

实现位于 `src/layout/scrolling.rs`（列的缩小、错开、恢复，以及连按时冻结当前位置）、`src/layout/tile.rs`（单窗口的缩放）和 `src/layout/floating.rs`（浮动窗口绘制同样的缩放）。

### 基线与构建

- 上游：<https://github.com/niri-wm/niri>
- 基线标签：[v26.04](https://github.com/niri-wm/niri/releases/tag/v26.04)
- 编译、运行和配置与这一版 niri 相同，见 [Getting Started](https://niri-wm.github.io/niri/Getting-Started.html)
- niri 本身不是完整桌面环境，还需要状态栏、启动器等组件

### 许可与反馈

本仓库与上游一样使用 [GPL-3.0-or-later](LICENSE)。niri 由 Ivan Molodetskikh 编写。这里的移动动画由 zelin_cai 修改。

本仓库的动画问题请提到这里。其余合成器行为的问题仍应报到 [niri-wm/niri](https://github.com/niri-wm/niri)。

---

## English

### What this is

[niri](https://github.com/niri-wm/niri) is a scrollable-tiling Wayland compositor. Windows sit in columns on a strip that extends to the right, and opening a window does not resize the ones already there. Each monitor has its own strip and its own workspaces.

**niri-better-action** forks niri **v26.04** (`8ed0da4`). Configuration, key bindings, IPC, multi-monitor layout, floating windows, tabs, the screenshot UI, and portal screencasting match that upstream release. This tree changes the motion used when a column moves left or right, and when a window moves up or down inside a column.

### Differences from upstream niri

Upstream `move-column-left` / `move-column-right` reorders the columns, then slides them into place with `animations.window-movement` (a spring by default). Windows keep their size for the whole move. Pressing again before that animation finishes recomputes the offset from the resting layout, so the picture returns to the settled arrangement and then starts the next slide.

This fork plays a left/right column move in three phases, and a repeated press continues from the current frame:

1. **Shrink.** The moved column eases to 92% of its size (`TRAVEL_SCALE_MIN`) with a 420ms ease-out cubic. During this phase every column on that workspace is drawn at the same scale, so the columns beside it shrink with it. Columns stay at the screen positions they had when the key was pressed.
2. **Cross.** Once the scale is about 94% (0.92 + 0.02), or the shrink animation has finished, the neighboring columns and the view ease to the new column order with the same 420ms ease-out cubic. The moved column stays small. The view and the column offsets share that curve, so a column does not drift and then jump into alignment.
3. **Grow.** After the column positions and the view have settled, the moved column eases back to 100% with a 480ms ease-out cubic. This return does not overshoot.

A further left/right press during shrink, cross, or grow — including move-to-first, move-to-last, and move-to-index — records each column's on-screen position and the current scale, then starts the next shrink from there. If the column is already small enough, the cross starts immediately. The picture stays where you see it, then moves toward the new order.

`move-window-up` / `move-window-down` inside a column scales the window you moved down to 92% and back to full size. The window it swaps with only slides. Repositioning a floating window uses the same shrink-and-return on the window that moved.

The scale is applied only while drawing, around each window's center. Layout size, focus, and hit testing still use the unscaled window.

The default bindings are unchanged:

| Action | Default binding |
| --- | --- |
| `move-column-left` | `Mod+Ctrl+Left`, `Mod+Ctrl+H` |
| `move-column-right` | `Mod+Ctrl+Right`, `Mod+Ctrl+L` |
| `move-window-up` / `move-window-down` | `Mod+Ctrl+Up` / `Down`, and `K` / `J` |
| `move-column-to-first` / `move-column-to-last` | `Mod+Ctrl+Home` / `End` |

The code lives in `src/layout/scrolling.rs` (column shrink, cross, grow, and holding the current position across repeated presses), `src/layout/tile.rs` (per-window scale), and `src/layout/floating.rs` (the same scale while drawing floating windows).

### Base and build

- Upstream: <https://github.com/niri-wm/niri>
- Base tag: [v26.04](https://github.com/niri-wm/niri/releases/tag/v26.04)
- Build, run, and configuration match that niri release. See [Getting Started](https://niri-wm.github.io/niri/Getting-Started.html).
- niri by itself is not a full desktop; it still needs a bar, a launcher, and the rest of a session.

### License and feedback

This repository is [GPL-3.0-or-later](LICENSE), the same as upstream. niri is written by Ivan Molodetskikh. The move animation here is by zelin_cai.

Report animation issues in this repository. Report other compositor behavior to [niri-wm/niri](https://github.com/niri-wm/niri).
