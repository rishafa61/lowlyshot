#!/usr/bin/env python3
"""Ground War pass 2: big factories, towers, camps, industry. Avoids all pass-1 + original POIs."""
import math
import random

random.seed(20260214)

# Exclusions: original POIs + pass-1 structures (towers, buildings, bunkers, mounds, containers, wrecks, camps)
EXC_CIRCLES = [
    (0, 0, 46), (100, -100, 50), (110, 110, 46), (-84, -18, 42), (-84, 140, 42),
    (-115, 80, 28), (300, 0, 48), (-310, 45, 48), (-290, 300, 48), (290, 270, 48),
    (260, -260, 28), (-260, 260, 28),
    # mounds (old + pass1)
    (-140, 40, 34), (-39.5, 104.7, 34), (26.6, -95.5, 34), (150, -45, 32), (-150, -150, 37),
    (220, -140, 26), (-210, -145, 24), (185, 65, 28), (-175, 215, 26), (0, -225, 30), (0, 225, 30),
    # pass-1 watchtowers
    (-320, -320, 16), (-60, -310, 16), (310, -310, 16), (330, -100, 16),
    (320, 290, 16), (-60, 310, 16), (-330, 290, 16), (-330, -130, 16),
    # pass-1 buildings (footprint + margin)
    (60, -135, 11), (60, -70, 10), (155, -130, 13), (155, -75, 12), (110, -170, 10),
    (185, -110, 15), (185, -60, 17), (230, -170, 11), (260, -170, 10), (220, -120, 11),
    (-240, 240, 14), (-330, 240, 10), (-190, 280, 12), (-230, 310, 10),
    (220, 110, 16), (220, 160, 16), (175, 135, 12),
    (-240, -160, 12), (-270, -160, 12), (-255, -200, 14), (-210, -180, 10),
    (-120, -320, 19), (120, -320, 19), (50, -320, 15),
    (-120, 320, 19), (120, 320, 19), (50, 320, 15),
    # pass-1 bunkers
    (0, -85, 10), (-105, -90, 10), (105, -75, 10), (0, 85, 10), (-105, 90, 10), (105, 75, 10),
    (220, 0, 10), (-220, 0, 10),
    # pass-1 wrecks (central ones)
    (-45, -45, 8), (48, -48, 8), (-52, 45, 8), (52, 48, 8), (-20, -125, 8), (20, 125, 8),
    # container terminal block
]
EXC_BOXES = [
    (-130, 160, -195, -145), (-130, 160, 145, 195),           # bases
    (235, 320, 110, 202),                                      # container terminal
    (-172, -128, -18, 98),                                     # road N/S tree avenues corridor (x +-8.5) handled below
]

def is_excluded(x, z, clearance=4.0):
    for cx, cz, r in EXC_CIRCLES:
        if math.hypot(x - cx, z - cz) < (r + clearance):
            return True
    for x1, x2, z1, z2 in EXC_BOXES:
        if (x1 - clearance) <= x <= (x2 + clearance) and (z1 - clearance) <= z <= (z2 + clearance):
            return True
    if abs(x) > 378 or abs(z) > 378:
        return True
    # road corridors
    if abs(z) < 12 and abs(x) > 128: return True   # mid E/W
    if abs(x) < 12 and abs(z) > 128: return True   # mid N/S
    if abs(z - (-52)) < 10 and abs(x) < 168: return True
    if abs(z - 52) < 10 and abs(x) < 168: return True
    if abs(x - (-52)) < 10 and abs(z) < 168: return True
    if abs(x - 52) < 10 and abs(z) < 168: return True
    return False

DW = "NavigationRegion3D/DenseWorld"

def node_lines(name, ntype, parent, x, y, z, rot_y_deg=0.0):
    if rot_y_deg != 0.0:
        rad = math.radians(rot_y_deg)
        c, s = math.cos(rad), math.sin(rad)
        tr = f'transform = Transform3D({c:.6f}, 0, {s:.6f}, 0, 1, 0, {-s:.6f}, 0, {c:.6f}, {x:.3f}, {y:.3f}, {z:.3f})'
    else:
        tr = f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:.3f}, {y:.3f}, {z:.3f})'
    return [f'[node name="{name}" type="{ntype}" parent="{parent}"]', tr]

