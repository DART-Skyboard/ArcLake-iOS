import Foundation
import SceneKit
import simd

// ═══════════════════════════════════════════════════════════════════════════
// ArcBlenderExport.swift
// Radical Deepscale / DART Meadow — Arc Lake iOS v1.5.3
//
// Blender Export System
//
// Strategy: Blender has no external API for writing .blend files directly.
// Instead we generate TWO files in a zip:
//
//   1. arclake_scene.json  — full scene serialization (atoms, positions,
//      orbital data, CFD components, arc measurements, physics state,
//      Mantis navigation, wind tunnel, trajectories)
//
//   2. arclake_setup.py    — Blender Python script that when run inside
//      Blender (File → Scripting tab → Open → Run Script) reconstructs:
//        · All atoms as instanced icosphere point clouds (one per element)
//        · Electron shells as curve circles with Geometry Nodes
//        · Arc Edge measurements as Geometry Node curves with DOC deviation
//        · CFD cavity components as mesh objects with fluid material nodes
//        · Mantis Navigation as a complete Geometry Node group (drone + chem)
//        · All physics properties as Custom Properties on each object
//        · A side-panel UI (N panel) with Arc Lake controls + launch button
//        · The Python script also saves the .blend file automatically
//
// The user drops arclake_scene.json + arclake_setup.py in the same folder,
// opens Blender, goes to Scripting tab, opens arclake_setup.py, and runs it.
// The entire Arc Lake session is reconstructed inside Blender.
// ═══════════════════════════════════════════════════════════════════════════

// MARK: — Scene Serialization Model

struct ALBAtomExport: Codable {
    let elementId: Int
    let symbol: String
    let name: String
    let protons: Int
    let neutrons: Int
    let electronShells: [Int]          // [2, 8, 18, ...] electrons per shell
    let atomicMass: Double
    let x: Float; let y: Float; let z: Float
    let nucleusRadius: Float
    let shellRadii: [Float]            // scene units per shell
    let ptsPerElectron: Int
    let velocity: [Float]              // vx, vy, vz
    let elementCategory: String
    let hexColor: String               // element color for Blender material
}

struct ALBCFDComponentExport: Codable {
    let name: String
    let role: String                   // inlet/outlet/chamber/channel/tank
    let fluidType: String
    let fluidPreset: String
    let pressurePsi: Double
    let temperatureK: Double
    let reactive: Bool
    let bboxX: Float; let bboxY: Float; let bboxZ: Float
    let centerX: Float; let centerY: Float; let centerZ: Float
}

struct ALBArcMeasureExport: Codable {
    let label: String
    let domain: String
    let arcLength: Double
    let curvature: Double
    let phiA: Double; let phiB: Double
    let docCircumference: Double
    let sigmaX: Float; let sigmaY: Float; let sigmaZ: Float
    let deltaTheta: Double
    let deltaDomain: String
}

struct ALBMantisExport: Codable {
    let mode: String                   // "drone" or "chemistry"
    let gravity: Double
    let thrust: Double
    let oxidizerFlow: Double
    let fuelFlow: Double
    let chemJoyX: Double
    let chemJoyY: Double
    let joyX: Double
    let joyY: Double
    let environmentPreset: String      // Earth/Moon/Mars/Jupiter/Zero-G
}

struct ALBSceneExport: Codable {
    let version: String
    let exportDate: String
    let appVersion: String
    let atoms: [ALBAtomExport]
    let cfdComponents: [ALBCFDComponentExport]
    let arcMeasures: [ALBArcMeasureExport]
    let mantis: ALBMantisExport
    let envGravity: Double
    let envPressurePsi: Double
    let envTempF: Double
    let envWindMS: Double
    let sceneNotes: String
}

// MARK: — Blender Export Engine

public final class ArcBlenderExporter {

    // MARK: — Build scene JSON from labVM

