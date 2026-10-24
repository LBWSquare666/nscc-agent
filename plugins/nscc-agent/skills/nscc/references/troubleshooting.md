# Troubleshooting

| Symptom | Cause → fix |
|---|---|
| `nscc.sh check` exits 2 / `Permission denied (gssapi-keyex,gssapi-with-mic,password)` | The socket is gone (laptop slept, network changed, reboot). Ask the user to run the login command again in their own terminal. Do not try other auth methods |
| `Control socket connect(...): No such file or directory` | Same as above |
| `Could not resolve hostname` | DNS or VPN. Hosts other than `aspire2antu.nscc.sg` (e.g. NUS) need the institution VPN off campus |
| `Connection timed out` / login command hangs | Network path: VPN not connected, or a network that blocks port 22. Test with `nc -vz -w 5 <host> 22` (macOS: `nc -vz -G 5 <host> 22`) |
| `Connection closed by remote host` right after login | Account or project not active, or NSCC login maintenance. Check [status.nscc.sg](https://status.nscc.sg) |
| Key host: `Permission denied (publickey…)` | Key not registered in the NSCC portal, wrong `NSCC_USER`, or wrong `NSCC_KEY` path. `ssh -v -i <key> <user>@<host>` shows which key was offered |
| Hugging Face `401 Unauthorized` only inside jobs | `HF_HOME` moved to scratch, so the home token is not read. Copy it: `install -m 600 ~/.cache/huggingface/token $HF_HOME/token` |
| Windows: `getsockname failed`, `ControlPath not supported` | Native Windows OpenSSH has no ControlMaster. Use WSL2 and run the agent inside WSL |
| Pasted login command fails with `^[[200~ssh: command not found` | The terminal pasted bracketed-paste escape codes. Type the command, or paste again without the stray characters |
| Job stays `Q`, comment `Insufficient amount of resource: node_pool` | That GPU-count queue is full. Use 1 GPU if possible, or wait (evenings are faster) |
| A second job of the same size stays `Q` while the first runs | One running job per queue per user. It starts when the first ends |
| Job ends at once, log shows `FileNotFoundError: /usr/bin/...` | A path hard-coded for another machine. Resolve tools from `PATH` (`shutil.which`) |
| `CUDA driver version is insufficient` inside a container | cu13x image without the compat library → `export APPTAINERENV_LD_LIBRARY_PATH=/usr/local/cuda/compat` |
| `apptainer: ... user namespaces` on the login node | Containers run only in jobs |
| `module load X` then `X: command not found` over ssh | Use the software's absolute path |
| Job log is empty while the job runs | PBS writes the `-o` log at the end. Tee your own progress log |
| Edited the job script but nothing changed | PBS copied it at submission. `qdel`, then resubmit |
| VS Code Remote-SSH keeps asking for a password | VS Code does not use the socket; type the password in its prompt. If it hangs: `pkill -u <user> -f vscode-server; rm -rf ~/.vscode-server/bin ~/.vscode-server/cli` on NSCC, then reconnect |