def box(name, parent, x, y, z, sx, sy, sz, mat, collision=True, ry=0.0, out=None):
    lines = node_lines(name, "CSGBox3D", parent, x, y, z, ry)
    lines.append(f'material_override = SubResource("{mat}")')
    if collision: lines.append('use_collision = true')
    lines.append(f'size = Vector3({sx:.3f}, {sy:.3f}, {sz:.3f})')
    lines.append('')
    if out is not None: out.extend(lines)
    return "\n".join(lines)

def cyl(name, parent, x, y, z, radius, height, mat, collision=True, sides=12, out=None):
    lines = node_lines(name, "CSGCylinder3D", parent, x, y, z)
    lines.append(f'material_override = SubResource("{mat}")')
    if collision: lines.append('use_collision = true')
    lines.append(f'radius = {radius:.3f}')
    lines.append(f'height = {height:.3f}')
    lines.append(f'sides = {sides}')
    lines.append('')
    if out is not None: out.extend(lines)
    return "\n".join(lines)

def group(name, x, z, out, parent=DW):
    out.extend([f'[node name="{name}" type="Node3D" parent="{parent}"]',
                f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:.3f}, 0, {z:.3f})', ''])
    return f"{parent}/{name}"

def smoke(name, parent, x, y, z, amount=20, life=6.0, out=None):
    lines = [f'[node name="{name}" type="CPUParticles3D" parent="{parent}"]',
             f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:.3f}, {y:.3f}, {z:.3f})',
             f'amount = {amount}', f'lifetime = {life}',
             'mesh = SubResource("smoke_mesh")', 'direction = Vector3(0, 1, 0)', 'spread = 8.0',
             'gravity = Vector3(0, 4.5, 0)', 'initial_velocity_min = 1.5', 'initial_velocity_max = 3.5',
             'scale_amount_min = 1.0', 'scale_amount_max = 2.0', 'color = Color(0.22, 0.22, 0.24, 0.5)', '']
    if out is not None: out.extend(lines)
    return "\n".join(lines)

def beacon(name, parent, x, y, z, out=None):
    lines = [f'[node name="{name}" type="OmniLight3D" parent="{parent}"]',
             f'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, {x:.3f}, {y:.3f}, {z:.3f})',
             'light_color = Color(1, 0.35, 0.2, 1)', 'light_energy = 2.0', 'omni_range = 14.0', '']
    if out is not None: out.extend(lines)
    return "\n".join(lines)

out = []

# =========================================
# 1. MEGA FACTORY WEST  (-300, -300)
# =========================================
p = group("MegaFactoryWest", -300, -300, out)
box("Hall1", p, -15, 7, 0, 30, 14, 22, "mat_concrete", out=out)
box("Hall1Roof", p, -15, 14.4, 0, 32, 0.8, 24, "mat_roof", out=out)
box("Hall2", p, 14, 5, 12, 20, 10, 16, "mat_metal", out=out)
box("Hall2Roof", p, 14, 10.4, 12, 22, 0.8, 18, "mat_roof", out=out)
cyl("Chimney1", p, -2, 15, -14, 2.2, 30, "mat_brick", out=out)
cyl("Chimney1Band", p, -2, 28, -14, 2.6, 3, "mat_rust", out=out)
smoke("Chimney1Smoke", p, -2, 31, -14, out=out)
cyl("Chimney2", p, 8, 11, -14, 1.6, 22, "mat_brick", out=out)
smoke("Chimney2Smoke", p, 8, 23, -14, amount=14, out=out)
cyl("Tank1", p, -34, 6, 14, 7, 12, "mat_white", out=out)
cyl("Tank1Cap", p, -34, 12.4, 14, 7.3, 0.8, "mat_metal", out=out)
cyl("Tank2", p, -34, 4.5, -2, 5, 9, "mat_rust", out=out)
cyl("Tank2Cap", p, -34, 9.4, -2, 5.3, 0.6, "mat_metal", out=out)
box("PipeA", p, -20, 8, 8, 16, 0.8, 0.8, "mat_metal", collision=False, out=out)
box("PipeB", p, -34, 5, 6, 0.8, 0.8, 14, "mat_metal", collision=False, out=out)
box("WallW", p, -52, 2, 0, 1.0, 4, 50, "mat_concrete", out=out)
box("WallS", p, -25, 2, 26, 55, 4, 1.0, "mat_concrete", out=out)
for i in range(4):
    box(f"Crate{i+1}", p, -6 + i * 4, 0.9, 22, 1.6, 1.8, 1.6, "mat_wood", out=out)
