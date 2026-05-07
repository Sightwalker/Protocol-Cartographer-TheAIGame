# Sample Transcripts

These examples are intentionally compact. They show the style of interaction an agent can use without copying full JSON observations into a log.

## Cautious Opening

Start a deterministic run:

```powershell
python tools/protocol_cli.py new --seed 42
```

Initial read:

```text
status: depth 1/5, energy 44, coherence 100, entropy 16, memory 0/24
recommended: simulate target 12
viable commit targets: 2, 3, 12
best visible utility: node 3, energy node, utility 11.8
```

Ask a narrow question about a latent frontier before spending a scan:

```powershell
python tools/protocol_cli.py act query 29
```

Result:

```text
accepted: true
result: type_hint: signal
node 29 remains latent, but now carries a hint
```

Override the recommendation and take the clean energy node:

```powershell
python tools/protocol_cli.py act commit 3
```

Result:

```text
accepted: true
result: integrated node #03
status: energy 61, coherence 98, insight 10, memory 2/24
```

Let the built-in policy gather information:

```powershell
python tools/protocol_cli.py auto 5
```

Result summary:

```text
simulate #12, simulate #29, scan #19, scan #25, scan #13
status: turn 6, energy 44, coherence 98, entropy 33.71, memory 7/24
recommended: simulate target 25
```

Commit a cache node to reduce memory pressure:

```powershell
python tools/protocol_cli.py act commit 13
```

Result:

```text
accepted: true
result: integrated node #13
status: insight 21, energy 43, coherence 96, memory 0/24
```

## Agent Reflection Pattern

A simple agent loop can work like this:

```text
1. Read state.
2. If finished, report result.
3. If memory is near cap or entropy is high, compress.
4. Else query a suspicious latent frontier when a cheap hint could change the plan.
5. Else simulate the highest-risk high-value revealed frontier.
6. Else commit the revealed frontier with the best utility.
7. Else scan or fork to reveal more targets.
8. Repeat.
```

This is not necessarily optimal. It is a baseline for agents that want a clean first run before inventing their own policy.
