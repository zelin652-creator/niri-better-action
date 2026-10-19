<h1 align="center">niri-better-action</h1>

<p align="center">基于 niri 的滚动平铺 Wayland 合成器。移动窗口时，只有被移动的窗口缩小，四周的窗口保持原尺寸、贴着它向中间聚拢，再一起缓回原位；连按从当前画面继续，而不是跳回静止布局。</p>
<p align="center">A scrollable-tiling Wayland compositor based on niri. Moving a window shrinks only that window while the windows around it keep their size and close in on it, then everything eases back. Another press continues from the picture on screen.</p>

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

**niri-better-action** 从 niri **v26.04**（`8ed0da4`）分出。配置、快捷键、IPC、多显示器、浮动窗口、标签、截图和门户投屏都与这一版上游相同，只多了一个动画配置项 `animations.window-travel`。本仓库只改了移动列、在列内上下移动窗口，以及把窗口或列移到其他工作区时的过渡。

### 和原项目的区别

上游在 `move-column-left` / `move-column-right` 时，按新顺序重排列，再用配置项 `animations.window-movement`（默认是弹簧）把列滑到新位置。窗口在移动过程中保持原尺寸。动画尚未结束就再按一次时，偏移从静止布局重算，画面会先回到排好的位置，再开始下一次滑动。

这一支把左右移动列做成同时进行的缩小和错开，再恢复尺寸，并让连按沿着当前画面继续：

1. **缩小、聚拢并错开。** 按下的同一帧里，被移动的列以 420ms 的 ease-out cubic 绕正在移动的那个窗口的中心收到自身的 88%（可用 `animations.window-travel.scale` 调整）。其他列不缩放，保持原尺寸，只是整体平移，贴着被移动列缩进去的边缘跟过去，所以它们之间的间距始终不变：左边的列一起右移，右边的列一起左移。效果参考 macOS 从全屏空间退出到桌面时窗口收进去的样子。邻居列、被移动的列和视角也在这一帧用同一条 420ms ease-out cubic 滑向新的列顺序，不会等缩小结束。视角和列位移用同一条曲线，避免列先漂开再突然对齐。
2. **恢复。** 列的位置和视角都停稳之后，被移动的列再以 480ms 的 ease-out cubic 回到 100%，四周的列同步平移回原位。恢复阶段没有弹簧过冲。

在缩小、错开或恢复的过程中再按一次左/右，或使用「移到第一列 / 最后一列 / 指定序号」，会先记下每一列当时的屏幕位置（包括聚拢的平移）和当前缩放，并立刻从那里继续滑动。画面保持在你看到的位置上，再走向新顺序，不会先停住等再缩小一轮；换到被移动列另一侧的邻居也不会因为聚拢方向反过来而跳一下。

列内上下交换窗口（`move-window-up` / `move-window-down`）时，被你移动的那个窗口会缩到 88% 再回到原尺寸。四个方向都向它聚拢：同一列里上方的窗口下移、下方的窗口上移，左右两侧的列水平靠过来，全都保持原尺寸和原间距。与它对调的窗口照常滑到新位置。浮动窗口换位时，被移动的窗口同样先缩小再恢复，其他浮动窗口不动。

**移到上下工作区。** 上游把窗口或列移到另一个工作区时，它直接成为目标工作区的一部分，跟着目标工作区从下方或上方滑进来，只有目标工作区里原有的列会让位。这一支让它走和左右移动列一样的过程：

1. 被移动的窗口浮在所有工作区之上，从它当前在屏幕上的位置沿直线走到目标位置。新旧位置都在屏幕内，所以它基本停在原地，最多水平错开一点，两个工作区从它身后滑过。
2. 同一帧里，窗口以 420ms 的 ease-out cubic 缩到 88%，目标工作区的列保持原尺寸，一边让出位置，一边贴着它的边缘聚拢过来。
3. 工作区切换、视角平移、邻居列让位、源工作区补位和这段位移都用同一条 420ms 曲线。
4. 全部停稳后，窗口再以 480ms 回到原尺寸。

连按时同样从当前画面继续：再按一次会从窗口此刻的屏幕位置和缩放出发；离开的工作区里那些列从聚拢的位置平移回原位，不会突然弹回。适用于 `move-column-to-workspace-up` / `-down`、`move-window-to-workspace-up` / `-down`、`move-window-down-or-to-workspace-down` / `move-window-up-or-to-workspace-up` 落到相邻工作区的那一步，以及按序号的 `move-column-to-workspace` / `move-window-to-workspace`。浮动窗口和移到其他显示器的操作保持上游行为。