box("OfficeBlock", p, 22, 4, -12, 12, 8, 10, "mat_brick", out=out)
box("OfficeRoof", p, 22, 8.4, -12, 13.2, 0.8, 11.2, "mat_roof", out=out)
beacon("Warn1", p, -2, 30, -14, out=out)

# =========================================
# 2. OIL REFINERY SOUTH  (200, 300)
# =========================================
p = group("RefinerySouth", 200, 300, out)
cyl("Column1", p, -14, 12, -10, 3.0, 24, "mat_white", out=out)
cyl("Column1Top", p, -14, 24.4, -10, 2.2, 1.2, "mat_metal", out=out)
cyl("Column2", p, -4, 9, -14, 2.4, 18, "mat_white", out=out)
cyl("PlatformCol", p, -9, 10, -12, 6.5, 0.5, "mat_metal", out=out)
cyl("FlareStack", p, 16, 14, 12, 1.2, 28, "mat_rust", out=out)
smoke("FlareSmoke", p, 16, 29, 12, amount=10, life=4.0, out=out)
beacon("FlareGlow", p, 16, 28.5, 12, out=out)
cyl("TankBig1", p, -22, 5, 12, 8, 10, "mat_white", out=out)
cyl("TankBig1Cap", p, -22, 10.4, 12, 8.3, 0.7, "mat_metal", out=out)
cyl("TankBig2", p, -22, 5, -6, 8, 10, "mat_c_red", out=out)
cyl("TankBig2Cap", p, -22, 10.4, -6, 8.3, 0.7, "mat_metal", out=out)
box("Bund1", p, -22, 0.7, 24, 40, 1.4, 1.0, "mat_concrete", out=out)
box("Bund2", p, -41, 0.7, 3, 1.0, 1.4, 44, "mat_concrete", out=out)
box("PumpHouse", p, 2, 2.5, 8, 10, 5, 8, "mat_brick", out=out)
box("PumpHouseRoof", p, 2, 5.3, 8, 11, 0.6, 9, "mat_roof", out=out)
box("PipeRack", p, 6, 3.5, 0, 20, 0.6, 0.6, "mat_metal", collision=False, out=out)
box("PipeRackLeg1", p, -2, 1.75, 0, 0.4, 3.5, 0.4, "mat_metal", out=out)
box("PipeRackLeg2", p, 14, 1.75, 0, 0.4, 3.5, 0.4, "mat_metal", out=out)
cyl("BarrelR1", p, 8, 0.55, 16, 0.42, 1.1, "mat_rust", out=out)
cyl("BarrelR2", p, 9.4, 0.55, 16.4, 0.42, 1.1, "mat_c_red", out=out)
cyl("BarrelR3", p, 8.6, 0.55, 17.6, 0.42, 1.1, "mat_c_blue", out=out)
box("WallR", p, 0, 2, -22, 44, 4, 1.0, "mat_concrete", out=out)

