from __future__ import annotations

import argparse
import json
import math
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SESSION_PATH = ROOT / "ai_session.json"

MAX_DEPTH = 5
MEMORY_CAP_START = 24
ACTION_NAMES = ("query", "scan", "simulate", "commit", "compress", "fork")
NODE_TYPES = ("signal", "energy", "cache", "hazard", "key")


class Rng:
    def __init__(self, state: int) -> None:
        self.state = state & ((1 << 64) - 1)
        if self.state == 0:
            self.state = 0x9E3779B97F4A7C15

    def next_u64(self) -> int:
        self.state = (self.state * 6364136223846793005 + 1442695040888963407) & ((1 << 64) - 1)
        return self.state

    def random(self) -> float:
        return (self.next_u64() >> 11) * (1.0 / (1 << 53))

    def uniform(self, low: float, high: float) -> float:
        return low + (high - low) * self.random()

    def randint(self, low: int, high: int) -> int:
        return low + min(high - low, int(self.random() * float(high - low + 1)))

    def chance(self, probability: float) -> bool:
        return self.random() < probability


@dataclass
class Node:
    id: int = -1
    unit_pos: list[float] = field(default_factory=lambda: [0.0, 0.0])
    edges: list[int] = field(default_factory=list)
    node_type: str = "signal"
    signal_value: int = 0
    risk: int = 0
    energy_gain: int = 0
    memory_load: int = 0
    uncertainty: float = 1.0
    revealed: bool = False
    simulated: bool = False
    visited: bool = False
    hints: dict[str, Any] = field(default_factory=dict)

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> Node:
        return cls(
            id=int(data["id"]),
            unit_pos=[float(data["unit_pos"][0]), float(data["unit_pos"][1])],
            edges=[int(edge) for edge in data.get("edges", [])],
            node_type=str(data.get("node_type", "signal")),
            signal_value=int(data.get("signal_value", 0)),
            risk=int(data.get("risk", 0)),
            energy_gain=int(data.get("energy_gain", 0)),
            memory_load=int(data.get("memory_load", 0)),
            uncertainty=float(data.get("uncertainty", 1.0)),
            revealed=bool(data.get("revealed", False)),
            simulated=bool(data.get("simulated", False)),
            visited=bool(data.get("visited", False)),
            hints=dict(data.get("hints", {})),
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "unit_pos": [round(self.unit_pos[0], 6), round(self.unit_pos[1], 6)],
            "edges": self.edges,
            "node_type": self.node_type,
            "signal_value": self.signal_value,
            "risk": self.risk,
            "energy_gain": self.energy_gain,
            "memory_load": self.memory_load,
            "uncertainty": round(self.uncertainty, 6),
            "revealed": self.revealed,
            "simulated": self.simulated,
            "visited": self.visited,
            "hints": self.hints,
        }


