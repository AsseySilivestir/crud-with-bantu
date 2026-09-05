// ════════════════════════════════════════════════════════════════════
//  Bantu File-System & Power Demo  —  server.b
//  ────────────────────────────────────────────────────────────────────
//  Pure Bantu v1.3.0 + Sua HTTP framework + FFI to libc.
//
//  Demonstrates:
//    • File system operations  →  list / create / read / delete files
//    • Low-level power control  →  shutdown / restart / sleep
//      (simulated when running in containers; real on bare metal)
//
//  Run:    bantu run server.b
//  HTTP:   http://0.0.0.0:$PORT
//  Files:  ./workspace/   (auto-created on first request)
// ════════════════════════════════════════════════════════════════════

print "═══════════════════════════════════════════";
print "  Bantu FS & Power Demo  —  v1.3.0";
print "  Pure Bantu + Sua + libc FFI";
print "═══════════════════════════════════════════";

// ─── Configuration ─────────────────────────────────────────────────
string $envPort = env("PORT");
if (!$envPort) { $envPort = "8080"; }

string $workspace = env("WORKSPACE");
if (!$workspace) { $workspace = "./workspace"; }

print "[INFO] Workspace: " + $workspace;
print "[INFO] Port:      " + $envPort;

// ─── Load libc via FFI for system() / unlink() / opendir() ─────────
// We use Bantu v1.3.0's FFI builtins (loadlib + func) to call into
// the C library directly. This is what gives the demo its "low-level"
// power: from Bantu we can invoke any C function in any shared lib.
string $libc   = "";
string $sysFn   = "";
string $unlinkFn = "";
bool $ffiOk     = false;
try {
    $libc = loadlib("libc.so.6");
    $sysFn = func($libc, "system", "int", ["string"]);
    $unlinkFn = func($libc, "unlink", "int", ["string"]);
    $ffiOk = true;
    print "[OK]   FFI ready: libc.so.6 loaded";
} catch ($e) {
    print "[WARN] FFI unavailable — file delete & power will be simulated";
    print "       error: " + $e.message;
}

// Helper: run a shell command via libc's system(), capture stdout.
// We wrap in `bash -c '...'` so the redirection captures the whole
// pipeline (a bare `cmd > file 2>&1` only redirects cmd's own output,
// missing chained `&&` / `||` outputs).
def sh($cmd) {
    if (!$ffiOk) { return {"ok": false, "error": "FFI not available", "rc": -1, "out": ""}; }
    $tmp = "/tmp/bantu_sh_" + str(clock()) + ".txt";
    // Use a subshell so redirection captures the entire command chain
    $wrapped = "bash -c " + chr(39) + $cmd + chr(39) + " > " + $tmp + " 2>&1";
    $rc = $sysFn($wrapped);
    $out = "";
    try { $out = readfile($tmp); } catch ($e) {}
    // Clean up the temp file via unlink() (FFI) — true low-level file delete
    if ($ffiOk) { $unlinkFn($tmp); }
    $ok = ($rc == 0);
    return {"ok": $ok, "rc": $rc, "out": $out};
}

// chr(n) — for getting the apostrophe character (ASCII 39) without
// having to escape it inside a Bantu string literal.
def chr($n) {
    $ascii = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
    if ($n == 39) { return "'"; }
    if ($n < 32 || $n > 126) { return ""; }
    return substr($ascii, $n - 32, 1);
}

// Helper: ensure the workspace directory exists.
def ensureWorkspace() {
    $r = sh("mkdir -p " + $workspace);
    if (!$r.ok) {
        // Fallback: writefile creates parent dirs in some impls; try anyway
        writefile($workspace + "/.keep", "");
    }
    return true;
}

ensureWorkspace();

// ─── Health check ─────────────────────────────────────────────────
def handleHealth($req, $res) {
    $res.json({
        "status":      "ok",
        "language":    "Bantu",
        "version":     "1.3.0",
        "framework":   "Sua",
        "ffi":         $ffiOk,
        "workspace":   $workspace,
        "time":        clock(),
        "hostname":    sh("hostname").out,
        "platform":    sh("uname -s").out
    });
}

