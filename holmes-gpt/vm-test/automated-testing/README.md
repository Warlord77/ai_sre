# Automated HolmesGPT testing on SREGym-Lite

Run any of the 17 [SREGym-Lite](https://github.com/SREGym/SREGym/blob/main/docs/SREGym-Lite.md) problems
against HolmesGPT (Docker) with the model of your choice, using one Makefile:

- **self-hosted LLM**: any OpenAI-compatible endpoint (vLLM, GPUStack, Ollama, a LiteLLM proxy)
- **Claude**: an Anthropic API key
- **OpenRouter**: an OpenRouter API key

It reuses the HolmesGPT SREGym driver in [`../client/holmesgpt/`](../client/holmesgpt/driver.py) and the
VM setup scripts in [`../scripts/`](../scripts/). For the machine setup itself see [`../setup.md`](../setup.md).

## Quick start

```bash
cd holmes-gpt/vm-test/automated-testing
cp .env.example .env          # set PROVIDER and that provider's key (see below)
make setup                    # tools, cluster, SREGym, HolmesGPT image, model check, driver
make list                     # the 17 problems with their numbers
make run P=3                  # run one
make pick                     # or choose interactively
make summary                  # results of the latest run
```

## Choosing a model

Set `PROVIDER` in `.env` and fill in only that block:

| `PROVIDER` | Needs | Default model (LiteLLM form) |
|---|---|---|
| `selfhosted` | `OPENAI_API_BASE`, `OPENAI_API_KEY`, `SELFHOSTED_MODEL` | `openai/<SELFHOSTED_MODEL>` |
| `claude` | `ANTHROPIC_API_KEY` (`CLAUDE_MODEL` optional) | `anthropic/claude-opus-5-5` |
| `openrouter` | `OPENROUTER_API_KEY` (`OPENROUTER_MODEL` optional) | `openrouter/anthropic/claude-opus-5.5` |

- Only the selected provider's credentials are passed to HolmesGPT; the others are unset.
- SREGym's judge uses the same model unless `JUDGE_MODEL` is set (LiteLLM form, e.g. `anthropic/claude-opus-5-5`).
- Check the OpenRouter slug at openrouter.ai/models; slugs use dots (`claude-opus-5.5`).
- Self-hosted behind an SSH tunnel: point `OPENAI_API_BASE` at the tunnel's port and map the hostname
  with `HOLMES_EXTRA_HOSTS=<host>:127.0.0.1` (the host also needs `127.0.0.1 <host>` in `/etc/hosts`
  for the judge).

`make check-model` sends one tool-calling request through LiteLLM, the library both HolmesGPT and the
judge use, and fails with the provider's error if the model can't answer it. HolmesGPT does all of its
work through tool calls, so a model that can't return one can't run the benchmark. Common causes:

| Symptom | Fix |
|---|---|
| `"auto" tool choice requires --enable-auto-tool-choice` (vLLM) | Start the model with `--enable-auto-tool-choice --tool-call-parser <parser>` (`openai` for gpt-oss, `qwen3_coder` or `hermes` for Qwen) |
| Answer with no tool call, `finish_reason=stop` | Wrong `--tool-call-parser` for the model |
| `403 Not allowed to access model` / `404 Model not found` | The key can't use that model, or it isn't deployed |
| `temperature` rejected (Claude) | Since 2026-10-21 the Claude API rejects `temperature`/`top_p`/`top_k`; use a HolmesGPT/LiteLLM version that doesn't send them |

## Choosing problems

`make run P=<selection>`:

| Selection | Runs |
|---|---|
| `P=3` | problem 3 (`network_policy_block`) |
| `P=1,4,7` | problems 1, 4 and 7 |
| `P=2-5` | problems 2 to 5 |
| `P=all` | all 17 |
| `P=network_policy_block` | by id; ids and numbers can be mixed |

`make pick` shows the numbered list, asks for a selection and confirms before running.

Problems run one at a time: SREGym deploys the app, injects the fault, starts HolmesGPT through the
driver, and has its LLM judge grade the diagnosis. Only the diagnosis stage runs (HolmesGPT is read-only).
If another SREGym run is in progress, the next problem waits for it, and each problem is skipped if the
model check fails right before it.

## Results

Each run goes to `results/<YYYYMMDD_HHMM>/`:

- `summary.csv`: `problem,verdict,score,minutes` (verdict: `pass`, `fail`, `error` = judge failed, `skipped`)
- `<problem>.log`: SREGym's console output
- `<problem>/`: HolmesGPT transcript (`holmes_*.log`), its JSON output with every tool call and token
  count (`holmes_*.json`), SREGym's log, and the judge's result row (`<problem>_results.csv`)

Provider keys are redacted from everything collected. `make summary` prints the latest run's table
(`make summary RUN=results/<stamp>` for an older one).

## Layout

```
automated-testing/
├── Makefile            # setup, check-model, install, list, pick, run, summary
├── .env.example        # provider blocks; copy to .env (git-ignored)
└── scripts/
    ├── common.sh       # loads .env, maps PROVIDER to LiteLLM model strings, problem selection
    ├── setup.sh        # setup steps (also: scripts/setup.sh <tools|cluster|sregym|holmes|model|install>)
    ├── check-model.py  # one LiteLLM tool-call request against the model
    ├── run.sh          # run selected problems and collect results
    ├── pick.sh         # interactive menu
    └── summary.sh      # results table
```

## Defaults worth knowing

| Setting | Default | Why |
|---|---|---|
| `PROFILE` | `full` | SREGym's standard stack; `svelte` for machines with under 16 GB |
| HolmesGPT network | host | SREGym's Kubernetes proxy, its MCP port-forward and SSH tunnels all listen on `127.0.0.1` |
| `HOLMES_MAX_STEPS` | 60 | Tool-calling steps per investigation |
| `WAIT_FOR_POD_READY_TIMEOUT` | 1800 s | Cold image pulls and slow deploys exceed SREGym's 600 s default |

HolmesGPT's built-in `tcp_check` runs in its container on the host, where cluster DNS names don't
resolve; its "could not resolve host" results are not cluster evidence (see the
[benchmark README](../README.md), run note 2).
