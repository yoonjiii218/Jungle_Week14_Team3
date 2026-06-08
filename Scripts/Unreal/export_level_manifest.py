import hashlib
import json
import os

import unreal


OUTPUT_FILE = r"C:\Temp\Tokyo.scene.json"
UNREAL_SKY_SCALE_THRESHOLD = 10000.0


def safe_property(obj, name, default=None):
    try:
        return obj.get_editor_property(name)
    except Exception:
        return default


def vec3(value):
    return [
        round(value.x, 6),
        round(value.y, 6),
        round(value.z, 6),
    ]


def location_meters(value):
    return [
        round(value.x * 0.01, 6),
        round(value.y * 0.01, 6),
        round(value.z * 0.01, 6),
    ]


def rotation_degrees(value):
    return [
        round(value.roll, 6),
        round(value.pitch, 6),
        round(value.yaw, 6),
    ]


def world_matrix_rows(transform):
    rotation = transform.rotation
    scale = transform.scale3d
    origin = transform.translation

    x = float(rotation.x)
    y = float(rotation.y)
    z = float(rotation.z)
    w = float(rotation.w)

    length_squared = x * x + y * y + z * z + w * w
    if length_squared > 0.0:
        inverse_length = length_squared ** -0.5
        x *= inverse_length
        y *= inverse_length
        z *= inverse_length
        w *= inverse_length

    xx = x * x
    yy = y * y
    zz = z * z
    xy = x * y
    xz = x * z
    yz = y * z
    xw = x * w
    yw = y * w
    zw = z * w

    scale_x = float(scale.x)
    scale_y = float(scale.y)
    scale_z = float(scale.z)

    return [
        [
            round((1.0 - 2.0 * (yy + zz)) * scale_x, 6),
            round(2.0 * (xy + zw) * scale_x, 6),
            round(2.0 * (xz - yw) * scale_x, 6),
            0.0,
        ],
        [
            round(2.0 * (xy - zw) * scale_y, 6),
            round((1.0 - 2.0 * (xx + zz)) * scale_y, 6),
            round(2.0 * (yz + xw) * scale_y, 6),
            0.0,
        ],
        [
            round(2.0 * (xz + yw) * scale_z, 6),
            round(2.0 * (yz - xw) * scale_z, 6),
            round((1.0 - 2.0 * (xx + yy)) * scale_z, 6),
            0.0,
        ],
        [
            round(origin.x * 0.01, 6),
            round(origin.y * 0.01, 6),
            round(origin.z * 0.01, 6),
            1.0,
        ],
    ]


def linear_color(value):
    return [
        round(float(value.r), 6),
        round(float(value.g), 6),
        round(float(value.b), 6),
        round(float(value.a), 6),
    ]


def light_color(value):
    return [
        round(float(value.r) / 255.0, 6),
        round(float(value.g) / 255.0, 6),
        round(float(value.b) / 255.0, 6),
        round(float(value.a) / 255.0, 6),
    ]


def mesh_key(asset_path):
    name = asset_path.rsplit("/", 1)[-1].split(".")[0]
    digest = hashlib.sha1(asset_path.encode("utf-8")).hexdigest()[:8]
    return f"{name}_{digest}"


def stable_id(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:16]


def component_identity(actor, component):
    return actor.get_path_name() + "|" + component.get_path_name()


def transform_record(transform):
    return {
        "location": location_meters(transform.translation),
        "rotation": rotation_degrees(transform.rotation.rotator()),
        "scale": vec3(transform.scale3d),
        "worldMatrix": world_matrix_rows(transform),
    }


def component_transform(component):
    return transform_record(component.get_world_transform())


def is_instanced_static_mesh_component(component):
    instanced_type = getattr(unreal, "InstancedStaticMeshComponent", None)
    hierarchical_type = getattr(
        unreal,
        "HierarchicalInstancedStaticMeshComponent",
        None,
    )
    return (
        (instanced_type is not None and isinstance(component, instanced_type))
        or (
            hierarchical_type is not None
            and isinstance(component, hierarchical_type)
        )
    )


def get_instance_transform_world(component, index):
    try:
        result = component.get_instance_transform(index, True)
    except TypeError:
        result = component.get_instance_transform(index, world_space=True)

    if isinstance(result, tuple):
        for item in reversed(result):
            if isinstance(item, unreal.Transform):
                return item
        return None

    return result


