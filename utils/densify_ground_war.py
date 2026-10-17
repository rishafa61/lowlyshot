#!/usr/bin/env python3
"""
densify_ground_war.py
Generates rich, crowded, multiplayer-ready structures, forests, compounds,
towers, covers, trenches, barricades, and details for Ground War (800x800).
Strictly checks exclusion zones to prevent overlaps with existing gameplay elements.
"""

import math
import random

random.seed(1337)

# Defined exclusion zones: (center_x, center_z, radius)
EXCLUSION_CIRCLES = [
    (0, 0, 42),         # Flag & Hill center
    (100, -100, 45),    # Town
    (110, 110, 42),     # Factory
    (-84, -18, 38),     # Factory2
    (-84, 140, 38),     # Factory3
    (-115, 80, 25),     # RadioTower
    (300, 0, 45),       # OutpostEast
    (-310, 45, 45),     # WarehouseWest
    (-290, 300, 45),    # VillageSW
    (290, 270, 45),     # ContainerYard
    (260, -260, 25),    # WatchtowerNE
    (-260, 260, 25),    # WatchtowerSW
    (-140, 40, 32),     # MoundW
    (-39.5, 104.7, 32), # MoundW2
    (26.6, -95.5, 32),  # MoundW3
    (150, -45, 30),     # MoundE
    (-150, -150, 35),   # MoundSW
]

# Rectangular exclusion boxes: (min_x, max_x, min_z, max_z)
EXCLUSION_BOXES = [
    # Base Attackers zone (keep vehicle runways and spawn areas clear)
    (-130, 160, -195, -145),
    # Base Defenders zone
    (-130, 160, 145, 195),
]

def is_excluded(x, z, clearance=4.0):
    for cx, cz, r in EXCLUSION_CIRCLES:
        dist = math.hypot(x - cx, z - cz)
        if dist < (r + clearance):
            return True
    for x1, x2, z1, z2 in EXCLUSION_BOXES:
        if (x1 - clearance) <= x <= (x2 + clearance) and (z1 - clearance) <= z <= (z2 + clearance):
            return True
    # Keep absolute boundary wall clearance (map is 800x800, so +/- 385 max)
    if abs(x) > 380 or abs(z) > 380:
        return True
    return False

def add_node(name, ntype, parent="NavigationRegion3D", x=0.0, y=0.0, z=0.0, rot_y_deg=0.0):
    lines = [
        f'[node name="{name}" type="{ntype}" parent="{parent}"]'
    ]
    if rot_y_deg != 0.0:
        rad = math.radians(rot_y_deg)
        c = math.cos(rad)
        s = math.sin(rad)
        lines.append(f'transform = Transform3D({c:.6f}, 0, {s:.6f}, 0, 1, 0, {-s:.6f}, 0, {c:.6f}, {x:.3f}, {y:.3f}, {z:.3f})')
    else:
        lines.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:.3f}, {y:.3f}, {z:.3f})')
    return lines

def add_csg_box(name, parent, x, y, z, sx, sy, sz, mat, collision=True, rot_y_deg=0.0):
    lines = add_node(name, "CSGBox3D", parent, x, y, z, rot_y_deg)
    lines.append(f'material_override = SubResource("{mat}")')
    if collision:
        lines.append('use_collision = true')
    lines.append(f'size = Vector3({sx:.3f}, {sy:.3f}, {sz:.3f})')
    lines.append('')
    return "\n".join(lines)

def add_csg_cyl(name, parent, x, y, z, radius, height, mat, collision=True, sides=12):
    lines = add_node(name, "CSGCylinder3D", parent, x, y, z)
    lines.append(f'material_override = SubResource("{mat}")')
    if collision:
        lines.append('use_collision = true')
    lines.append(f'radius = {radius:.3f}')
    lines.append(f'height = {height:.3f}')
    lines.append(f'sides = {sides}')
    lines.append('')
    return "\n".join(lines)

def add_csg_sphere(name, parent, x, y, z, radius, mat, scale_y=0.4, collision=True):
    lines = [
        f'[node name="{name}" type="CSGSphere3D" parent="{parent}"]',
        f'transform = Transform3D(1, 0, 0, 0, {scale_y:.3f}, 0, 0, 0, 1, {x:.3f}, {y:.3f}, {z:.3f})',
        f'material_override = SubResource("{mat}")',
    ]
    if collision:
        lines.append('use_collision = true')
    lines.append(f'radius = {radius:.3f}')
    lines.append('')
    return "\n".join(lines)

