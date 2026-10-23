---
name: nscc
description: Run and watch experiments on Singapore's NSCC supercomputer (ASPIRE 2A) — upload code and data, set up Python/CUDA/container environments, submit PBS jobs, keep watching them until they finish, read the logs, fix failures and resubmit, and fetch results — either from the user's own computer over an SSH connection they opened once with their own password, or from Claude Code running on the NSCC login node itself. Use when the user mentions NSCC, ASPIRE 2A, "the supercomputer", PBS/qsub jobs there, or asks to run, monitor, babysit or debug an experiment on NSCC.
---

# NSCC (ASPIRE 2A) for coding agents

NSCC accepts **passwords only**, which you must never type, store or forward. You run in one of two places:

- **A. On the user's computer** (usual): you reach NSCC through an SSH ControlMaster socket the user opened **once** in their own terminal. Every command below reuses that socket, with no password.
- **B. On the NSCC login node itself** (`hostname` starts with `asp2a-login`): Claude Code was installed there and the user may be steering you from their phone through Remote Control. There is no socket; commands run directly. Setup and limits: `references/on-nscc.md`.

Your main job is to **watch experiments for the user**: submit, wait, read logs, catch failures, fix, resubmit, report.

All commands go through `scripts/nscc.sh` in this skill's directory (call it by its full path). It reads `NSCC_USER`, `NSCC_HOST`, `NSCC_PROJECT` from the environment or from `~/.config/nscc/config`, and detects mode B from the hostname (`NSCC_LOCAL=1` forces it).

## 0. Mode B: running on NSCC

If `nscc.sh check` prints `running on NSCC itself`, skip section 1's connection step and keep these rules:

- `run`, `submit`, `jobs`, `status`, `tail`, `wait` work as below. `put`/`get` are not needed: files are already on NSCC (`cp`/`rsync` within NSCC, `git pull` on the login node).
- You share a **login node** with other users: edit, install, download, `qsub`, `qstat` only. Anything heavier than a few CPU-minutes goes in a PBS job.
- The user is often away. Prefer finishing a decision you are allowed to make over leaving a question open; when you must ask, ask one clear question and keep the job state in `docs/experiments.md` so nothing depends on the chat.
- You live in `tmux` on one of two login nodes. If you are restarted, run `nscc.sh jobs` and read `docs/experiments.md` before anything else.

## 1. Before anything: settings and connection

1. **Settings.** If `NSCC_USER` is unknown, ask the user for their NSCC username, login host (NTU: `aspire2antu.nscc.sg`; others: see `references/environment.md`) and PBS project id. Suggest they save them as `KEY=value` lines in `~/.config/nscc/config`. These are not secrets.
2. **Connection.** Run `scripts/nscc.sh check`.
   - `connected` → continue.
   - exit 2 → it prints one login command. Give that exact command to the user and ask them to run it **in their own terminal** (not through you), type their password, and tell you when it prints a hostname. Then check again.
3. **Never** use `sshpass`, `expect`, password files, or keyboard automation. Never ask the user to paste a password, token or API key into the chat. If a secret has to reach NSCC, give the user this command to run in their own terminal (reads the secret without echo, writes a 600-mode file):

   ```bash
   read -rsp 'Secret: ' S; echo; printf 'MY_KEY=%s\n' "$S" | ssh -o ControlPath=<socket> <user>@<host> 'umask 077; mkdir -p ~/.config/<app> && cat > ~/.config/<app>/secrets.env'; unset S
   ```

## 2. Commands

| Task | Command |
|---|---|
| Run on the login node | `nscc.sh run 'hostname; myquota'` |
| Run a multi-line script | `nscc.sh run <<'EOF'` … `EOF` (quoted heredoc: nothing expands locally) |
| Upload / download (resumable rsync) | `nscc.sh put <local> <remote> [--exclude .venv …]` · `nscc.sh get <remote> <local>` |
| Submit a PBS script | `nscc.sh submit job.pbs [qsub options]` → prints the job id |
| Recent jobs, finished ones too | `nscc.sh jobs` |
| One job | `nscc.sh status <jobid>` (state, queue comment, walltime, exit status, log path) |
| Read a log | `nscc.sh tail <remote file> [n]` |
| Block until a job ends | `nscc.sh wait <jobid> [log]` → exit 0 job succeeded · 1 job failed · 2 connection lost |

