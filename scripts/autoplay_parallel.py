# SPDX-FileCopyrightText: 2026 Juan Medina
# SPDX-License-Identifier: MIT

import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time

MATRIX_HEROES = [
    "archer",
    "armored_axeman",
    "knight",
    "knight_templar",
    "priest",
    "soldier",
    "swordsman",
    "wizard",
]


def build_tasks(args: argparse.Namespace) -> list[dict]:
    if args.mode == "matrix":
        configs: list[tuple[str, str]] = []
        if args.matrix_set in ("all", "balanced"):
            for hero_id in MATRIX_HEROES:
                configs.append((hero_id, "balanced"))
        if args.matrix_set in ("all", "comps"):
            configs.append(("knight", "melee_stack"))
            configs.append(("archer", "ranged_kite"))
            configs.append(("knight", "random"))
        if args.matrix_set in ("all", "mono"):
            for hero_id in MATRIX_HEROES:
                configs.append((hero_id, f"mono:{hero_id}"))
        return [
            {
                "label": f"{leader} | {build}",
                "leader": leader,
                "build": build,
                "seed": args.seed,
                "seeds": args.seeds,
            }
            for leader, build in configs
        ]

    # Split seeds evenly across jobs for parallel balance mode.
    workers = min(args.jobs, args.seeds)
    base_count, rem = divmod(args.seeds, workers)
    tasks: list[dict] = []
    cur_seed = args.seed
    for idx in range(workers):
        count = base_count + (1 if idx < rem else 0)
        if count <= 0:
            continue
        tasks.append(
            {
                "label": f"{args.leader} | {args.build} (seed {cur_seed}..{cur_seed + count - 1})",
                "leader": args.leader,
                "build": args.build,
                "seed": cur_seed,
                "seeds": count,
            }
        )
        cur_seed += count
    return tasks


def run_worker(
    idx: int,
    task: dict,
    slot_queue: list[int],
    slot_lock: threading.Lock,
    repo_root: Path,
    tmp_dir: Path,
    args: argparse.Namespace,
) -> dict:
    with slot_lock:
        slot = slot_queue.pop(0)
    try:
        worker_cache = repo_root / ".venv" / "cache" / "workers" / f"w{slot}"
        appdata = worker_cache / "appdata"
        localappdata = worker_cache / "localappdata"
        appdata.mkdir(parents=True, exist_ok=True)
        localappdata.mkdir(parents=True, exist_ok=True)

        env = os.environ.copy()
        env["APPDATA"] = str(appdata)
        env["LOCALAPPDATA"] = str(localappdata)

        out_json = tmp_dir / f"worker_{idx}.json"
        cmd = [
            args.godot_bin,
            "--headless",
            "--audio-driver",
            "Dummy",
            "--fixed-fps",
            "60",
            "--path",
            "src",
            "res://autoplay/autoplay_runner.tscn",
            "--",
            "--mode=balance",
            f"--leader={task['leader']}",
            f"--build={task['build']}",
            f"--seeds={task['seeds']}",
            f"--seed={task['seed']}",
            f"--max_depth={args.max_depth}",
        ]
        if args.max_frames >= 0:
            cmd.append(f"--max_frames={args.max_frames}")
        if args.speed > 0.0:
            cmd.append(f"--speed={args.speed}")
        if args.immortal:
            cmd.append(f"--immortal={args.immortal}")
        cmd.append(f"--out={out_json}")

        t0 = time.monotonic()
        proc = subprocess.run(
            cmd,
            cwd=str(repo_root),
            env=env,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
        )
        elapsed = time.monotonic() - t0
        if proc.returncode != 0 or not out_json.exists():
            return {
                "ok": False,
                "task": task,
                "elapsed": elapsed,
                "returncode": proc.returncode,
                "stdout": proc.stdout,
                "stderr": proc.stderr,
                "runs": [],
            }

        with out_json.open("r", encoding="utf-8") as fh:
            payload = json.load(fh)
        runs = payload.get("balance", {}).get("runs", [])
        return {
            "ok": True,
            "task": task,
            "elapsed": elapsed,
            "runs": runs,
        }
    finally:
        with slot_lock:
            slot_queue.append(slot)


