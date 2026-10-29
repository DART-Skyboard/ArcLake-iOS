# ArcLake project format (`*.ash`) and module presets

`*.ash` is a JSON document holding the complete, versioned application state
(like a `.blend`). Source: `Sources/ArcLakeApp/Ash/`.

```jsonc
{
  "format": "arclake.ash",
  "schemaVersion": 1,
  "appVersion": "1.5.9", "appBuild": "412",
  "createdAt": "ISO8601", "updatedAt": "ISO8601",
  "revision": 17,                 // +1 per persisted change; sync ordering
  "deviceId": "uuid", "sessionId": "uuid", "name": "My session",
  "modules": {                    // one entry per module, each independent
    "ui":        { "moduleVersion": 1, "settings": { "global": {...} } },
    "theme":     { ... }, "render": { ... }, "camera": { ... },
    "physics":   { ... }, "algebra": { ... }, "chemistry": { ... },
    "scene":     { "settings": { "tabs": [ { "index": 0, "assets": [ { "nodeName", "name", "sha256", "bytes", "source", "transform": {...} } ] } ] } },
    "fluid":     { "settings": { "global": {...}, "parts": { "<partKey>": {...} } } },
    "mantis":    { ... }
  },
  "assets": [ { "name", "fileName", "ext", "sha256", "bytes", "source", "storage" } ],
  "embeddedAssets": { "<sha256>": "<base64 GLB>" }   // only in "Save As" copies with embedding on
}
```

Forward compatibility: unknown top-level fields, unknown modules and unknown
fields inside known modules are preserved on load/save.

## Module preset (`*.arcmodule.json`)

```json
{"schema":"arclake.module-preset","version":1,"module":"fluid",
 "createdAt":"ISO8601","appVersion":"1.5.9",
 "asset":{"name":"Combustion_flow","sha256":"…","bytes":123,"source":"imported",
          "parts":[{"key":"Oxidizer","name":"Oxidizer","bbox":[minX,minY,minZ,maxX,maxY,maxZ]}]},
 "settings":{"global":{…},"parts":{"<partKey>":{…}}}}
```

Importing replaces only that module's state. Part keys are mesh node names
(duplicates get `#2`, `#3`…); on import parts are matched by key, then by `name`
via `asset.parts`. A bare `{ "global", "parts" }` object (no envelope) is
accepted as a `fluid` preset.

### `fluid` settings keys

`global`: `mode` (Liquid|Gas|Viscous|Granular), `scenePreset`, `particleVisual`,
`particleCount`, `gravityScale`, `smoothingH`, `envTempK`, `envPressurePa`,
`autoSealEnabled`, `liveLeaksEnabled`, `floorHeatEnabled`, `xrayGlow`,
`extensions{}` (open-ended: other code registers state via
`ArcAshFluidExtensions.register`).
`parts[key]`: `name`, `alloy{name,densityKgM3,thermalConductivity,
tensileStrengthMPa,maxTempK,maxPressureMPa,specificHeat,emissivity}`, `isInlet`,
`isOutlet`, `inletFlowRate`, `fillLevel`, `particleCapacity`,
`particlesPerM3Visible`, `pressurePsi`, `isCombustionChamber`,
`fluidType` (Fuel|Oxidizer), `geometricKind` (container|pipe|unknown),
`connectedContainerNames[]`. Common aliases are accepted (`ambientTempK`,
`pressure_psi`, `flowRate`, `kind`, …). `thermal` is a focused view onto the
temperature/pressure/alloy subset of `fluid`.

## Sync

Signed in with GitHub → private repo `<you>/arclake-ash`
(`sessions/<sessionId>.ash`, `assets/<sha256>.<ext>`, ≤ 25 MB per asset, larger
files stay reference-only). Signed in with Apple only → iCloud vault
`Autumn-Ash/ArcLake/sessions` (+ `models`). Conflicts: last writer (by
`updatedAt`) wins; the loser is kept as a forked session named
"… (conflict …)".