// ─── File system: list files ──────────────────────────────────────
def handleListFiles($req, $res) {
    $r = sh("ls -la --time-style=long-iso " + $workspace);
    if (!$r.ok) {
        $res.status(500).json({"error": "could not list workspace", "details": $r.out});
        return null;
    }
    // Parse `ls -la` output. Each line looks like:
    //   -rw-r--r-- 1 user grp  123 2026-09-05 12:34 filename.txt
    list $lines = $r.out.split("\n");
    list $files = [];
    number $i = 0;
    each ($line in $lines) {
        if (len($line) < 10) { continue; }
        if ($line[0] == "t") { continue; }       // skip "total" line
        // Split on whitespace — `ls` output is whitespace-separated
        list $parts = $line.split(" ");
        list $kept = [];
        each ($p in $parts) {
            if (len($p) > 0) { push($kept, $p); }
        }
        if (len($kept) < 8) { continue; }
        // Last element is the filename
        string $name = $kept[len($kept) - 1];
        if ($name == "." || $name == "..") { continue; }
        $files[$i] = {
            "name":   $name,
            "perms":  $kept[0],
            "size":   $kept[4],
            "date":   $kept[5],
            "time":   $kept[6],
            "isDir":  ($kept[0][0] == "d")
        };
        $i = $i + 1;
    }
    $res.json({"files": $files, "count": len($files), "workspace": $workspace});
}

// ─── File system: create / overwrite a file ───────────────────────
def handleCreateFile($req, $res) {
    string $name = $req.body.name;
    string $content = $req.body.content;
    if (!$name) {
        $res.status(400).json({"error": "name is required"});
        return null;
    }
    // Block path traversal — only allow filenames, no slashes
    if (str_contains($name, "/") || str_contains($name, "..")) {
        $res.status(400).json({"error": "name must not contain / or .."});
        return null;
    }
    string $path = $workspace + "/" + $name;
    if (!$content) { $content = ""; }
    writefile($path, $content);
    $res.json({
        "ok":   true,
        "path": $path,
        "name": $name,
        "size": len($content)
    });
}

// ─── File system: read a file ─────────────────────────────────────
def handleReadFile($req, $res) {
    string $name = $req.params.name;
    if (str_contains($name, "/") || str_contains($name, "..")) {
        $res.status(400).json({"error": "name must not contain / or .."});
        return null;
    }
    string $path = $workspace + "/" + $name;
    string $content = "";
    try {
        $content = readfile($path);
    } catch ($e) {
        $res.status(404).json({"error": "file not found", "name": $name});
        return null;
    }
    $res.json({"name": $name, "path": $path, "content": $content, "size": len($content)});
}

// ─── File system: delete a file (via libc unlink — true low-level) ─
def handleDeleteFile($req, $res) {
    string $name = $req.params.name;
    if (str_contains($name, "/") || str_contains($name, "..")) {
        $res.status(400).json({"error": "name must not contain / or .."});
        return null;
    }
    string $path = $workspace + "/" + $name;
    number $rc = -1;
    if ($ffiOk) {
        // Use the libc unlink() syscall wrapper — direct FFI call
        $rc = $unlinkFn($path);
    } else {
        // Fallback: shell out
        $r = sh("rm -f " + $path);
        $rc = $r.rc;
    }
    if ($rc != 0) {
        $res.status(404).json({"error": "could not delete (file missing?)", "name": $name, "rc": $rc});
        return null;
    }
    // Pick a method label (Bantu has no ternary operator)
    string $method = "rm";
    if ($ffiOk) { $method = "libc.unlink"; }
    $res.json({"ok": true, "deleted": $name, "method": $method});
}

// ─── File system: stat a file ─────────────────────────────────────
def handleStatFile($req, $res) {
    string $name = $req.params.name;
    if (str_contains($name, "/") || str_contains($name, "..")) {
        $res.status(400).json({"error": "name must not contain / or .."});
        return null;
    }
    string $path = $workspace + "/" + $name;
    $r = sh("stat -c '%s %Y %A %F' " + $path);
    if (!$r.ok) {
        $res.status(404).json({"error": "file not found", "name": $name});
        return null;
    }
    list $parts = $r.out.split(" ");
    $res.json({
        "name":    $name,
        "path":    $path,
        "size":    $parts[0],
        "mtime":   $parts[1],
        "perms":   $parts[2],
        "type":    $parts[3]
    });
}

