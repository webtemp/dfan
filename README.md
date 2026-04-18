# dfan

A lightweight CPU fan controller daemon for Linux. Reads temperature from the **k10temp** kernel module and drives fan PWM channels through the **nct6687** chip, with a configurable curve, live tuning, and clean systemd integration.

---

## Features

- **Five curve shapes** — linear, quadratic, cubic, sqrt, sigmoid (smoothstep)
- **Live tuning** — adjust temperature thresholds and curve shape at runtime, no restart needed
- **Fan modes** — force fans off, full speed, or back to auto from the command line
- **Hysteresis** — 2 °C dead-band prevents fan flutter at threshold boundaries
- **Clean shutdown** — restores hardware AUTO mode on exit
- **Minimal logging** — one line per fan speed change, heartbeat every 60 s

---

## Requirements

| Component | Details |
|-----------|---------|
| CPU sensor | `k10temp` kernel module (AMD Ryzen / EPYC) |
| Fan controller | `nct6687` chip via `nct6687d` kernel module |
| Init system | systemd |
| Shell | bash 4.0+ |

---

## Installation

```bash
git clone https://github.com/webtemp/dfan.git dfan
cd dfan
sudo ./install.sh
```

The installer will:

1. Symlink `src/dfan` and `src/dfanctl` into `/usr/local/sbin/`
2. Install and enable the systemd service
3. Create `/run/dfan/` (world-writable tmpfs dir) via `tmpfiles.d`
4. Install a polkit rule so `dfanctl` works without `sudo`

## Uninstallation

```bash
sudo ./uninstall.sh
```

Stops the service, removes all installed files, and returns fans to hardware AUTO mode.

---

## Project Structure

```
dfan/
├── src/
│   ├── dfan            # daemon script
│   ├── dfanctl         # control tool
│   └── dfan-tray       # system tray icon (PyQt6)
├── systemd/
│   ├── dfan.service        # system daemon unit
│   └── dfan-tray.service   # user-level tray unit
├── polkit/
│   └── dfan.rules      # polkit rule (dfanctl without sudo)
├── tmpfiles/
│   └── dfan.conf       # /run/dfan runtime dir
├── install.sh
├── uninstall.sh
└── README.md
```

## Usage

```bash
dfanctl --help
```

### Adjust temperature thresholds

```bash
dfanctl low 50     # fans start ramping at 50 °C
dfanctl hi  75     # fans hit full speed at 75 °C
```

Takes effect immediately via signal — no cycle delay.

### Change fan curve

```bash
dfanctl curve sigmoid
dfanctl curve sqrt
dfanctl curve linear
```

Takes effect within 5 seconds (next daemon cycle).

### Fan modes

```bash
dfanctl off        # force all fans OFF (0 PWM)
dfanctl full       # force all fans to 100%
dfanctl auto       # return to temperature-driven curve
```

---

## Fan Curves

All curves share the same endpoints (`FAN_T_LO` → 0%, `FAN_T_HI` → 100%). They differ in how aggressively fans ramp through the middle range.

| Temp (°C) | linear | quadratic | cubic | **sqrt** | sigmoid |
|:---------:|:------:|:---------:|:-----:|:--------:|:-------:|
| 50        |  0%    |  0%       |  0%   |  0%      |  0%     |
| 55        | 20%    |  4%       |  1%   | 45%      | 16%     |
| 60        | 40%    | 16%       |  6%   | 63%      | 50%     |
| 65        | 60%    | 36%       | 22%   | 77%      | 68%     |
| 70        | 80%    | 64%       | 51%   | 89%      | 97%     |
| 75        | 100%   | 100%      | 100%  | 100%     | 100%    |

```
100% ┤                                         ╭─── linear
     │                                    ╭────╯
 75% ┤                          ╭─────────╯         sqrt
     │                    ╭─────╯
 50% ┤              ╭─────╯                       sigmoid
     │         ╭────╯
 25% ┤    ╭────╯                               quadratic
     │╭───╯
  0% ┼─────────────────────────────────────────────────▶
    50°C  55°C  60°C  65°C  70°C  75°C
```

- **sqrt** — spins up quickly, good for reactive cooling
- **sigmoid** — smooth S-curve, gentle at both ends, natural feeling *(default)*
- **quadratic / cubic** — whisper-quiet until the upper range, then aggressive

---

## Monitoring

```bash
# Live log output
journalctl -fu dfan

# Current service status
systemctl status dfan
```

Example log output:

```
14:03:12  CPU 55°C → setting fans to 45%
14:04:12  CPU 55°C — fans steady at 45%
14:05:33  curve → sigmoid
14:07:41  SIGUSR1 — FAN_T_LO → 45°C (ramp now 45–75°C)
14:08:00  mode → full — fans forced to 100%
14:08:10  mode → auto
```

---

## Configuration

Default values live at the top of `src/dfan`. The most commonly tuned parameters:

| Variable | Default | Description |
|----------|---------|-------------|
| `FAN_T_LO` | `50` | °C where ramp begins |
| `FAN_T_HI` | `75` | °C where fans hit full speed |
| `FAN_CURVE` | `sqrt` | Curve shape |
| `FAN_PWM_MAX` | `230` | PWM cap (~90% — hardware protection) |
| `FAN_HYST` | `2` | °C dead-band to prevent flutter |
| `INTERVAL` | `5` | Seconds between cycles |

These can also be changed at runtime with `dfanctl` without editing the file.

---

## How It Works

1. On start, the daemon locates `k10temp` and `nct6687` dynamically via `/sys/class/hwmon/hwmon*/name` — no hardcoded paths
2. Every 5 seconds it reads the CPU temperature and maps it through the configured curve to a PWM value
3. It only writes to sysfs when the target PWM actually changes (hysteresis prevents thrashing)
4. `SIGUSR1` / `SIGUSR2` update `FAN_T_LO` / `FAN_T_HI` live; curve and mode changes are picked up by polling `/run/dfan/`
5. On exit (shutdown, SIGTERM, Ctrl-C), all fan channels are restored to hardware AUTO mode

---

## System tray (optional)

A PyQt6 tray icon is installed alongside the daemon. It shows current
fan % inside a colour-coded ring (green/yellow/orange/red by CPU temp,
blue when forced off, red when forced full) and a tooltip with full
stats. Right-click menu lets you switch mode or curve without opening
a terminal.

```bash
sudo pacman -S python-pyqt6                       # or your distro's equivalent
systemctl --user start dfan-tray                  # run now
systemctl --user enable dfan-tray                 # auto-start on login (default)
systemctl --user status dfan-tray                 # check it
journalctl --user -u dfan-tray -f                 # tail logs
```

The tray runs as a **user** systemd service, not system-wide — logs are
per-user and it starts when your graphical session does.

---

## License

MIT © [webtemp](https://github.com/webtemp)
