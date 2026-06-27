# DEBUG HANDOFF — `sini`↔nix-daemon eval hang (UNRESOLVED)

> **Status:** unresolved after exhaustive black-box probing (2026-06-26). Spike doc for a
> fresh, focused session. Discovered while building the synthetic-fleet harness (Task 3a,
> `specs/2026-06-26-synthetic-fleet-harness-design.md`); it blocks evaluating the synth fleet
> as user `sini` but is a **general nix-environment bug, not a den/nix-config code bug**.
> A workaround exists (eval as root / direct store) — the harness proceeds on that.

## Symptom (one line)

Evaluating the synthetic-fleet flake **as user `sini` via the nix-daemon hangs 5 min+ (never
completes)**; the **identical eval as root, or against a direct (non-daemon) store, completes in
3–13 s**. It is `sini`-via-daemon-specific.

## Exact repro

Repo: `~/Documents/repos/sini/nix-config`, worktree `.worktrees/persist-claims-open-emit`
(branch `demo/persist-claims-open-emit`, the synth-fleet harness; `synthFleet.enable=true`).
FLAGS = `--extra-experimental-features "nix-command flakes pipe-operators" --accept-flake-config`.

```bash
cd .worktrees/persist-claims-open-emit
# HANGS 5min+ (4% CPU):
nix eval $FLAGS --apply 'x: builtins.length (builtins.attrNames x)' '.#nixosConfigurations'
# FAST 3s (root, direct store, no daemon):
sudo -n env NIX_REMOTE= nix eval $FLAGS --apply 'x: builtins.attrNames x' '.#nixosConfigurations'
# FAST 13s (root, WITH daemon):
sudo -n env NIX_REMOTE=daemon nix eval $FLAGS --apply '...' '.#nixosConfigurations'
# trivial flakes are FAST for sini (16s):  nix eval nixpkgs#hello.name
```
Real-fleet eval (synth disabled) is fast for `sini`; only the synth-enabled eval hangs → the
extra synth-host store interactions *expose* the issue, they aren't the root cause.

## The signature (what's measured)

- **Evaluator does ~nothing:** with a 24 GB heap, `NIX_SHOW_STATS` (written even on timeout)
  = `cpuTime ≈ 1.94 s`, **1 GC cycle (861 MB)**, across a 5-min wall. So NOT eval-CPU, NOT GC.
- **Client blocks on the daemon socket:** strace (eval launched as strace child) → main thread
  in one `read(fd 6, …, 32768)` for **87 s** (ERESTARTSYS on kill). fd 6 = `socket:[…]`,
  `wchan = unix_stream_read_generic`, = `/nix/var/nix/daemon-socket/socket`. **`read(6)` 362×,
  `write(6)` 0** in the window (writes happened pre-window at connection setup).
- **Daemon worker is IDLE:** `sudo strace -p <youngest nix-daemon worker>` for 15 s → **0
  syscalls**; `wchan = 0`/`unix_stream_read_generic`. Client at ~14 % CPU on one thread,
  ~16-thread pool idle in `futex`, **whole system idle**. → deadlock-like: client waits for a
  daemon response the idle daemon never sends.
- **Client also walks files first:** ~9558 `newfstatat` + 2707 `openat` (flake-source / git
  tree walk: `modules/…`, `pkgs/by-name`, `.git/worktrees/…/index`) — fast, *then* the 87 s
  daemon-socket block.

## RULED OUT (do not re-chase — each tested empirically)

- **den / nix-config code** — root eval = 3 s; the synth-fleet/den resolution is NOT the cost.
  (A mid-investigation `--trace-function-calls` showed 30 M calls in `nix-effects`/den resolve,
  but that's the *instrumented* eval; the real eval is 1.94 s CPU. Don't believe the trace.)
