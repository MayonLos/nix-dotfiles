{
  lib,
  runCommand,
  writeText,
  makeWrapper,
  makeDesktopItem,
  fetchurl,
  python3,
  chromium,
  libnotify,
  dsh,
}:
let
  # Upstream's Electron release targets currently cover macOS and Windows only.
  # Use its complete, locked Web application in an isolated Linux app window.
  # This is a local launcher, not an unofficial replacement Harness distribution.
  icon = fetchurl {
    url = "https://raw.githubusercontent.com/deepseek-ai/deepseek-harness/687f282e8625c6b8d11ff58211a90524be2e4317/apps/desktop/resources/icon.png";
    hash = "sha256-mCwoWVaNg9JXYRClJ8VF8EZB9ACL2yz+tnWPMzwPsHo=";
  };
  launcher = writeText "dsh-desktop.py" ''
    import fcntl
    import os
    import pathlib
    import queue
    import re
    import signal
    import subprocess
    import sys
    import threading
    import time

    if len(sys.argv) > 1:
        if sys.argv[1:] == ["--version"]:
            print("dsh-desktop (Web app launcher) ${dsh.version}")
            sys.exit(0)
        print("Usage: dsh-desktop [--version]")
        sys.exit(0 if sys.argv[1:] == ["--help"] else 2)

    os.umask(0o077)
    home = pathlib.Path.home()
    state = pathlib.Path(os.environ.get("XDG_STATE_HOME", home / ".local/state")) / "dsh-desktop"
    state.mkdir(parents=True, exist_ok=True)
    runtime = pathlib.Path(os.environ["XDG_RUNTIME_DIR"]) / "dsh-desktop"
    runtime.mkdir(mode=0o700, exist_ok=True)
    data = pathlib.Path(os.environ.get("XDG_DATA_HOME") or home / ".local/share") / "dsh-desktop"
    profile = data / "chromium"
    profile.mkdir(parents=True, exist_ok=True)
    # Desktop owns its runtime: never reactivate legacy ~/.dsh plugins or an
    # inherited CLI DSH_HOME. Account migration is an explicit, separate step.
    harness = data / "harness"
    harness.mkdir(parents=True, exist_ok=True)
    backend_env = dict(os.environ, DSH_HOME=str(harness))
    url_file = runtime / "url"
    lock = (runtime / "lock").open("w")

    def browser(url):
        return subprocess.Popen([
            "${lib.getExe chromium}", "--class=dsh-desktop",
            "--user-data-dir=" + str(profile), "--no-first-run",
            "--no-default-browser-check", "--app=" + url,
        ], cwd=home, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        # Chromium forwards this request to the already running app window.
        for _ in range(120):
            if url_file.exists():
                sys.exit(browser(url_file.read_text()).wait())
            time.sleep(0.5)
        sys.exit("DeepSeek Harness is still starting; see " + str(state / "launcher.log"))

    backend = None
    window = None
    reader = None
    log = None
    def interrupted(signum, frame):
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        url_file.unlink(missing_ok=True)
        log = (state / "launcher.log").open("w")
        backend = subprocess.Popen([
            "${lib.getExe dsh}", "web", "--no-open", "--host", "127.0.0.1", "--port", "0",
        ], cwd=home, env=backend_env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
           text=True, bufsize=1, start_new_session=True)
        ready = queue.Queue()
        def output():
            for line in backend.stdout:
                match = re.search(r"dsh web: (http://127\.0\.0\.1:\d+\S*)", line)
                if match:
                    # The URL can contain an access token: keep it only in
                    # the private runtime directory, never in persistent logs.
                    ready.put(match.group(1))
                else:
                    log.write(line)
                    log.flush()
            ready.put(None)
        reader = threading.Thread(target=output, daemon=True)
        reader.start()
        url = ready.get(timeout=120)
        if url is None:
            raise RuntimeError("Harness exited before becoming ready")
        url_file.write_text(url)
        window = browser(url)
        while window.poll() is None:
            if backend.poll() is not None:
                raise RuntimeError("Harness stopped unexpectedly")
            time.sleep(0.5)
        if window.returncode != 0:
            raise RuntimeError("The desktop window could not open")
    except Exception:
        message = "DeepSeek Harness could not start. See " + str(state / "launcher.log")
        print(message, file=sys.stderr)
        subprocess.run(["${lib.getExe libnotify}", "DeepSeek Harness", message], check=False)
        sys.exit(1)
    finally:
        url_file.unlink(missing_ok=True)
        if window is not None and window.poll() is None:
            window.terminate()
        if backend is not None:
            try:
                os.killpg(backend.pid, signal.SIGTERM)
                backend.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(backend.pid, signal.SIGKILL)
                backend.wait()
            except ProcessLookupError:
                pass
        if reader is not None:
            reader.join(timeout=2)
        if log is not None and (reader is None or not reader.is_alive()):
            log.close()
  '';
  desktop = makeDesktopItem {
    name = "dsh-desktop";
    desktopName = "DeepSeek Harness";
    comment = "DeepSeek Harness Web in a dedicated desktop window";
    exec = "dsh-desktop";
    icon = "dsh-desktop";
    terminal = false;
    categories = [ "Development" ];
    startupWMClass = "dsh-desktop";
  };
in
runCommand "dsh-desktop-${dsh.version}"
  {
    inherit (dsh) version;
    nativeBuildInputs = [ makeWrapper ];
    meta = {
      description = "Local desktop launcher for the official DeepSeek Harness Web app";
      homepage = "https://github.com/deepseek-ai/deepseek-harness";
      license = lib.licenses.mit;
      mainProgram = "dsh-desktop";
      platforms = lib.platforms.linux;
    };
  }
  ''
    ${python3}/bin/python3 -c 'import ast; ast.parse(open("${launcher}").read())'
    mkdir -p $out/bin $out/share/icons/hicolor/1024x1024/apps
    makeWrapper ${python3}/bin/python3 $out/bin/dsh-desktop --add-flags ${launcher}
    cp ${icon} $out/share/icons/hicolor/1024x1024/apps/dsh-desktop.png
    cp -r ${desktop}/share/applications $out/share/
  ''