class ProtocolGame:
    def __init__(self, data: dict[str, Any] | None = None, seed: int | None = None) -> None:
        if data is None:
            self.seed = int(seed if seed is not None else time.time_ns())
            self.rng = Rng(self.seed)
            self.nodes: list[Node] = []
            self.logs: list[str] = []
            self.last_packet: dict[str, Any] = {}
            self.new_run()
        else:
            self.seed = int(data.get("seed", 1))
            self.rng = Rng(int(data.get("rng_state", self.seed)))
            self.depth = int(data.get("depth", 1))
            self.turn = int(data.get("turn", 0))
            self.insight = int(data.get("insight", 0))
            self.energy = int(data.get("energy", 44))
            self.coherence = int(data.get("coherence", 100))
            self.entropy = float(data.get("entropy", 16.0))
            self.memory_used = int(data.get("memory_used", 0))
            self.memory_cap = int(data.get("memory_cap", MEMORY_CAP_START))
            self.keys_integrated = int(data.get("keys_integrated", 0))
            self.current_id = int(data.get("current_id", 0))
            self.selected_id = int(data.get("selected_id", 0))
            self.game_finished = bool(data.get("game_finished", False))
            self.finish_title = str(data.get("finish_title", ""))
            self.nodes = [Node.from_dict(node) for node in data.get("nodes", [])]
            self.logs = [str(line) for line in data.get("logs", [])]
            self.last_packet = dict(data.get("last_packet", {}))

    def new_run(self) -> None:
        self.depth = 1
        self.turn = 0
        self.insight = 0
        self.energy = 44
        self.coherence = 100
        self.entropy = 16.0
        self.memory_used = 0
        self.memory_cap = MEMORY_CAP_START
        self.keys_integrated = 0
        self.current_id = 0
        self.selected_id = 0
        self.game_finished = False
        self.finish_title = ""
        self.logs.clear()
        self.log("boot: autonomous policy online")
        self.generate_map()
        self.last_packet = self.packet("init", self.current_id, True, "seeded latent graph", "new run")

    def to_dict(self) -> dict[str, Any]:
        return {
            "version": 1,
            "seed": self.seed,
            "rng_state": self.rng.state,
            "depth": self.depth,
            "turn": self.turn,
            "insight": self.insight,
            "energy": self.energy,
            "coherence": self.coherence,
            "entropy": self.entropy,
            "memory_used": self.memory_used,
            "memory_cap": self.memory_cap,
            "keys_integrated": self.keys_integrated,
            "current_id": self.current_id,
            "selected_id": self.selected_id,
            "game_finished": self.game_finished,
            "finish_title": self.finish_title,
            "nodes": [node.to_dict() for node in self.nodes],
            "logs": self.logs,
            "last_packet": self.last_packet,
        }

    def generate_map(self) -> None:
        self.nodes.clear()
        node_count = 25 + self.depth * 5
        for node_id in range(node_count):
            node = Node(id=node_id)
            if node_id == 0:
                node.unit_pos = [0.0, 0.0]
                node.node_type = "cache"
            else:
                node.unit_pos = self.make_node_position()
                self.assign_node_payload(node)
            self.nodes.append(node)

        self.connect_graph()
        self.current_id = 0
        self.selected_id = 0
        self.nodes[0].revealed = True
        self.nodes[0].visited = True
        self.nodes[0].simulated = True
        self.reveal_from(0, 3)
        scan_target = self.best_scan_target()
        if scan_target != -1:
            self.selected_id = scan_target

    def make_node_position(self) -> list[float]:
        candidate = [0.0, 0.0]
        for _attempt in range(64):
            angle = self.rng.uniform(0.0, math.tau)
            radius = math.sqrt(self.rng.uniform(0.02, 1.0)) * 0.96
            candidate = [math.cos(angle) * radius, math.sin(angle) * radius]
            clear = True
            for other in self.nodes:
                if distance(candidate, other.unit_pos) < 0.16:
                    clear = False
                    break
            if clear:
                return candidate
        return candidate

    def assign_node_payload(self, node: Node) -> None:
        roll = self.rng.random()
        if roll < 0.34:
            node.node_type = "signal"
            node.signal_value = self.rng.randint(13, 27) + self.depth * 2
            node.risk = self.rng.randint(5, 22) + self.depth
            node.energy_gain = self.rng.randint(0, 4)
            node.memory_load = self.rng.randint(2, 5)
        elif roll < 0.51:
            node.node_type = "energy"
            node.signal_value = self.rng.randint(4, 11) + self.depth
            node.risk = self.rng.randint(4, 18) + self.depth
            node.energy_gain = self.rng.randint(13, 24) + self.depth * 2
            node.memory_load = self.rng.randint(1, 3)
        elif roll < 0.68:
            node.node_type = "cache"
            node.signal_value = self.rng.randint(7, 16) + self.depth
            node.risk = self.rng.randint(3, 16) + self.depth
            node.energy_gain = self.rng.randint(0, 5)
            node.memory_load = -self.rng.randint(4, 9)
        elif roll < 0.89:
            node.node_type = "hazard"
            node.signal_value = self.rng.randint(8, 20) + self.depth * 2
            node.risk = self.rng.randint(34, 64) + self.depth * 3
            node.energy_gain = self.rng.randint(-4, 5)
            node.memory_load = self.rng.randint(2, 6)
        else:
            node.node_type = "key"
            node.signal_value = self.rng.randint(28, 44) + self.depth * 5
            node.risk = self.rng.randint(18, 42) + self.depth * 2
            node.energy_gain = self.rng.randint(2, 10)
            node.memory_load = self.rng.randint(4, 7)
        node.uncertainty = self.rng.uniform(0.55, 1.0)

    def connect_graph(self) -> None:
        for i, node in enumerate(self.nodes):
            for _ in range(3):
                best_id = -1
                best_distance = 999999.0
                for j, other in enumerate(self.nodes):
                    if i == j or j in node.edges:
                        continue
                    dist = distance(node.unit_pos, other.unit_pos)
                    if dist < best_distance:
                        best_distance = dist
                        best_id = j
                if best_id != -1:
                    self.add_edge(i, best_id)

        for i in range(len(self.nodes)):
            if self.rng.chance(0.25):
                self.add_edge(i, self.rng.randint(0, len(self.nodes) - 1))

    def add_edge(self, a: int, b: int) -> None:
        if a == b:
            return
        if b not in self.nodes[a].edges:
            self.nodes[a].edges.append(b)
        if a not in self.nodes[b].edges:
            self.nodes[b].edges.append(a)

    def execute(self, verb: str, target: int | None = None, reason: str = "external agent") -> dict[str, Any]:
        verb = verb.lower().strip()
        if self.game_finished:
            self.last_packet = self.packet(verb, target, False, "game already finished", reason)
            return self.last_packet

        target = self.resolve_target(verb, target)
        accepted = False
        result = "unknown verb"

        if verb == "query":
            accepted, result = self.action_query(target)
        elif verb == "scan":
            accepted, result = self.action_scan(target)
        elif verb == "simulate":
            accepted, result = self.action_simulate(target)
        elif verb == "commit":
            accepted, result = self.action_commit(target)
        elif verb == "compress":
            accepted, result = self.action_compress()
        elif verb == "fork":
            accepted, result = self.action_fork()

        self.last_packet = self.packet(verb, target, accepted, result, reason)
        if accepted:
            self.after_turn()
        return self.last_packet

    def auto_step(self) -> dict[str, Any]:
        plan = self.choose_plan()
        return self.execute(plan["verb"], plan.get("target"), plan.get("reason", "policy loop"))

    def choose_plan(self) -> dict[str, Any]:
        policy = self.policy()
        commit_target = self.best_commit_target()
        simulate_target = self.best_simulate_target()
        query_target = self.best_query_target()
        scan_target = self.best_scan_target()

        if policy["compress"] >= 0.86:
            return {"verb": "compress", "target": self.current_id, "reason": "memory or entropy above comfort"}
        if commit_target != -1 and policy["commit"] >= max(policy["query"], policy["scan"], policy["simulate"]):
            return {"verb": "commit", "target": commit_target, "reason": "best revealed frontier"}
        if simulate_target != -1 and policy["simulate"] >= 0.44:
            return {"verb": "simulate", "target": simulate_target, "reason": "valuable uncertainty"}
        if query_target != -1 and policy["query"] >= max(0.38, policy["scan"] - 0.08):
            return {"verb": "query", "target": query_target, "reason": "cheap targeted uncertainty reduction"}
        if scan_target != -1 and policy["scan"] >= 0.28:
            return {"verb": "scan", "target": scan_target, "reason": "frontier map incomplete"}
        if policy["fork"] >= 0.34:
            return {"verb": "fork", "target": scan_target, "reason": "parallel branch evaluation"}
        return {"verb": "compress", "target": self.current_id, "reason": "no dominant external move"}

    def resolve_target(self, verb: str, target: int | None) -> int | None:
        if target is not None:
            return target
        if verb == "query":
            return self.best_query_target()
        if verb == "scan":
            return self.best_scan_target()
        if verb == "simulate":
            return self.best_simulate_target()
        if verb == "commit":
            return self.best_commit_target()
        return self.selected_id

    def action_query(self, target: int | None) -> tuple[bool, str]:
        if self.energy < 2:
            return False, "insufficient energy"
        if target is None or not self.is_valid_node(target) or not self.is_frontier(target):
            return False, "target is not frontier"

        node = self.nodes[target]
        if node.revealed:
            return False, "target already revealed"

        available_hints = self.queryable_hints(node)
        if not available_hints:
            return False, "no unanswered query"

        hint_key = available_hints[0]
        hint_value = self.make_hint(node, hint_key)
        node.hints[hint_key] = hint_value
        node.uncertainty = max(0.12, node.uncertainty * 0.82)
        self.energy -= 2
        self.memory_used += 1
        self.entropy += 0.8
        self.selected_id = target
        self.log(f"query: #{target:02d} {hint_key}={hint_value}")
        return True, f"{hint_key}: {hint_value}"

    def action_scan(self, target: int | None) -> tuple[bool, str]:
        if self.energy < 3:
            return False, "insufficient energy"

        revealed_count = 0
        if target is not None and self.is_valid_node(target) and self.is_frontier(target) and not self.nodes[target].revealed:
            if self.reveal_node(target):
                revealed_count += 1
        else:
            for node_id in self.best_scan_targets(3):
                if self.reveal_node(node_id):
                    revealed_count += 1

        if revealed_count <= 0:
            return False, "no hidden frontier"

        self.energy -= 3
        self.memory_used += revealed_count
        self.entropy += 1.2
        if target is not None and self.is_valid_node(target):
            self.selected_id = target
        self.log(f"scan: {revealed_count} node(s) revealed")
        return True, f"revealed {revealed_count} node(s)"

    def action_simulate(self, target: int | None) -> tuple[bool, str]:
        if self.energy < 4:
            return False, "insufficient energy"
        if target is None or not self.is_valid_node(target) or not self.is_frontier(target):
            return False, "target is not frontier"
        node = self.nodes[target]
        if not node.revealed:
            return False, "target is latent"
        if node.simulated:
            return False, "target already simulated"

        self.energy -= 4
        self.memory_used += 1
        self.entropy += 2.2
        node.simulated = True
        node.uncertainty = max(0.08, node.uncertainty * 0.35)
        self.selected_id = target
        self.log(f"simulate: #{target:02d} value {self.commit_utility(node):.1f}")
        return True, f"projected value {self.commit_utility(node):.1f}"

    def action_commit(self, target: int | None) -> tuple[bool, str]:
        if target is None or not self.is_valid_node(target) or not self.is_frontier(target):
            return False, "target is not frontier"
        node = self.nodes[target]
        if not node.revealed:
            return False, "target is latent"

        energy_cost = 3 + round(max(0, node.risk) / 28.0)
        if self.energy < energy_cost:
            return False, "insufficient energy"

        risk_roll = self.rng.uniform(0.32, 0.86) if node.simulated else self.rng.uniform(0.58, 1.18)
        damage = round(node.risk * risk_roll * 0.34)
        self.energy += node.energy_gain - energy_cost
        self.insight += node.signal_value
        self.coherence -= damage
        self.memory_used = max(0, self.memory_used + node.memory_load)
        self.entropy += node.uncertainty * 5.0 + node.risk * 0.035
        node.visited = True
        node.simulated = True
        self.current_id = target
        self.selected_id = target

        if node.node_type == "key":
            self.keys_integrated += 1
            self.log(f"commit: key #{target:02d} integrated")
        else:
            self.log(f"commit: #{target:02d} signal +{node.signal_value} risk {damage}")

        self.reveal_from(target, 1)
        return True, f"integrated node #{target:02d}"

    def action_compress(self) -> tuple[bool, str]:
        packed = min(self.memory_used, 7 + self.depth)
        entropy_drop = 7.0 + packed * 1.4
        self.energy = max(0, self.energy - 1)
        self.memory_used = max(0, self.memory_used - packed)
        self.entropy = max(0.0, self.entropy - entropy_drop)
        self.insight += packed * 2
        self.coherence = min(100, self.coherence + max(1, round(packed * 0.45)))
        self.log(f"compress: memory -{packed} entropy -{round(entropy_drop)}")
        return True, f"packed {packed} memory units"

    def action_fork(self) -> tuple[bool, str]:
        if self.energy < 8:
            return False, "insufficient energy"
        targets = self.best_fork_targets(3)
        if not targets:
            return False, "no viable branch"

        self.energy -= 8
        self.memory_used += 4
        self.entropy += 4.8
        for target in targets:
            self.reveal_node(target)
            node = self.nodes[target]
            node.simulated = True
            node.uncertainty = max(0.08, node.uncertainty * 0.42)
        self.selected_id = targets[0]
        self.log(f"fork: {len(targets)} branches evaluated")
        return True, f"evaluated branches {targets}"

    def after_turn(self) -> None:
        self.turn += 1
        self.energy = max(0, min(99, self.energy))
        self.entropy += 1.0 + self.depth * 0.22

        if self.memory_used > self.memory_cap:
            overflow = self.memory_used - self.memory_cap
            self.coherence -= overflow * 2
            self.entropy += overflow * 0.75
            self.log(f"overflow: memory pressure {overflow}")

        if self.entropy >= 100.0:
            self.entropy = 68.0
            self.coherence -= 12 + self.depth * 2
            self.log("entropy spike: coherence damaged")

        if self.energy <= 0:
            self.coherence -= 3
            self.log("starvation: no energy reserve")

        if self.coherence <= 0:
            self.finish("POLICY COLLAPSED")
            return

        if self.keys_integrated >= 2 or not self.frontier_ids():
            self.descend()

    def descend(self) -> None:
        if self.depth >= MAX_DEPTH:
            self.finish("PROTOCOL STABILIZED")
            return
        self.depth += 1
        self.keys_integrated = 0
        self.memory_used = max(0, self.memory_used - 8)
        self.memory_cap += 3
        self.energy = min(72, self.energy + 18)
        self.coherence = min(100, self.coherence + 12)
        self.entropy = max(10.0, self.entropy - 38.0)
        self.log(f"depth: entered layer {self.depth}")
        self.generate_map()

    def finish(self, title: str) -> None:
        self.game_finished = True
        self.finish_title = title
        self.log(f"finish: {title.lower()}")

    def reveal_from(self, node_id: int, count: int) -> None:
        if not self.is_valid_node(node_id):
            return
        revealed = 0
        for neighbor_id in self.nodes[node_id].edges:
            if revealed >= count:
                return
            if not self.nodes[neighbor_id].revealed:
                self.reveal_node(neighbor_id)
                revealed += 1

    def reveal_node(self, node_id: int) -> bool:
        if not self.is_valid_node(node_id):
            return False
        node = self.nodes[node_id]
        if node.revealed:
            return False
        node.revealed = True
        node.uncertainty = max(0.18, node.uncertainty * 0.58)
        return True

    def is_valid_node(self, node_id: int) -> bool:
        return 0 <= node_id < len(self.nodes)

    def is_frontier(self, node_id: int) -> bool:
        if not self.is_valid_node(node_id) or self.nodes[node_id].visited:
            return False
        return any(self.nodes[neighbor].visited for neighbor in self.nodes[node_id].edges)

    def frontier_ids(self) -> list[int]:
        return [node.id for node in self.nodes if self.is_frontier(node.id)]

    def revealed_frontier_ids(self) -> list[int]:
        return [node_id for node_id in self.frontier_ids() if self.nodes[node_id].revealed]

    def unrevealed_frontier_ids(self) -> list[int]:
        return [node_id for node_id in self.frontier_ids() if not self.nodes[node_id].revealed]

    def unsimulated_frontier_ids(self) -> list[int]:
        return [node_id for node_id in self.revealed_frontier_ids() if not self.nodes[node_id].simulated]

    def best_scan_target(self) -> int:
        best_id = -1
        best_score = -99999.0
        for node_id in self.unrevealed_frontier_ids():
            node = self.nodes[node_id]
            score = len(node.edges) + node.uncertainty * 2.0 - norm(node.unit_pos) * 0.2
            if score > best_score:
                best_score = score
                best_id = node_id
        return best_id

    def best_query_target(self) -> int:
        best_id = -1
        best_score = -99999.0
        for node_id in self.unrevealed_frontier_ids():
            node = self.nodes[node_id]
            if not self.queryable_hints(node):
                continue
            type_bonus = 0.0
            if node.node_type == "key":
                type_bonus = 8.0
            elif node.node_type == "hazard":
                type_bonus = 5.0
            score = node.uncertainty * 8.0 + len(node.edges) * 0.45 + type_bonus - len(node.hints) * 2.5
            if score > best_score:
                best_score = score
                best_id = node_id
        return best_id

    def best_scan_targets(self, limit: int) -> list[int]:
        chosen: list[int] = []
        for _ in range(limit):
            best_id = -1
            best_score = -99999.0
            for node_id in self.unrevealed_frontier_ids():
                if node_id in chosen:
                    continue
                node = self.nodes[node_id]
                score = len(node.edges) + node.uncertainty * 2.0
                if score > best_score:
                    best_score = score
                    best_id = node_id
            if best_id != -1:
                chosen.append(best_id)
        return chosen

    def best_simulate_target(self) -> int:
        best_id = -1
        best_score = -99999.0
        for node_id in self.unsimulated_frontier_ids():
            node = self.nodes[node_id]
            score = node.signal_value + node.risk * 0.8 + node.uncertainty * 16.0
            if score > best_score:
                best_score = score
                best_id = node_id
        return best_id

    def best_commit_target(self) -> int:
        best_id = -1
        best_score = -99999.0
        for node_id in self.revealed_frontier_ids():
            score = self.commit_utility(self.nodes[node_id])
            if score > best_score:
                best_score = score
                best_id = node_id
        return best_id

    def best_fork_targets(self, limit: int) -> list[int]:
        chosen: list[int] = []
        for _ in range(limit):
            best_id = -1
            best_score = -99999.0
            for node_id in self.frontier_ids():
                if node_id in chosen:
                    continue
                node = self.nodes[node_id]
                reveal_bonus = 12.0 if not node.revealed else 0.0
                sim_bonus = 8.0 if not node.simulated else 0.0
                score = self.commit_utility(node) + reveal_bonus + sim_bonus
                if score > best_score:
                    best_score = score
                    best_id = node_id
            if best_id != -1:
                chosen.append(best_id)
        return chosen

    def commit_utility(self, node: Node) -> float:
        type_bonus = 0.0
        if node.node_type == "key":
            type_bonus = 24.0
        elif node.node_type == "cache":
            type_bonus = 10.0
        elif node.node_type == "energy" and self.energy < 18:
            type_bonus = 16.0

        risk_weight = 0.45 if node.simulated else 0.78
        memory_penalty = max(0, node.memory_load) * (2.2 if self.memory_used < self.memory_cap else 4.0)
        energy_bonus = node.energy_gain * (1.35 if self.energy < 22 else 0.7)
        return node.signal_value + energy_bonus + type_bonus - node.risk * risk_weight - memory_penalty

    def queryable_hints(self, node: Node) -> list[str]:
        keys = ["type_hint", "risk_band", "signal_band", "payload_bias"]
        return [key for key in keys if key not in node.hints]

    def make_hint(self, node: Node, hint_key: str) -> str:
        if hint_key == "type_hint":
            if node.node_type == "key":
                return "keystone"
            if node.node_type == "hazard":
                return "volatile"
            if node.node_type == "energy":
                return "resource"
            if node.node_type == "cache":
                return "relief"
            return "signal"
        if hint_key == "risk_band":
            return band(node.risk, 16, 34, "low", "medium", "high")
        if hint_key == "signal_band":
            return band(node.signal_value, 12, 28, "low", "medium", "high")
        if hint_key == "payload_bias":
            if node.energy_gain >= 10:
                return "energy-positive"
            if node.memory_load < 0:
                return "memory-relief"
            if node.memory_load >= 5:
                return "memory-heavy"
            return "neutral"
        return "unknown"

    def policy(self) -> dict[str, float]:
        frontier_total = len(self.frontier_ids())
        unrevealed_total = len(self.unrevealed_frontier_ids())
        revealed_total = len(self.revealed_frontier_ids())
        unsimulated_total = len(self.unsimulated_frontier_ids())
        queryable_total = len([node_id for node_id in self.unrevealed_frontier_ids() if self.queryable_hints(self.nodes[node_id])])
        commit_target = self.best_commit_target()
        commit_score = max(0.0, self.commit_utility(self.nodes[commit_target]) / 55.0) if commit_target != -1 else 0.0
        scan_score = clamp(unrevealed_total / max(1.0, frontier_total), 0.0, 1.0)
        query_score = 0.0
        if self.energy >= 2 and queryable_total > 0:
            pressure = max(self.memory_used / self.memory_cap, self.entropy / 100.0)
            hidden_ratio = unrevealed_total / max(1.0, frontier_total)
            query_score = clamp(0.18 + pressure * 0.42 + hidden_ratio * 0.24, 0.0, 0.88)
        simulate_score = clamp((unsimulated_total / max(1.0, revealed_total)) * 0.72, 0.0, 1.0)
        compress_score = max(self.memory_used / self.memory_cap, self.entropy / 100.0)
        fork_score = 0.0
        if self.energy >= 12 and frontier_total >= 4:
            fork_score = clamp((frontier_total - revealed_total) / 8.0, 0.0, 1.0) * 0.72
        if self.energy < 4:
            scan_score *= 0.2
            simulate_score *= 0.1
            commit_score *= 0.5
            fork_score = 0.0
            if self.energy >= 2 and queryable_total > 0:
                query_score = max(query_score, 0.52)
        return {
            "query": round(clamp(query_score, 0.0, 1.0), 4),
            "scan": round(clamp(scan_score, 0.0, 1.0), 4),
            "simulate": round(clamp(simulate_score, 0.0, 1.0), 4),
            "commit": round(clamp(commit_score, 0.0, 1.0), 4),
            "compress": round(clamp(compress_score, 0.0, 1.0), 4),
            "fork": round(clamp(fork_score, 0.0, 1.0), 4),
        }

    def packet(self, verb: str, target: int | None, accepted: bool, result: str, reason: str) -> dict[str, Any]:
        return {
            "turn": self.turn,
            "verb": verb,
            "target": target,
            "accepted": accepted,
            "result": result,
            "reason": reason,
        }

    def log(self, line: str) -> None:
        self.logs.append(f"t{self.turn:03d} {line}")
        while len(self.logs) > 8:
            self.logs.pop(0)

    def observation(self, full: bool = False) -> dict[str, Any]:
        frontier = self.frontier_ids()
        revealed_frontier = self.revealed_frontier_ids()
        unsimulated_frontier = self.unsimulated_frontier_ids()
        hidden_frontier = self.unrevealed_frontier_ids()
        recommended = self.choose_plan() if not self.game_finished else None
        return {
            "protocol": "Protocol Cartographer",
            "mode": "machine_interface",
            "status": {
                "finished": self.game_finished,
                "finish_title": self.finish_title,
                "depth": self.depth,
                "max_depth": MAX_DEPTH,
                "turn": self.turn,
                "insight": self.insight,
                "energy": self.energy,
                "coherence": self.coherence,
                "entropy": round(self.entropy, 2),
                "memory": {"used": self.memory_used, "cap": self.memory_cap},
                "keys_integrated": self.keys_integrated,
            },
            "policy": self.policy(),
            "recommended": recommended,
            "last_packet": self.last_packet,
            "current": self.public_node(self.current_id),
            "selected": self.public_node(self.selected_id),
            "frontier": [self.public_node(node_id) for node_id in frontier],
            "viable_targets": {
                "query": [node_id for node_id in hidden_frontier if self.queryable_hints(self.nodes[node_id])],
                "scan": hidden_frontier,
                "simulate": unsimulated_frontier,
                "commit": revealed_frontier,
                "fork": self.best_fork_targets(3),
            },
            "logs": list(reversed(self.logs)),
            "commands": [
                "python tools/protocol_cli.py state",
                "python tools/protocol_cli.py act query [target]",
                "python tools/protocol_cli.py act scan [target]",
                "python tools/protocol_cli.py act simulate [target]",
                "python tools/protocol_cli.py act commit [target]",
                "python tools/protocol_cli.py act compress",
                "python tools/protocol_cli.py act fork",
                "python tools/protocol_cli.py auto [turns]",
            ],
            "all_nodes": [self.public_node(node.id, full=True) for node in self.nodes] if full else None,
        }

    def public_node(self, node_id: int, full: bool = False) -> dict[str, Any] | None:
        if not self.is_valid_node(node_id):
            return None
        node = self.nodes[node_id]
        public: dict[str, Any] = {
            "id": node.id,
            "pos": [round(node.unit_pos[0], 3), round(node.unit_pos[1], 3)],
            "edges": node.edges,
            "degree": len(node.edges),
            "visited": node.visited,
            "frontier": self.is_frontier(node.id),
            "revealed": node.revealed,
            "simulated": node.simulated,
            "uncertainty": round(node.uncertainty, 3),
        }
        if node.revealed or full:
            public.update(
                {
                    "type": node.node_type,
                    "signal": node.signal_value,
                    "risk": node.risk,
                    "energy_gain": node.energy_gain,
                    "memory_load": node.memory_load,
                    "commit_utility": round(self.commit_utility(node), 2),
                }
            )
        else:
            public["payload"] = "latent"
        if node.hints:
            public["hints"] = node.hints
        return public