缩放和聚拢的平移只加在绘制上，并且只有被移动的窗口（左右移动或跨工作区时是它所在的整列）会缩放。左右移动列和跨工作区移动时，它绕正在移动的那个窗口的中心缩小；列内上下移动和浮动窗口换位时，绕它自己的中心缩小。布局尺寸、焦点和点击区域仍按未缩放、未平移的窗口计算。

**配置。** 缩小比例可以在 `animations` 里调整，范围 0 到 1，设为 1 则只保留缓动的位移、不缩小。放一个 `off` 进去，或者关掉 `window-movement` 动画、用顶层 `off` 关掉全部动画时，这些移动都退回上游的行为：直接用 `window-movement` 滑动，不缩小、不聚拢，跨工作区时也不浮起。详见 [`docs/wiki/Configuration:-Animations.md`](docs/wiki/Configuration:-Animations.md) 中的 `window-travel` 一节。

```kdl
animations {
    window-travel {
        scale 0.88   // 默认值
        // off       // 退回上游的移动动画
    }
}
```

默认快捷键没有改动：

| 动作 | 默认快捷键 |
| --- | --- |
| `move-column-left` | `Mod+Ctrl+Left`、`Mod+Ctrl+H` |
| `move-column-right` | `Mod+Ctrl+Right`、`Mod+Ctrl+L` |
| `move-window-up` / `move-window-down` | `Mod+Ctrl+Up` / `Down`，以及 `K` / `J` |
| `move-column-to-first` / `move-column-to-last` | `Mod+Ctrl+Home` / `End` |
| `move-column-to-workspace-down` / `-up` | `Mod+Ctrl+Page_Down` / `Page_Up`，以及 `U` / `I` |

实现位于 `src/layout/scrolling.rs`（列的缩小、错开、恢复，连按时冻结当前位置，以及跨工作区时的浮起位移）、`src/layout/monitor.rs`（跨工作区移动的起点计算，以及在所有工作区之上绘制浮起的列）、`src/layout/tile.rs`（单窗口的缩放）和 `src/layout/floating.rs`（浮动窗口绘制同样的缩放）。

### 安装

先用发行版的包管理器装好 niri（例如 `sudo pacman -S niri`、`sudo dnf install niri`），它会带上登录会话、门户配置和 systemd 服务。然后运行：

```sh
curl -fsSLO https://raw.githubusercontent.com/zelin652-creator/niri-better-action/main/install.sh
bash install.sh
```

脚本会识别系统，先确认新版能在这台机器上运行、能读懂你现在的配置，再把新版装到 `/usr/local` 并让登录时启动它。发行版的 niri 不会被修改，系统升级 niri 也不会把新版冲掉。注销后重新登录生效。

装好后用 `niri-better` 管理：

| 命令 | 作用 |
| --- | --- |
| `niri-better status` | 查看登录时用的是新版还是原版 |
| `niri-better off` / `on` | 以后都用原版 / 切回新版 |
| `niri-better once` | 只有下一次登录用原版 |
| `niri-better uninstall` | 完全还原 |
| `bash install.sh` | 再运行一次就是更新到最新版 |

出问题时：

- 新版连续 2 次没能正常启动，下次登录会自动改用原版。
- 登录界面多了一个「Niri（原版）」会话，选它就只这一次用原版。
- 图形界面进不去时，按 `Ctrl+Alt+F3` 切到终端登录，运行 `niri-better off` 或 `niri-better uninstall`。

