# HolmesGPT on SREGym — VM setup

Runs HolmesGPT (Docker) against an SREGym kind cluster on an Ubuntu VM, using `gpt-oss-120b` on the
one2n GPUStack for both the agent and SREGym's judge. HolmesGPT is connected to SREGym's Prometheus,
Loki and Jaeger MCP servers.

Run every command from this folder. `make help` lists all targets.

---

## 1. Layout

```
vm-test/
├── Makefile                 # every step below as a target
├── .env.example             # copy to .env and set OPENAI_API_KEY (.env is git-ignored)
├── client/holmesgpt/        # SREGym agent driver (linked into SREGym/clients/holmesgpt)
│   └── driver.py
└── scripts/
    ├── lib.sh               # loads .env, docker/tunnel helpers
    ├── 01-install-docker.sh # sudo: Docker, docker group, inotify limits, make
    ├── 02-install-tools.sh  # kind, kubectl, Helm 4, uv → ~/.local/bin
    ├── 03-create-cluster.sh # SREGym kind cluster + 4 GB cap per node
    ├── 04-setup-sregym.sh   # submodules, uv sync, pre-commit hook
    ├── 05-pull-holmes.sh    # HolmesGPT image
    ├── check-model.sh       # tunnel, model listed, tool calls parsed
    ├── holmes-ask.sh        # ad-hoc `holmes ask` against the cluster (--mcp adds SREGym MCP)
    ├── mcp-server.sh        # start/stop SREGym's MCP server outside a benchmark run
    ├── install-tailscale.sh # optional, see "Model access"
    └── run-list.sh          # several problems one at a time
```

---

## 2. How it fits together

```
SREGym conductor ──(fault injected)──► app namespace on kind-kind (1 control plane + 3 workers)
      │  GET /status, /get_app                      ▲
      ▼                                             │ SREGym filtered K8s proxy :16443
client/holmesgpt/driver.py (host)                   │
      │  docker run --network host holmes ask ...   │
      ▼                                             │
HolmesGPT container ────────────────────────────────┘
      ├── kubernetes/core, kubernetes/logs, helm, bash
      ├── MCP (SSE) 127.0.0.1:9954: sregym-prometheus, sregym-loki, sregym-jaeger
      └── LLM: https://gpustack.apps.one2n.io:8443/v1 ──► 127.0.0.1:8443 (SSH tunnel) ──► GPUStack
      ▼
answer ──► POST /submit ──► SREGym judge (same model, same tunnel)
```

The container uses the host network because the SSH tunnel only listens on the host's loopback.
`host.docker.internal` and the GPUStack hostname both map to `127.0.0.1`, so TLS still validates
against GPUStack's real certificate.

---

## 3. Host and tools

```bash
make docker          # sudo: Docker, docker group, inotify limits, make
make tools           # kind v0.27.0, kubectl, Helm 4, uv into ~/.local/bin
```

- `sudo` needs a real terminal; it can't read a password from Claude Code's `!` prompt.
- Log out and back in after `make docker` for the docker group to apply. Until then the scripts use `sg docker`.

---

## 4. Cluster (16 GB)

```bash
make cluster
```

Runs `SREGym/kind/setup_kind_cluster.sh` unchanged, then caps memory:

| Setting | Value |
|---|---|
| Nodes | 1 control plane, 3 workers |
| Node image | `ghcr.io/sregym/kind-node:sha-b97d681…` (kind node + `udev`, `socat`), Kubernetes v1.32.1 |
| Mounts | `/run/udev` on every node |
| CNI | default disabled; Calico v3.29.3 |
| Memory | `docker update --memory 4g --memory-swap 4g` per node = **16 GB** |

kind has no memory setting, so the cap is applied to each node container. It survives restarts but not
a recreated cluster; rerun `make cluster` after recreating. Change it with `NODE_MEMORY=6g make cluster`.

Delete the cluster with `kind delete cluster --name kind`.

---

## 5. SREGym and HolmesGPT

