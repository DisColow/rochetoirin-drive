"""Animations des clients du taxi (issue #77) : animations libres de Quaternius (« Universal Animation Library » 1 et 2,
CC0, opengameart.org) transférées sur le squelette « game_engine » des clients MakeHuman (assets/clients/mh_N.glb de
blender_makehuman.py), puis réécrites dans chaque mh_N.glb. Choix de l'utilisateur : marche normale (Walk_Loop),
marche titubante des ivres (Zombie_Walk_Fwd_Loop), quatre attentes (Idle_Loop, Idle_Talking_Loop, Idle_FoldArms_Loop,
Idle_TalkingPhone_Loop). Transfert par rotations en repère monde rapportées aux poses de repos (pose en T des
mannequins, pose en A de MakeHuman) ; translation du bassin : hauteur seulement, à l'échelle du personnage (sur place).
Actions écrites : marche, titube, attente_0 … attente_3 (scripts/pieton.gd).
Prérequis : venv bpy ; UAL dans data/anim/ (fetch : voir docs/REPRISE.md).   <venv>/bin/python blender_animer_clients.py"""
import glob, os
import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
CLIENTS = os.path.join(HERE, "..", "godot", "assets", "clients")
UAL1 = os.path.join(HERE, "data", "anim", "ual1", "Animation Library[Standard]", "Godot", "AnimationLibrary_Godot_Standard.glb")
UAL2 = os.path.join(HERE, "data", "anim", "ual2", "Universal Animation Library 2 [Standard]", "Unreal-Godot", "UAL2_Standard.glb")
CARTE1 = {"DEF-hips": "pelvis", "DEF-spine.001": "spine_01", "DEF-spine.002": "spine_02", "DEF-spine.003": "spine_03",
          "DEF-neck": "neck_01", "DEF-head": "head", "DEF-thigh.L": "thigh_l", "DEF-shin.L": "calf_l", "DEF-foot.L": "foot_l",
          "DEF-toe.L": "ball_l", "DEF-thigh.R": "thigh_r", "DEF-shin.R": "calf_r", "DEF-foot.R": "foot_r", "DEF-toe.R": "ball_r",
          "DEF-shoulder.L": "clavicle_l", "DEF-upper_arm.L": "upperarm_l", "DEF-forearm.L": "lowerarm_l", "DEF-hand.L": "hand_l",
          "DEF-shoulder.R": "clavicle_r", "DEF-upper_arm.R": "upperarm_r", "DEF-forearm.R": "lowerarm_r", "DEF-hand.R": "hand_r"}
CARTE2 = {n: n for n in ["pelvis", "spine_01", "spine_02", "spine_03", "neck_01", "thigh_l", "calf_l", "foot_l", "ball_l",
                         "thigh_r", "calf_r", "foot_r", "ball_r", "clavicle_l", "upperarm_l", "lowerarm_l", "hand_l",
                         "clavicle_r", "upperarm_r", "lowerarm_r", "hand_r"]}
CARTE2["Head"] = "head"
ANIMS = [("marche", UAL1, "Walk_Loop", CARTE1), ("titube", UAL2, "Zombie_Walk_Fwd_Loop", CARTE2),
         ("attente_0", UAL1, "Idle_Loop", CARTE1), ("attente_1", UAL1, "Idle_Talking_Loop", CARTE1),
         ("attente_2", UAL2, "Idle_FoldArms_Loop", CARTE2), ("attente_3", UAL2, "Idle_TalkingPhone_Loop", CARTE2)]


def importer(f):
    avant = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    return [o for o in bpy.data.objects if o not in avant]