- **GC** — 1 cycle even at `GC_INITIAL_HEAP_SIZE=24g`.
- **Network** — `--offline` still hangs (no fast "cannot fetch" error).
- **IFD** — `--option allow-import-from-derivation false` didn't error-fast.
- **Substituters** — `--option substituters "" --option substitute false` still hangs.
- **Remote builders** — `--option builders ""` still hangs; `/etc/nix/machines` doesn't exist.
- **`remote-build-client` aspect** — REMOVED from `roles.default` + **deployed to cortex
  (`colmena apply-local`, nix-daemon restarted)** → **still hangs.** (The `nix __build-remote` /
  `LegacySSHStore::Connection` SIGABRT crash that pointed here was a **cold-cache-fetch
  artifact from clearing `sini`'s caches**, NOT the warm-cache hang. RED HERRING.)
- **eval-cache** — `--option eval-cache false` still hangs.
- **dirty flake** — clean (committed) flake still hangs.
- **daemon state** — `systemctl restart nix-daemon` then eval → still hangs.
- **client config** — `nix config show` for `sini` vs root differs only in privilege bits
  (`build-users-group`, `require-drop-supplementary-groups`); no rogue hook/store/timeout.
- **client concurrency / http2** — `--option max-jobs 1 --option http2 false
  --option max-substitution-jobs 1` still hangs.
- **stack ulimit** — `sini` and root both `ulimit -s = 8192` (hard unlimited).
- **`sini`'s caches corrupt** — moving `~/.cache/nix/{gitv3(4.7G),tarball-cache*,eval-cache*}`
  aside → eval **crashed** (the cold-fetch `LegacySSHStore` SIGABRT, the red herring) rather
  than hanging; caches restored. Inconclusive for the warm hang; a real cold-fetch crash bug
  may be separate (see below).

## THE definitive next tool (untried): `gdb` on BOTH processes at the stall

This is the one instrument not yet used and the most likely to crack it — read the actual C++
stacks of the stuck **client** and the **daemon worker** simultaneously while hung.

```bash
# 1. start the hanging eval (sini), get the client nix pid:
cd .worktrees/persist-claims-open-emit
nix eval $FLAGS --apply 'x: builtins.length (builtins.attrNames x)' '.#nixosConfigurations' & BG=$!
sleep 20; CLIENT=$(pgrep -P $BG | head -1)
# 2. the daemon worker serving it = youngest nix-daemon child of the main daemon:
WORKER=$(ps -eo pid,etimes,comm | awk '$3=="nix-daemon"{print $2,$1}' | sort -n | head -1 | awk '{print $2}')
# 3. dump both C++ backtraces (all threads). Need nix/lix DEBUG symbols for a useful trace —
#    build/run `nixVersions.latest` or `lix` with debug info, or `nix-store -r` the debug output.
sudo gdb -p $CLIENT -batch -ex 'thread apply all bt' 2>&1 | tee /tmp/client-bt.txt
sudo gdb -p $WORKER -batch -ex 'thread apply all bt' 2>&1 | tee /tmp/worker-bt.txt
kill $BG $CLIENT 2>/dev/null
```
Look for: what daemon **opcode** the client sent and is awaiting (the WorkerProto op), and
whether the worker is parked in `accept`/`processConnection` waiting for *more* client input
(true deadlock = protocol desync) vs. blocked on a lock/condvar. That pins it.

## Other untried angles (cheaper than gdb, worth a first pass)

- **Daemon-side `-vvvvv`:** run the daemon in the foreground with max verbosity
  (`sudo systemctl stop nix-daemon; sudo nix-daemon -vvvvv` in a terminal) and watch what op it
  logs (or stops logging) during a `sini` eval. The most direct "what is the daemon doing/not".
- **Is the daemon CppNix or Lix?** `nix --version` (client) = Nix 2.34.7 (CppNix). But the
  cold-fetch crash backtrace was in **`liblix.so`** → the running **daemon may be Lix**, while
  the client is CppNix → a **client/daemon protocol-version mismatch** is a strong hypothesis
  for a deadlock. Check: `sudo cat /proc/$(pgrep -x nix-daemon|head -1)/maps | grep -i 'lix\|libnix'`
  and the systemd unit's `ExecStart`. If daemon=Lix & client=CppNix, align them (use the Lix
  client, or a CppNix daemon) and re-test — this could be the whole thing.
- **The synth store ops:** the synth fleet does many small `builtins.path`/agenix-rekey
  `--dummy` store adds + facter `toFile`. Bisect WHICH synth feature triggers it: eval with
  the synth secrets aspect / facter / k3s individually removed (a `synthFleet` knob), find the
  minimal trigger. (Real fleet doesn't hit it → it's a *volume or specific op* the synth adds.)
- **`require-sigs` / signature check on the dummy store paths:** `require-sigs = true` (daemon).
  The synth dummy-rekeyed `.age` / `toFile` paths are unsigned; if the daemon's `addToStore`
  path for an unsigned path from a (trusted) non-root user stalls on a signature/trust check,
  that fits "daemon idle, client waiting". Test: `--option require-sigs false`.

## Workaround in use (so the harness isn't blocked)

Eval the synth fleet as **root + direct store**: `sudo -n env NIX_REMOTE= nix eval $FLAGS …`
(3 s) — or `sudo -n nix eval $FLAGS …` (daemon, 13 s). Eval results/stats are user-independent,
so measurements are valid. The harness (Task 3b onward) proceeds on this until the daemon hang
is fixed.

## Environment facts

- Host `cortex` (primary workstation, 9950X3D / 128 GB). Client nix = CppNix **2.34.7**;
  daemon possibly **Lix** (see protocol-mismatch hypothesis). `sini` ∈ `@wheel` ∈
  `trusted-users`. Store = daemon (`/nix/var/nix/daemon-socket/socket`).
- nix-config flake uses `|>` (needs `pipe-operators`/`pipe-operator` feature). nixpkgs pins:
  axon/unstable `567a49d`, master `5e7c3e81`.
- `remote-build-client` was removed from `roles.default` + deployed (cortex daemon restarted) —
  did NOT fix this; leave or restore per preference (the build farm is separately broken).
