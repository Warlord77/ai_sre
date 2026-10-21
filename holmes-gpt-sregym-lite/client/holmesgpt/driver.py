"""
HolmesGPT agent driver for SREGym.

Runs `holmes ask` in Docker against the problem's cluster and submits the
answer as the diagnosis. HolmesGPT is read-only, so a mitigation stage (if one
is requested) is submitted empty and will be graded as a failed mitigation.

Registered with `container_isolation: false`: the driver runs on the host,
and only HolmesGPT itself runs in a container.
  - Kubernetes: SREGym's filtered proxy kubeconfig ($KUBECONFIG), rewritten from
    127.0.0.1 to host.docker.internal (the proxy cert carries that SAN).
  - Observability: SREGym's Prometheus / Loki / Jaeger MCP servers (SSE).
"""

import json
import logging
import os
import subprocess
import sys
import tempfile
import time
from datetime import datetime
from pathlib import Path

import requests
import yaml

# Add SREGym root to path (this file is symlinked into SREGym/clients/holmesgpt)
sregym_root = Path(os.environ.get("SREGYM_ROOT", Path.cwd()))
if str(sregym_root) not in sys.path:
    sys.path.insert(0, str(sregym_root))

from clients.harness.problem_id import resolve_problem_id  # noqa: E402
from logger import init_logger  # noqa: E402

init_logger()

logger = logging.getLogger("all.holmesgpt.driver")

HOLMES_IMAGE = os.environ.get("HOLMES_IMAGE", "us-central1-docker.pkg.dev/genuine-flight-317411/devel/holmes:latest")
DOCKER_HOST_ALIAS = "host.docker.internal"
MCP_SERVERS = {
    "prometheus": "PromQL queries against the cluster Prometheus (metrics)",
    "loki": "LogQL queries against the cluster Loki (pod logs, including from deleted pods)",
    "jaeger": "Distributed traces from Jaeger (service call graph, latency, errors)",
}


def api_base() -> str:
    return f"http://{os.getenv('API_HOSTNAME', 'localhost')}:{os.getenv('API_PORT', '8000')}".replace(
        "0.0.0.0", "localhost"
    )


def mcp_base_for_container() -> str:
    port = os.getenv("MCP_SERVER_PORT", "9954")
    return f"http://{DOCKER_HOST_ALIAS}:{port}"


def get_stage() -> str | None:
    try:
        r = requests.get(f"{api_base()}/status", timeout=10)
        r.raise_for_status()
        return r.json().get("stage")
    except Exception as e:
        logger.debug(f"status check failed: {e}")
        return None


def wait_for_stage(allowed: set[str], timeout: int = 300) -> str | None:
    start = time.time()
    while time.time() - start < timeout:
        stage = get_stage()
        if stage in allowed:
            return stage
        if stage == "done":
            return stage
        time.sleep(2)
    return None


def submit(solution: str) -> None:
    r = requests.post(f"{api_base()}/submit", json={"solution": solution}, timeout=600)
    logger.info(f"Submit -> {r.status_code}: {r.text[:500]}")
    r.raise_for_status()


def build_prompt(app_info: dict) -> str:
    namespaces = app_info.get("namespaces") or [app_info.get("namespace", "default")]
    return f"""You are an SRE investigating an incident in a Kubernetes application.

Application: {app_info.get("app_name", "unknown")}
Namespace(s): {", ".join(namespaces)}

{app_info.get("descriptions", "")}

Something in this application is currently broken. Investigate using Kubernetes resources,
events, pod logs, metrics (Prometheus), logs (Loki) and traces (Jaeger).

Work autonomously; there is no human to answer questions.

Finish with a section titled "ROOT CAUSE" stating:
- the faulty component(s) (exact Kubernetes resource kinds and names)
- the root cause (what is misconfigured or failing, and why it breaks the application)
- the evidence you found
"""


def write_container_kubeconfig(workdir: Path) -> Path:
    """Copy $KUBECONFIG with loopback servers rewritten to host.docker.internal."""
    src = Path(os.environ.get("KUBECONFIG", Path.home() / ".kube" / "config"))
    config = yaml.safe_load(src.read_text())
    for cluster in config.get("clusters", []):
        c = cluster.get("cluster", {})
        server = c.get("server", "")
        for loopback in ("127.0.0.1", "localhost", "0.0.0.0"):
            server = server.replace(f"//{loopback}:", f"//{DOCKER_HOST_ALIAS}:")
        c["server"] = server
    out = workdir / "kubeconfig.yaml"
    out.write_text(yaml.safe_dump(config, sort_keys=False))
    out.chmod(0o644)
    return out