def transferer(dst, src, action, carte, nom):
    src.animation_data_create(); src.animation_data.action = bpy.data.actions[action]
    if hasattr(src.animation_data, "action_slot") and len(bpy.data.actions[action].slots) > 0:
        src.animation_data.action_slot = bpy.data.actions[action].slots[0]       # Blender 4.4+ : actions à emplacements
    dst.animation_data_create()
    act = bpy.data.actions.new(nom)
    dst.animation_data.action = act
    sc = bpy.context.scene
    # os dans l'ordre des parents d'abord
    ordre = [b.name for b in dst.data.bones if b.name in carte.values()]
    inv = {v: k for k, v in carte.items()}
    srest = {k: (src.matrix_world @ src.data.bones[k].matrix_local) for k in carte if k in src.data.bones}
    drest = {b: (dst.matrix_world @ dst.data.bones[b].matrix_local) for b in ordre}
    # bras : la pose de repos des mannequins est en T, celle de MakeHuman en A ; on aligne d'abord la direction de
    # chaque os du bras sur celle du mannequin (le reste du corps a la même direction de repos)
    aligne = {}
    for b in ordre:
        s = inv[b]
        if s in srest and any(k in b for k in ("clavicle", "upperarm", "lowerarm", "hand")):
            td = drest[b].to_quaternion() @ Vector((0, 1, 0))
            sd = srest[s].to_quaternion() @ Vector((0, 1, 0))
            aligne[b] = td.rotation_difference(sd)
        else:
            aligne[b] = Matrix.Identity(3).to_quaternion()
    ks = srest[inv["pelvis"]].to_translation().z
    kd = drest["pelvis"].to_translation().z
    f0, f1 = (int(x) for x in bpy.data.actions[action].frame_range)
    for pb in dst.pose.bones:
        pb.rotation_mode = "QUATERNION"
    for f in range(f0, f1 + 1):
        sc.frame_set(f)
        for b in ordre:
            s = inv[b]
            if s not in srest:
                continue
            sw = src.matrix_world @ src.pose.bones[s].matrix
            delta = sw.to_quaternion() @ srest[s].to_quaternion().inverted()
            rot = delta @ aligne[b] @ drest[b].to_quaternion()
            pos = drest[b].to_translation()
            if b == "pelvis":
                pos.z = kd + (sw.to_translation().z - ks) * (kd / max(ks, 1e-3))
            m = Matrix.Translation(pos) @ rot.to_matrix().to_4x4()
            pb = dst.pose.bones[b]
            pb.matrix = dst.matrix_world.inverted() @ m
            bpy.context.view_layer.update()
            pb.keyframe_insert("rotation_quaternion", frame=f - f0)
            if b == "pelvis":
                pb.keyframe_insert("location", frame=f - f0)
    src.animation_data.action = None
    dst.animation_data.action = None
    act.use_fake_user = True
    return act


import sys
SEULS = sys.argv[1:]                  # noms de fichiers à traiter (essai), sinon tous
for fichier in sorted(glob.glob(os.path.join(CLIENTS, "mh_*.glb"))):
    if SEULS and os.path.basename(fichier) not in SEULS:
        continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    perso = importer(fichier)
    dst = next(o for o in perso if o.type == "ARMATURE")
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    if dst.animation_data:                 # fichier déjà animé (nouveau passage) : anciennes pistes retirées
        for t in list(dst.animation_data.nla_tracks):
            dst.animation_data.nla_tracks.remove(t)
    faites = []
    for nom, src_f, action, carte in ANIMS:
        objs = importer(src_f)
        src = next(o for o in objs if o.type == "ARMATURE")
        faites.append(transferer(dst, src, action, carte, nom))
        for o in objs:
            bpy.data.objects.remove(o, do_unlink=True)
        for a in list(bpy.data.actions):
            if a not in faites:
                bpy.data.actions.remove(a)
    # une piste NLA par action : toutes exportées
    for a in faites:
        tr = dst.animation_data.nla_tracks.new(); tr.name = a.name
        tr.strips.new(a.name, 0, a)
    for pb in dst.pose.bones:
        pb.matrix_basis = Matrix.Identity(4)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=fichier, export_format="GLB", export_image_format="JPEG", export_apply=False,
                              export_animations=True, export_animation_mode="NLA_TRACKS", export_force_sampling=True)
    print("animé", os.path.basename(fichier), [a.name for a in faites])
