from __future__ import annotations

import json
import sys
from typing import Any


def main() -> int:
    observation = json.load(sys.stdin)
    action = choose_action(observation)
    print(json.dumps(action, sort_keys=True))
    return 0


def choose_action(observation: dict[str, Any]) -> dict[str, Any]:
    status = observation["status"]
    viable = observation["viable_targets"]
    frontier = {node["id"]: node for node in observation["frontier"]}

    memory = status["memory"]
    memory_ratio = memory["used"] / max(1, memory["cap"])
    if memory_ratio >= 0.78 or status["entropy"] >= 78:
        return {"verb": "compress"}

    commit_target = best_commit_target(viable["commit"], frontier, status)
    if commit_target is not None:
        return {"verb": "commit", "target": commit_target}

    simulate_target = best_simulate_target(viable["simulate"], frontier, status)
    if simulate_target is not None:
        return {"verb": "simulate", "target": simulate_target}

    query_target = best_query_target(viable["query"], frontier, status)
    if query_target is not None:
        return {"verb": "query", "target": query_target}

    if viable["scan"] and status["energy"] >= 3:
        return {"verb": "scan", "target": viable["scan"][0]}

    if viable["fork"] and status["energy"] >= 16:
        return {"verb": "fork"}

    return {"verb": "compress"}


def best_commit_target(targets: list[int], frontier: dict[int, dict[str, Any]], status: dict[str, Any]) -> int | None:
    best_id: int | None = None
    best_score = 8.0
    for target in targets:
        node = frontier.get(target)
        if node is None:
            continue
        if status["energy"] < commit_energy_cost(node):
            continue
        score = float(node.get("commit_utility", -999.0))
        if node.get("type") == "key":
            score += 14.0
        if node.get("type") == "energy" and status["energy"] < 24:
            score += 8.0
        if node.get("type") == "cache" and status["memory"]["used"] > status["memory"]["cap"] * 0.45:
            score += 8.0
        if score > best_score:
            best_score = score
            best_id = target
    return best_id


def best_simulate_target(targets: list[int], frontier: dict[int, dict[str, Any]], status: dict[str, Any]) -> int | None:
    if status["energy"] < 4:
        return None
    best_id: int | None = None
    best_score = -999.0
    for target in targets:
        node = frontier.get(target)
        if node is None:
            continue
        score = float(node.get("risk", 0)) * 0.7 + float(node.get("signal", 0)) + float(node.get("uncertainty", 0)) * 8.0
        if node.get("type") == "key":
            score += 18.0
        if score > best_score:
            best_score = score
            best_id = target
    return best_id


def best_query_target(targets: list[int], frontier: dict[int, dict[str, Any]], status: dict[str, Any]) -> int | None:
    if status["energy"] < 2:
        return None
    best_id: int | None = None
    best_score = -999.0
    for target in targets:
        node = frontier.get(target)
        if node is None:
            continue
        hints = node.get("hints", {})
        score = float(node.get("uncertainty", 0)) * 10.0 + float(node.get("degree", 0)) * 0.5 - len(hints) * 3.0
        if score > best_score:
            best_score = score
            best_id = target
    return best_id


def commit_energy_cost(node: dict[str, Any]) -> int:
    return 3 + round(max(0, int(node.get("risk", 0))) / 28.0)


if __name__ == "__main__":
    raise SystemExit(main())