def aggregate_by_build(runs: list[dict]) -> list[dict]:
    groups: dict[str, list[dict]] = {}
    for r in runs:
        key = f"{r['leader']} | {r['build']}"
        groups.setdefault(key, []).append(r)

    results: list[dict] = []
    for key, arr in groups.items():
        n = len(arr)
        wins = sum(1 for r in arr if r.get("won"))
        sum_depth = sum(float(r.get("max_depth", 0)) for r in arr)
        sum_doors = sum(float(r.get("doors_unlocked", 0)) for r in arr)
        sum_cleared = sum(float(r.get("rooms_cleared", 0)) for r in arr)
        sum_time = sum(float(r.get("duration_sec", 0.0)) for r in arr)
        sum_squad = sum(float(r.get("final_squad_size", 0)) for r in arr)
        frame_limits = sum(1 for r in arr if r.get("reason") == "frame_limit")
        sum_dmg = 0.0
        sum_combat_sec = 0.0
        sum_deaths = 0
        for r in arr:
            for st in r.get("classes", {}).values():
                sum_dmg += float(st.get("damage", 0.0))
                sum_combat_sec += float(st.get("combat_unit_sec", 0.0))
                sum_deaths += int(st.get("deaths", 0))

        denom = max(1, n)
        results.append(
            {
                "key": key,
                "runs": n,
                "win_pct": float(wins) / float(denom) * 100.0,
                "avg_depth": sum_depth / float(denom),
                "avg_doors": sum_doors / float(denom),
                "avg_cleared": sum_cleared / float(denom),
                "avg_time": sum_time / float(denom),
                "avg_squad": sum_squad / float(denom),
                "avg_unit_dps": sum_dmg / max(1.0, sum_combat_sec),
                "avg_deaths": float(sum_deaths) / float(denom),
                "frame_limits": frame_limits,
            }
        )

    results.sort(key=lambda b: (-round(b["win_pct"], 2), -b["avg_depth"]))
    return results


def aggregate_classes(runs: list[dict]) -> list[dict]:
    totals: dict[str, dict] = {}
    for r in runs:
        for cid, st in r.get("classes", {}).items():
            acc = totals.setdefault(
                cid,
                {
                    "id": cid,
                    "picks": 0,
                    "sum_max_lv": 0,
                    "runs_present": 0,
                    "damage": 0.0,
                    "healing": 0.0,
                    "damage_taken": 0.0,
                    "deaths": 0,
                    "combat_sec": 0.0,
                    "alive_sec": 0.0,
                },
            )
            acc["picks"] += int(st.get("picks", 0))
            acc["sum_max_lv"] += int(st.get("max_level", 1))
            acc["runs_present"] += 1
            acc["damage"] += float(st.get("damage", 0.0))
            acc["healing"] += float(st.get("healing", 0.0))
            acc["damage_taken"] += float(st.get("damage_taken", 0.0))
            acc["deaths"] += int(st.get("deaths", 0))
            acc["combat_sec"] += float(st.get("combat_unit_sec", 0.0))
            acc["alive_sec"] += float(st.get("alive_unit_sec", 0.0))

    out: list[dict] = []
    for cid, acc in totals.items():
        picks = acc["picks"]
        rp = max(1, acc["runs_present"])
        out.append(
            {
                "id": cid,
                "picks": picks,
                "avg_max_lv": float(acc["sum_max_lv"]) / float(rp),
                "combat_dps": acc["damage"] / max(1.0, acc["combat_sec"]),
                "hps": acc["healing"] / max(1.0, acc["alive_sec"]),
                "dmg_taken_per_pick": acc["damage_taken"] / float(max(1, picks)),
                "deaths": acc["deaths"],
                "death_rate": float(acc["deaths"]) / float(max(1, picks)) * 100.0,
            }
        )
    out.sort(key=lambda c: -c["combat_dps"])
    return out