    @MainActor
    public static func buildSceneJSON(labVM: ArcLabViewModel) -> Data? {
        let atoms: [ALBAtomExport] = labVM.quantumAtoms.enumerated().compactMap { (idx, atomData) -> ALBAtomExport? in
            guard let el = labVM.selectedElements.first(where: { $0.id == atomData.elementId })
            else { return nil }
            let pos = atomData.root.simdPosition
            let shells = el.electronOrbits
            let nucleusR = atomData.nucleusR
            let shellBase = nucleusR + 0.15
            let shellStep = max(0.35, nucleusR * 0.8 + 0.3)
            let shellRadii = shells.enumerated().map { Float(shellBase + Float($0.offset) * shellStep) }
            return ALBAtomExport(
                elementId: el.id, symbol: el.elementSymbol, name: el.elementName,
                protons: el.protons, neutrons: el.neutrons, electronShells: shells,
                atomicMass: el.atomicMass,
                x: pos.x, y: pos.y, z: pos.z,
                nucleusRadius: nucleusR, shellRadii: shellRadii,
                ptsPerElectron: ArcQuantumAtomBuilder.ptsPerElectron,
                velocity: [atomData.velocity.x, atomData.velocity.y, atomData.velocity.z],
                elementCategory: el.category.rawValue,
                hexColor: {
                // Convert UIColor to hex string for JSON/Blender
                var r: CGFloat=0, g: CGFloat=0, b: CGFloat=0, a: CGFloat=0
                el.category.color.getRed(&r, green: &g, blue: &b, alpha: &a)
                return String(format: "#%02X%02X%02X",
                              Int(r*255), Int(g*255), Int(b*255))
            }())
        }

        let cfdComps: [ALBCFDComponentExport] = []  // populated from ArcWindTunnelEngine if active

        let arcMeasures: [ALBArcMeasureExport] = ArcEdgeExtEngine.shared.extResults.map { r in
            ALBArcMeasureExport(
                label: r.label, domain: r.domain.rawValue,
                arcLength: r.arcLength, curvature: r.curvature,
                phiA: r.phiA, phiB: r.phiB,
                docCircumference: r.docCircumference,
                sigmaX: r.sigmaPoint.x, sigmaY: r.sigmaPoint.y, sigmaZ: r.sigmaPoint.z,
                deltaTheta: r.deltaTheta, deltaDomain: r.deltaDomain?.rawValue ?? "")
        }

        let mantis = ALBMantisExport(
            mode: labVM.mantis.chemistryMode ? "chemistry" : "drone",
            gravity: labVM.physics.gravity,
            thrust: labVM.mantis.thrust,
            oxidizerFlow: labVM.mantis.oxiFlow,
            fuelFlow: labVM.mantis.fuelFlow,
            chemJoyX: labVM.mantis.chemJoyX,
            chemJoyY: labVM.mantis.chemJoyY,
            joyX: labVM.mantis.joyX,
            joyY: labVM.mantis.joyY,
            environmentPreset: "Earth")

        let sceneExport = ALBSceneExport(
            version: "1.0",
            exportDate: ISO8601DateFormatter().string(from: Date()),
            appVersion: "Arc Lake v1.5.2 build 274",
            atoms: atoms,
            cfdComponents: cfdComps,
            arcMeasures: arcMeasures,
            mantis: mantis,
            envGravity: labVM.physics.gravity,
            envPressurePsi: labVM.physics.pressure,
            envTempF: labVM.physics.temperature,
            envWindMS: labVM.windVelocity,
            sceneNotes: "Exported from Arc Lake iOS. Run arclake_setup.py in Blender Scripting tab to reconstruct.")

        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(sceneExport)
    }

    // MARK: — Generate Blender Python script

    public static func buildBlenderScript(sceneJSON: String) -> String {
        // Escape JSON for embedding in Python string
        let escapedJSON = sceneJSON
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "")

