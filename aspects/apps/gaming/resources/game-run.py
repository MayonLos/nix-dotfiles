"""Shared launch environment; does not issue GPU power-switching commands or change profiles itself."""
import os
import shlex
import shutil
import subprocess
import sys

GPU_KEYS = ("__NV_PRIME_RENDER_OFFLOAD", "__NV_PRIME_RENDER_OFFLOAD_PROVIDER",
            "__GLX_VENDOR_LIBRARY_NAME", "__VK_LAYER_NV_optimus", "DRI_PRIME")


def environment(env):
    env = env.copy()
    # Drop stale inherited offload variables, including Prism's discrete-GPU option.
    for key in GPU_KEYS:
        env.pop(key, None)
    env.update(__GL_SHADER_DISK_CACHE="1", __GL_SHADER_DISK_CACHE_SIZE="10737418240",
               __GL_SHADER_DISK_CACHE_SKIP_CLEANUP="1", MESA_SHADER_CACHE_MAX_SIZE="10G")
    smi = shutil.which("nvidia-smi")
    if not smi and os.path.isfile("/run/current-system/sw/bin/nvidia-smi"):
        smi = "/run/current-system/sw/bin/nvidia-smi"
    available = False
    if env.get("GAME_RUN_GPU", "auto") != "integrated" and smi:
        try:
            probe = subprocess.run([smi, "-L"], capture_output=True, text=True, timeout=3)
            available = probe.returncode == 0 and any(
                line.startswith("GPU ") for line in probe.stdout.splitlines())
        except (OSError, subprocess.TimeoutExpired):
            pass
    if available:
        env.update(__NV_PRIME_RENDER_OFFLOAD="1", __GLX_VENDOR_LIBRARY_NAME="nvidia",
                   __VK_LAYER_NV_optimus="NVIDIA_only")
    elif env.get("GAME_RUN_GPU", "auto") != "integrated":
        print("game-run: NVIDIA 不可用，使用核显（未执行独显电源切换命令）。", file=sys.stderr)
    return env


def main():
    args = sys.argv[1:]
    if args == ["--env"]:
        env = environment(os.environ)
        for key in (*GPU_KEYS, "__GL_SHADER_DISK_CACHE", "__GL_SHADER_DISK_CACHE_SIZE",
                    "__GL_SHADER_DISK_CACHE_SKIP_CLEANUP", "MESA_SHADER_CACHE_MAX_SIZE"):
            print(f"export {key}={shlex.quote(env[key])}" if key in env else f"unset {key}")
        return
    if args and args[0] == "--":
        args.pop(0)
    if not args:
        sys.exit("usage: game-run [--] COMMAND [ARG ...]; GAME_RUN_GPU=integrated skips NVIDIA")
    env = environment(os.environ)
    os.execvpe("gamemoderun", ["gamemoderun", *args], env)


if __name__ == "__main__":
    main()