def finalize_room_buckets(buckets: dict[str, list[dict]], sort_by_key: bool) -> list[dict]:
    keys = sorted(buckets.keys()) if sort_by_key else list(buckets.keys())
    out: list[dict] = []
    for k in keys:
        lst = buckets[k]
        entered = len(lst)
        cleared = sum(1 for rec in lst if rec.get("cleared"))
        sum_time = sum(float(rec.get("clear_time", 0.0)) for rec in lst if rec.get("cleared"))
        sum_hp_lost = sum(float(rec.get("hp_lost_pct", 0.0)) for rec in lst)
        deaths = sum(int(rec.get("deaths", 0)) for rec in lst)
        wipes = sum(int(rec.get("wipes", 0)) for rec in lst)
        out.append(
            {
                "key": k,
                "entered": entered,
                "cleared": cleared,
                "avg_clear_sec": sum_time / float(max(1, cleared)),
                "avg_hp_lost_pct": sum_hp_lost / float(max(1, entered)),
                "deaths": deaths,
                "wipes": wipes,
            }
        )
    return out


def aggregate_archetypes(runs: list[dict]) -> list[dict]:
    buckets: dict[str, list[dict]] = {}
    for r in runs:
        for rec in r.get("rooms", []):
            buckets.setdefault(str(rec.get("archetype", "SLIME_PIT")), []).append(rec)
    return finalize_room_buckets(buckets, False)


def aggregate_depths(runs: list[dict]) -> list[dict]:
    buckets: dict[str, list[dict]] = {}
    for r in runs:
        for rec in r.get("rooms", []):
            buckets.setdefault(f"{int(rec.get('depth', 0)):02d}", []).append(rec)
    return finalize_room_buckets(buckets, True)