def write_holmes_config(workdir: Path) -> Path:
    config = {
        "toolsets": {
            "kubernetes/core": {"enabled": True},
            "kubernetes/logs": {"enabled": True},
        },
        "mcp_servers": {
            f"sregym-{name}": {
                "description": desc,
                "config": {"url": f"{mcp_base_for_container()}/{name}/sse", "mode": "sse"},
            }
            for name, desc in MCP_SERVERS.items()
        },
    }
    out = workdir / "holmes-config.yaml"
    out.write_text(yaml.safe_dump(config, sort_keys=False))
    return out


def run_holmes(prompt: str, logs_dir: Path, problem_id: str) -> tuple[int, str, dict]:
    workdir = Path(tempfile.mkdtemp(prefix="holmes-sregym-"))
    workdir.chmod(0o755)
    kubeconfig = write_container_kubeconfig(workdir)
    holmes_config = write_holmes_config(workdir)
    (workdir / "prompt.txt").write_text(prompt)

    model = os.environ.get("AGENT_MODEL_ID", "openrouter/anthropic/claude-sonnet-4-5")
    timeout = int(os.environ.get("HOLMES_TIMEOUT", "1500"))
    cmd = [
        "docker", "run", "--rm",
        "--add-host", f"{DOCKER_HOST_ALIAS}:host-gateway",
        "-e", "OPENROUTER_API_KEY",
        "-e", "KUBECONFIG=/work/kubeconfig.yaml",
        "-v", f"{workdir}:/work",
        HOLMES_IMAGE,
        "ask",
        "--prompt-file", "/work/prompt.txt",
        "--model", model,
        "--config", "/work/holmes-config.yaml",
        "--no-interactive",
        "--json-output-file", "/work/output.json",
        "--max-steps", os.environ.get("HOLMES_MAX_STEPS", "60"),
        "--log-costs",
    ]  # fmt: skip
    logger.info(f"Running HolmesGPT: {' '.join(cmd)}")
    logger.info(f"Holmes config:\n{holmes_config.read_text()}")
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
        rc, stdout, stderr = r.returncode, r.stdout, r.stderr
    except subprocess.TimeoutExpired as e:
        rc, stdout, stderr = 124, (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or ""), "timeout"

    logs_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    (logs_dir / f"holmes_{problem_id}_{stamp}.log").write_text(f"$ rc={rc}\n--- stdout ---\n{stdout}\n--- stderr ---\n{stderr}")

    output = {}
    out_json = workdir / "output.json"
    if out_json.exists():
        try:
            output = json.loads(out_json.read_text())
        except json.JSONDecodeError:
            pass
        (logs_dir / f"holmes_{problem_id}_{stamp}.json").write_text(out_json.read_text())

    answer = output.get("result") or output.get("analysis") or stdout.strip()
    return rc, answer, output


def main():
    logs_dir = Path(os.environ.get("AGENT_LOGS_DIR", "./logs/holmesgpt"))
    if wait_for_stage({"diagnosis", "mitigation"}) is None:
        logger.error("Conductor never reached a submission stage")
        sys.exit(1)

    app_info = requests.get(f"{api_base()}/get_app", timeout=30).json()
    problem_id = resolve_problem_id(cli_problem_id=None)
    logger.info(f"Problem ID (harness): {problem_id}; app: {app_info}")

    stage = get_stage()
    rc = 0
    if stage == "diagnosis":
        rc, answer, _ = run_holmes(build_prompt(app_info), logs_dir, problem_id)
        if not answer:
            answer = "HolmesGPT produced no answer."
        logger.info(f"HolmesGPT answer:\n{answer}")
        submit(answer)
        stage = wait_for_stage({"mitigation"}, timeout=120)

    if stage == "mitigation":
        # HolmesGPT is read-only by design and never changes the cluster.
        logger.info("Mitigation stage: HolmesGPT does not remediate; submitting empty mitigation")
        submit("")

    sys.exit(0 if rc in (0, None) else rc)


if __name__ == "__main__":
    main()