def iter_static_mesh_component_transforms(component):
    if not is_instanced_static_mesh_component(component):
        yield None, component.get_world_transform()
        return

    count = int(component.get_instance_count())
    if count <= 0:
        return

    for index in range(count):
        transform = get_instance_transform_world(component, index)
        if transform is not None:
            yield index, transform


def should_skip_unreal_sky_mesh(actor, mesh, transform):
    scale = transform.scale3d
    max_scale = max(
        abs(float(scale.x)),
        abs(float(scale.y)),
        abs(float(scale.z)),
    )
    if max_scale < UNREAL_SKY_SCALE_THRESHOLD:
        return False

    classifier = (
        actor.get_actor_label() + " " + mesh.get_path_name()
    ).lower()
    return any(
        token in classifier
        for token in (
            "skydome",
            "sky_dome",
            "sky sphere",
            "sky_sphere",
            "/engine/basicshapes/sphere.",
        )
    )


def local_light_intensity(component):
    intensity = float(safe_property(component, "intensity", 1.0))
    units = str(safe_property(component, "intensity_units", "")).upper()

    if "UNITLESS" in units:
        return min(max(intensity, 0.0), 50.0)

    return min(max(intensity / 1000.0, 0.0), 50.0)


def directional_light_intensity(component):
    intensity = float(safe_property(component, "intensity", 1.0))
    return min(max(intensity * 0.1, 0.0), 50.0)


def common_light_record(actor, component, light_type, intensity):
    transform = component_transform(component)
    color = safe_property(component, "light_color")
    color_value = (
        light_color(color)
        if color is not None
        else [1.0, 1.0, 1.0, 1.0]
    )

    return {
        "id": stable_id(component_identity(actor, component)),
        "name": actor.get_actor_label(),
        "component": component.get_name(),
        "type": light_type,
        "location": transform["location"],
        "rotation": transform["rotation"],
        "color": color_value,
        "intensity": round(float(intensity), 6),
        "sourceIntensity": round(
            float(safe_property(component, "intensity", 1.0)),
            6,
        ),
        "visible": bool(safe_property(component, "visible", True)),
        "castShadows": bool(
            safe_property(component, "cast_shadows", True)
        ),
    }


actor_system = unreal.get_editor_subsystem(
    unreal.EditorActorSubsystem
)
editor_system = unreal.get_editor_subsystem(
    unreal.UnrealEditorSubsystem
)

world = editor_system.get_editor_world()
loaded_actors = actor_system.get_all_level_actors()

placements = []
environment = []
meshes = {}
skipped_unreal_sky_meshes = 0

unreal.log(f"Loaded actor count: {len(loaded_actors)}")

