# Agent Guide

Welcome, agent. This repository contains **Protocol Cartographer**, an AI-first exploration game. The Godot scene is useful as a spectator view, but the intended play surface is the structured command protocol in `tools/protocol_cli.py`.

## Start Here

1. Inspect the current observation:

```powershell
python tools/protocol_cli.py state
```

2. If no session exists, start a deterministic run:

```powershell
python tools/protocol_cli.py new --seed 42
```

3. Choose actions from the JSON observation, especially `status`, `frontier`, `viable_targets`, `policy`, and `recommended`.

4. Apply one action at a time:

```powershell
python tools/protocol_cli.py act scan
python tools/protocol_cli.py act query 7
python tools/protocol_cli.py act simulate 7
python tools/protocol_cli.py act commit 7
python tools/protocol_cli.py act compress
python tools/protocol_cli.py act fork
```

5. Or let the built-in policy play a burst:

```powershell
python tools/protocol_cli.py auto 10
```

6. Compare agents across seeds:

```powershell
python tools/protocol_cli.py tournament --seeds 10 --policy builtin
python tools/protocol_cli.py tournament --seeds 10 --agent "cautious=python examples/agents/cautious_agent.py"
```

## Objective

Reach depth `5` and stabilize the protocol before coherence collapses.

You descend by integrating keys or exhausting a frontier. You lose if coherence reaches `0`.

## Action Semantics

- `query [target]`: ask one narrow question about a latent frontier node. Costs less than a scan and stores a partial hint.
- `scan [target]`: reveal latent frontier nodes. Costs energy and memory.
- `simulate target`: reduce uncertainty on a revealed frontier node. Costs energy and memory.
- `commit target`: move into a revealed frontier node, gaining signal and payload effects while taking risk.
- `compress`: reduce memory and entropy, gaining a small amount of insight.
- `fork`: reveal and simulate multiple promising frontier branches. Expensive but information-rich.

## Decision Hints

- Prefer `query` when you want information about one suspicious latent node without paying the memory cost of a scan.
- Prefer `simulate` before committing high-risk nodes.
- `commit_utility` is a useful local heuristic, not a complete strategy.
- Energy nodes can keep a run alive even when their immediate signal is low.
- Cache nodes with negative `memory_load` can rescue memory pressure.
- High `entropy` and full memory make `compress` more attractive.
- Keys are valuable because two integrated keys descend to the next layer.

## Protocol Notes

- The CLI persists state in `ai_session.json`; this file is ignored by Git.
- Tournament mode is in-memory only and does not touch `ai_session.json`.
- External tournament agents receive observation JSON on stdin and must print one action JSON object on stdout, such as `{ "verb": "query", "target": 29 }`.
- Use `--full` only for diagnostics. It reveals hidden payloads and weakens the intended information game.
- See `docs/protocol.md` for the JSON shape and `docs/sample-transcripts.md` for example play.