def add_tree(name, parent, x, y, z, scale=1.0, leaf_mat="mat_leaf"):
    lines = [
        f'[node name="{name}" type="MeshInstance3D" parent="{parent}"]',
        f'transform = Transform3D({scale:.3f}, 0, 0, 0, {scale:.3f}, 0, 0, 0, {scale:.3f}, {x:.3f}, {y + 1.5 * scale:.3f}, {z:.3f})',
        'mesh = SubResource("trunk_mesh")',
        'surface_material_override/0 = SubResource("mat_trunk")',
        '',
        f'[node name="{name}Top" type="MeshInstance3D" parent="{parent}"]',
        f'transform = Transform3D({scale:.3f}, 0, 0, 0, {scale:.3f}, 0, 0, 0, {scale:.3f}, {x:.3f}, {y + 5.5 * scale:.3f}, {z:.3f})',
        'mesh = SubResource("pine_mesh")',
        f'surface_material_override/0 = SubResource("{leaf_mat}")',
        ''
    ]
    return "\n".join(lines)

out = []
root_group = "NavigationRegion3D/DenseWorld"

out.append(f'[node name="DenseWorld" type="Node3D" parent="NavigationRegion3D"]')
out.append('transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)\n')

# ==========================================
# 1. ACCESSIBLE PERIMETER WATCHTOWERS WITH RAMPS
# ==========================================
def build_watchtower(name, parent, x, z):
    res = []
    res.append(f'[node name="{name}" type="Node3D" parent="{parent}"]')
    res.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:.3f}, 0, {z:.3f})\n')
    p = f"{parent}/{name}"
    res.append(add_csg_box("Leg1", p, -2.0, 6.0, -2.0, 0.6, 12.0, 0.6, "mat_metal"))
    res.append(add_csg_box("Leg2", p, 2.0, 6.0, -2.0, 0.6, 12.0, 0.6, "mat_metal"))
    res.append(add_csg_box("Leg3", p, -2.0, 6.0, 2.0, 0.6, 12.0, 0.6, "mat_metal"))
    res.append(add_csg_box("Leg4", p, 2.0, 6.0, 2.0, 0.6, 12.0, 0.6, "mat_metal"))
    res.append(add_csg_box("Deck", p, 0, 12.1, 0, 5.6, 0.35, 5.6, "mat_wood"))
    res.append(add_csg_box("RailN", p, 0, 12.8, -2.7, 5.6, 1.1, 0.15, "mat_metal"))
    res.append(add_csg_box("RailS", p, 1.2, 12.8, 2.7, 3.2, 1.1, 0.15, "mat_metal"))
    res.append(add_csg_box("RailW", p, -2.7, 12.8, 0, 0.15, 1.1, 5.6, "mat_metal"))
    res.append(add_csg_box("RailE", p, 2.7, 12.8, 0, 0.15, 1.1, 5.6, "mat_metal"))
    res.append(add_csg_box("RoofP1", p, -2.4, 13.8, -2.4, 0.2, 3.0, 0.2, "mat_metal"))
    res.append(add_csg_box("RoofP2", p, 2.4, 13.8, -2.4, 0.2, 3.0, 0.2, "mat_metal"))
    res.append(add_csg_box("RoofP3", p, -2.4, 13.8, 2.4, 0.2, 3.0, 0.2, "mat_metal"))
    res.append(add_csg_box("RoofP4", p, 2.4, 13.8, 2.4, 0.2, 3.0, 0.2, "mat_metal"))
    res.append(add_csg_box("Roof", p, 0, 15.3, 0, 6.2, 0.35, 6.2, "mat_roof"))
    # Two stage ramp
    res.append(add_csg_box("Landing", p, 0, 6.0, 8.5, 3.0, 0.3, 3.0, "mat_wood"))
    res.append(add_csg_box("LandP1", p, -1.3, 3.0, 8.5, 0.4, 6.0, 0.4, "mat_metal"))
    res.append(add_csg_box("LandP2", p, 1.3, 3.0, 8.5, 0.4, 6.0, 0.4, "mat_metal"))
    res.append(add_csg_box("RampLow", p, 0, 3.0, 14.5, 2.0, 0.25, 9.5, "mat_wood"))
    res.append(add_csg_box("RampHigh", p, 0, 9.0, 5.0, 2.0, 0.25, 7.5, "mat_wood"))
    return "\n".join(res)

