# Circuit Bastion desktop architecture

The Godot project is the primary game implementation. The older Node prototype
remains a reference build and release fallback.

## Runtime layers

```text
game_root.gd
  ├─ BattleView             presentation and player commands
  └─ CircuitSimulation      fixed-step deterministic domain state
       ├─ modules / links / rules
       ├─ enemies / waves / boss
       └─ event log / replay / save state
```

The simulation is UI-independent. It advances in fixed 100 ms steps and uses a
seeded integer generator. UI commands are recorded in `BastionReplay`, so the
same seed and command sequence produce the same replay signature.

## P0 slice

- One 8×6 PCB-style battlefield and one core
- Five placed modules, three connection types, and readable signal paths
- Ten deterministic waves with six enemy archetypes and a final boss
- Pause, 1×/2×/4× speed, event trace, replay export, save/load state
- Headless scene, simulation, and interaction smoke probes

## Growth path

- Move module, enemy, wave, and firmware definitions into versioned data assets
- Add command-driven `GameSession` orchestration for preparation, battle, and recap phases
- Replace static presentation hints with live connection topology and module placement
- Add audio buses, signal pulse emitters, damage feedback, and export-platform QA

## Test contract

The required smoke probes are intentionally explicit because Godot can return
success after a script load failure. `godot_smoke.gd` checks scene instantiation,
`simulation_probe.gd` checks deterministic replay and save/load, and `qa_smoke.gd`
checks pause, speed, and wave progression.

## Native world contract

The deterministic simulation owns deployment and movement through direct command methods. Its event log is telemetry for UI, audio, replay, and diagnostics. It is not an input table for changing module state.

The headless native motion probe instantiates Godot Node2D, CharacterBody2D, StaticBody2D, and CollisionShape2D nodes. It checks collision response, bounded smooth movement substeps, and a deployed module node with a collision shape. Desktop CI, Android validation, and release Godot checks run this probe.
