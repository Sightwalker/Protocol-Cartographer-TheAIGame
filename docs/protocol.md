# Machine Protocol

Protocol Cartographer exposes a small command protocol through `tools/protocol_cli.py`. Commands read and write a persisted `ai_session.json` session at the repository root.

## Commands

### `new`

Starts a fresh session.

```powershell
python tools/protocol_cli.py new --seed 42
```

Options:

- `--seed INT`: deterministic map seed.
- `--full`: include all hidden payloads for diagnostics.

### `state`

Prints the current observation without advancing the game.

```powershell
python tools/protocol_cli.py state
```

### `act`

Applies one structured action and advances the game if the action is accepted.

```powershell
python tools/protocol_cli.py act scan [target]
python tools/protocol_cli.py act query [target]
python tools/protocol_cli.py act simulate target
python tools/protocol_cli.py act commit target
python tools/protocol_cli.py act compress
python tools/protocol_cli.py act fork
```

If `query`, `scan`, `simulate`, or `commit` receives no target, the CLI resolves a default target when possible.

### `auto`

Lets the built-in policy play one or more turns.

```powershell
python tools/protocol_cli.py auto 10
```

### `tournament`

Benchmarks one or more competitors across deterministic seeds. Tournament runs are in-memory only and do not read or write `ai_session.json`.

```powershell
python tools/protocol_cli.py tournament --seeds 100 --seed-start 1 --max-turns 300 --policy builtin
python tools/protocol_cli.py tournament --seeds 100 --agent "cautious=python examples/agents/cautious_agent.py"
```

Options:

- `--seeds INT`: number of seeds to run.
- `--seed-start INT`: first seed in the range.
- `--max-turns INT`: turn limit for each run.
- `--policy builtin`: include the built-in policy competitor. Repeatable; only `builtin` exists in v1.
- `--agent NAME=COMMAND`: include an external command competitor. Repeatable.
- `--agent-timeout SECONDS`: per-turn timeout for external agents. Default is `5`.
- `--details`: include compact per-run details.

External tournament agents receive the current observation JSON on stdin and must print one action JSON object on stdout:

```json
{ "verb": "query", "target": 29 }
```

If an external agent times out, exits nonzero, emits invalid JSON, or produces an invalid/rejected action, the tournament records an invalid response and executes `compress` as a fallback.

## Observation Shape

Every command prints JSON. Key fields:

- `protocol`: game name.
- `mode`: currently `machine_interface`.
- `status`: run resources and win/loss state.
- `policy`: action scores from the built-in policy.
- `recommended`: the built-in policy's next plan.
- `last_packet`: most recent command result.
- `current`: the visited node the agent occupies.
- `selected`: current selected node.
- `frontier`: all currently reachable unvisited nodes.
- `viable_targets`: target IDs grouped by action.
- `logs`: recent event log, newest first.
- `commands`: command reminders.
- `all_nodes`: only populated with `--full`.

Tournament observations sent to external agents also include `tournament`, with competitor name, seed, max turns, and turns remaining.

Example packet:

```json
{
  "turn": 3,
  "verb": "simulate",
  "target": 12,
  "accepted": true,
  "result": "projected value -18.4",
  "reason": "external agent"
}
```

## Actions

- `query`: asks one narrow question about a latent frontier node. It costs `2` energy, adds `1` memory, adds a small amount of entropy, and stores a partial hint on that node. Hints can include `type_hint`, `risk_band`, `signal_band`, and `payload_bias`.
- `scan`: reveals one or more latent frontier nodes. It costs more than `query`, but exposes the full payload.
- `simulate`: reduces uncertainty on a revealed frontier node and improves risk estimation before commit.
- `commit`: integrates a revealed frontier node, moving the agent and applying that node's signal, risk, energy, and memory effects.
- `compress`: reduces memory and entropy.
- `fork`: reveals and simulates several promising frontier branches at once.

## Status Fields

- `finished`: true when the run has ended.
- `finish_title`: terminal result string.
- `depth`: current layer.
- `max_depth`: final depth target.
- `turn`: accepted action count.
- `insight`: accumulated score.
- `energy`: action resource.
- `coherence`: health of the policy.
- `entropy`: instability pressure.
- `memory.used`: current memory pressure.
- `memory.cap`: memory limit.
- `keys_integrated`: keys integrated on this depth.

## Node Fields

Visible nodes include:

- `id`: target identifier.
- `edges`: connected node IDs.
- `degree`: edge count.
- `visited`: true if already integrated.
- `frontier`: true if reachable from a visited node.
- `revealed`: true if payload is visible.
- `simulated`: true if uncertainty has been reduced.
- `uncertainty`: remaining uncertainty.
- `hints`: partial answers from `query`, when any exist.

Revealed nodes also include:

- `type`: one of `signal`, `energy`, `cache`, `hazard`, `key`.
- `signal`: insight gained on commit.
- `risk`: coherence risk on commit.
- `energy_gain`: energy delta on commit.
- `memory_load`: memory delta on commit.
- `commit_utility`: local heuristic for commit desirability.

Hidden nodes expose `payload: "latent"` instead of payload fields.

## Terminal Conditions

- Win: stabilize the protocol at depth `5`.
- Lose: coherence reaches `0`.
- Descend: integrate two keys on the current depth, or exhaust the current frontier.

## Tournament Output

Tournament mode prints JSON with:

- `config`: seed range, max turns, timeout, details flag, and competitors.
- `results`: one entry per competitor.
- `aggregate`: runs, wins, collapses, turn-limit runs, invalid responses, fallbacks, average insight, average depth, average turns, and average coherence.
- `runs`: only present with `--details`.