def aggregate_reasons(runs: list[dict]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for r in runs:
        reason = r.get("reason") or ("won" if r.get("won") else "leader_dead")
        counts[reason] = counts.get(reason, 0) + 1
    return counts


def aggregate_death_causes(runs: list[dict]) -> list[dict]:
    counts: dict[str, int] = {}
    for r in runs:
        if not r.get("leader_dead"):
            continue
        cause = str(r.get("death_cause", "none"))
        counts[cause] = counts.get(cause, 0) + 1
    out = [{"cause": k, "count": v} for k, v in counts.items()]
    out.sort(key=lambda item: -item["count"])
    return out


def aggregate_door_funnel(runs: list[dict]) -> dict[str, int]:
    funnel = {"B": 0, "G": 0, "Y": 0, "R": 0, "D12": 0}
    for r in runs:
        mask = str(r.get("doors_mask", "-"))
        for key in ("B", "G", "Y", "R"):
            if key in mask:
                funnel[key] += 1
        if r.get("won"):
            funnel["D12"] += 1
    return funnel


def print_class_table(classes: list[dict], title: str) -> None:
    if not classes:
        return
    avg_dps = sum(c["combat_dps"] for c in classes) / float(max(1, len(classes)))
    print(f"\n{title} (Combat Unit DPS avg={avg_dps:.1f}):")
    print(f"  {'Class':<16s}  Picks  AvgLv  UnitDPS   Heal/s  DmgTaken/u  Death%   Flag")
    for c in classes:
        dps = c["combat_dps"]
        hps = c["hps"]
        death_rate = c["death_rate"]
        flag = ""
        if dps >= avg_dps * 1.35:
            flag = "HIGH_DPS"
        elif hps < 0.5 and dps <= avg_dps * 0.65:
            flag = "LOW_DPS"
        if death_rate >= 35.0:
            flag = f"{flag}+FRAGILE" if flag else "FRAGILE"
        print(
            f"  {c['id']:<16s}  {c['picks']:5d}   {c['avg_max_lv']:4.1f}   {dps:6.1f}   {hps:6.2f}"
            f"      {c['dmg_taken_per_pick']:6.1f}   {death_rate:5.1f}%  {flag}"
        )


def print_report(report: dict, title: str) -> None:
    print(f"\n================ {title} ================")
    print(f"Runs Completed: {report['run_count']}")
    reasons_str = ", ".join(f"{k}={v}" for k, v in report["reasons"].items())
    print(f"End Reasons: {reasons_str}")
    if report["death_causes"]:
        causes_str = ", ".join(f"{item['cause']}={item['count']}" for item in report["death_causes"])
        print(f"Death Causes: {causes_str}")
    df = report["door_funnel"]
    print(f"Sector Door Funnel: B={df['B']}  G={df['G']}  Y={df['Y']}  R={df['R']}  D12Win={df['D12']}")

    print("\nBUILD LEADERBOARD:")
    print(f"  {'Leader | Build':<30s}  Runs   Win%  AvgDepth  Doors  Cleared  AvgTime  Squad  UnitDPS  Deaths  FLim")
    for b in report["builds"]:
        print(
            f"  {b['key']:<30s}  {b['runs']:4d}  {b['win_pct']:5.1f}     {b['avg_depth']:5.1f}   {b['avg_doors']:4.1f}"
            f"    {b['avg_cleared']:5.1f}   {b['avg_time']:6.1f}s   {b['avg_squad']:4.1f}   {b['avg_unit_dps']:6.1f}"
            f"   {b['avg_deaths']:5.1f}  {b['frame_limits']:4d}"
        )

    if report["classes_balanced"] and report["classes_mono"]:
        print_class_table(report["classes_balanced"], "CLASS BALANCE BREAKDOWN (BALANCED RUNS)")
        print_class_table(report["classes_mono"], "CLASS BALANCE BREAKDOWN (MONO RUNS)")
    else:
        print_class_table(report["classes"], "CLASS BALANCE BREAKDOWN")

    if report["archetypes"]:
        print("\nROOM ARCHETYPE DIFFICULTY:")
        print(f"  {'Archetype':<16s}  Entered  Cleared  AvgClear  AvgHPLost  Deaths  Wipes")
        for a in report["archetypes"]:
            print(
                f"  {a['key']:<16s}  {a['entered']:7d}  {a['cleared']:7d}    {a['avg_clear_sec']:5.1f}s"
                f"     {a['avg_hp_lost_pct']:5.1f}%  {a['deaths']:6d}  {a['wipes']:5d}"
            )

    if report["depths"]:
        print("\nDEPTH PROGRESSION CURVE:")
        print("  Depth  Entered  Cleared  AvgClear  AvgHPLost  Deaths  Wipes")
        for d in report["depths"]:
            print(
                f"  D{d['key']:<4s}  {d['entered']:7d}  {d['cleared']:7d}    {d['avg_clear_sec']:5.1f}s"
                f"     {d['avg_hp_lost_pct']:5.1f}%  {d['deaths']:6d}  {d['wipes']:5d}"
            )
    print("===========================================================\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Parallel headless Autoplay runner")
    parser.add_argument("--mode", choices=["balance", "matrix"], required=True)
    parser.add_argument("--matrix-set", choices=["all", "balanced", "mono", "comps"], default="all")
    parser.add_argument("--leader", default="knight")
    parser.add_argument("--build", default="balanced")
    parser.add_argument("--seeds", type=int, default=5)
    parser.add_argument("--seed", type=int, default=12345)
    parser.add_argument("--max-depth", type=int, default=12)
    parser.add_argument("--max-frames", type=int, default=108000)
    parser.add_argument("--speed", type=float, default=0.0)
    parser.add_argument("--immortal", default="")
    parser.add_argument("--jobs", type=int, default=8)
    parser.add_argument("--godot-bin", default="")
    parser.add_argument("--out", default="")
    args = parser.parse_args()
    if not args.godot_bin:
        args.godot_bin = shutil.which("godot") or "godot"

    repo_root = Path(__file__).resolve().parent.parent
    tasks = build_tasks(args)
    if not tasks:
        print("No autoplay tasks to run.", file=sys.stderr)
        return 1

    workers = max(1, min(args.jobs, len(tasks)))
    slot_queue = list(range(workers))
    slot_lock = threading.Lock()
    results_by_idx: dict[int, dict] = {}
    failures: list[dict] = []

    print(
        f"[Autoplay Parallel] mode={args.mode} tasks={len(tasks)} workers={workers} "
        f"seeds={args.seeds} seed={args.seed} max_depth={args.max_depth} max_frames={args.max_frames}",
        flush=True,
    )
    t_all = time.monotonic()

    with tempfile.TemporaryDirectory(prefix="escapeteers_autoplay_") as tmp:
        tmp_dir = Path(tmp)
        with ThreadPoolExecutor(max_workers=workers) as pool:
            futures = {
                pool.submit(run_worker, idx, task, slot_queue, slot_lock, repo_root, tmp_dir, args): idx
                for idx, task in enumerate(tasks)
            }
            done_count = 0
            for fut in as_completed(futures):
                idx = futures[fut]
                res = fut.result()
                done_count += 1
                results_by_idx[idx] = res
                task = res["task"]
                if not res["ok"]:
                    failures.append(res)
                    print(
                        f"  [{done_count}/{len(tasks)}] FAIL {task['label']} (rc={res['returncode']}, {res['elapsed']:.1f}s)",
                        file=sys.stderr,
                        flush=True,
                    )
                else:
                    runs = res["runs"]
                    wins = sum(1 for r in runs if r.get("won"))
                    avg_d = sum(float(r.get("max_depth", 0)) for r in runs) / float(max(1, len(runs)))
                    avg_doors = sum(float(r.get("doors_unlocked", 0)) for r in runs) / float(max(1, len(runs)))
                    print(
                        f"  [{done_count}/{len(tasks)}] {task['label']:<28s} wins={wins}/{len(runs)} "
                        f"avgD={avg_d:.1f} doors={avg_doors:.1f} ({res['elapsed']:.1f}s)",
                        flush=True,
                    )

    if failures:
        first = failures[0]
        print(f"\nWorker failed ({len(failures)} total): {first['task']['label']}", file=sys.stderr)
        if first.get("stderr"):
            print(first["stderr"][-2000:], file=sys.stderr)
        if first.get("stdout"):
            print(first["stdout"][-2000:], file=sys.stderr)
        return 1

    all_runs: list[dict] = []
    for idx in range(len(tasks)):
        all_runs.extend(results_by_idx[idx]["runs"])

    balance_report = {
        "run_count": len(all_runs),
        "runs": all_runs,
        "builds": aggregate_by_build(all_runs),
        "reasons": aggregate_reasons(all_runs),
        "death_causes": aggregate_death_causes(all_runs),
        "door_funnel": aggregate_door_funnel(all_runs),
        "classes": aggregate_classes(all_runs),
        "classes_balanced": aggregate_classes([r for r in all_runs if r.get("build") == "balanced"]),
        "classes_mono": aggregate_classes([r for r in all_runs if str(r.get("build", "")).startswith("mono:")]),
        "depths": aggregate_depths(all_runs),
        "archetypes": aggregate_archetypes(all_runs),
    }
    print_report(balance_report, f"AUTOPLAY {args.mode.upper()} REPORT")
    print(f"[Autoplay Parallel] Completed {len(all_runs)} runs in {time.monotonic() - t_all:.1f}s.")

    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {"mode": args.mode, "runs": len(all_runs), "balance": balance_report}
        with out_path.open("w", encoding="utf-8") as fh:
            json.dump(payload, fh, indent="\t")
        print(f"[Autoplay] JSON report saved to: {out_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
