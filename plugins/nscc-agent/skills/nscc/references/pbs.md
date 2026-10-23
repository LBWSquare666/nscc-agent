# PBS on ASPIRE 2A

## Queues and limits

| Item | Value |
|---|---|
| Submit to | `-q normal` (routed automatically) |
| Routing | 1 GPU → `g1`, 2–3 GPUs → `g2`, 4 GPUs → `g3`, ≥ 5 GPUs → `g4`, > 24 h → `glong`; CPU-only → `q*` queues |
| GPU walltime | **> 2 h and ≤ 24 h** (request `02:10:00` for short jobs) |
| Concurrency | **1 running job per queue per user** — shared by every project on that account |
| Node | 4 × A100-SXM4-40GB, 128 cores, ~440 GB RAM |
| Per GPU | ~16 cores and ~110 GB RAM, e.g. `-l select=1:ncpus=16:ngpus=1:mem=110gb` |
| Billing | GPU hours × the project's SU rate (`myquota` shows the balance) |
| Start time | 1 GPU: often minutes (backfill). 2–3 GPUs: can be hours. Evenings are faster for big jobs |

## Job template

```bash
#!/bin/bash
#PBS -N myexp
#PBS -q normal
#PBS -l select=1:ncpus=16:ngpus=1:mem=110gb
#PBS -l walltime=04:00:00
#PBS -j oe
#PBS -o /scratch/users/ntu/<user>/<project>/logs/myexp.log
set -uo pipefail
cd /scratch/users/ntu/<user>/<project>
export PYTHONNOUSERSITE=1 HF_HOME=/scratch/users/ntu/<user>/hf
nvidia-smi -L
.venv/bin/python train.py --out runs/${PBS_JOBID%%.*} 2>&1 | tee runs/progress_${PBS_JOBID%%.*}.log
```

- `-P <project>` is added by `nscc.sh submit` from `NSCC_PROJECT` (or put `#PBS -P <project>` in the script).
- Pass variables with `qsub -v A=1,B=2 job.pbs`.
- Chain jobs: `qsub -W depend=afterany:<jobid> next.pbs`.
- Several GPUs in one job, one process each: `CUDA_VISIBLE_DEVICES=$i python worker.py --shard $i/$N &` in a loop, then `wait`.

## Commands

| Task | Command |
|---|---|
| My jobs | `qstat -u <user>` |
| Why queued | `qstat -f <jobid> \| grep comment` |
| Cancel | `qdel <jobid>` |
| Balance / disk | `myquota` |
| Interactive (debug only) | `qsub -I -q normal -l select=1:ncpus=16:ngpus=1:mem=110gb -l walltime=02:10:00 -P <project>` |

## Monitoring from the agent

Do not loop in the foreground. Start a background command and let the agent be woken when it exits:

```bash
scripts/nscc.sh wait <jobid> /scratch/users/ntu/<user>/<project>/logs/myexp.log
```

Long training: save checkpoints to scratch at a sensible interval (tens of GB written to Lustre every few minutes slows training noticeably); resubmit with `--resume` when walltime runs out.