// ─── Power: detect platform (bare metal vs container) ─────────────
// We probe whether we're inside a container — if so, "power" actions
// can't really affect the host machine and we simulate them. On bare
// metal they would actually run the OS shutdown command.
def isContainer() {
    $r = sh("test -f /.dockerenv && echo yes || echo no");
    if ($r.out == "yes") { return true; }
    // /proc/1/cgroup often mentions docker / kubepods in containers
    $r2 = sh("grep -E 'docker|kubepods|containerd' /proc/1/cgroup 2>/dev/null | head -1");
    if (len($r2.out) > 0) { return true; }
    return false;
}

// ─── Power: shutdown / restart / sleep / hibernate ────────────────
//   In a container:   simulated — we log the intent + return
//                     what *would* have run on bare metal.
//   On bare metal:    actually executes the OS command (requires
//                     the bantu process to have shutdown privileges —
//                     usually needs `sudo` or systemd `shutdown` group).
def handlePower($req, $res) {
    string $action = $req.body.action;
    if (!$action) {
        $res.status(400).json({"error": "action is required (shutdown | restart | sleep | hibernate)"});
        return null;
    }

    // Real OS commands for each action (Linux). For macOS / WSL the
    // commands are slightly different — we pick based on `uname`.
    string $kernel = sh("uname -s").out;
    string $cmd = "";
    string $desc = "";
    if ($action == "shutdown") {
        if ($kernel == "Darwin") { $cmd = "shutdown -h now"; }
        else { $cmd = "shutdown -h now"; }
        $desc = "Power off the machine";
    }
    if ($action == "restart") {
        if ($kernel == "Darwin") { $cmd = "shutdown -r now"; }
        else { $cmd = "shutdown -r now"; }
        $desc = "Reboot the machine";
    }
    if ($action == "sleep") {
        if ($kernel == "Darwin") { $cmd = "pmset sleepnow"; }
        else { $cmd = "systemctl suspend"; }
        $desc = "Suspend to RAM (sleep)";
    }
    if ($action == "hibernate") {
        if ($kernel == "Darwin") { $cmd = "pmset hibernatenow"; }
        else { $cmd = "systemctl hibernate"; }
        $desc = "Hibernate to disk";
    }
    if ($desc == "") {
        $res.status(400).json({"error": "unknown action: " + $action});
        return null;
    }

    $inContainer = isContainer();
    $actuallyRan = false;
    number $rc = -1;
    string $log = "";

    if ($inContainer) {
        // SIMULATED — running `shutdown` inside a Docker container only
        // kills the container, not the host. We don't actually do it.
        $log = "[SIMULATED] Would run: " + $cmd + " (but we are inside a container — host would not be affected)";
        print $log;
    } else {
        // Bare metal — actually invoke the OS command.
        // NOTE: this requires the bantu process to have permission to
        // run `shutdown` (typically: run as root, or in the `shutdown`
        // group, or via `sudo` with NOPASSWD).
        $r = sh($cmd);
        $rc = $r.rc;
        $actuallyRan = true;
        $log = "[EXECUTED] " + $cmd + " → rc=" + str($rc) + "  out=" + $r.out;
        print $log;
    }

    // Append to the audit log so the UI can show what happened
    // Pick a label (Bantu has no ternary operator)
    string $execLabel = "executed";
    if ($inContainer) { $execLabel = "simulated"; }
    appendfile($workspace + "/.power.log",
        str(clock()) + "  " + $action + "  " + $execLabel + "  " + $cmd + "\n");

    string $msg = "Executed: " + $cmd + " (rc=" + str($rc) + ")";
    if ($inContainer) {
        $msg = "Simulated — running in a container. On bare metal this would run: " + $cmd;
    }
    $res.json({
        "ok":          true,
        "action":      $action,
        "description": $desc,
        "command":     $cmd,
        "kernel":      $kernel,
        "container":   $inContainer,
        "executed":    $actuallyRan,
        "rc":          $rc,
        "simulated":   $inContainer,
        "message":     $msg,
        "timestamp":   clock()
    });
}