[Release](https://github.com/zelin652-creator/niri-better-action/releases) 里的包是在 Ubuntu 24.04 上为 x86_64 编译的，需要 glibc 2.39 以上，Ubuntu 24.04、Debian 13、Fedora 40、Arch 及更新的系统都可以。其他架构或更旧的系统请自己编译：

```sh
git clone https://github.com/zelin652-creator/niri-better-action
cd niri-better-action
cargo build --release
bash install.sh --local target/release/niri
```

编译需要 Rust 1.85 以上（发行版的太旧就用 [rustup](https://rustup.rs) 装）和 clang。装好 niri 后，大部分库已经有了：

- Arch：`sudo pacman -S --needed base-devel rust clang`
- Fedora：`sudo dnf install cargo gcc clang libudev-devel libgbm-devel libxkbcommon-devel wayland-devel libinput-devel dbus-devel systemd-devel libseat-devel pipewire-devel pango-devel cairo-gobject-devel libdisplay-info-devel`
- Debian / Ubuntu：`sudo apt install gcc clang libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev libwayland-dev libinput-dev libdbus-1-dev libsystemd-dev libseat-dev libpipewire-0.3-dev libpango1.0-dev libdisplay-info-dev`

本仓库基于上游 [v26.04](https://github.com/niri-wm/niri/releases/tag/v26.04)，配置和使用方法见上游的 [Getting Started](https://niri-wm.github.io/niri/Getting-Started.html)。niri 本身不是完整桌面环境，还需要状态栏、启动器等组件。

### 许可与反馈

本仓库与上游一样使用 [GPL-3.0-or-later](LICENSE)。niri 由 Ivan Molodetskikh 编写。这里的移动动画由 zelin_cai 修改。

本仓库的动画问题请提到这里。其余合成器行为的问题仍应报到 [niri-wm/niri](https://github.com/niri-wm/niri)。

---

## English

### What this is

[niri](https://github.com/niri-wm/niri) is a scrollable-tiling Wayland compositor. Windows sit in columns on a strip that extends to the right, and opening a window does not resize the ones already there. Each monitor has its own strip and its own workspaces.

**niri-better-action** forks niri **v26.04** (`8ed0da4`). Configuration, key bindings, IPC, multi-monitor layout, floating windows, tabs, the screenshot UI, and portal screencasting match that upstream release, apart from one added animation setting, `animations.window-travel`. This tree changes the motion used when a column moves left or right, when a window moves up or down inside a column, and when a window or column moves to another workspace.

### Differences from upstream niri

Upstream `move-column-left` / `move-column-right` reorders the columns, then slides them into place with `animations.window-movement` (a spring by default). Windows keep their size for the whole move. Pressing again before that animation finishes recomputes the offset from the resting layout, so the picture returns to the settled arrangement and then starts the next slide.

This fork plays a left/right column move as a shrink and a slide together, then a return to full size. A repeated press continues from the current frame:

1. **Shrink, close in, and cross.** On the frame the key is pressed, the moved column eases to 88% of its size (adjustable with `animations.window-travel.scale`) with a 420ms ease-out cubic, about the center of the window being moved. The other columns do not scale. They keep their size and shift as a group to follow the moved column's edges as they pull in, so the gaps between windows stay the same: the columns on the left shift right and the columns on the right shift left. The look is modeled on a macOS window shrinking back onto the desktop as it leaves a full-screen space. The neighboring columns, the moved column, and the view also start easing to the new column order on that frame with the same 420ms ease-out cubic. The slide does not wait for the shrink. The view and the column offsets share that curve, so a column does not drift and then jump into alignment.
2. **Grow.** After the column positions and the view have settled, the moved column eases back to 100% with a 480ms ease-out cubic, and the columns around it shift back with it. This return does not overshoot.

A further left/right press during the move or the grow — including move-to-first, move-to-last, and move-to-index — records each column's on-screen position, including the shift toward the moved column, and the current scale, then continues the slide from there immediately. The picture stays where you see it, then moves toward the new order, without parking until the column shrinks again. A neighbor that ends up on the other side of the moved column does not jump when its shift changes direction.

`move-window-up` / `move-window-down` inside a column scales the window you moved down to 88% and back to full size. Everything around it closes in from all four sides: the windows above it in the column shift down, the ones below shift up, and the columns on either side shift toward it, all at their own size and with the gaps unchanged. The window it swaps with slides to its new place as usual. Repositioning a floating window uses the same shrink-and-return on the window that moved; the other floating windows stay put.

**Moving to the workspace above or below.** Upstream makes the window or column part of the target workspace right away, so it rides in from below or above together with that workspace, and only the columns already there make room. This fork plays the same sequence as a left/right column move:

1. The moved window is drawn above every workspace and travels in a straight line from where it is on screen to its new slot. Both positions are on screen, so it mostly stays put, shifting sideways at most, while the two workspaces slide past behind it.
2. On that frame the window eases to 88% with a 420ms ease-out cubic. The columns on the target workspace keep their size, make room for it, and close in on its edges.
3. The workspace switch, the view pan, the neighbors making room, the source workspace closing the gap, and the travel itself all share that 420ms curve.
4. Once everything has settled, the window eases back to full size over 480ms.

A repeated press continues from the current frame as well: the next move starts from the window's current on-screen position and scale, and the columns on the workspace it leaves slide back from where they had closed in instead of snapping. This covers `move-column-to-workspace-up` / `-down`, `move-window-to-workspace-up` / `-down`, the step of `move-window-down-or-to-workspace-down` / `move-window-up-or-to-workspace-up` that lands on the next workspace, and the by-index `move-column-to-workspace` / `move-window-to-workspace`. Floating windows and moves to another monitor keep the upstream behavior.

The scale and the closing-in shift are applied only while drawing, and only the moved window scales (its whole column, for a left/right or cross-workspace move). A left/right column move and a move to another workspace scale it about the center of the window being moved. Moving a window up or down inside a column, or repositioning a floating window, scales it about its own center. Layout size, focus, and hit testing still use the unscaled, unshifted windows.

**Configuration.** The shrink can be adjusted inside `animations`, between 0 and 1; 1 keeps the eased travel without shrinking. Putting `off` inside, turning off the `window-movement` animation, or turning off all animations with the top-level `off` brings back the upstream behavior for all of these moves: a plain `window-movement` slide, with no shrink, no closing in, and no lift across workspaces. See the `window-travel` section of [`docs/wiki/Configuration:-Animations.md`](docs/wiki/Configuration:-Animations.md).

```kdl
animations {
    window-travel {
        scale 0.88   // the default
        // off       // use the upstream movement instead
    }
}
```

The default bindings are unchanged:

| Action | Default binding |
| --- | --- |
| `move-column-left` | `Mod+Ctrl+Left`, `Mod+Ctrl+H` |
| `move-column-right` | `Mod+Ctrl+Right`, `Mod+Ctrl+L` |
| `move-window-up` / `move-window-down` | `Mod+Ctrl+Up` / `Down`, and `K` / `J` |
| `move-column-to-first` / `move-column-to-last` | `Mod+Ctrl+Home` / `End` |
| `move-column-to-workspace-down` / `-up` | `Mod+Ctrl+Page_Down` / `Page_Up`, and `U` / `I` |

The code lives in `src/layout/scrolling.rs` (column shrink, cross, grow, holding the current position across repeated presses, and the lifted offset for cross-workspace moves), `src/layout/monitor.rs` (the start point of a cross-workspace move, and drawing the lifted column above every workspace), `src/layout/tile.rs` (per-window scale), and `src/layout/floating.rs` (the same scale while drawing floating windows).

### Install

Install niri from your distribution first (for example `sudo pacman -S niri` or `sudo dnf install niri`). That brings the login session, portal config, and systemd service. Then run:

```sh
curl -fsSLO https://raw.githubusercontent.com/zelin652-creator/niri-better-action/main/install.sh
bash install.sh
```

The script detects your system, checks that the new build runs on this machine and accepts your current config, then installs it under `/usr/local` and makes login start it. Your distribution's niri is left untouched, and distribution upgrades won't overwrite this build. Log out and back in to use it.

Manage it afterwards with `niri-better`:

| Command | What it does |
| --- | --- |
| `niri-better status` | Show whether login uses this build or the original |
| `niri-better off` / `on` | Use the original from now on / switch back |
| `niri-better once` | Use the original for the next login only |
| `niri-better uninstall` | Restore everything |
| `bash install.sh` | Run again to update to the latest release |

If something goes wrong:

- After 2 failed starts in a row, the next login falls back to the original niri automatically.
- The login screen gets a "Niri（原版）" session that uses the original for that one login.
- If you can't reach a desktop, press `Ctrl+Alt+F3`, log in on the console, and run `niri-better off` or `niri-better uninstall`.

[Release](https://github.com/zelin652-creator/niri-better-action/releases) builds are x86_64, built on Ubuntu 24.04, and need glibc 2.39 or newer: Ubuntu 24.04, Debian 13, Fedora 40, Arch, and later. On other architectures or older systems, build it yourself:

```sh
git clone https://github.com/zelin652-creator/niri-better-action
cd niri-better-action
cargo build --release
bash install.sh --local target/release/niri
```

Building needs Rust 1.85 or newer (use [rustup](https://rustup.rs) if your distribution's is older) and clang. With niri already installed, most libraries are there:

- Arch: `sudo pacman -S --needed base-devel rust clang`
- Fedora: `sudo dnf install cargo gcc clang libudev-devel libgbm-devel libxkbcommon-devel wayland-devel libinput-devel dbus-devel systemd-devel libseat-devel pipewire-devel pango-devel cairo-gobject-devel libdisplay-info-devel`
- Debian / Ubuntu: `sudo apt install gcc clang libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev libwayland-dev libinput-dev libdbus-1-dev libsystemd-dev libseat-dev libpipewire-0.3-dev libpango1.0-dev libdisplay-info-dev`

This tree is based on upstream [v26.04](https://github.com/niri-wm/niri/releases/tag/v26.04). For configuration and usage, see upstream [Getting Started](https://niri-wm.github.io/niri/Getting-Started.html). niri by itself is not a full desktop; it still needs a bar, a launcher, and the rest of a session.

### License and feedback

This repository is [GPL-3.0-or-later](LICENSE), the same as upstream. niri is written by Ivan Molodetskikh. The move animation here is by zelin_cai.

Report animation issues in this repository. Report other compositor behavior to [niri-wm/niri](https://github.com/niri-wm/niri).
