# Bantu File-System & Power Demo

A small Bantu v1.3.0 web app that demonstrates **two things**:

1. **File-system operations** — list / create / read / delete files, all from pure Bantu using its v1.3.0 file-I/O builtins and FFI to `libc.so.6`.
2. **Low-level power control** — shutdown / restart / sleep / hibernate the host. Inside Docker or Render the action is *simulated*; on bare metal it runs the real OS command (`shutdown -h now`, `systemctl suspend`, etc.).

Packaged with a multi-stage Dockerfile and a Render Blueprint so you can run it locally, then deploy to Render with one click.

---

## Quick start (local, no Docker)

You need the Bantu v1.3.0 binary on your `PATH`. (Either download it from the [v1.3.0 release](https://github.com/AsseySilivestir/Bantu/releases/tag/v1.3.0) or build it from source.)

```bash
cd bantu-fs-power-demo
bantu run server.b
# → http://localhost:8080
```

## With Docker

```bash
cd bantu-fs-power-demo
docker compose up --build
# → http://localhost:8080
```

The first build takes ~3-5 minutes (compiles the Bantu interpreter from source inside Ubuntu 22.04). Subsequent builds are cached.

## Deploy to Render

1. Push this folder to a GitHub repo.
2. In Render → **New → Blueprint** → pick the repo.
3. Render will detect `render.yaml` and create a web service on the free plan.
4. Wait for the build, then click the `*.onrender.com` URL.

A persistent disk is mounted at `/app/workspace`, so files you create in the demo survive redeploys.

---

## What the demo shows

### File-system operations

| Endpoint | Method | Description |
|---|---|---|
| `/api/files` | GET | List files in the workspace (`ls -la` parsed) |
| `/api/files` | POST | Create / overwrite a file (uses Bantu's `writefile`) |
| `/api/files/:name` | GET | Read a file (uses Bantu's `readfile`) |
| `/api/files/:name` | DELETE | Delete a file (uses **FFI → `libc.unlink()`** — a real syscall) |
| `/api/files/:name/stat` | GET | File metadata (`stat`) |

**The interesting part:** Bantu v1.3.0 ships `writefile` / `readfile` / `open` / `appendfile` as native builtins, but it does *not* ship a file-delete builtin. The demo shows how to fill that gap with the FFI:

```bantu
$libc     = loadlib("libc.so.6");
$unlink   = func($libc, "unlink", "int", ["string"]);
$rc       = $unlink("/app/workspace/file.txt");   # → 0 on success
```

That's a real `unlink(2)` syscall, invoked through `libffi` — Bantu calls straight into libc without going through `system("rm …")`.

### Low-level power control

| Action | Linux command | macOS command |
|---|---|---|
| Shutdown | `shutdown -h now` | `shutdown -h now` |
| Restart | `shutdown -r now` | `shutdown -r now` |
| Sleep | `systemctl suspend` | `pmset sleepnow` |
| Hibernate | `systemctl hibernate` | `pmset hibernatenow` |

**Inside Docker / Render:** the action is *simulated*. We detect `/.dockerenv` or containerd cgroup markers, log the intent, and return what *would* have run. (A container can't power off its host anyway.)

**On bare metal:** the actual OS command runs. This requires the `bantu` process to have permission to call `shutdown` — usually you need to either:
- run bantu as `root` (not recommended in production), or
- put the bantu user in the `shutdown` group: `usermod -aG shutdown bantu`, or
- allow it via `sudo` without a password: `echo "bantu ALL=(ALL) NOPASSWD: /sbin/shutdown" >> /etc/sudoers.d/bantu`

Every power action — simulated or real — is appended to `workspace/.power.log`, viewable in the UI.

### System info

`GET /api/sysinfo` exposes low-level host details by reading from `/proc`, `uname`, `uptime`, etc. — proving the Bantu process can introspect the machine it runs on.

---

## Project layout

```
bantu-fs-power-demo/
├── server.b                # Bantu backend — all endpoints live here
├── public/
│   ├── index.html          # Single-page UI (vanilla HTML)
│   ├── style.css            # Dark theme, GitHub-flavored
│   └── app.js              # Frontend logic (fetch + render, no framework)
├── lib/                    # Bantu standard library modules
│   ├── hash/                #   (not used by the demo, but bundled so
│   ├── crypto/              #    your own Bantu app can `include` them)
│   ├── uuid/
│   ├── random/
│   └── orm/
├── bantu-src/compiler/     # Bantu interpreter source (needed by Docker build)
├── Dockerfile              # Multi-stage: build bantu → run server.b
├── docker-compose.yml       # Local dev: `docker compose up`
├── render.yaml              # Render Blueprint (one-click deploy)
├── .dockerignore
└── README.md
```

---

## How it works (under the hood)

```
  ┌─────────────────────────────────────────────────────┐
  │                    Browser (you)                     │
  │  http://localhost:8080  /  *.onrender.com           │
  └────────────────────────┬────────────────────────────┘
                           │ HTTP (fetch)
                           ▼
  ┌─────────────────────────────────────────────────────┐
  │              Bantu v1.3.0 (Sua HTTP)                │
  │  server.b  ←  sua.server.get/post/delete/static      │
  └──────┬──────────────┬─────────────────┬─────────────┘
         │              │                 │
         ▼              ▼                 ▼
   writefile()      readfile()        loadlib("libc.so.6")
   readfile()       sh("ls …")        func(lib, "unlink", …)
   (builtins)       (FFI → system())  func(lib, "system", …)
         │              │                 │
         ▼              ▼                 ▼
  ┌─────────────────────────────────────────────────────┐
  │                Linux kernel (host)                   │
  │  open(2)  read(2)  write(2)  unlink(2)  stat(2)       │
  └─────────────────────────────────────────────────────┘
```

---

## Endpoints (full list)

| Method | Path | Description |
|---|---|---|
| GET | `/api/health` | Health check + version + hostname + platform |
| GET | `/api/sysinfo` | `uname`, `uptime`, `/proc/loadavg`, `/proc/meminfo`, `df` |
| GET | `/api/files` | List files in `workspace/` |
| POST | `/api/files` | `{name, content}` → create/overwrite |
| GET | `/api/files/:name` | Read file contents |
| DELETE | `/api/files/:name` | Delete via `libc.unlink()` |
| GET | `/api/files/:name/stat` | File metadata |
| POST | `/api/power` | `{action: shutdown\|restart\|sleep\|hibernate}` |
| GET | `/api/power/log` | Audit log of all power actions |

The web UI at `/` calls all of these — open the browser tab and click around.

---

## Security notes

- **Path traversal is blocked:** file `name` is rejected if it contains `/` or `..`.
- **Power actions are simulated in containers:** no way to accidentally kill the host.
- **On bare metal** the power commands *do* run — make sure only authorized users can reach the demo. (It is *not* meant to be internet-exposed without auth.)
- The workspace is world-writable inside the container so the bantu process can write regardless of the UID Render uses. Files written there persist across redeploys via the Render disk.

---

## Tech stack

- **Backend:** [Bantu](https://github.com/AsseySilivestir/Bantu) v1.3.0 (pure language, no Node.js / Python / Go)
- **HTTP framework:** Sua (bundled with Bantu)
- **File I/O:** Bantu's v1.3.0 builtins (`writefile`, `readfile`, `open`)
- **Low-level access:** Bantu's v1.3.0 FFI (`loadlib` + `func`) → `libc.so.6`
- **Frontend:** vanilla HTML/CSS/JS, no framework
- **Packaging:** multi-stage Dockerfile, Render Blueprint