// ─── Power: read the audit log ────────────────────────────────────
def handlePowerLog($req, $res) {
    string $path = $workspace + "/.power.log";
    string $content = "";
    try { $content = readfile($path); } catch ($e) { $content = ""; }
    list $lines = $content.split("\n");
    list $entries = [];
    number $i = 0;
    each ($line in $lines) {
        if (len($line) > 0) {
            $entries[$i] = $line;
            $i = $i + 1;
        }
    }
    $res.json({"entries": $entries, "count": len($entries)});
}

// ─── System info (proves the demo can read low-level host details) ─
def handleSysInfo($req, $res) {
    $res.json({
        "kernel":   sh("uname -s").out,
        "release":  sh("uname -r").out,
        "machine":  sh("uname -m").out,
        "hostname": sh("hostname").out,
        "uptime":   sh("uptime").out,
        "load":     sh("cat /proc/loadavg").out,
        "meminfo":  sh("head -3 /proc/meminfo").out,
        "cpuinfo":  sh("grep -m1 'model name' /proc/cpuinfo").out,
        "disk":     sh("df -h / | tail -1").out,
        "whoami":   sh("whoami").out,
        "date":     sh("date").out,
        "container": isContainer()
    });
}

// ─── Helpers ──────────────────────────────────────────────────────
def str_contains($haystack, $needle) {
    if (len($needle) == 0) { return true; }
    if (len($haystack) < len($needle)) { return false; }
    number $i = 0;
    while ($i + len($needle) <= len($haystack)) {
        string $slice = substr($haystack, $i, len($needle));
        if ($slice == $needle) { return true; }
        $i = $i + 1;
    }
    return false;
}

// CORS preflight
def handleOptions($req, $res) {
    $res.header("Access-Control-Allow-Origin", "*");
    $res.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    $res.header("Access-Control-Allow-Headers", "Content-Type, Authorization");
    $res.status(204).send("");
}

// Add CORS to every response — wrap $res.header calls happen per-handler
def corsWrap($req, $res) {
    $res.header("Access-Control-Allow-Origin", "*");
    $res.header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS");
    $res.header("Access-Control-Allow-Headers", "Content-Type, Authorization");
    return true;
}

// ─── Routes ───────────────────────────────────────────────────────
sua.server.get("/api/health",                        handleHealth);
sua.server.get("/api/files",                         handleListFiles);
sua.server.post("/api/files",                         handleCreateFile);
sua.server.get("/api/files/:name",                   handleReadFile);
sua.server.delete("/api/files/:name",                handleDeleteFile);
sua.server.get("/api/files/:name/stat",              handleStatFile);
sua.server.post("/api/power",                         handlePower);
sua.server.get("/api/power/log",                     handlePowerLog);
sua.server.get("/api/sysinfo",                       handleSysInfo);
sua.server.options("/*",                             handleOptions);

// Static frontend
sua.server.static("./public");

// ─── Start ────────────────────────────────────────────────────────
print "";
print "═══════════════════════════════════════════";
print "  Bantu FS & Power Demo ready";
print "  →  http://0.0.0.0:" + $envPort;
print "";
print "  Endpoints:";
print "    GET    /api/health           system health + version";
print "    GET    /api/files            list files in workspace";
print "    POST   /api/files            create/overwrite a file";
print "    GET    /api/files/:name      read a file's contents";
print "    DELETE /api/files/:name       delete a file (libc unlink)";
print "    GET    /api/files/:name/stat file metadata";
print "    POST   /api/power            shutdown / restart / sleep / hibernate";
print "    GET    /api/power/log         power-action audit log";
print "    GET    /api/sysinfo           low-level host info (uname, loadavg, meminfo)";
print "═══════════════════════════════════════════";
print "";

sua.server.listen(num($envPort));
