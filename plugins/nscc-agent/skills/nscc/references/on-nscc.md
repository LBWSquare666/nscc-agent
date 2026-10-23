# Running Claude Code on NSCC itself

The other way to use this skill: install Claude Code on the ASPIRE 2A login node, keep it alive in `tmux`, and steer it from your phone or any browser with [Remote Control](https://code.claude.com/docs/en/remote-control). Your own computer can be off.

Install tested in October 2026 on `asp2a-login-ntu01` (Claude Code 2.1.309). **Remote Control on NSCC has not been verified yet**; see [step 4](#4-remote-control).

## Which way to use

| | A. Agent on your computer (default) | B. Agent on NSCC (this page) |
|---|---|---|
| Where the agent runs | Your laptop / desktop, through the SSH socket | The NSCC login node, inside `tmux` |
| Your computer | Must stay on and online the whole time | Only needed to start it; can be off afterwards |
| Watching from your phone | Only if that computer is still running | Claude app / claude.ai/code, from anywhere |
| Agents | Claude Code and Codex | Claude Code only (Codex not tested; npm is blocked on NSCC) |
| Login | Password once per socket; sleep or network change drops it | Password once per `tmux` session; survives your computer sleeping |
| Code and data | Stay on your computer; `put`/`get` sync them | Already on NSCC; nothing to upload. Edit there, or `git pull` on the login node |
| Speed | Each command is an SSH round trip | Commands run directly |
| Install on NSCC | Nothing | Claude Code in `~/.local/bin` (from `downloads.claude.ai`) |
| Account | Any Claude Code / Codex login, API key included | Remote Control needs a claude.ai Pro, Max, Team or Enterprise login (no API key); Team/Enterprise owner must enable it |
| What stops it | Laptop sleeps, network changes, chat closed | Login-node reboot or maintenance, the process being killed, ~30 min without reaching Anthropic |
| Windows | WSL2 only | Any (VS Code Remote-SSH to start it) |
| Shared machine | Login state stays on your computer | Claude login token lives in `~/.claude` on a shared login node (mode 600) |

**Rule of thumb:** A at your desk, B for overnight and weekend runs. Both can be used on the same account; jobs and logs are the same either way.

## 1. Install

NSCC blocks `claude.ai`, so the official `curl -fsSL https://claude.ai/install.sh | bash` fails with `SSL_ERROR_SYSCALL`. That URL only redirects to `downloads.claude.ai`, which is reachable, so run the same installer from there. In a terminal **on NSCC** (VS Code Remote-SSH, or your own `ssh`):

```bash
curl -fsSL https://downloads.claude.ai/claude-code-releases/bootstrap.sh | bash
grep -q 'HOME/.local/bin' ~/.bashrc || echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"
claude --version
```

| Host | Use | From the login node |
|---|---|---|
| `claude.ai` | official install entry | blocked |
| `downloads.claude.ai` | installer, binary, auto-update | reachable |
| `api.anthropic.com` | Claude Code at run time, Remote Control | reachable |
| `registry.npmjs.org` | npm install | blocked — don't use npm |

If `downloads.claude.ai` is ever blocked too: download `https://downloads.claude.ai/claude-code-releases/<version>/linux-x64/claude` on your computer (`<version>` from `.../claude-code-releases/latest`), `scp` it to NSCC, then `chmod +x claude && ./claude install`.

## 2. Add the skill and project rules

Install the skill on NSCC with `install.sh` (from a clone, or the `curl … | bash` one-liner in the README; both need GitHub). In the project directory, write a `CLAUDE.md`:

```markdown
- You are running on an NSCC login node. Light work only: edit files, read logs, qstat, qsub.
- Training, rendering and other heavy work always go to a compute node with qsub.
```

## 3. Start it inside tmux

```bash
hostname                     # note it: asp2a-login-ntu01 or -ntu02
tmux new -s cc               # later: tmux attach -t cc
cd /scratch/users/<org>/<user>/<project>
claude --remote-control      # first run: trust the folder, then /login
```

- **`tmux` is required.** Without it, closing VS Code or SSH kills `claude`.
- **Two login nodes.** `aspire2antu.nscc.sg` picks one at random, and `tmux` exists only on the node that started it. If `tmux attach` says `no sessions`, you landed on the other node: `ssh <noted hostname>` from there, then attach.
- **First login:** `/login` prints a link; open it on your computer or phone, approve, paste the code back.
- Detach with `Ctrl-b d`. Close VS Code and the computer; `claude` keeps running.

## 4. Remote Control

Open the session from the Claude app (**Code** tab) or [claude.ai/code](https://claude.ai/code). Online sessions show a computer icon with a green dot. You can also run `/remote-control` inside the session for its URL and a QR code.

- Remote Control only makes outbound HTTPS requests to Anthropic's API and opens no ports. It should therefore work on NSCC even though `claude.ai` is blocked there: your phone or browser opens claude.ai, not the login node. **Not verified on NSCC yet.** If it fails, the session still works from the terminal.
- Use the interactive `claude --remote-control`, not server mode (`claude remote-control`): server mode exits after ~10 minutes without network, while an interactive session keeps retrying.
- Permission prompts and questions appear on your phone; until you answer, Claude waits.
- If it says `could not reach the Remote Control server for about 30 minutes`, attach to `tmux` and run `/remote-control`.

## 5. When it stops

Login-node maintenance, a reboot, or NSCC cleaning up long-running processes ends the `tmux` session. Jobs keep running. Someone has to log in with the password again (from off campus too, for `aspire2antu.nscc.sg`), then:

```bash
tmux new -s cc
cd <project> && claude --continue --remote-control
```

`--continue` brings back the last conversation in that directory; `nscc.sh jobs` shows what ran in the meantime.

## Security

- The Claude login token is stored in `~/.claude/` on a shared machine. Check that only you can read it: `chmod -R go-rwx ~/.claude`.
- Anyone who can read your NSCC home can use that token; log out with `/logout` when you stop using this setup.
- On a Pro or Max plan you can turn on **Require trusted devices** in your claude.ai settings so only your own devices can steer Remote Control sessions.