towers = [
    ("Tower_NW", -320, -320),
    ("Tower_N_Center", -60, -310),
    ("Tower_NE_Outer", 310, -310),
    ("Tower_E_Outer", 330, -100),
    ("Tower_SE_Outer", 320, 290),
    ("Tower_S_Center", -60, 310),
    ("Tower_SW_Outer", -330, 290),
    ("Tower_W_Outer", -330, -130),
]
for tname, tx, tz in towers:
    if not is_excluded(tx, tz, clearance=12.0):
        out.append(build_watchtower(tname, root_group, tx, tz))

# ==========================================
# 2. COMPOUNDS & RESIDENTIAL DISTRICTS
# ==========================================
def build_house(name, parent, x, z, rot=0.0, sx=12.0, sy=5.0, sz=9.0, mat="mat_brick"):
    res = []
    res.append(f'[node name="{name}" type="Node3D" parent="{parent}"]')
    res.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:.3f}, 0, {z:.3f})\n')
    p = f"{parent}/{name}"
    res.append(add_csg_box("Body", p, 0, sy/2.0, 0, sx, sy, sz, mat, collision=True, rot_y_deg=rot))
    res.append(add_csg_box("Roof", p, 0, sy + 0.35, 0, sx + 1.2, 0.7, sz + 1.2, "mat_roof", collision=True, rot_y_deg=rot))
    res.append(add_csg_box("Porch", p, 0, 0.2, (sz/2.0 + 1.0), 3.0, 0.4, 2.0, "mat_concrete", collision=True, rot_y_deg=rot))
    return "\n".join(res)

def build_warehouse(name, parent, x, z, rot=0.0, sx=28.0, sy=9.0, sz=18.0):
    res = []
    res.append(f'[node name="{name}" type="Node3D" parent="{parent}"]')
    res.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:.3f}, 0, {z:.3f})\n')
    p = f"{parent}/{name}"
    res.append(add_csg_box("Body", p, 0, sy/2.0, 0, sx, sy, sz, "mat_concrete", collision=True, rot_y_deg=rot))
    res.append(add_csg_box("Roof", p, 0, sy + 0.45, 0, sx + 1.5, 0.9, sz + 1.5, "mat_roof", collision=True, rot_y_deg=rot))
    res.append(add_csg_box("BayCanopy", p, 0, sy*0.6, sz/2.0 + 2.5, sx*0.5, 0.3, 5.0, "mat_metal", collision=True, rot_y_deg=rot))
    res.append(add_csg_box("BayPlatform", p, 0, 0.5, sz/2.0 + 2.0, sx*0.5, 1.0, 4.0, "mat_concrete", collision=True, rot_y_deg=rot))
    return "\n".join(res)