- Anything with quotes, loops or several lines: use the heredoc form, not a long one-liner.
- The login node is for editing, installing and downloading. CPU/GPU work goes in a PBS job.
- Do not edit `~/.ssh/config` or shell start-up files on the user's machine; the script does not need it.

## 3. Watching an experiment (the core loop)

1. **Before submitting**, make the job easy to watch: it should `tee` a progress log you can `tail` while it runs (PBS writes its own `-o` log only at the end), print a clear final line (e.g. `DONE` or metrics), and save checkpoints so it can resume.
2. **Submit**, note the job id, and tell the user what you submitted, the resources and the expected start time (1 GPU: usually minutes; 2–3 GPUs: can be hours).
3. **Wait in the background, never by polling in the foreground.** Start `nscc.sh wait <jobid> <log>` as a background command (Claude Code: `run_in_background`; Codex: a background terminal). You are woken when it exits; its exit code tells you success, failure, or a dropped connection.
4. **Long jobs:** while waiting, check progress at a slow pace (every 20–60 min, e.g. Claude Code `/loop`), each time with `status` + `tail` of the progress log. Look for: loss/metrics moving, NaN, `CUDA out of memory`, stalls (log not growing), walltime close to the limit.
5. **When it ends**, read `Exit_status` and the log tail, then:
   - success → `get` the results (or summarize them on NSCC if large) and report numbers, not just "done";
   - failure → find the cause (see `references/troubleshooting.md`), fix the script or config, resubmit, and go back to step 3. Ask the user first if the fix changes the experiment itself (model, data, hyper-parameters) or costs much more GPU time;
   - walltime hit → resubmit with resume.
6. **Keep a short log** of job ids, what changed and the outcome (in the project, e.g. `docs/experiments.md`), so the user and the next session can follow.

In mode A the socket lives on the user's computer: if it sleeps or goes offline, commands exit 2. Jobs keep running on NSCC, and PBS keeps their history, so nothing is lost: ask the user to log in again, run `jobs`, and carry on with `wait`/`status`. Suggest keeping the machine awake for long runs, or mode B (`references/on-nscc.md`) for overnight ones.

## 4. PBS rules that bite

Details and a job template: `references/pbs.md`.

- Submit with `-q normal`; PBS routes by GPU count (1 GPU → g1, 2–3 → g2, 4 → g3). **GPU walltime must be > 2 h** (use `02:10:00` even for short jobs) and ≤ 24 h.
- **One running job per queue per user**, across all of that user's projects. Parallel work = different GPU counts, or several processes inside one multi-GPU job.
- Prefer 1 GPU when it fits (A100 40 GB); it starts much sooner.
- PBS copies the script at submission — after editing it, `qdel` and resubmit.

## 5. Data and environments

Details: `references/environment.md`.

- Work in **scratch** (`/scratch/users/<org>/<user>/`, large but purged periodically — copy results back). Home is ~50 GB: no datasets, venvs or caches there.
- Large public data and model weights: download **on NSCC** (nodes have direct internet). Long downloads: `nohup … &` or `tmux` on the login node.
- Code: compute nodes have no `git`. Sync with `put` (exclude `.venv`, caches, outputs) or ship a `git bundle` and `git pull` it on NSCC.
- Caches on scratch (`UV_CACHE_DIR`, `UV_PYTHON_INSTALL_DIR`, `XDG_CACHE_HOME`, `HF_HOME`); `uv` venvs on scratch; `PYTHONNOUSERSITE=1` at run time.
- Driver 570 (CUDA 12.8): cu12x wheels work directly. **cu13x wheels need a container**: `module load apptainer/1.5.0` and `export APPTAINERENV_LD_LIBRARY_PATH=/usr/local/cuda/compat` in the job. Containers run only on compute nodes.
- Validate a new environment with a short probe job before the real one.
