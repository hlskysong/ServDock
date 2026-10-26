# 启服 · ServDock

中文 | [English](README.en.md)

macOS 本地服务与运行时控制台：把 **Homebrew services、launchd / cron、Docker / OrbStack 容器、Bun / fnm / mise 版本管理器、Homebrew 包**收在一个窗口里管，并且提供一套**给脚本和 AI 用的 JSON CLI**。

参考 [FlyEnv](https://github.com/FlyEnvApp/FlyEnv) 的交互思路，用 **SwiftUI + swiftc 直接编译**，不依赖 Xcode 工程、不依赖 SPM 第三方库。

![总览](docs/screenshots/overview.png)

## 进度

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| 1 | Homebrew services（Redis / Nginx / ZooKeeper / MySQL / PG …） | ✅ 完成 |
| 2 | Bun 运行时（版本、缓存、全局工具、安装与升级） | ✅ 完成 |
| 3 | fnm / Node（版本列表、默认切换、安装、卸载、磁盘占用） | ✅ 完成 |
| 4 | MongoDB（含 8.0 / 7.0 线）与 RustFS（brew 无 service，用本地 LaunchAgent 托管） | ✅ 完成 |
| 5 | 系统定时器 / 定时任务（LaunchAgents、LaunchDaemons、cron） | ✅ 完成 |
| 6 | EasyTier 组网（守护进程管控 + 节点 / 路由表格 + 本机网络信息） | ✅ 完成 |
| 7 | Homebrew 包管理（search / install / list / uninstall，formula 与 cask 双轨） | ✅ 完成 |
| 8 | mise 开发环境管理（工具列表、registry 搜索、安装 / 升级 / 卸载版本） | ✅ 完成 |
| 9 | 中英双语界面（可切换、可持久化、CLI `--lang`） | ✅ 完成 |
| 10 | 资源占用（brew 缓存 + 前后台自适应轮询） | ✅ 完成 |
| 11 | Docker / OrbStack 容器管理（容器、镜像、引擎状态） | ✅ 完成 |
| 12 | 面向脚本与 AI 的 JSON CLI（子命令 + 统一信封 + 退出码） | ✅ 完成 |

## 构建与运行

```bash
bash build.sh          # 编译 + 打包 build/ServDock.app（ad-hoc 签名）
open build/ServDock.app
bash run.sh            # 编译并重启
```

环境要求：macOS 14+、CommandLineTools（`xcode-select --install`），无需完整 Xcode。

## 功能

**服务（阶段 1 / 4 / 6）**

- 卡片式总览：运行状态、版本、端口、PID、开机自启、托管方式标记
- 启动 / 停止 / 重启 / 仅本次启动（`brew services run`）
- 端口占用检测：默认端口被别的进程占用时直接标红提示（例：Nginx 的 8080 被 ZooKeeper 的 java 占着）
- 分类浏览：数据库 / Web / 消息与协调 / 搜索与缓存 / **对象存储** / 网络工具 / 其他（MinIO、RustFS 归入对象存储）
- 详情三联：概览（标识、托管方式、版本、PID、plist、数据目录）、日志（tail + 自动刷新 2s）、配置（只读预览）
- 一键安装：23 个常用服务，遇到 Homebrew 7 的「不受信任 tap」会自动 `brew trust` 后重试

**三种托管方式（关键设计）**

| 方式 | 适用 | 启停实现 |
| --- | --- | --- |
| `brew` | Redis / Nginx / MongoDB…（formula 带 `service do`） | `brew services start/stop/restart` |
| `managed` | **RustFS**（brew 只装二进制，没有 service 定义） | 生成 `~/Library/LaunchAgents/local.servdock.<id>.plist` + `launchctl bootstrap/bootout` |
| `external` | **EasyTier**（官方 GUI 自带系统级 LaunchDaemon） | `launchctl bootstrap/bootout system`，走管理员授权弹窗 |

**定时任务（阶段 5）**

- 一个页面看全 launchd 任务：用户代理（`~/Library/LaunchAgents`）、系统代理（`/Library/LaunchAgents`）、系统守护进程（`/Library/LaunchDaemons`）
- 规则翻译成人话：`每天 10:15`、`每周一 08:30`、`每 1 小时`、`常驻（KeepAlive）`、`登录时运行`，日历型规则还给出**下次触发时间**
- 真实运行态：PID、上次退出码、已加载 / 未加载；**系统域也能读**（`launchctl print system/<label>` 非特权可读）
- 操作：加载 / 卸载、立即运行一次（`kickstart`）、启用 / 禁用（`enable` / `disable`，禁用后开机不加载）、看日志（`StandardOutPath`）、在 Finder 显示 plist
- cron：解析 `crontab -l`，展示表达式 + 人话 + 命令，一键在终端 `crontab -e`
- 系统级任务启停需要管理员授权，用 `osascript ... with administrator privileges` 弹系统密码框，取消会提示「已取消管理员授权」

**运行时（阶段 2 / 3）**

- Bun：版本、全局 bin 目录、缓存体积、全局包、PATH 检测、一键升级
- Node：fnm 版本列表 + npm 版本 + 磁盘占用、设为默认（`fnm default`）、安装任意版本（`lts` / `22` / `v20.11.0`）、卸载
- 菜单栏常驻：不打开主窗口也能快速启停服务

**EasyTier 组网（阶段 6）**

- 数据来源是 `easytier-cli -p <rpc> -o json peer|node`，RPC 端口从系统 plist 的 `--rpc-portal` 里读（GUI 守护进程常用 15999，CLI 默认 15888）
- 节点表 10 列对齐：虚拟 IPv4 / 主机名 / 路由（p2p、relay、Local）/ 协议 / 延迟 / 上传 / 下载 / 丢包 / NAT 类型 / 版本，斑马纹 + 右键复制 IP、主机名
- 本机信息：虚拟 IP、主机名、NAT 类型、网络名、公网 IP、节点数、RPC 端口，以及 listeners、配置目录
- 运行态判断：进程表命中 **或** RPC 已连上（GUI 守护进程不在 `launchctl list` 里，只看进程表会误判「未运行」）
- 缺 `easytier-cli` 时页面直接给「下载 CLI」：GitHub release 取 zip 解到 `~/Library/Application Support/ServDock/bin`，不写系统路径

**Homebrew 包（阶段 7）**

- 搜索 / 已安装两个 tab，formula 与 cask 双轨切换
- 已安装来自 `brew list --formula` / `--cask`；搜索结果用 `brew search` + `brew info --json=v2` 补全版本、摘要、主页
- 安装 / 卸载直接跑 brew，遇到 Homebrew 7 的「不受信任 tap」自动 `brew trust` 后重试；行内可跳到终端看 `brew info`

**mise（阶段 8）**

- 概览：版本、已管理工具数、shell 激活状态、登录 shell（未激活时给可照抄的引导卡）
- 工具表：名称、版本、已下载 / 生效状态，支持升级与卸载
- 安装工具：搜索 registry、常用工具快捷 chip、版本选择弹窗（`mise ls-remote` 列表 + 手填版本）
- 动作：`mise use -g`、`mise uninstall`、`mise upgrade`、`mise self-update`、写入 shell 激活配置

**mise 激活状态怎么判（重要）**

`mise doctor` 的 `activated:` 只反映**当前进程**的环境变量。GUI App 不是从登录 shell 启动的，永远是 `no`，
拿它当判据会一直误报「未激活」。真正的判据是 **shell 启动配置文件里有没有 `mise activate`**：

| shell | 检查的文件 |
| --- | --- |
| fish | `~/.config/fish/config.fish` + `~/.config/fish/conf.d/*.fish` |
| zsh | `~/.zshrc`、`~/.zprofile`、`~/.zshenv` |
| bash | `~/.bashrc`、`~/.bash_profile`、`~/.profile` |

登录 shell 用 `getpwuid` 取（GUI 进程的 `$SHELL` 常是系统默认值）。

另外 `mise activate` **只是把脚本打印到 stdout**，直接敲等于「看了一眼」，必须交给 shell 执行：

```bash
mise activate fish | source          # fish
eval "$(mise activate zsh)"          # zsh
eval "$(mise activate bash)"         # bash
```

页内「写入 fish 配置」按钮会把上面这行追加到对应配置文件（幂等，已存在则不重复写），
命令行也可 `ServDock --mise-activate fish` 走同一条代码路径。

新版 mise 用 activate 直接注入 PATH，**不再依赖 `~/.local/share/mise/shims`**，
所以该目录不存在属正常，不作为「未激活」的依据。

**Docker / OrbStack（阶段 11）**

- 引擎状态卡：docker CLI 路径、引擎类型（OrbStack / Docker Desktop / Colima / Rancher 自动识别）、Server 版本、容器与镜像计数、镜像占用与可回收空间
- **引擎没起来时给的是能点的按钮**：检测到 OrbStack 就显示「启动 OrbStack」（`orb start`），否则提示启动 Docker Desktop / colima；同时把 `docker` 的原始报错折叠成 3 行，方便判断是 socket 没起还是权限问题
- 容器表：名称 / 镜像 / 状态 / 端口 / 运行时长，运行态用色点区分；端口 `0.0.0.0:6379->6379/tcp` 归一成 `6379→6379`
- 操作：启动 / 停止 / 重启 / 删除 / 看日志（`docker logs --tail 200`，可复制全部），右键复制名称、ID、端口
- 镜像 tab：`repo:tag`、大小、创建时间、短 ID，顶部带 `docker system df` 的镜像占用
- 已停止容器的状态显示成 `Exited (0)` 而不是被省略号截断的 `Exited (0) 2 minutes...`

**AI 友好的 CLI（阶段 12）**

给脚本 / AI 用的一套子命令，设计上的四条硬约定：

1. **所有查询都支持 `--json`**，统一信封：`{ok, schema, tool, version, command, data}`，失败时是 `{ok: false, error: {code, message}}`
2. **字段名稳定**：小写下划线，状态用枚举字面量（`started` / `stopped` / `running` / `exited`），不放中文
3. **退出码**：`0` 成功 / `1` 执行失败 / `2` 用法错误
4. **`help --json` 输出机器可读的命令清单**，工具可以自发现，不用猜

动作类命令（启停、容器操作、定时任务）执行完会**回读真实状态**再输出，不只报「已发送」。

**多语言（阶段 9）**

- 三处切换：侧栏底部徽标、设置页语言卡片、`⌘⇧L` 一键切英文；写 `UserDefaults`（`servdock.language`）
- 词条以**中文原文为 key**，英文表缺词时回落中文；`%@` / `%d` 占位走 `String(format:)`
- 通用组件（PillButton / IconButton / KeyValueRow / TagChip / EmptyStateView / SearchField / InfoTile…）内部自动翻译，调用点只写中文

**资源占用（阶段 10）**

- **brew 结果缓存**：`brew --version` 与 `brew list --versions` 缓存 60 秒，安装 / 卸载 / 升级后主动失效 → 每轮子进程从 6 个降到 4 个
- **自适应轮询**：应用在前台且主窗口可见时 4 秒；窗口关掉 / 最小化 / 应用失焦时降到 30 秒，回到前台立刻恢复（不靠定时器轮询开关状态，用 `didBecomeActive` / 窗口显隐通知唤醒）
- **按需探测**：定时任务、EasyTier、mise、Homebrew 包列表都只在进入对应页面或手动刷新时才跑，不参与轮询
- 实测（`--bench`）：单轮采集子进程 **6 → 4 个**、墙钟 **940 ms → 532 ms**；其中 `brew list --versions` 单项就从 332 ms 降到 0 ms

## 界面

| 定时任务 | cron 定时任务 |
| --- | --- |
| ![定时任务](docs/screenshots/timers.png) | ![cron](docs/screenshots/cron.png) |

| 服务详情 · 概览 | 服务详情 · 日志 |
| --- | --- |
| ![详情](docs/screenshots/detail.png) | ![日志](docs/screenshots/logs.png) |

| Bun | Node.js（fnm） |
| --- | --- |
| ![Bun](docs/screenshots/bun.png) | ![Node](docs/screenshots/node.png) |

| EasyTier 组网 | Homebrew 包 |
| --- | --- |
| ![EasyTier](docs/screenshots/easytier.png) | ![Homebrew 包](docs/screenshots/packages.png) |

| mise | 对象存储 |
| --- | --- |
| ![mise](docs/screenshots/mise.png) | ![对象存储](docs/screenshots/storage.png) |

| Docker 容器 | Docker 镜像 |
| --- | --- |
| ![Docker](docs/screenshots/docker.png) | ![镜像](docs/screenshots/docker-images.png) |

| 设置 · 语言 | 英文界面 |
| --- | --- |
| ![设置](docs/screenshots/settings.png) | ![English](docs/screenshots/english.png) |

深色模式：

![深色](docs/screenshots/dark.png)

## 代码结构

```
Sources/
  App.swift                  # 入口、窗口、菜单栏、离屏截图
  Models/
    ServiceSpec.swift        # 服务清单（23 个）+ 分类 + 三种托管方式 + 路径工具
    ServiceItem.swift        # 静态描述 + 实时状态合并体
    TimerItem.swift          # launchd 任务 / cron 条目 / 触发规则翻译 + 下次触发时间
  Core/
    Shell.swift              # Process 执行器（自己拼 PATH、超时、临时文件收输出）
    SystemProbe.swift        # brew services --json / brew list --versions / launchctl / lsof / ps
    BrewCache.swift          # brew --version 与 brew list --versions 的 60s 缓存（安装卸载后失效）
    Launchctl.swift          # launchctl 封装：用户域、系统域提权、生成 LaunchAgent
    TimerProbe.swift         # 扫 plist + crontab + launchctl print 取系统域状态
    RuntimeProbe.swift       # Bun 与 fnm 探测
    EasyTierProbe.swift      # easytier-cli 解析 peer / node JSON、RPC 端口探测、CLI 自下载
    BrewCatalog.swift        # brew search / info --json=v2 / 已安装枚举 / 安装卸载（含 tap 信任重试）
    MiseProbe.swift          # mise doctor / ls --json / registry 搜索 / 安装升级卸载 / shell 激活检测
    DockerProbe.swift        # docker CLI 定位、引擎探测、容器 / 镜像 / df 解析、容器与 OrbStack 动作
    LogLocator.swift         # 日志定位与 tail / 配置读取
    AppModel.swift           # 状态机：自适应轮询（前台 4s / 后台 30s），90s 缓存运行时
    AppModel+Actions.swift   # 启停（按托管方式分流）、安装、Bun 升级、Node 版本操作
    AppModel+Timers.swift    # 定时任务加载与动作
    AppModel+Tools.swift     # EasyTier / Homebrew 包 / mise / Docker / 语言切换
    CLIRunner.swift          # CLI 子命令（list/status/start/logs/containers/timer/runtime/doctor + --json）
    ProbeRunner.swift        # CLI: --probe
    BenchRunner.swift        # CLI: --bench（采集耗时 / 轮询间隔自检）
    ActionRunner.swift       # CLI: --action
  Support/
    Brand.swift              # 品牌名 / bundle id / 数据目录 / 老包名（ServiceDock）兼容迁移
    L10n.swift               # 语言枚举 + L.t 查表（中文为 key）
    L10nDictionary.swift     # 480+ 条中英词条
    Summarize.swift          # 输出首行 / 错误摘要
  Views/                     # 侧边栏、总览、卡片、详情、定时任务、Docker、EasyTier、Homebrew 包、mise、设置、运行时页、组件
Tools/make-icon.swift        # 生成 AppIcon.icns
```

## 命令行

### 子命令（给脚本 / AI 用）

```bash
BIN=build/ServDock.app/Contents/MacOS/ServDock

$BIN list                                  # 服务列表（表格）
$BIN list --json                           # 机器可读
$BIN list --installed --running            # 只看已装且运行中
$BIN status redis --json                   # 单个服务全部字段
$BIN start redis / stop redis / restart redis
$BIN run redis                             # 仅本次启动，不设开机自启
$BIN logs redis --lines 50

$BIN containers                            # 容器列表（默认含已停止）
$BIN containers --running --json
$BIN container stop my-redis --json        # start|stop|restart|rm|logs
$BIN container logs my-redis --lines 100
$BIN images
$BIN docker-status --json                  # 引擎 / OrbStack 状态

$BIN timers --json
$BIN timer run com.example.job             # run|load|unload|enable|disable
$BIN runtime --json                        # bun / node / mise 概览
$BIN doctor --json                         # 环境体检
$BIN help --json                           # 命令清单（给 AI 自发现）
```

JSON 输出长这样：

```json
{
  "ok": true,
  "schema": 1,
  "tool": "ServDock",
  "version": "0.2.0",
  "command": "container",
  "data": {
    "name": "my-redis",
    "verb": "stop",
    "previous_state": "running",
    "state": "exited",
    "running": false
  }
}
```

失败时：`{"ok": false, "error": {"code": "not_found", "message": "未知服务：foo"}}`，退出码 `1`。

`code` 取值：`bad_usage` / `not_found` / `not_installed` / `action_failed` / `engine_down` / `cli_missing` / `no_log`。

### 开发与自检参数

```bash
$BIN --probe                                      # 打印所有探测结果（brew / 端口 / PID / 定时任务 / bun / node）
$BIN --bench                                      # 自检：每轮子进程数 / 墙钟耗时（缓存冷热对比）、轮询间隔规则、唤醒链路
$BIN --snapshot out.png [--select bun] [--dark]   # 离屏渲染界面，用于自检与文档
$BIN --snapshot out.png --lang en                 # 出英文界面截图
$BIN --snapshot out.png --select easytier --redact # 脱敏截图：主机名 / 网络名 / 公网 IP / 虚拟 IP 全换占位值
$BIN --action start rustfs [--out result.txt]     # 走界面同一条代码路径执行动作
$BIN --mise-activate [fish|zsh|bash]              # 把 mise activate 写进 shell 配置（幂等，默认取登录 shell）
```

`--select` 可选：`overview`（默认）/ `detail` / `logs` / `config` / `category` / `storage` / `timers` / `cron` / `bun` / `node` / `easytier` / `packages` / `packages-installed` / `mise` / `docker` / `docker-images` / `settings`。

## 踩过的坑（已处理）

1. **brew 退出码不可靠**：`brew list --versions` 在有不受信任 tap（如 `roversx/tap`）时报 `Error:` 并 **exit 1**，但 stdout 里 67 行数据完全可用。所有解析都改成「有输出就解析」，不再用 `ok` 做门禁。
2. **brew 7 的 launchd label 变了**：服务 label 从 `homebrew.mxcl.<formula>` 变成 `sh.brew.<formula>`，plist 也从 `~/Library/LaunchAgents/homebrew.mxcl.*.plist` 变为 `sh.brew.*.plist`。两种前缀都兼容（本机两个都真实存在）。
3. **lsof 要显式要字段**：`lsof -Fpc` 拿不到端口，必须 `-Fpcn`；端口是 `n` 字段。
4. **GUI App 没有登录 shell 的 PATH**：`Process` 启动 brew / launchctl 前必须自己拼 `PATH`（含 `/opt/homebrew/bin`、`~/.bun/bin`）。
5. **JVM 服务没有自己的进程名**：ZooKeeper / Kafka / ES 的进程都叫 `java`，只能靠「默认端口 + java」辅助归属 PID。
6. **`pgrep -f` 在这台机器上会返回无关 PID**（沙箱干扰），已从主链路移除；PID 走 `launchctl` → `lsof` 命令名 → 端口归属 → `ps` 进程表四级解析。
7. **RustFS 的 formula 没有 `service do` 块**：`brew services` 完全不认它（官方也说明只装二进制）。所以必须自己写 LaunchAgent，`managed` 这一层就是为它加的。
8. **`rustfs server --console-enable` 是布尔开关，不能跟 `true`**：多写一个 `true` 会被 clap 当成 VOLUMES 位置参数，启动即失败。
9. **Homebrew 7 的 tap 信任**：`brew install rustfs/homebrew-tap/rustfs` 会先拒绝加载（`Refusing to load formula … from untrusted tap`），要 `brew trust <tap>`；安装流程里已自动识别报错并信任后重试。
10. **系统域状态其实读得到**：`launchctl print system/<label>` 普通用户就能拿到 `state = running` / `pid` / `last exit code`，不必 sudo；`launchctl print-disabled system` 同样可读，用来做「已禁用」标记。
11. **`launchctl list` 只列当前用户域**：系统守护进程（如 `easytier-gui`）不会出现在里面，必须走 `launchctl print system/*` 或 `ps` 兜底。
12. **Bash 工具沙箱内 `launchctl` / `ps` / `crontab` 都被禁**：`open --args` 传参也会被吞。验证真实链路要用「临时 .app 经 LaunchServices 启动，再由它调用被测程序」的办法；应用本身在真实会话里是正常的。
13. **`easytier-cli` 的全局参数必须放在子命令之前**：正确的写法是 `easytier-cli -p 15999 -o json peer`；写成 `peer -o json` 会报 `unexpected argument '-o'`，拿不到任何 JSON。
14. **EasyTier 运行态不能只看进程表**：GUI 守护进程是系统域 LaunchDaemon，`launchctl list` 里没有它，受限环境下 `ps` 也可能读不到，会误报「未运行」但节点表却有数据。判断条件改成「进程表命中 **或** RPC 已连上」。
15. **本地化字典里重复 key 会让程序一启动就崩**：Swift 的字典字面量在首次初始化时去重冲突会直接 `EXC_BREAKPOINT / SIGTRAP`（栈指向 `one-time initialization function for en`），426 条里重复 1 条就挂。改词条后要查重。
16. **`.disabled(true)` 会再叠一层自动调暗**：自定义禁用配色（白底 + 描边 + 灰字）被这层调暗压得几乎看不见，改用 `.allowsHitTesting(false)` 才能真正控制渲染。
17. **`--snapshot` 直接写仓库目录会被沙箱拦**（`sandbox-center … missing actual resource subject`）：先输出到 `/tmp` 再 `cp` 回 `docs/screenshots/`。
18. **`MenuBarExtra` 里遍历 `NSApp.windows` 打不开已关闭的窗口**：SwiftUI 的 `WindowGroup` 窗口关掉即销毁，循环必然是空转（表现就是「点菜单栏→打开主窗口」没反应，Dock 图标却正常）。正解是 `openWindow(id: "main")` 让它重建，再在下一个 runloop 里 `activate` + `makeKeyAndOrderFront`。
19. **`@MainActor` 类的 `static let` 不能在 `nonisolated` 上下文引用**（Swift 6 直接报错）：轮询间隔常量要写成 `nonisolated static let`，纯函数才能被 `--bench` 这类非隔离代码调用。
20. **`brew list --versions` 单项就要 300+ ms**：它每次 fork 一个 ruby，每 4 秒跑一次等于一天几万次进程创建。这类「内容几乎不变」的探测必须缓存（见 `BrewCache`），且要在安装 / 卸载后主动失效，否则版本号会滞后。
21. **`NSApp` 在没起过 App 的进程里是 nil**：`--bench` 这类 CLI 分支读 `NSApp.isActive` 会因隐式解包直接 `SIGTRAP`（崩溃栈指向 `AppModel.waitForNextTick()`，很容易误判成并发问题）。统一改用 `NSApplication.shared`。
22. **`mise doctor` 的 `activated:` 不能当「用户有没有激活」的判据**：它只读当前进程的环境变量。GUI App 不是从登录 shell 起的，恒为 `no`；而 `shims_on_path: no` 在新版 mise 里也正常（activate 直接注入 PATH，不再用 shims）。判据得回到 shell 启动文件里 grep `mise activate`。
23. **`mise activate` 不执行、只打印**：直接敲会输出一屏 `set -gx` / `function ...`，看起来像报错。fish 要 `mise activate fish | source`，zsh / bash 要 `eval "$(mise activate ...)"`。
24. **改名会打断已经在跑的 managed 服务**：`local.servicedock.*` 的 LaunchAgent 已经在系统里注册，直接把前缀改成 `local.servdock.*` 会让老 plist「消失」。处理方式是**以磁盘上实际存在的 plist 为准**选前缀，新旧都兼容，不强行迁移；数据目录与 UserDefaults key 同理，启动时做一次性合并（不覆盖新数据）。
25. **`docker ps --format '{{json .}}'` 的 `Ports` 是长串**：`0.0.0.0:6379->6379/tcp, [::]:6379->6379/tcp`，直接显示会把表格撑爆，也重复（v4 / v6 各一条）。要按 `->` 拆出 host/guest 端口并去重。
26. **容器已停止时的 `Status` 是 `Exited (0) 2 minutes ago`**：列宽不够就被省略号吃掉关键信息。状态列只取 `Exited (0)` 这一段，运行中的 `Up 2 minutes` 才保留。
27. **引擎没起来时 `docker` 会卡几秒才报错**：探测超时要给短（12s），否则 UI 像卡死；同时把 socket 路径的报错折叠展示，能直接判断是「没启动」还是「权限不对」。
28. **CLI 的 `Never` 返回函数让分支提前收敛**：`emit()` / `fail()` 声明成 `-> Never`（内部 `exit()`），`guard ... else { fail(...) }` 就能直接通过编译，不用写无意义的 `return`——但要注意 `if json { emit(...) }` 之后的代码编译器知道「永远到不了」，别在里面放真正需要的逻辑。

## 已知限制

- 配置文件只读预览，不内置编辑器（避免误改导致服务起不来）
- 定时任务目前只能管理已有任务，还不能在界面里新建 launchd / cron 任务（cron 走「编辑 crontab」跳终端）
- `managed` 服务的「开机自启」等价于「LaunchAgent plist 存在」，没有单独的开关项
- 同一 formula 的多版本并存（如 `mysql@8.4` 与 `mysql` 同时跑）未做端口隔离
- Docker 只做容器 / 镜像的查看与启停删，不做 compose 编排、网络 / 卷管理、镜像拉取与 `system prune`
- CLI 的 JSON schema 目前是 v1，字段新增向后兼容，破坏性变更会递增 `schema`
- mise 的 shell 激活会改用户 shell 配置：界面给可照抄的命令与「写入配置」按钮（幂等追加），也支持 `--mise-activate`，但写的是用户自己的文件，首次使用建议先备份
- 多语言只做中英两种，词条以中文原文为 key；新增文案要同步补 `L10nDictionary.swift`（缺词回落中文，不会崩）
- Homebrew 包页只做 search / install / uninstall 与已安装列表，不做 `brew upgrade` 批量升级
- 图标与界面按浅色为主设计，深色模式已适配但未做逐像素打磨