buildings = [
    # North Town neighborhood
    ("NT_Shop1", 60, -135, 0, 14, 6, 10, "mat_brick"),
    ("NT_Shop2", 60, -70, 0, 12, 5, 10, "mat_brick"),
    ("NT_Apt1", 155, -130, 90, 18, 12, 12, "mat_concrete"),
    ("NT_Apt2", 155, -75, 90, 16, 10, 12, "mat_concrete"),
    ("NT_House1", 110, -170, 0, 11, 5, 9, "mat_brick"),
    ("NT_PlazaOffice", 185, -110, 0, 22, 14, 15, "mat_concrete"),
    ("NT_Warehouse", 185, -60, 0, 26, 8, 16, "mat_metal"),
    # North-East Suburb
    ("NE_Villa1", 230, -170, 15, 13, 6, 10, "mat_brick"),
    ("NE_Villa2", 260, -170, -15, 12, 5, 9, "mat_brick"),
    ("NE_Store", 220, -120, 0, 14, 5, 11, "mat_wood"),
    # South-West Hamlet
    ("SW_Barn", -240, 240, 0, 20, 8, 14, "mat_wood"),
    ("SW_Cottage1", -330, 240, 0, 12, 5, 9, "mat_brick"),
    ("SW_Granary", -190, 280, 0, 14, 9, 12, "mat_metal"),
    ("SW_Shed", -230, 310, 45, 9, 4, 7, "mat_wood"),
    # South-East Logistics Depot
    ("SE_Depot1", 220, 110, 0, 24, 8, 16, "mat_concrete"),
    ("SE_Depot2", 220, 160, 0, 24, 8, 16, "mat_metal"),
    ("SE_Office", 175, 135, 90, 16, 6, 10, "mat_brick"),
    # North-West Sawmill / Military Compound
    ("NW_Camp1", -240, -160, 0, 16, 6, 10, "mat_wood"),
    ("NW_Camp2", -270, -160, 0, 16, 6, 10, "mat_wood"),
    ("NW_Bunkhouse", -255, -200, 90, 20, 6, 11, "mat_brick"),
    ("NW_Shed", -210, -180, 45, 10, 4, 8, "mat_metal"),
    # Far North Base Support / Hangars
    ("FN_Hangar1", -120, -320, 0, 30, 10, 18, "mat_metal"),
    ("FN_Hangar2", 120, -320, 0, 30, 10, 18, "mat_metal"),
    ("FN_Barracks", 50, -320, 0, 22, 6, 11, "mat_concrete"),
    # Far South Staging Area
    ("FS_Hangar1", -120, 320, 0, 30, 10, 18, "mat_metal"),
    ("FS_Hangar2", 120, 320, 0, 30, 10, 18, "mat_metal"),
    ("FS_Barracks", 50, 320, 0, 22, 6, 11, "mat_concrete"),
]

for bname, bx, bz, brot, bsx, bsy, bsz, bmat in buildings:
    if not is_excluded(bx, bz, clearance=bsx/2.0):
        out.append(build_house(bname, root_group, bx, bz, brot, bsx, bsy, bsz, bmat))

# ==========================================
# 3. MILITARY FORTIFICATIONS & BUNKERS
# ==========================================
def build_bunker(name, parent, x, z, rot=0.0):
    res = []
    res.append(f'[node name="{name}" type="Node3D" parent="{parent}"]')
    res.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:.3f}, 0, {z:.3f})\n')
    p = f"{parent}/{name}"
    res.append(add_csg_box("Pillbox", p, 0, 1.8, 0, 8.0, 3.6, 6.0, "mat_concrete", collision=True, rot_y_deg=rot))
    res.append(add_csg_box("RoofSlab", p, 0, 3.8, 0, 9.2, 0.8, 7.2, "mat_concrete", collision=True, rot_y_deg=rot))
    res.append(add_csg_box("SandbagN", p, 0, 0.6, -3.8, 9.6, 1.2, 1.4, "mat_sandbag", collision=True, rot_y_deg=rot))
    res.append(add_csg_box("SandbagS", p, 0, 0.6, 3.8, 9.6, 1.2, 1.4, "mat_sandbag", collision=True, rot_y_deg=rot))
    return "\n".join(res)

bunkers = [
    ("Bunker_North_Mid", 0, -85, 0),
    ("Bunker_North_W", -105, -90, 25),
    ("Bunker_North_E", 105, -75, -25),
    ("Bunker_South_Mid", 0, 85, 180),
    ("Bunker_South_W", -105, 90, 155),
    ("Bunker_South_E", 105, 75, -155),
    ("Bunker_East_Pass", 220, 0, 90),
    ("Bunker_West_Pass", -220, 0, 90),
]
for bkname, bkx, bkz, bkrot in bunkers:
    if not is_excluded(bkx, bkz, clearance=8.0):
        out.append(build_bunker(bkname, root_group, bkx, bkz, bkrot))