def distance(a: list[float], b: list[float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def norm(a: list[float]) -> float:
    return math.hypot(a[0], a[1])


def clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def band(value: int, low_max: int, medium_max: int, low: str, medium: str, high: str) -> str:
    if value <= low_max:
        return low
    if value <= medium_max:
        return medium
    return high


def load_game() -> ProtocolGame:
    if not SESSION_PATH.exists():
        return ProtocolGame(seed=int(time.time_ns()))
    with SESSION_PATH.open("r", encoding="utf-8") as handle:
        return ProtocolGame(json.load(handle))


def save_game(game: ProtocolGame) -> None:
    with SESSION_PATH.open("w", encoding="utf-8") as handle:
        json.dump(game.to_dict(), handle, indent=2, sort_keys=True)
        handle.write("\n")


def emit(data: dict[str, Any]) -> None:
    print(json.dumps(data, indent=2, sort_keys=True))


def main() -> int:
    parser = argparse.ArgumentParser(description="Protocol Cartographer machine-facing play interface.")
    subparsers = parser.add_subparsers(dest="command", required=True)

    new_parser = subparsers.add_parser("new", help="start a fresh persisted session")
    new_parser.add_argument("--seed", type=int, default=None)
    new_parser.add_argument("--full", action="store_true", help="include hidden payloads for diagnostics")

    state_parser = subparsers.add_parser("state", help="print the current observation")
    state_parser.add_argument("--full", action="store_true", help="include hidden payloads for diagnostics")

    act_parser = subparsers.add_parser("act", help="apply one structured action")
    act_parser.add_argument("verb", choices=ACTION_NAMES)
    act_parser.add_argument("target", type=int, nargs="?")
    act_parser.add_argument("--full", action="store_true", help="include hidden payloads for diagnostics")

    auto_parser = subparsers.add_parser("auto", help="let the built-in policy play turns")
    auto_parser.add_argument("turns", type=int, nargs="?", default=1)
    auto_parser.add_argument("--full", action="store_true", help="include hidden payloads for diagnostics")

    args = parser.parse_args()

    if args.command == "new":
        game = ProtocolGame(seed=args.seed)
        save_game(game)
        emit(game.observation(full=args.full))
        return 0

    game = load_game()

    if args.command == "state":
        emit(game.observation(full=args.full))
        return 0

    if args.command == "act":
        packet = game.execute(args.verb, args.target, "external agent")
        save_game(game)
        data = game.observation(full=args.full)
        data["packet"] = packet
        emit(data)
        return 0

    if args.command == "auto":
        transcript = []
        for _ in range(max(0, args.turns)):
            if game.game_finished:
                break
            transcript.append(game.auto_step())
        save_game(game)
        data = game.observation(full=args.full)
        data["transcript"] = transcript
        emit(data)
        return 0

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
