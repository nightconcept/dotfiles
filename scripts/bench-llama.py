#!/usr/bin/env python3
"""Benchmark terra's deployed llama.cpp build against upstream master.

This benchmarks the deployed 35B A3B MTP service configuration on terra:
- pinned: the current native build in /opt/llama-cpp
- master: an isolated native upstream master build under /tmp

If llama-server is already running on :8080, the script benchmarks that live
service in place instead of stopping it. The scratch master benchmark runs on
its own port so the comparison does not require root or cause downtime.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Any, NoReturn

DEFAULT_RUNS = 3
DEFAULT_N_PREDICT = 200
DEFAULT_CONTEXT = 131072
DEFAULT_READY_TIMEOUT = 900
DEFAULT_WARMUP_N_PREDICT = 64
DEFAULT_PINNED_PORT = 8080
DEFAULT_MASTER_PORT = 8081

MODEL_PATH = Path("/mnt/storage/llm-models/Qwen3.6-35B-A3B-MTP-UD-Q5_K_XL.gguf")
PINNED_SERVER = Path("/opt/llama-cpp/llama-server")
PINNED_LIBRARY_DIR = Path("/opt/llama-cpp")
ROCM_LIBRARY_PATH = "/opt/rocm/lib:/opt/rocm/lib64"

MASTER_REPO_URL = "https://github.com/ggml-org/llama.cpp.git"
MASTER_ROOT = Path("/tmp/bench-llama-master-native")
MASTER_SRC_DIR = MASTER_ROOT / "src"
MASTER_BUILD_DIR = MASTER_ROOT / "build-hip"
MASTER_STAGE_DIR = MASTER_ROOT / "stage"
MASTER_COMMIT_FILE = MASTER_ROOT / "master-commit.txt"
ARTIFACT_ROOT = Path("/tmp/bench-llama-results")

PROMPT = (
    "You are debugging a production inference deployment. "
    "Explain, in technical depth, how speculative decoding with draft MTP heads "
    "interacts with KV cache precision, flash attention, batching, and long "
    "context limits on ROCm. Include concrete tradeoffs, failure modes, and "
    "what metrics you would watch when deciding whether to upgrade llama.cpp."
)


@dataclass
class BuildTarget:
    name: str
    binary: Path
    library_dir: Path
    version: str
    commit: str


@dataclass
class BenchResult:
    target: BuildTarget
    source: str
    port: int
    prompt_tps: float
    gen_tps: float
    runs: list[dict[str, float]]


def die(message: str) -> NoReturn:
    print(f"error: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(
    cmd: list[str],
    *,
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    capture_output: bool = False,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        env=env,
        check=True,
        text=True,
        stdout=subprocess.PIPE if capture_output else None,
        stderr=subprocess.STDOUT if capture_output else None,
    )


def ensure_required_paths() -> None:
    if not MODEL_PATH.is_file():
        die(f"missing model file: {MODEL_PATH}")
    if not PINNED_SERVER.is_file():
        die(f"missing pinned server binary: {PINNED_SERVER}")


def run_systemctl(*args: str) -> None:
    direct = subprocess.run(
        ["systemctl", *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if direct.returncode == 0:
        return

    if os.geteuid() == 0:
        print(direct.stdout or "", end="")
        die(f"systemctl {' '.join(args)} failed")

    fallback = subprocess.run(
        ["sudo", "systemctl", *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    if fallback.returncode == 0:
        return

    if direct.stdout:
        print(direct.stdout, end="")
    if fallback.stdout:
        print(fallback.stdout, end="")
    die(f"systemctl {' '.join(args)} failed")


def service_was_active(name: str) -> bool:
    return subprocess.run(["systemctl", "is-active", "--quiet", name]).returncode == 0


def stop_service(name: str) -> None:
    run_systemctl("stop", name)


def start_service(name: str) -> None:
    run_systemctl("start", name)


def server_base_url(port: int) -> str:
    return f"http://127.0.0.1:{port}"


def health_code(port: int) -> int | None:
    try:
        with urllib.request.urlopen(f"{server_base_url(port)}/health", timeout=2) as response:
            return response.status
    except urllib.error.HTTPError as exc:
        return exc.code
    except Exception:
        return None


def wait_for_server(port: int, timeout: int = DEFAULT_READY_TIMEOUT) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        code = health_code(port)
        if code == 200:
            return
        if code not in (None, 503):
            die(f"server on port {port} returned unexpected health status {code}")
        time.sleep(2)
    raise TimeoutError(f"server on port {port} did not become ready within {timeout}s")


def server_request(port: int, n_predict: int) -> dict[str, Any]:
    payload = json.dumps(
        {
            "prompt": PROMPT,
            "n_predict": n_predict,
            "temperature": 0,
            "top_k": 1,
            "top_p": 1.0,
            "min_p": 0.0,
            "repeat_penalty": 1.0,
            "cache_prompt": False,
        }
    ).encode()
    request = urllib.request.Request(
        f"{server_base_url(port)}/completion",
        data=payload,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(request, timeout=600) as response:
        return json.loads(response.read())


def benchmark_target(
    target: BuildTarget,
    *,
    source: str,
    port: int,
    runs: int,
    n_predict: int,
) -> BenchResult:
    print(f"\n[{target.name}] {target.version}")
    print(f"  source: {source} on :{port}")
    print("  warming up...")
    server_request(port, min(DEFAULT_WARMUP_N_PREDICT, n_predict))

    measurements: list[dict[str, float]] = []
    for index in range(1, runs + 1):
        timings = server_request(port, n_predict)["timings"]
        prompt_tps = float(timings["prompt_per_second"])
        gen_tps = float(timings["predicted_per_second"])
        measurements.append({"prompt_tps": prompt_tps, "gen_tps": gen_tps})
        print(
            f"  run {index}/{runs}: "
            f"prompt={prompt_tps:6.1f} tok/s  gen={gen_tps:6.1f} tok/s"
        )
        if index < runs:
            time.sleep(1)

    prompt_avg = sum(item["prompt_tps"] for item in measurements) / len(measurements)
    gen_avg = sum(item["gen_tps"] for item in measurements) / len(measurements)
    print(f"  avg: prompt={prompt_avg:.1f} tok/s  gen={gen_avg:.1f} tok/s")
    return BenchResult(
        target=target,
        source=source,
        port=port,
        prompt_tps=prompt_avg,
        gen_tps=gen_avg,
        runs=measurements,
    )


def server_env(library_dir: Path) -> dict[str, str]:
    existing = os.environ.get("LD_LIBRARY_PATH", "")
    joined = f"{library_dir}:{ROCM_LIBRARY_PATH}"
    if existing:
        joined = f"{joined}:{existing}"
    return {
        **os.environ,
        "ROCM_PATH": "/opt/rocm",
        "LD_LIBRARY_PATH": joined,
    }


def version_from_binary(binary: Path, env: dict[str, str]) -> str:
    output = run([str(binary), "--version"], env=env, capture_output=True).stdout.strip()
    return output.splitlines()[0] if output else "unknown"


def commit_from_version(version: str) -> str:
    match = re.search(r"\(([0-9a-f]{7,40})\)", version)
    if match:
        return match.group(1)
    return "unknown"


def detect_gpu_arch() -> str:
    output = run(["rocminfo"], capture_output=True).stdout
    match = re.search(r"gfx[0-9]+", output)
    if not match:
        die("unable to detect AMD GPU architecture from rocminfo")
    return match.group(0)


def sync_master_source() -> str:
    MASTER_ROOT.mkdir(parents=True, exist_ok=True)
    if (MASTER_SRC_DIR / ".git").is_dir():
        print("updating upstream master source...")
    else:
        print("cloning upstream master source...")
        run(
            ["git", "clone", "--depth", "1", "--branch", "master", MASTER_REPO_URL, str(MASTER_SRC_DIR)]
        )

    run(["git", "fetch", "--depth", "1", "origin", "master"], cwd=MASTER_SRC_DIR)
    run(["git", "checkout", "--detach", "FETCH_HEAD"], cwd=MASTER_SRC_DIR)
    commit = run(["git", "rev-parse", "HEAD"], cwd=MASTER_SRC_DIR, capture_output=True).stdout.strip()
    if not commit:
        die("failed to resolve upstream master commit")
    return commit


def current_master_commit() -> str | None:
    if not MASTER_COMMIT_FILE.is_file():
        return None
    commit = MASTER_COMMIT_FILE.read_text(encoding="utf-8").strip()
    return commit or None


def build_master_if_needed(force_rebuild: bool = False) -> BuildTarget:
    master_commit = sync_master_source()
    installed_commit = current_master_commit()
    stage_server = MASTER_STAGE_DIR / "llama-server"
    stage_cli = MASTER_STAGE_DIR / "llama-cli"

    needs_build = force_rebuild or installed_commit != master_commit or not stage_server.is_file()
    if needs_build:
        print(f"building upstream master at {master_commit[:12]}...")
        shutil.rmtree(MASTER_BUILD_DIR, ignore_errors=True)
        shutil.rmtree(MASTER_STAGE_DIR, ignore_errors=True)
        MASTER_BUILD_DIR.mkdir(parents=True, exist_ok=True)
        MASTER_STAGE_DIR.mkdir(parents=True, exist_ok=True)

        env = {
            **os.environ,
            "ROCM_PATH": "/opt/rocm",
            "PATH": f"/opt/rocm/bin:{os.environ.get('PATH', '')}",
            "LD_LIBRARY_PATH": (
                f"/opt/rocm/lib:/opt/rocm/lib64"
                f"{':' + os.environ['LD_LIBRARY_PATH'] if os.environ.get('LD_LIBRARY_PATH') else ''}"
            ),
            "HIPCXX": f"{run(['hipconfig', '-l'], capture_output=True).stdout.strip()}/clang",
            "HIP_PATH": run(["hipconfig", "-R"], capture_output=True).stdout.strip(),
        }
        gpu_arch = detect_gpu_arch()
        cmake_args = [
            "cmake",
            "-S",
            str(MASTER_SRC_DIR),
            "-B",
            str(MASTER_BUILD_DIR),
            "-DGGML_HIP=ON",
            "-DGGML_HIP_ROCWMMA_FATTN=ON",
            f"-DGPU_TARGETS={gpu_arch}",
            "-DLLAMA_BUILD_UI=OFF",
            "-DLLAMA_BUILD_TESTS=OFF",
            "-DLLAMA_BUILD_EXAMPLES=OFF",
            "-DLLAMA_TESTS_INSTALL=OFF",
            "-DLLAMA_BUILD_TOOLS=ON",
            "-DLLAMA_BUILD_SERVER=ON",
            "-DCMAKE_BUILD_TYPE=Release",
            f"-DCMAKE_INSTALL_PREFIX={MASTER_STAGE_DIR}",
            "-DCMAKE_INSTALL_BINDIR=.",
            "-DCMAKE_INSTALL_LIBDIR=.",
            "-DCMAKE_INSTALL_RPATH=$ORIGIN;/opt/rocm/lib;/opt/rocm/lib64",
        ]
        run(cmake_args, env=env)
        run(
            ["cmake", "--build", str(MASTER_BUILD_DIR), "--config", "Release", "--", f"-j{os.cpu_count() or 1}"],
            env=env,
        )
        run(["cmake", "--install", str(MASTER_BUILD_DIR), "--prefix", str(MASTER_STAGE_DIR)], env=env)

        if not stage_server.is_file() or not stage_cli.is_file():
            die("master build completed without llama-server/llama-cli")

        device_output = run(
            [str(stage_cli), "--list-devices"],
            env=server_env(MASTER_STAGE_DIR),
            capture_output=True,
        ).stdout
        if not any(line.strip() for line in device_output.splitlines()[1:]):
            print(device_output)
            die("master build did not expose any usable ROCm devices")

        MASTER_COMMIT_FILE.write_text(master_commit, encoding="utf-8")
    else:
        print(f"reusing existing upstream master build at {master_commit[:12]}")

    version = version_from_binary(stage_server, server_env(MASTER_STAGE_DIR))
    return BuildTarget(
        name="master",
        binary=stage_server,
        library_dir=MASTER_STAGE_DIR,
        version=version,
        commit=commit_from_version(version),
    )


def pinned_target() -> BuildTarget:
    version = version_from_binary(PINNED_SERVER, server_env(PINNED_LIBRARY_DIR))
    return BuildTarget(
        name="pinned",
        binary=PINNED_SERVER,
        library_dir=PINNED_LIBRARY_DIR,
        version=version,
        commit=commit_from_version(version),
    )


def port_is_listening(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.settimeout(1)
        return sock.connect_ex(("127.0.0.1", port)) == 0


def launch_args(*, port: int, context: int) -> list[str]:
    return [
        "-m",
        str(MODEL_PATH),
        "-c",
        str(context),
        "-ngl",
        "all",
        "-fa",
        "on",
        "-ctk",
        "q8_0",
        "-ctv",
        "q8_0",
        "--no-mmproj",
        "--jinja",
        "--spec-type",
        "draft-mtp",
        "--spec-draft-n-max",
        "3",
        "--host",
        "127.0.0.1",
        "--port",
        str(port),
    ]


def launch_target(target: BuildTarget, *, port: int, context: int) -> subprocess.Popen[str]:
    if port_is_listening(port):
        die(f"port {port} is already in use")
    return subprocess.Popen(
        [str(target.binary), *launch_args(port=port, context=context)],
        env=server_env(target.library_dir),
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        text=True,
    )


def terminate_process(proc: subprocess.Popen[str] | None) -> None:
    if proc is None:
        return
    proc.terminate()
    try:
        proc.wait(timeout=30)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=30)


def write_artifacts(
    results: list[BenchResult],
    *,
    runs: int,
    n_predict: int,
    context: int,
) -> tuple[Path, Path]:
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    artifact_dir = ARTIFACT_ROOT / timestamp
    artifact_dir.mkdir(parents=True, exist_ok=True)

    raw_path = artifact_dir / "raw.json"
    summary_path = artifact_dir / "summary.tsv"

    raw_payload = {
        "model": str(MODEL_PATH),
        "context": context,
        "n_predict": n_predict,
        "runs": runs,
        "results": [
            {
                "name": result.target.name,
                "version": result.target.version,
                "commit": result.target.commit,
                "source": result.source,
                "port": result.port,
                "prompt_tps": result.prompt_tps,
                "gen_tps": result.gen_tps,
                "runs": result.runs,
            }
            for result in results
        ],
    }
    raw_path.write_text(json.dumps(raw_payload, indent=2), encoding="utf-8")

    lines = [
        "\t".join(
            [
                "build",
                "version",
                "commit",
                "source",
                "port",
                "prompt_tps",
                "gen_tps",
            ]
        )
    ]
    for result in results:
        lines.append(
            "\t".join(
                [
                    result.target.name,
                    result.target.version,
                    result.target.commit,
                    result.source,
                    str(result.port),
                    f"{result.prompt_tps:.3f}",
                    f"{result.gen_tps:.3f}",
                ]
            )
        )
    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return raw_path, summary_path


def print_summary(results: list[BenchResult], *, context: int, runs: int, n_predict: int) -> None:
    if len(results) != 2:
        return

    pinned, master = results
    delta_prompt = master.prompt_tps - pinned.prompt_tps
    delta_gen = master.gen_tps - pinned.gen_tps
    delta_prompt_pct = (delta_prompt / pinned.prompt_tps * 100.0) if pinned.prompt_tps else 0.0
    delta_gen_pct = (delta_gen / pinned.gen_tps * 100.0) if pinned.gen_tps else 0.0

    print("\nConfiguration")
    print(f"  model:    {MODEL_PATH.name}")
    print(f"  context:  {context}")
    print(f"  runs:     {runs}")
    print(f"  predict:  {n_predict}")

    print("\nResults")
    print(
        f"  pinned  {pinned.target.version:<24} "
        f"prompt={pinned.prompt_tps:6.1f} tok/s  gen={pinned.gen_tps:6.1f} tok/s"
    )
    print(
        f"  master  {master.target.version:<24} "
        f"prompt={master.prompt_tps:6.1f} tok/s  gen={master.gen_tps:6.1f} tok/s"
    )

    print("\nDelta (master - pinned)")
    print(f"  prompt: {delta_prompt:+.1f} tok/s ({delta_prompt_pct:+.2f}%)")
    print(f"  gen:    {delta_gen:+.1f} tok/s ({delta_gen_pct:+.2f}%)")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=DEFAULT_RUNS, help=f"Benchmark runs per build (default: {DEFAULT_RUNS})")
    parser.add_argument(
        "--n-predict",
        type=int,
        default=DEFAULT_N_PREDICT,
        help=f"Generated tokens per request (default: {DEFAULT_N_PREDICT})",
    )
    parser.add_argument(
        "--context",
        type=int,
        default=DEFAULT_CONTEXT,
        help=f"Server context to benchmark (default: {DEFAULT_CONTEXT})",
    )
    parser.add_argument(
        "--pinned-port",
        type=int,
        default=DEFAULT_PINNED_PORT,
        help=f"Port for the deployed pinned service (default: {DEFAULT_PINNED_PORT})",
    )
    parser.add_argument(
        "--master-port",
        type=int,
        default=DEFAULT_MASTER_PORT,
        help=f"Port for the scratch upstream master benchmark (default: {DEFAULT_MASTER_PORT})",
    )
    parser.add_argument(
        "--rebuild-master",
        action="store_true",
        help="Force a rebuild of the isolated upstream master binary",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.pinned_port == args.master_port:
        die("--pinned-port and --master-port must differ")

    ensure_required_paths()

    print(f"model:         {MODEL_PATH}")
    print(f"context:       {args.context}")
    print(f"runs:          {args.runs}")
    print(f"n_predict:     {args.n_predict}")

    pinned = pinned_target()
    master = build_master_if_needed(force_rebuild=args.rebuild_master)

    print(f"pinned:        {pinned.version}")
    print(f"master:        {master.version}")

    results: list[BenchResult] = []
    master_proc: subprocess.Popen[str] | None = None
    pinned_proc: subprocess.Popen[str] | None = None
    restore_service = False

    try:
        live_code = health_code(args.pinned_port)
        if live_code == 200:
            print(f"\nusing live pinned service on :{args.pinned_port}")
            results.append(
                benchmark_target(
                    pinned,
                    source="live-service",
                    port=args.pinned_port,
                    runs=args.runs,
                    n_predict=args.n_predict,
                )
            )
            if service_was_active("llama-server"):
                print("\nstopping live llama-server.service before master benchmark...")
                stop_service("llama-server")
                restore_service = True
        else:
            print(f"\nlaunching pinned benchmark server on :{args.pinned_port}")
            pinned_proc = launch_target(pinned, port=args.pinned_port, context=args.context)
            print("waiting for pinned readiness...", end=" ", flush=True)
            wait_for_server(args.pinned_port)
            print("ready")
            results.append(
                benchmark_target(
                    pinned,
                    source="launched-binary",
                    port=args.pinned_port,
                    runs=args.runs,
                    n_predict=args.n_predict,
                )
            )
            terminate_process(pinned_proc)
            pinned_proc = None

        print(f"\nlaunching master benchmark server on :{args.master_port}")
        master_proc = launch_target(master, port=args.master_port, context=args.context)
        print("waiting for master readiness...", end=" ", flush=True)
        wait_for_server(args.master_port)
        print("ready")
        results.append(
            benchmark_target(
                master,
                source="scratch-build",
                port=args.master_port,
                runs=args.runs,
                n_predict=args.n_predict,
            )
        )
    finally:
        terminate_process(master_proc)
        terminate_process(pinned_proc)
        if restore_service:
            print("\nrestoring llama-server.service...")
            start_service("llama-server")

    print_summary(results, context=args.context, runs=args.runs, n_predict=args.n_predict)
    raw_path, summary_path = write_artifacts(
        results,
        runs=args.runs,
        n_predict=args.n_predict,
        context=args.context,
    )
    print("\nArtifacts")
    print(f"  raw:     {raw_path}")
    print(f"  summary: {summary_path}")


if __name__ == "__main__":
    main()