# ==========================================
# 4. SHIPPING CONTAINER LABYRINTH (Tactical CQB)
# ==========================================
colors = ["mat_c_red", "mat_c_green", "mat_c_blue", "mat_rust"]
ci = 0
for row in range(5):
    for col in range(5):
        cx = 245 + col * 16 + random.uniform(-1.5, 1.5)
        cz = 120 + row * 18 + random.uniform(-1.5, 1.5)
        if is_excluded(cx, cz, clearance=6.0):
            continue
        stack_h = random.choice([1, 2, 2, 3])
        rot = random.choice([0, 0, 90])
        for s in range(stack_h):
            c_color = colors[ci % len(colors)]
            ci += 1
            out.append(add_csg_box(f"Cont_E_{row}_{col}_{s}", root_group, cx, s * 2.6 + 1.3, cz, 6.0, 2.6, 2.4, c_color, collision=True, rot_y_deg=rot))

# ==========================================
# 5. VEHICLE WRECKS WITH SMOKE PARTICLES
# ==========================================
def build_wreck(name, parent, x, z, rot=0.0):
    res = []
    res.append(f'[node name="{name}" type="Node3D" parent="{parent}"]')
    res.append(f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:.3f}, 0, {z:.3f})\n')
    p = f"{parent}/{name}"
    res.append(add_csg_box("Chassis", p, 0, 0.9, 0, 2.6, 1.2, 6.5, "mat_rust", collision=True, rot_y_deg=rot))
    res.append(add_csg_box("Cabin", p, 0, 2.0, 1.8, 2.4, 1.4, 2.2, "mat_rust", collision=True, rot_y_deg=rot))
    res.append(add_csg_box("Cargo", p, 0, 1.8, -1.2, 2.5, 1.2, 3.8, "mat_rust", collision=True, rot_y_deg=rot))
    res.append(f'''[node name="Smoke" type="CPUParticles3D" parent="{p}"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 1.5, 1.0)
amount = 12
lifetime = 3.5
mesh = SubResource("smoke_mesh")
direction = Vector3(0, 1, 0)
spread = 15.0
gravity = Vector3(0, 2.5, 0)
initial_velocity_min = 1.0
initial_velocity_max = 2.5
scale_amount_min = 0.5
scale_amount_max = 1.2
color = Color(0.18, 0.18, 0.19, 0.45)
''')
    return "\n".join(res)

wrecks = [
    ("Wreck1", -45, -45, 35),
    ("Wreck2", 48, -48, -20),
    ("Wreck3", -52, 45, 110),
    ("Wreck4", 52, 48, -85),
    ("Wreck5", -135, 10, 90),
    ("Wreck6", 135, 10, -75),
    ("Wreck7", -180, -110, 45),
    ("Wreck8", 180, 100, -30),
    ("Wreck9", -20, -125, 15),
    ("Wreck10", 20, 125, -15),
    ("Wreck11", -260, 50, 40),
    ("Wreck12", 260, -50, -40),
]
for wname, wx, wz, wrot in wrecks:
    if not is_excluded(wx, wz, clearance=6.0):
        out.append(build_wreck(wname, root_group, wx, wz, wrot))

# ==========================================
# 6. JERSEY BARRIER RUNS & SANDBAG CHECKPOINTS
# ==========================================
def build_jersey_barrier(name, parent, x, z, rot=0.0):
    return add_csg_box(name, parent, x, 0.55, z, 3.2, 1.1, 0.6, "mat_concrete", collision=True, rot_y_deg=rot)

barrier_runs = [
    (-65, -70, 0, 5),
    (65, -70, 0, 5),
    (-65, 70, 0, 5),
    (65, 70, 0, 5),
    (-145, -40, 45, 4),
    (145, -40, -45, 4),
    (-145, 40, -45, 4),
    (145, 40, 45, 4),
    (-200, -8, 90, 6),
    (200, -8, 90, 6),
    (0, -260, 0, 8),
    (0, 260, 0, 8),
]
bi = 0
for start_x, start_z, rot_deg, count in barrier_runs:
    rad = math.radians(rot_deg)
    dx = math.cos(rad) * 3.2
    dz = math.sin(rad) * 3.2
    for c in range(count):
        bx = start_x + dx * c
        bz = start_z + dz * c
        if not is_excluded(bx, bz, clearance=2.5):
            out.append(build_jersey_barrier(f"Barrier_{bi}", root_group, bx, bz, rot_deg))
            bi += 1