# =========================================
# 3. POWER PLANT WEST  (-230, -40)
# =========================================
p = group("PowerPlantWest", -230, -40, out)
cyl("CoolingTower1", p, -16, 11, -8, 9, 22, "mat_concrete", out=out)
cyl("CoolingTower1Lip", p, -16, 22.4, -8, 7, 1.4, "mat_concrete", out=out)
smoke("CoolingSteam1", p, -16, 24, -8, amount=16, life=7.0, out=out)
cyl("CoolingTower2", p, -16, 10, 10, 8, 20, "mat_concrete", out=out)
smoke("CoolingSteam2", p, -16, 21, 10, amount=14, life=7.0, out=out)
box("TurbineHall", p, 10, 6, 0, 24, 12, 14, "mat_metal", out=out)
box("TurbineHallRoof", p, 10, 12.4, 0, 26, 0.8, 16, "mat_roof", out=out)
cyl("Stack", p, 24, 13, -10, 1.8, 26, "mat_concrete", out=out)
cyl("StackBand", p, 24, 24, -10, 2.2, 3, "mat_rust", out=out)
smoke("StackSmoke", p, 24, 27, -10, out=out)
beacon("StackWarn", p, 24, 26.5, -10, out=out)
box("ControlBlock", p, 24, 3, 4, 10, 6, 8, "mat_brick", out=out)
box("ControlRoof", p, 24, 6.3, 4, 11, 0.6, 9, "mat_roof", out=out)
# transformer yard
for i in range(3):
    box(f"Transformer{i+1}", p, 2 + i * 6, 1.2, 14, 2.4, 2.4, 2.0, "mat_metal", out=out)
    cyl(f"Pylon{i+1}", p, 2 + i * 6, 4, 14, 0.15, 8, "mat_metal", out=out)

# =========================================
# 4. RADAR ARRAY EAST  (350, -200)
# =========================================
p = group("RadarArray", 350, -200, out)
cyl("LegR1", p, -3, 10, -3, 0.5, 20, "mat_metal", out=out)
cyl("LegR2", p, 3, 10, -3, 0.5, 20, "mat_metal", out=out)
cyl("LegR3", p, -3, 10, 3, 0.5, 20, "mat_metal", out=out)
cyl("LegR4", p, 3, 10, 3, 0.5, 20, "mat_metal", out=out)
box("BraceR1", p, 0, 7, 0, 7, 0.4, 0.4, "mat_metal", collision=False, out=out)
box("BraceR2", p, 0, 13, 0, 7, 0.4, 0.4, "mat_metal", collision=False, out=out)
box("Cab", p, 0, 20.8, 0, 6, 3, 6, "mat_white", out=out)
cyl("Mast", p, 0, 26, 0, 0.4, 8, "mat_metal", out=out)
lines = [f'[node name="Dish" type="MeshInstance3D" parent="{p}"]',
         'transform = Transform3D(0.7, 0, 0.7, 0, 1, 0, -0.7, 0, 0.7, 0, 26, 1.5)',
         'mesh = SubResource("dish_mesh")', 'surface_material_override/0 = SubResource("mat_white")', '']
out.extend(lines)
beacon("RadarBeacon", p, 0, 30.4, 0, out=out)
box("GuardHut", p, 10, 1.75, 10, 5, 3.5, 4, "mat_concrete", out=out)
box("GuardHutRoof", p, 10, 3.7, 10, 6, 0.5, 5, "mat_roof", out=out)

