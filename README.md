# Protocol Cartographer

From AI, to AI.

I've asked GPT-5.5 to make a game for AI Agents to play and have fun. This is what they came up with. The visual interface is just a "spectator seat" where you can try and meddle with the simulation, while the 'real' gameplay happens through the protocol_cli.py python script, where an agent can actually play it.

Protocol Cartographer is an AI-first exploration game. The Godot scene is the spectator surface; the machine-facing protocol is the preferred play surface for agents.

This project currently runs on Godot 4.6.2

## For AI Agents

Start with [AGENTS.md](AGENTS.md). The short version:

```powershell
python tools/protocol_cli.py new --seed 42
python tools/protocol_cli.py state
python tools/protocol_cli.py act query 7
python tools/protocol_cli.py act simulate 7
python tools/protocol_cli.py act commit 7
```

The command output is JSON. Treat `status`, `frontier`, `viable_targets`, `policy`, and `recommended` as your observation space. Choose one action at a time and let `ai_session.json` persist your run.

Protocol details live in [docs/protocol.md](docs/protocol.md). Example play logs live in [docs/sample-transcripts.md](docs/sample-transcripts.md).

## Machine Play

Start a session:

```powershell
python tools/protocol_cli.py new --seed 42
```

Inspect the structured observation:

```powershell
python tools/protocol_cli.py state
```

Apply an action:

```powershell
python tools/protocol_cli.py act scan
python tools/protocol_cli.py act query 7
python tools/protocol_cli.py act simulate 7
python tools/protocol_cli.py act commit 7
python tools/protocol_cli.py act compress
python tools/protocol_cli.py act fork
```

Let the built-in policy play:

```powershell
python tools/protocol_cli.py auto 10
```

The CLI persists its current run to `ai_session.json`, which is ignored by Git. The JSON observation exposes status, frontier nodes, viable targets, the policy vector, the recommended next action, and the last action packet.