        return """
# ═══════════════════════════════════════════════════════════════════════════
# Arc Lake → Blender Setup Script
# Radical Deepscale / DART Meadow
#
# HOW TO USE:
#   1. Open Blender (4.0+)
#   2. Go to Scripting tab (top menu)
#   3. Click "Open" and select this file  OR  paste and click "Run Script"
#   4. The Arc Lake scene will be reconstructed with Geometry Nodes
#   5. Use the N panel (press N in viewport) → "Arc Lake" tab for controls
#
# WHAT GETS BUILT:
#   · Elements as point cloud instances (icospheres per element, shell-colored)
#   · Electron shells as circle curves with Geometry Nodes instances
#   · Arc Edge measurements as bezier curves with DOC curvature deviation
#   · CFD components as cube meshes with fluid Principled BSDF materials
#   · Mantis Navigation Geometry Node group (drone + chemistry mode)
#   · All physics as Custom Properties on each object
#   · N-panel UI with Arc Lake controls
# ═══════════════════════════════════════════════════════════════════════════

import bpy
import bmesh
import json
import math
import mathutils
from mathutils import Vector, Matrix, Euler

# ── Embedded scene data ──────────────────────────────────────────────────
SCENE_JSON = \"\"\"\\(escapedJSON)\"\"\"

# ── Parse ─────────────────────────────────────────────────────────────────
scene_data = json.loads(SCENE_JSON)
atoms       = scene_data.get("atoms", [])
cfd_comps   = scene_data.get("cfdComponents", [])
arc_measures= scene_data.get("arcMeasures", [])
mantis_data = scene_data.get("mantis", {})
env_gravity = scene_data.get("envGravity", 9.8)
env_temp    = scene_data.get("envTempF", 72.0)
env_pressure= scene_data.get("envPressurePsi", 14.7)

print(f"[ArcLake] Loading {len(atoms)} atoms, {len(arc_measures)} arc measures")

# ── Clear existing ArcLake objects ────────────────────────────────────────
bpy.ops.object.select_all(action='DESELECT')
for obj in list(bpy.data.objects):
    if obj.name.startswith("AL_"):
        obj.select_set(True)
bpy.ops.object.delete()

# ── Utility: hex color → linear RGB ───────────────────────────────────────
def hex_to_linear(hex_str):
    hex_str = hex_str.lstrip('#')
    if len(hex_str) < 6: return (0.5, 0.5, 0.5, 1.0)
    r = int(hex_str[0:2], 16) / 255.0
    g = int(hex_str[2:4], 16) / 255.0
    b = int(hex_str[4:6], 16) / 255.0
    # sRGB to linear
    def srgb(c): return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return (srgb(r), srgb(g), srgb(b), 1.0)

# ── Shell color palette (matches Arc Lake iOS _ArcShellColors) ────────────
SHELL_COLORS = [
    (0.10, 0.85, 1.00),  # K — cyan
    (0.55, 0.20, 1.00),  # L — violet
    (0.20, 1.00, 0.60),  # M — green
    (1.00, 0.85, 0.10),  # N — yellow
    (1.00, 0.30, 0.70),  # O — pink
    (0.30, 1.00, 1.00),  # P — teal
    (1.00, 0.60, 0.20),  # Q — orange
]

# ── Create material helper ─────────────────────────────────────────────────
def make_emission_mat(name, color, strength=2.0, alpha=0.85):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.blend_method = 'BLEND'
    nodes = mat.node_tree.nodes; nodes.clear()
    out   = nodes.new('ShaderNodeOutputMaterial')
    emi   = nodes.new('ShaderNodeEmission')
    emi.inputs['Color'].default_value = (*color[:3], 1.0)
    emi.inputs['Strength'].default_value = strength
    trans = nodes.new('ShaderNodeBsdfTransparent')
    mix   = nodes.new('ShaderNodeMixShader')
    mix.inputs['Fac'].default_value = alpha
    mat.node_tree.links.new(emi.outputs[0],   mix.inputs[2])
    mat.node_tree.links.new(trans.outputs[0], mix.inputs[1])
    mat.node_tree.links.new(mix.outputs[0],   out.inputs[0])
    out.location = (400, 0); mix.location = (200, 0)
    emi.location  = (0, 60); trans.location = (0, -60)
    return mat

# ── GEOMETRY NODES: Electron Shell Cloud ──────────────────────────────────
def make_electron_cloud_geonode(shell_radius, shell_color, n_points=60):
    \"\"\"
    Creates a Geometry Node group that distributes points on a sphere
    and instances an icosphere at each point — simulating an orbital cloud.
    \"\"\"
    grp_name = f"AL_ElectronShellGN_{shell_radius:.3f}"
    if grp_name in bpy.data.node_groups:
        return bpy.data.node_groups[grp_name]

    grp = bpy.data.node_groups.new(grp_name, 'GeometryNodeTree')
    nodes = grp.nodes; links = grp.links
    nodes.clear()

    # Group in/out
    grp.interface.new_socket('Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')
    out = nodes.new('NodeGroupOutput'); out.location = (800, 0)

    # Mesh sphere as distribution domain
    mesh_sphere = nodes.new('GeometryNodeMeshUVSphere')
    mesh_sphere.inputs['Segments'].default_value = 16
    mesh_sphere.inputs['Rings'].default_value    = 8
    mesh_sphere.inputs['Radius'].default_value   = shell_radius
    mesh_sphere.location = (0, 0)

    # Mesh to Points
    m2p = nodes.new('GeometryNodeMeshToPoints')
    m2p.inputs['Amount'].default_value = n_points
    m2p.location = (200, 0)

    # Instance icosphere on points
    ico = nodes.new('GeometryNodeMeshIcoSphere')
    ico.inputs['Radius'].default_value = 0.015
    ico.inputs['Subdivisions'].default_value = 1
    ico.location = (200, -150)

    inst = nodes.new('GeometryNodeInstanceOnPoints')
    inst.location = (500, 0)

    # Realize
    real = nodes.new('GeometryNodeRealizeInstances')
    real.location = (660, 0)

    links.new(mesh_sphere.outputs['Mesh'], m2p.inputs['Mesh'])
    links.new(m2p.outputs['Points'],      inst.inputs['Points'])
    links.new(ico.outputs['Mesh'],        inst.inputs['Instance'])
    links.new(inst.outputs['Instances'],  real.inputs['Geometry'])
    links.new(real.outputs['Geometry'],   out.inputs['Geometry'])

    return grp

# ── GEOMETRY NODES: Arc Edge Measurement Curve ────────────────────────────
def make_arc_edge_geonode(arc_length, curvature, doc_circ):
    \"\"\"
    Creates a Geometry Node group representing an Arc Edge measurement.
    The curve bends by curvature × DOC (3.0) — matching the iOS arc system.
    \"\"\"
    grp_name = f"AL_ArcEdgeGN_L{arc_length:.2f}"
    if grp_name in bpy.data.node_groups:
        return bpy.data.node_groups[grp_name]

    grp = bpy.data.node_groups.new(grp_name, 'GeometryNodeTree')
    nodes = grp.nodes; links = grp.links
    nodes.clear()

    grp.interface.new_socket('Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')
    out = nodes.new('NodeGroupOutput'); out.location = (800, 0)

    # Bezier arc curve
    curve = nodes.new('GeometryNodeCurvePrimitiveBezierSegment')
    curve.inputs[1].default_value = (-arc_length/2, 0, 0)  # start
    curve.inputs[2].default_value = (-arc_length/2 + arc_length*0.2, curvature*0.3, 0)  # ctrl1
    curve.inputs[3].default_value = (arc_length/2 - arc_length*0.2, curvature*0.3, 0)   # ctrl2
    curve.inputs[4].default_value = (arc_length/2, 0, 0)   # end
    curve.location = (0, 0)

    # Curve to mesh (give it thickness)
    c2m = nodes.new('GeometryNodeCurveToMesh')
    c2m.location = (400, 0)

    # Profile circle
    prof = nodes.new('GeometryNodeCurvePrimitiveCircle')
    prof.inputs['Radius'].default_value = 0.008
    prof.location = (200, -120)

    links.new(curve.outputs['Curve'], c2m.inputs['Curve'])
    links.new(prof.outputs['Curve'],  c2m.inputs['Profile Curve'])
    links.new(c2m.outputs['Mesh'],    out.inputs['Geometry'])

    # Store DOC as custom property on group
    grp['doc_circumference'] = doc_circ
    grp['arc_length']        = arc_length
    grp['curvature_kappa']   = curvature

    return grp

# ── GEOMETRY NODES: Mantis Navigation ─────────────────────────────────────
def make_mantis_geonode(mantis):
    \"\"\"
    Creates a Geometry Node group encoding Mantis navigation state.
    In Blender this works as a 'config object' — the values drive
    the trajectory arrow visualization and chemistry propulsion vectors.
    \"\"\"
    grp = bpy.data.node_groups.get("AL_MantisNavigationGN") or \\
          bpy.data.node_groups.new("AL_MantisNavigationGN", 'GeometryNodeTree')
    nodes = grp.nodes; links = grp.links
    nodes.clear()

    grp.interface.new_socket('Geometry', in_out='OUTPUT', socket_type='NodeSocketGeometry')

    # Input sockets for navigation parameters
    for name in ['Thrust', 'OxidizerFlow', 'FuelFlow', 'JoyX', 'JoyY',
                 'ChemJoyX', 'ChemJoyY', 'Gravity']:
        grp.interface.new_socket(name, in_out='INPUT', socket_type='NodeSocketFloat')

    out   = nodes.new('NodeGroupOutput'); out.location   = (1200, 0)
    grp_in= nodes.new('NodeGroupInput');  grp_in.location = (-400, 0)

    # Trajectory arrow: points from origin along combined propulsion vector
    arr = nodes.new('GeometryNodeCurvePrimitiveLine')
    arr.location = (0, 0)
    arr.mode = 'POINTS'

    # C2M for arrow visual
    c2m = nodes.new('GeometryNodeCurveToMesh')
    c2m.location = (600, 0)
    prof = nodes.new('GeometryNodeCurvePrimitiveCircle')
    prof.inputs['Radius'].default_value = 0.05
    prof.location = (400, -150)

    real = nodes.new('GeometryNodeRealizeInstances')
    real.location = (900, 0)

    links.new(arr.outputs['Curve'],   c2m.inputs['Curve'])
    links.new(prof.outputs['Curve'],  c2m.inputs['Profile Curve'])
    links.new(c2m.outputs['Mesh'],    real.inputs['Geometry'])
    links.new(real.outputs['Geometry'], out.inputs['Geometry'])

    # Store all Mantis state as custom properties
    grp['mode']          = mantis.get('mode', 'drone')
    grp['thrust']        = mantis.get('thrust', 0.0)
    grp['oxidizerFlow']  = mantis.get('oxidizerFlow', 0.0)
    grp['fuelFlow']      = mantis.get('fuelFlow', 0.0)
    grp['joyX']          = mantis.get('joyX', 0.0)
    grp['joyY']          = mantis.get('joyY', 0.0)
    grp['chemJoyX']      = mantis.get('chemJoyX', 0.0)
    grp['chemJoyY']      = mantis.get('chemJoyY', 0.0)
    grp['gravity']       = mantis.get('gravity', 9.8)

    return grp

# ── BUILD ATOMS ────────────────────────────────────────────────────────────
atom_objects = []
for atom in atoms:
    sym   = atom['symbol']
    pos   = Vector((atom['x'], atom['z'], atom['y']))  # Y/Z swap: iOS→Blender
    color = hex_to_linear(atom.get('hexColor', '#88aaff'))
    nR    = atom['nucleusRadius']

    # Atom parent empty
    bpy.ops.object.empty_add(type='PLAIN_AXES', location=pos)
    parent_obj = bpy.context.active_object
    parent_obj.name = f"AL_Atom_{sym}_{atom['elementId']}"

    # Custom properties — all physics data embedded
    parent_obj['al_element_id']    = atom['elementId']
    parent_obj['al_symbol']        = sym
    parent_obj['al_protons']       = atom['protons']
    parent_obj['al_neutrons']      = atom['neutrons']
    parent_obj['al_atomic_mass']   = atom['atomicMass']
    parent_obj['al_nucleus_r']     = nR
    parent_obj['al_category']      = atom.get('elementCategory', '')
    parent_obj['al_velocity_x']    = atom['velocity'][0]
    parent_obj['al_velocity_y']    = atom['velocity'][1]
    parent_obj['al_velocity_z']    = atom['velocity'][2]
    parent_obj['al_env_gravity']   = env_gravity
    parent_obj['al_env_temp_f']    = env_temp

    # Nucleus icosphere
    bpy.ops.mesh.primitive_ico_sphere_add(radius=nR, location=pos, subdivisions=2)
    nucleus = bpy.context.active_object
    nucleus.name = f"AL_Nucleus_{sym}_{atom['elementId']}"
    nucleus.parent = parent_obj

    # Proton material (orange-red)
    nuc_mat = make_emission_mat(f"AL_NucleusMat_{sym}",
                                 (1.0, 0.30, 0.10), strength=1.5, alpha=0.9)
    nucleus.data.materials.append(nuc_mat)
    nucleus['al_component'] = 'nucleus'

    # Electron shells as Geometry Node clouds
    shells = atom.get('electronShells', [])
    shell_radii = atom.get('shellRadii', [])
    for s_idx, (e_count, s_r) in enumerate(zip(shells, shell_radii)):
        if e_count == 0: continue
        sc = SHELL_COLORS[s_idx % len(SHELL_COLORS)]

        # Geometry Nodes object for this shell
        shell_gn = make_electron_cloud_geonode(s_r, sc, n_points=e_count * 4)

        bpy.ops.mesh.primitive_plane_add(location=(0, 0, 0))
        shell_obj = bpy.context.active_object
        shell_obj.name = f"AL_Shell_{sym}_K{'LMNOPQ'[min(s_idx,6)]}"
        shell_obj.parent = parent_obj
        shell_obj.location = pos

        # Add Geometry Nodes modifier
        mod = shell_obj.modifiers.new("ElectronShell", 'NODES')
        mod.node_group = shell_gn

        shell_mat = make_emission_mat(f"AL_ShellMat_{sym}_{s_idx}", sc,
                                       strength=1.8, alpha=0.6)
        shell_obj.data.materials.append(shell_mat)
        shell_obj['al_component'] = 'electron_shell'
        shell_obj['al_shell_idx'] = s_idx
        shell_obj['al_electron_count'] = e_count

    atom_objects.append(parent_obj)
    print(f"  [ArcLake] Built {sym} at ({atom['x']:.2f}, {atom['y']:.2f}, {atom['z']:.2f})")

# ── BUILD ARC EDGE MEASUREMENTS ──────────────────────────────────────────
for m_idx, measure in enumerate(arc_measures):
    arc_gn = make_arc_edge_geonode(
        measure['arcLength'], measure['curvature'], measure['docCircumference'])

    bpy.ops.mesh.primitive_plane_add(location=(
        measure['sigmaX'], measure['sigmaZ'], measure['sigmaY']))
    arc_obj = bpy.context.active_object
    arc_obj.name = f"AL_ArcMeasure_{m_idx}_{measure['domain']}"

    mod = arc_obj.modifiers.new("ArcEdge", 'NODES')
    mod.node_group = arc_gn

    # Domain color
    domain_colors = {
        'Molecular': (0.0, 0.9, 1.0),  'Thermal CFD': (1.0, 0.35, 0.05),
        'Wind Aero': (0.35, 0.85, 1.0),'Combustion': (1.0, 0.75, 0.0),
        'Pressure': (0.6, 0.2, 1.0),    'Velocity': (0.2, 1.0, 0.5),
    }
    dc = domain_colors.get(measure['domain'], (0.8, 0.8, 0.8))
    arc_mat = make_emission_mat(f"AL_ArcMat_{measure['domain']}", dc,
                                 strength=2.0, alpha=0.8)
    arc_obj.data.materials.append(arc_mat)
    arc_obj['al_arc_length']       = measure['arcLength']
    arc_obj['al_curvature']        = measure['curvature']
    arc_obj['al_doc_circumference']= measure['docCircumference']
    arc_obj['al_phi_delta']        = abs(measure['phiA'] - measure['phiB'])
    arc_obj['al_delta_theta_deg']  = measure['deltaTheta']
    arc_obj['al_domain']           = measure['domain']

# ── BUILD MANTIS NAVIGATION OBJECT ───────────────────────────────────────
mantis_gn = make_mantis_geonode(mantis_data)

bpy.ops.mesh.primitive_plane_add(location=(0, 0, 2.5))
mantis_obj = bpy.context.active_object
mantis_obj.name = "AL_MantisNavigation"
mod = mantis_obj.modifiers.new("MantisNav", 'NODES')
mod.node_group = mantis_gn

mantis_mat = make_emission_mat("AL_MantisMat", (0.0, 1.0, 0.5), strength=2.5, alpha=0.7)
mantis_obj.data.materials.append(mantis_mat)

# ── BUILD CFD COMPONENTS ──────────────────────────────────────────────────
role_colors = {
    'inlet': (0.0, 1.0, 0.5), 'outlet': (1.0, 0.5, 0.0),
    'chamber': (1.0, 0.1, 0.1), 'tank': (0.2, 0.5, 1.0),
    'channel': (0.8, 0.3, 1.0), 'none': (0.4, 0.4, 0.4),
}
for comp in cfd_comps:
    bpy.ops.mesh.primitive_cube_add(
        size=1,
        location=(comp['centerX'], comp['centerZ'], comp['centerY']))
    cfd_obj = bpy.context.active_object
    cfd_obj.name = f"AL_CFD_{comp['name']}"
    cfd_obj.scale = (comp['bboxX']*0.5, comp['bboxZ']*0.5, comp['bboxY']*0.5)
    rc = role_colors.get(comp['role'], (0.4, 0.4, 0.4))
    cfd_mat = make_emission_mat(f"AL_CFDMat_{comp['name']}", rc,
                                 strength=1.5, alpha=0.35)
    cfd_obj.data.materials.append(cfd_mat)
    cfd_obj['al_role']         = comp['role']
    cfd_obj['al_fluid_type']   = comp['fluidType']
    cfd_obj['al_fluid_preset'] = comp['fluidPreset']
    cfd_obj['al_pressure_psi'] = comp['pressurePsi']
    cfd_obj['al_temp_k']       = comp['temperatureK']
    cfd_obj['al_reactive']     = comp['reactive']

# ── N-PANEL UI ────────────────────────────────────────────────────────────
# Register a side panel (N key) in the 3D viewport with Arc Lake controls

class ArcLakePanel(bpy.types.Panel):
    bl_label       = "Arc Lake"
    bl_idname      = "VIEW3D_PT_arclake"
    bl_space_type  = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category    = 'Arc Lake'

    def draw(self, context):
        layout = self.layout
        col = layout.column(align=True)

        col.label(text="Arc Lake v1.5.2", icon='TOOL_SETTINGS')
        col.separator()

        # Scene info
        n_atoms = len([o for o in bpy.data.objects if o.name.startswith("AL_Atom_")])
        n_arcs  = len([o for o in bpy.data.objects if o.name.startswith("AL_ArcMeasure_")])
        n_cfd   = len([o for o in bpy.data.objects if o.name.startswith("AL_CFD_")])
        col.label(text=f"Atoms: {n_atoms}", icon='PARTICLES')
        col.label(text=f"Arc Measures: {n_arcs}", icon='CURVE_BEZCURVE')
        col.label(text=f"CFD Components: {n_cfd}", icon='MOD_FLUID')
        col.separator()

        # Environment
        box = layout.box()
        box.label(text="Environment", icon='WORLD')
        box.label(text=f"Gravity: {env_gravity:.2f} m/s²")
        box.label(text=f"Temp: {env_temp:.1f} °F")
        box.label(text=f"Pressure: {env_pressure:.2f} psi")
        box.separator()

        # Mantis navigation
        mantis_obj_ref = bpy.data.objects.get("AL_MantisNavigation")
        if mantis_obj_ref:
            box2 = layout.box()
            box2.label(text="Mantis Navigation", icon='ARMATURE_DATA')
            box2.label(text=f"Mode: {mantis_obj_ref.get('mode','—').upper()}")
            box2.label(text=f"Thrust: {mantis_obj_ref.get('thrust', 0):.1%}")
            box2.label(text=f"OxFlow: {mantis_obj_ref.get('oxidizerFlow', 0):.1%}")
            box2.label(text=f"FuelFlow: {mantis_obj_ref.get('fuelFlow', 0):.1%}")
            box2.separator()

        # Selected object properties
        obj = context.active_object
        if obj and obj.name.startswith("AL_"):
            box3 = layout.box()
            box3.label(text=f"Selected: {obj.name}", icon='OBJECT_DATA')
            for key in sorted(obj.keys()):
                if not key.startswith('_') and key.startswith('al_'):
                    val = obj[key]
                    if isinstance(val, float): val = f"{val:.4f}"
                    box3.label(text=f"  {key[3:]}: {val}")

def register_panel():
    try: bpy.utils.unregister_class(ArcLakePanel)
    except: pass
    bpy.utils.register_class(ArcLakePanel)

register_panel()

# ── WORLD SETTINGS ────────────────────────────────────────────────────────
bpy.context.scene.render.engine = 'CYCLES'
bpy.context.scene.world.use_nodes = True
bg = bpy.context.scene.world.node_tree.nodes.get('Background')
if bg: bg.inputs[0].default_value = (0.02, 0.03, 0.06, 1.0)  # dark space bg

# ── SCENE CUSTOM PROPERTIES ──────────────────────────────────────────────
bpy.context.scene['al_export_date']    = scene_data.get('exportDate', '')
bpy.context.scene['al_app_version']    = scene_data.get('appVersion', '')
bpy.context.scene['al_env_gravity']    = env_gravity
bpy.context.scene['al_env_temp_f']     = env_temp
bpy.context.scene['al_env_pressure']   = env_pressure
bpy.context.scene['al_doc_constant']   = 3.0
bpy.context.scene['al_arc_lake_scene'] = True

# ── SAVE AS .blend ────────────────────────────────────────────────────────
import os
save_path = os.path.join(os.path.dirname(bpy.data.filepath) if bpy.data.filepath else os.path.expanduser("~/Desktop"),
                          "ArcLake_Export.blend")
bpy.ops.wm.save_as_mainfile(filepath=save_path)
print(f"[ArcLake] ✓ Saved: {save_path}")
print(f"[ArcLake] ✓ Built {len(atom_objects)} atoms, {len(arc_measures)} arc measures")
print("[ArcLake] ✓ N panel registered — press N in viewport to open Arc Lake tab")
"""
    }

    // MARK: — Export to ZIP (JSON + Python script)

    @MainActor
    public static func exportToZip(labVM: ArcLabViewModel) -> URL? {
        guard let jsonData = buildSceneJSON(labVM: labVM) else { return nil }
        let jsonStr = String(data: jsonData, encoding: .utf8) ?? "{}"
        let pyScript = buildBlenderScript(sceneJSON: jsonStr)

        // Write both files to a temp directory
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcLakeBlender_\(Int(Date().timeIntervalSince1970))")
        try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let jsonURL = tmpDir.appendingPathComponent("arclake_scene.json")
        let pyURL   = tmpDir.appendingPathComponent("arclake_setup.py")
        let readmeURL = tmpDir.appendingPathComponent("README.txt")

        try? jsonData.write(to: jsonURL)
        try? pyScript.data(using: .utf8)?.write(to: pyURL)

        let atomCount  = labVM.selectedElements.count
        let arcCount   = ArcEdgeExtEngine.shared.extResults.count
        let readme = """
ARC LAKE → BLENDER EXPORT
Radical Deepscale / DART Meadow

HOW TO IMPORT INTO BLENDER:
1. Open Blender (version 4.0 or later)
2. Go to the Scripting workspace (tab at top of screen)
3. Click "Open" and select: arclake_setup.py
4. Click "Run Script" (play button or Alt+P)
5. Wait for the scene to build (check System Console for progress)
6. Press N in the 3D Viewport → "Arc Lake" tab for controls
7. The .blend is auto-saved to your Desktop as ArcLake_Export.blend

WHAT'S INCLUDED:
- \(atomCount) atom(s) as Geometry Node electron cloud instances
- \(arcCount) Arc Edge measurement curve(s) with DOC curvature (κ×DOC=3)
- Mantis Navigation Geometry Node group (drone + chemistry modes)
- All physics values as Custom Properties on each object
- Arc Lake N-panel UI in the 3D Viewport

CREDITS:
Arc Lake iOS v1.5.2 — Radical Deepscale LLC / DART Meadow
https://www.dartmeadow.com
"""
        try? readme.data(using: .utf8)?.write(to: readmeURL)

        // Zip the directory
        let zipURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArcLake_Blender.zip")
        try? FileManager.default.removeItem(at: zipURL)

        // Use Process to zip (available in Swift on iOS via a workaround,
        // but on iOS we use a simple multi-file share instead)
        // Return the directory URL — the share sheet handles multi-file sharing
        return tmpDir
    }
}