```bash
make sregym          # git submodule update --init --recursive, uv sync, prek install
make holmes          # docker pull the HolmesGPT image
cp .env.example .env # then set OPENAI_API_KEY to your GPUStack key
make install         # link client/holmesgpt into SREGym, register agent 'holmesgpt'
```

`make setup` runs `tools cluster sregym holmes install` in one go.

`.env` settings:

| Variable | Value |
|---|---|
| `OPENAI_API_BASE` | `https://gpustack.apps.one2n.io:8443/v1` (through the tunnel) |
| `OPENAI_API_KEY` | GPUStack key |
| `MODEL`, `JUDGE_MODEL` | `openai/gpt-oss-120b` |
| `HOLMES_NETWORK` | `host` |
| `HOLMES_EXTRA_HOSTS` | `gpustack.apps.one2n.io:127.0.0.1` |
| `KUBE_CONTEXT` | `kind-kind` |
| `PROFILE` | `full` |

---

## 6. Model access

GPUStack resolves to a private address (`10.3.58.6`) that the VM can't reach directly.

### SSH reverse tunnel (current)

From a laptop that is on the one2n VPN:

```bash
ssh -R 8443:gpustack.apps.one2n.io:443 w77@<vm>
```

While that session is open, `127.0.0.1:8443` on the VM reaches GPUStack. Keep it open for the whole run.

SREGym's judge runs on the host, not in Docker, so the host must also resolve the GPUStack name to the tunnel:

```bash
make hosts-entry     # sudo: adds "127.0.0.1 gpustack.apps.one2n.io" to /etc/hosts
```

### Headscale (alternative)

Needs the VM's public IP (`103.121.155.94`) allowed by the Headscale server first; it currently drops
the VM's traffic.

```bash
sudo bash scripts/install-tailscale.sh
tailscale up --login-server https://headscale.one2n.io --accept-routes
```

With Headscale, set `OPENAI_API_BASE=https://gpustack.apps.one2n.io/v1`, clear `HOLMES_EXTRA_HOSTS`,
and skip `make hosts-entry`.

### Model server requirements

HolmesGPT works only through tool calls, so the vLLM deployment must parse them:

| Model | vLLM backend parameters |
|---|---|
| `gpt-oss-120b` | `--enable-auto-tool-choice --tool-call-parser openai` |
| Qwen3 family | `--enable-auto-tool-choice --tool-call-parser qwen3_coder --reasoning-parser qwen3` |

The key also needs access to the model in GPUStack (otherwise `403 Not allowed to access model`).
`make check-model` tells these apart: a missing parser returns 400, a wrong parser returns an empty reply.

---

## 7. Checks

```bash
make check-model     # tunnel up, model listed, tool call parsed
make smoke           # holmes ask about kube-system, Kubernetes toolsets only
make mcp-smoke       # starts SREGym's MCP server, holmes ask with sregym-* MCP attached
make mcp-stop        # stop that MCP server
make preflight       # everything a benchmark run needs
```

`mcp-smoke` only checks that the MCP servers connect; Prometheus, Loki and Jaeger themselves are
installed by SREGym during a problem run.

Ad-hoc questions: `scripts/holmes-ask.sh "why is pod X crashing?" [--mcp]`.

---

## 8. Running SREGym

```bash
make run-one PROBLEM=network_policy_block
make run-lite                                   # all 17 SREGym-Lite problems
make run-list PROBLEMS="<id> <id> ..."
```

Start the OpenEBS watchdog in another terminal first. It unsticks PVCs left Pending when the OpenEBS
provisioner restarts mid-provision (symptom: MongoDB pods stuck Pending):

```bash
scripts/openebs-watchdog.sh
```

Defaults: `--stages diagnosis` (HolmesGPT is read-only), `--profile full`, `--internet-access open`.
Answers and HolmesGPT logs go to SREGym's `results/` and `logs/holmesgpt/`.

`make uninstall` removes the client link and the `agents.yaml` entry from SREGym.
