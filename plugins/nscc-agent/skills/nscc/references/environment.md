# ASPIRE 2A environment notes

Tested in October 2026 on ASPIRE 2A GPU nodes. Check NSCC's own documentation ([help.nscc.sg](https://help.nscc.sg)) when something here disagrees with what you see.

## Login hosts

| Who | Host | Notes |
|---|---|---|
| NTU users | `aspire2antu.nscc.sg` | Reachable off campus. **Password only** (no SSH keys). Host key `SHA256:vxgy6AWm2WeyHyONvzWxBEeBuZ6OAvwHVDjNKvD/jfo` (ED25519) |
| NUS users | `aspire2a.nus.edu.sg` | Needs NUS VPN off campus. Reportedly accepts an SSH key generated in the NSCC portal (not tested here): set `NSCC_KEY` and `nscc.sh` logs in by itself. Scratch is `/scratch/users/nus/<user>/` |
| Other institutions | see your NSCC account e-mail | Some hosts need your institution's VPN first |

`aspire2antu.nscc.sg` lands on one of two login nodes at random; a `tmux` session lives only on the node that started it.

From the login node, `claude.ai` and `registry.npmjs.org` are blocked; `downloads.claude.ai` and `api.anthropic.com` are reachable (see `on-nscc.md`).

## Storage

| Path | Size | Use |
|---|---|---|
| `~` (home) | ~50 GB | config, small scripts |
| `/scratch/users/<org>/<user>/` | large (check with `myquota`) | data, venvs, caches, outputs — **purged periodically**, copy results back |

## Software

| Item | What works |
|---|---|
| GPU driver | 570 (CUDA 12.8) |
| Python | install `uv` (`curl -LsSf https://astral.sh/uv/install.sh \| sh`) → `~/.local/bin/uv`; create venvs on scratch |
| PyTorch / JAX | cu12x builds work directly. JAX on a 40 GB A100: `XLA_PYTHON_CLIENT_MEM_FRACTION=0.95` for large models |
| cu13x builds (e.g. vLLM 0.30) | driver too old → run inside a container with `APPTAINERENV_LD_LIBRARY_PATH=/usr/local/cuda/compat` |
| Containers | `module load apptainer/1.5.0`; **compute nodes only** (login nodes disable user namespaces). Pull images inside a job: `apptainer pull x.sif docker://<image>`; run: `apptainer exec --nv -B /scratch x.sif <cmd>` |
| `~/.local` packages | can clash with venv/container packages → `PYTHONNOUSERSITE=1` |
| Internet | login and compute nodes reach the internet directly (Hugging Face, PyPI, APIs). The proxy mentioned in older ASPIRE 2A+ guides is not needed here |
| MuJoCo | `MUJOCO_GL=egl` works on compute nodes |
| Blender | `pip install bpy` works on compute nodes; A100 has no RT cores, use the CUDA device |
| ffmpeg | `module load` is unreliable over non-interactive ssh; call `/app/apps/ffmpeg/5.0.1/ffmpeg` directly (static build with x264/x265/aac) |
| Not available | `git` on compute nodes, docker, systemd user units, system fonts on compute nodes |

## Cache variables (put them in every job and install session)

```bash
S=/scratch/users/ntu/<user>
export UV_CACHE_DIR=$S/cache/uv UV_PYTHON_INSTALL_DIR=$S/cache/py XDG_CACHE_HOME=$S/cache HF_HOME=$S/hf PYTHONNOUSERSITE=1
```

**Hugging Face token pitfall.** Once `HF_HOME` points to scratch, `huggingface_hub` no longer reads the token from `~/.cache/huggingface/token`, so gated or private repos fail with `401 Unauthorized` inside jobs even though `hf auth whoami` works on the login node. Fix it once, without printing the token:

```bash
mkdir -p $S/hf && install -m 600 ~/.cache/huggingface/token $S/hf/token
```

Or log in with `HF_HOME` already set, or pass `HF_TOKEN` to the job (`qsub -v HF_TOKEN …`; it then shows in `qstat -f`). In logs, print only whether a token exists and its length.

## Probe job (validate a new environment first)

```bash
nvidia-smi -L
.venv/bin/python -c "import torch; print(torch.__version__, torch.cuda.is_available())"
curl -s -o /dev/null -w 'hf %{http_code}\n' https://huggingface.co
```
