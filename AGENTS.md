# 项目经验记录

## Project Skills

- `ptyxis-fleet-release`
  - Path: `.codex/skills/ptyxis-fleet-release/SKILL.md`
  - Use for: building and testing x86_64 releases on AI, dispatching native
    ARM64 GitHub builds, publishing release assets, installing Ptyxis across
    the x86/Jetson fleet, configuring VPN-assisted Flatpak downloads, and
    verifying versions and GUI startup.
  - Trigger examples: “编译 Ptyxis release”, “发布 ARM Flatpak”, “安装到
    edge/nx/nano”, “参考 skill 更新所有设备”.

## 经验：Ptyxis / SSH 远端路径 title 的正确做法

目标：在 MI 上使用 Ptyxis 时，`ssh AI` 登录远端后，窗口 subtitle 能显示远端设备名和当前路径，例如：

```text
ai-X10DRG: /home/ai
ai-X10DRG: /tmp
```

关键结论：
- 不要在 Ptyxis 或本地 shell 里覆盖/包装 `ssh` 命令。包装 `ssh` 很容易破坏用户现有别名、大小写 Host、参数、ProxyCommand、端口转发和交互行为。
- 终端模拟器无法单方面知道远端当前目录。进入 SSH 后，subtitle/title 是否能变化，取决于远端 shell 是否主动发送 OSC title 序列。
- 正确做法是在远端账号的 shell 启动文件里加 title hook，让提示符刷新时发送 `ESC ] 0 ; user@host:pwd BEL`。
- 如果远端默认登录 shell 是 bash，但裸 `ssh HOST` 后没有加载 `.bashrc`，需要补 `~/.bash_profile` 或 `.profile`，让登录 bash source `.bashrc`。

AI 设备上已经验证可用的配置：

`/home/ai/.bashrc` 末尾加入：

```bash
# >>> ptyxis title integration >>>
__ptyxis_prompt_command() {
  case "${TERM:-}" in
    xterm*|vte*|rxvt*|screen*|tmux*)
      printf '\033]0;%s@%s:%s\007' "${USER:-$(id -un)}" "${HOSTNAME:-$(hostname)}" "$PWD"
      ;;
  esac
}

case ";${PROMPT_COMMAND:-};" in
  *";__ptyxis_prompt_command;"*) ;;
  *) PROMPT_COMMAND="__ptyxis_prompt_command${PROMPT_COMMAND:+;$PROMPT_COMMAND}" ;;
esac
# <<< ptyxis title integration <<<
```

如果远端没有 `~/.bash_profile`，创建：

```bash
# ptyxis/login shell bootstrap
if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
```

验证命令（在 MI 上执行）：

```bash
python3 - <<'PY'
import subprocess, os, time, re

cmd = ["ssh", "-tt", "AI"]
env = dict(os.environ, TERM="xterm-256color")

p = subprocess.Popen(cmd, env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
time.sleep(2)
p.stdin.write(b"cd /tmp\n")
p.stdin.flush()
time.sleep(2)
p.stdin.write(b"exit\n")
p.stdin.flush()

out, _ = p.communicate(timeout=15)
for title in re.findall(rb"\x1b\]0;([^\x07]+)\x07", out):
    print(title.decode("utf-8", "replace"))
PY
```

期望输出类似：

```text
ai@ai-X10DRG:/home/ai
ai@ai-X10DRG:/tmp
```

Ptyxis 真实窗口验证命令（在 MI 图形会话里执行）：

```bash
pkill -x ptyxis || true

export XDG_RUNTIME_DIR=/run/user/1000
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus
export DISPLAY=:0
export WAYLAND_DISPLAY=wayland-0

/usr/bin/ptyxis -s -- bash -lc "ssh -tt AI"
```

注意事项：
- 修改 `.bashrc` 后，已经打开的 SSH session 不会生效；需要退出后重新 `ssh AI`。
- 若 `ssh AI` 不命中配置，先用 `ssh -G AI | grep -E '^(hostname|user) '` 检查 Host 大小写和 `~/.ssh/config`。
- 对机器配置动手前先备份，例如 `cp ~/.bashrc ~/.bashrc.bak-ptyxis-title-$(date +%Y%m%d%H%M%S)`。