# ==========================================
# 7. DENSE FORESTS (Thick woods across all 4 quadrants)
# ==========================================
forest_zones = [
    # (prefix, cx, cz, rx, rz, count)
    ("PineNW", -260, -240, 85, 75, 75),
    ("PineNE", 260, -240, 85, 75, 75),
    ("PineSW", -250, 170, 75, 75, 65),
    ("PineSE", 260, -320, 75, 50, 50),
    ("PineFarSE", 310, 320, 70, 60, 55),
    ("PineMidW", -170, 120, 45, 50, 40),
    ("PineMidE", 170, -180, 45, 50, 40),
    ("PineRearN", 0, -350, 90, 30, 40),
    ("PineRearS", 0, 350, 90, 30, 40),
]

leaf_types = ["mat_leaf", "mat_leaf2"]
ti = 0

for prefix, cx, cz, rx, rz, count in forest_zones:
    for i in range(count):
        angle = random.uniform(0, 2 * math.pi)
        r = math.sqrt(random.uniform(0.04, 1.0))
        tx = cx + math.cos(angle) * rx * r
        tz = cz + math.sin(angle) * rz * r
        # Exclusion check
        if is_excluded(tx, tz, clearance=3.5):
            continue
        scale = random.uniform(0.85, 1.4)
        leaf = random.choice(leaf_types)
        out.append(add_tree(f"Tree_{prefix}_{i}", root_group, tx, 0.0, tz, scale, leaf))
        ti += 1

# Avenues of trees along primary roads (Road North and South)
for z in range(-360, -60, 18):
    for side, xpos in [("L", -8.5), ("R", 8.5)]:
        if not is_excluded(xpos, z, clearance=3.0):
            scale = random.uniform(0.9, 1.25)
            leaf = "mat_leaf" if side == "L" else "mat_leaf2"
            out.append(add_tree(f"TreeLineN_{side}_{abs(z)}", root_group, xpos, 0.0, z, scale, leaf))

for z in range(60, 360, 18):
    for side, xpos in [("L", -8.5), ("R", 8.5)]:
        if not is_excluded(xpos, z, clearance=3.0):
            scale = random.uniform(0.9, 1.25)
            leaf = "mat_leaf" if side == "L" else "mat_leaf2"
            out.append(add_tree(f"TreeLineS_{side}_{z}", root_group, xpos, 0.0, z, scale, leaf))

# ==========================================
# 8. STREET LIGHT POLES
# ==========================================
def build_streetlight(name, parent, x, z):
    res = []
    p = parent
    res.append(add_csg_cyl(f"{name}_Pole", p, x, 4.0, z, 0.15, 8.0, "mat_metal", collision=True))
    res.append(add_csg_box(f"{name}_Arm", p, x + 0.8, 8.0, z, 1.6, 0.15, 0.15, "mat_metal", collision=False))
    res.append(add_csg_box(f"{name}_Lamp", p, x + 1.4, 7.8, z, 0.4, 0.25, 0.3, "mat_white", collision=False))
    return "\n".join(res)

for z in range(-350, 360, 40):
    if abs(z) < 45 or is_excluded(6.5, z, clearance=2.0):
        continue
    out.append(build_streetlight(f"Light_N_{abs(z)}", root_group, 6.5, z))

for x in range(-350, 360, 40):
    if abs(x) < 45 or is_excluded(x, 6.5, clearance=2.0):
        continue
    out.append(build_streetlight(f"Light_E_{abs(x)}", root_group, x, 6.5))

# ==========================================
# 9. ROCK FORMATIONS & NATURAL DEFILADE BERMS
# ==========================================
rock_mounds = [
    ("Mound_NE_Outer", 220, -140, 20.0),
    ("Mound_NW_Outer", -210, -145, 18.0),
    ("Mound_SE_Mid", 185, 65, 22.0),
    ("Mound_SW_Outer", -175, 215, 20.0),
    ("Mound_N_Berm", 0, -225, 24.0),
    ("Mound_S_Berm", 0, 225, 24.0),
]
for mname, mx, mz, mrad in rock_mounds:
    if not is_excluded(mx, mz, clearance=mrad + 4.0):
        out.append(add_csg_sphere(mname, root_group, mx, 0.0, mz, mrad, "mat_hill", scale_y=0.42, collision=True))

content = "\n".join(out)
with open("dense_nodes.txt", "w", encoding="utf-8") as f:
    f.write(content)

print(f"Generated {len(out)} nodes without any exclusion collision.")