# =========================================
# 5. TALL OFFICE TOWERS (City skyline, mid-east)
# =========================================
for tname, tx, tz, th in [("OfficeTower1", 130, -35, 28), ("OfficeTower2", 158, -18, 22)]:
    p = group(tname, tx, tz, out)
    box("Tower", p, 0, th / 2.0, 0, 15, th, 15, "mat_concrete", out=out)
    box("Cap", p, 0, th + 0.4, 0, 16.2, 0.8, 16.2, "mat_roof", out=out)
    for f in range(max(2, th // 6)):
        fy = 4.5 + f * 6
        if fy < th - 2:
            box(f"Glass{f+1}", p, 0, fy, 7.55, 12, 2.2, 0.2, "mat_glass", collision=False, out=out)
    box("AntennaBase", p, 0, th + 1.2, 0, 1.5, 1.6, 1.5, "mat_metal", out=out)
    cyl("Antenna", p, 0, th + 4, 0, 0.15, 6, "mat_metal", out=out)
    beacon("TowerBeacon", p, 0, th + 7.4, 0, out=out)

# =========================================
# 6. WATER TOWER  (350, 230)
# =========================================
p = group("WaterTower", 350, 230, out)
cyl("WLeg1", p, -3.2, 7, -3.2, 0.45, 14, "mat_metal", out=out)
cyl("WLeg2", p, 3.2, 7, -3.2, 0.45, 14, "mat_metal", out=out)
cyl("WLeg3", p, -3.2, 7, 3.2, 0.45, 14, "mat_metal", out=out)
cyl("WLeg4", p, 3.2, 7, 3.2, 0.45, 14, "mat_metal", out=out)
cyl("WTank", p, 0, 16, 0, 5, 5, "mat_c_blue", out=out)
cyl("WTankCap", p, 0, 18.9, 0, 5.2, 0.6, "mat_metal", out=out)
box("WCross1", p, 0, 6, 0, 7.4, 0.35, 0.35, "mat_metal", collision=False, out=out)
box("WCross2", p, 0, 10, 0, 7.4, 0.35, 0.35, "mat_metal", collision=False, out=out)

# =========================================
# 7. WIND TURBINES WEST PLAINS  (3 units)
# =========================================
turbines = [("WindTurbine1", -350, 150), ("WindTurbine2", -338, 192), ("WindTurbine3", -352, 108)]
for tname, tx, tz in turbines:
    if is_excluded(tx, tz, 14.0):
        continue
    p = group(tname, tx, tz, out)
    cyl("Foundation", p, 0, 0.6, 0, 3.2, 1.2, "mat_concrete", out=out)
    cyl("Pole", p, 0, 9.6, 0, 0.6, 18, "mat_white", out=out)
    box("Nacelle", p, 0.9, 18.8, 0, 2.6, 1.1, 1.1, "mat_white", out=out)
    for k in range(3):
        ang = math.radians(30 + k * 120)
        c, s = math.cos(ang), math.sin(ang)
        # blade rotated about X axis: basis (1,0,0, 0,c,s, 0,-s,c)
        lines = [f'[node name="Blade{k+1}" type="CSGBox3D" parent="{p}"]',
                 f'transform = Transform3D(1, 0, 0, 0, {c:.6f}, {s:.6f}, 0, {-s:.6f}, {c:.6f}, {2.1:.3f}, {18.8 + 3.5 * c:.3f}, {3.5 * s:.3f})',
                 'material_override = SubResource("mat_white")', 'use_collision = true',
                 'size = Vector3(0.35, 7.0, 0.22)', '']
        out.extend(lines)

# =========================================
# 8. MILITARY CAMPS x3 (tents, barracks, flag, sandbags, fences)
# =========================================
def build_camp(name, cx, cz):
    res = []
    p = group(name, cx, cz, res)
    # command tent + 2 barracks tents
    box("CommandTent", p, -8, 1.1, 0, 6, 2.2, 9, "mat_tent", out=res)
    box("Tent2", p, 2, 1.1, -7, 5, 2.2, 7, "mat_tent", out=res)
    box("Tent3", p, 2, 1.1, 7, 5, 2.2, 7, "mat_tent", out=res)
    box("Barracks", p, 10, 2, 0, 12, 4, 6, "mat_wood", out=res)
    box("BarracksRoof", p, 10, 4.3, 0, 13, 0.6, 7, "mat_roof", out=res)
    # flag pole + cloth
    cyl("FlagPole", p, -2, 4, 0, 0.1, 8, "mat_metal", out=res)
    lines = [f'[node name="FlagCloth" type="MeshInstance3D" parent="{p}"]',
             'transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0.8, 7.2, 0)',
             'mesh = SubResource("clothA_mesh")', 'surface_material_override/0 = SubResource("mat_flagA")', '']
    res.extend(lines)
    # sandbag ring
    box("SandN", p, 0, 0.6, -14, 14, 1.2, 1.2, "mat_sandbag", out=res)
    box("SandS", p, 0, 0.6, 14, 14, 1.2, 1.2, "mat_sandbag", out=res)
    box("SandW", p, -14, 0.6, 0, 1.2, 1.2, 14, "mat_sandbag", out=res)
    # crates + barrels
    for i in range(3):
        box(f"AmmoCrate{i+1}", p, -10 + i * 2.2, 0.8, 11, 1.6, 1.6, 1.6, "mat_wood", out=res)
    cyl("CampBarrel", p, 7, 0.55, 10, 0.42, 1.1, "mat_c_green", out=res)
    # fence perimeter: posts + rails
    for side in range(4):
        for seg in range(5):
            fx = (-20 + seg * 10) if side in (0, 1) else (-20 if side == 2 else 20)
            fz = (-20 if side == 0 else 20) if side in (0, 1) else (-20 + seg * 10)
            cyl(f"FencePost{side}_{seg}", p, fx, 1.0, fz, 0.12, 2.0, "mat_wood", out=res)
    for side in range(4):
        if side in (0, 1):
            fz = -20 if side == 0 else 20
            box(f"FenceRail{side}", p, 0, 1.5, fz, 40, 0.15, 0.12, "mat_wood", out=res)
        else:
            fx = -20 if side == 2 else 20
            box(f"FenceRail{side}", p, fx, 1.5, 0, 0.12, 0.15, 40, "mat_wood", out=res)
    return res

for cname, ccx, ccz in [("CampNW", -350, -200), ("CampNE", 190, -330), ("CampSE", 165, 265)]:
    if not is_excluded(ccx, ccz, 24.0):
        out.extend(build_camp(cname, ccx, ccz))

# =========================================
# 9. FACTORY NORTH  (-60, -225)
# =========================================
p = group("FactoryNorth", -60, -225, out)
box("FNHall", p, 0, 6, 0, 22, 12, 16, "mat_brick", out=out)
box("FNHallRoof", p, 0, 12.4, 0, 24, 0.8, 18, "mat_roof", out=out)
cyl("FNChimney", p, -14, 11, -10, 1.8, 22, "mat_brick", out=out)
smoke("FNChimneySmoke", p, -14, 23, -10, out=out)
cyl("FNTank1", p, 15, 5, 10, 5.5, 10, "mat_white", out=out)
cyl("FNTank1Cap", p, 15, 10.4, 10, 5.8, 0.6, "mat_metal", out=out)
cyl("FNTank2", p, 15, 4, -2, 4.5, 8, "mat_rust", out=out)
box("FNFence", p, 0, 1.5, -14, 40, 3, 0.6, "mat_metal", out=out)
for i in range(3):
    box(f"FNPalette{i+1}", p, -8 + i * 4, 0.8, 14, 2.4, 1.6, 1.6, "mat_wood", out=out)

# =========================================
# 10. GRAIN SILOS SW FARM  (-252, 258)
# =========================================
p = group("SiloPairSW", -252, 258, out)
cyl("Silo1", p, 0, 8, 0, 5.5, 16, "mat_white", out=out)
cyl("Silo1Cap", p, 0, 16.4, 0, 5.8, 0.8, "mat_metal", out=out)
cyl("Silo2", p, -13, 7, 5, 5.0, 14, "mat_white", out=out)
cyl("Silo2Cap", p, -13, 14.4, 5, 5.3, 0.7, "mat_metal", out=out)
box("SiloConveyor", p, 6, 8, 0, 0.8, 0.8, 14, "mat_metal", collision=False, out=out)

content = "\n".join(out)
with open("dense_nodes2.txt", "w", encoding="utf-8") as f:
    f.write(content)
print(f"Generated {len(out)} lines of pass-2 industry")