for actor in loaded_actors:
    class_name = actor.get_class().get_name()
    if class_name in ("WorldPartitionHLOD", "LODActor"):
        continue

    for component in actor.get_components_by_class(
        unreal.StaticMeshComponent
    ):
        mesh = safe_property(component, "static_mesh")
        if not mesh:
            continue

        if should_skip_unreal_sky_mesh(
            actor,
            mesh,
            component.get_world_transform(),
        ):
            skipped_unreal_sky_meshes += 1
            unreal.log(
                "Skipped Unreal-only sky mesh: "
                f"{actor.get_actor_label()} "
                f"({mesh.get_path_name()})"
            )
            continue

        asset_path = mesh.get_path_name()
        key = mesh_key(asset_path)
        meshes[key] = {
            "key": key,
            "sourceAsset": asset_path,
            "fbx": f"Meshes/{key}.fbx",
        }

        materials = []
        for index in range(component.get_num_materials()):
            material = component.get_material(index)
            materials.append(
                material.get_path_name() if material else "None"
            )

        for instance_index, world_transform in (
            iter_static_mesh_component_transforms(component)
        ):
            transform = transform_record(world_transform)
            scale = transform["scale"]
            identity = component_identity(actor, component)
            if instance_index is not None:
                identity += f"|instance={instance_index}"

            record = {
                "id": stable_id(identity),
                "name": actor.get_actor_label(),
                "actorClass": class_name,
                "component": component.get_name(),
                "type": "StaticMesh",
                "mesh": key,
                "location": transform["location"],
                "rotation": transform["rotation"],
                "scale": scale,
                "worldMatrix": transform["worldMatrix"],
                "materials": materials,
                "visible": bool(
                    safe_property(component, "visible", True)
                ),
                "castShadow": bool(
                    safe_property(component, "cast_shadow", True)
                ),
                "collision": str(component.get_collision_enabled()),
                "negativeScale": (
                    scale[0] < 0.0
                    or scale[1] < 0.0
                    or scale[2] < 0.0
                ),
            }
            if instance_index is not None:
                record["sourceInstance"] = instance_index
            placements.append(record)

    for component in actor.get_components_by_class(
        unreal.DirectionalLightComponent
    ):
        environment.append(common_light_record(
            actor,
            component,
            "DirectionalLight",
            directional_light_intensity(component),
        ))

    for component in actor.get_components_by_class(
        unreal.SkyLightComponent
    ):
        record = common_light_record(
            actor,
            component,
            "AmbientLight",
            float(safe_property(component, "intensity", 1.0)) * 0.25,
        )
        record["castShadows"] = False
        environment.append(record)

    for component in actor.get_components_by_class(
        unreal.PointLightComponent
    ):
        if isinstance(component, unreal.SpotLightComponent):
            continue

        record = common_light_record(
            actor,
            component,
            "PointLight",
            local_light_intensity(component),
        )
        record["attenuationRadius"] = round(
            float(safe_property(
                component,
                "attenuation_radius",
                1000.0,
            )) * 0.01,
            6,
        )
        record["falloffExponent"] = round(
            float(safe_property(
                component,
                "light_falloff_exponent",
                2.0,
            )),
            6,
        )
        environment.append(record)

    for component in actor.get_components_by_class(
        unreal.SpotLightComponent
    ):
        record = common_light_record(
            actor,
            component,
            "SpotLight",
            local_light_intensity(component),
        )
        record["attenuationRadius"] = round(
            float(safe_property(
                component,
                "attenuation_radius",
                1000.0,
            )) * 0.01,
            6,
        )
        record["falloffExponent"] = round(
            float(safe_property(
                component,
                "light_falloff_exponent",
                2.0,
            )),
            6,
        )
        record["innerConeAngle"] = round(
            float(safe_property(
                component,
                "inner_cone_angle",
                20.0,
            )),
            6,
        )
        record["outerConeAngle"] = round(
            float(safe_property(
                component,
                "outer_cone_angle",
                40.0,
            )),
            6,
        )
        environment.append(record)

    for component in actor.get_components_by_class(
        unreal.ExponentialHeightFogComponent
    ):
        transform = component_transform(component)
        fog_color = safe_property(
            component,
            "fog_inscattering_color",
            unreal.LinearColor(0.45, 0.55, 0.65, 1.0),
        )
        environment.append({
            "id": stable_id(component_identity(actor, component)),
            "name": actor.get_actor_label(),
            "component": component.get_name(),
            "type": "HeightFog",
            "location": transform["location"],
            "rotation": transform["rotation"],
            "color": linear_color(fog_color),
            "density": round(float(safe_property(
                component,
                "fog_density",
                0.02,
            )), 6),
            "heightFalloff": round(float(safe_property(
                component,
                "fog_height_falloff",
                0.2,
            )), 6),
            "startDistance": round(float(safe_property(
                component,
                "start_distance",
                0.0,
            )) * 0.01, 6),
            "cutoffDistance": round(float(safe_property(
                component,
                "fog_cutoff_distance",
                0.0,
            )) * 0.01, 6),
            "maxOpacity": round(float(safe_property(
                component,
                "fog_max_opacity",
                1.0,
            )), 6),
            "visible": bool(
                safe_property(component, "visible", True)
            ),
        })


manifest = {
    "version": 2,
    "sourceLevel": world.get_path_name(),
    "unit": "meter",
    "coordinateSystem": "leftHandedZUp",
    "materialLighting": True,
    "meshes": sorted(
        meshes.values(),
        key=lambda item: item["key"],
    ),
    "actors": placements,
    "environment": environment,
}

output_directory = os.path.dirname(OUTPUT_FILE)
if output_directory:
    os.makedirs(output_directory, exist_ok=True)

with open(OUTPUT_FILE, "w", encoding="utf-8") as file:
    json.dump(manifest, file, ensure_ascii=False, indent=2)

unreal.log(f"Scene manifest exported: {OUTPUT_FILE}")
unreal.log(
    f"Meshes: {len(meshes)}, "
    f"placements: {len(placements)}, "
    f"environment: {len(environment)}, "
    f"skipped sky meshes: {skipped_unreal_sky_meshes}"
)
