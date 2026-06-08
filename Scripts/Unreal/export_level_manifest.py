import hashlib
import json
import os
import sys

import unreal


DEFAULT_OUTPUT_FILE = r"C:\Temp\Tokyo.scene.json"
DEFAULT_MAP_PATH = "/Game/TokyoStylizedEnvironment/Maps/Tokyo"
UNREAL_SKY_SCALE_THRESHOLD = 10000.0


def script_arg(name, default=None):
    prefix = name + "="
    for index, arg in enumerate(sys.argv[1:]):
        if arg == name and index + 2 <= len(sys.argv[1:]):
            return sys.argv[index + 2]
        if arg.startswith(prefix):
            return arg[len(prefix):]
    return default


def script_bool(name, default=False):
    value = script_arg(name)
    if value is None:
        return default
    return str(value).strip().lower() in ("1", "true", "yes", "on")


OUTPUT_FILE = (
    script_arg("--output")
    or os.environ.get("UE_SCENE_OUTPUT")
    or DEFAULT_OUTPUT_FILE
)
MAP_PATH = (
    script_arg("--map")
    or os.environ.get("UE_SCENE_MAP")
    or DEFAULT_MAP_PATH
)
EXPORT_MESHES = script_bool(
    "--export-meshes",
    os.environ.get("UE_SCENE_EXPORT_MESHES", "1").lower()
    not in ("0", "false", "no", "off"),
)


def safe_property(obj, name, default=None):
    try:
        return obj.get_editor_property(name)
    except Exception:
        try:
            return getattr(obj, name)
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


def scale_components(value):
    if isinstance(value, (list, tuple)) and len(value) >= 3:
        return float(value[0]), float(value[1]), float(value[2])
    return float(value.x), float(value.y), float(value.z)


def world_matrix_rows(transform, override_scale=None):
    rotation = transform.rotation
    scale = override_scale if override_scale is not None else transform.scale3d
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

    scale_x, scale_y, scale_z = scale_components(scale)

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


def asset_key(asset_path):
    name = asset_path.rsplit("/", 1)[-1].split(".")[0]
    digest = hashlib.sha1(asset_path.encode("utf-8")).hexdigest()[:8]
    return f"{name}_{digest}"


def mesh_key(asset_path):
    return asset_key(asset_path)


def material_key(asset_path):
    return asset_key(asset_path)


def texture_key(asset_path):
    return asset_key(asset_path)


def stable_id(text):
    return hashlib.sha1(text.encode("utf-8")).hexdigest()[:16]


def editor_array(obj, property_name):
    value = safe_property(obj, property_name)
    if value is None:
        return []

    try:
        return list(value)
    except Exception:
        return []


def parameter_name(parameter):
    info = safe_property(parameter, "parameter_info")
    name = safe_property(info, "name") if info is not None else None
    if name is None:
        name = safe_property(parameter, "parameter_name")
    if name is None:
        name = safe_property(parameter, "name")
    return str(name) if name is not None else ""


def vector_value(value):
    if value is None:
        return None

    if all(hasattr(value, channel) for channel in ("r", "g", "b", "a")):
        return linear_color(value)

    if all(hasattr(value, channel) for channel in ("x", "y", "z")):
        return [
            round(float(value.x), 6),
            round(float(value.y), 6),
            round(float(value.z), 6),
            round(float(getattr(value, "w", 1.0)), 6),
        ]

    return None


def texture_usage_guess(parameter, texture):
    classifier = (
        f"{parameter} {texture.get_name()} {texture.get_path_name()}"
    ).lower()

    if any(token in classifier for token in ("normal", "_n.", "_n_", "nrml")):
        return "normal"
    if any(token in classifier for token in ("opacity", "alpha", "mask")):
        return "opacity"
    if any(token in classifier for token in ("rmo", "orm", "roughness", "metallic", "metalness")):
        return "rmo"
    if any(token in classifier for token in ("emissive", "emission")):
        return "emissive"
    if any(token in classifier for token in ("base", "albedo", "diffuse", "color")):
        return "baseColor"
    return "unknown"


def unreal_name(value):
    name_type = getattr(unreal, "Name", None)
    if name_type is None:
        return value
    try:
        return name_type(value)
    except Exception:
        return value


def material_library_call(method_name, *args):
    library = getattr(unreal, "MaterialEditingLibrary", None)
    method = getattr(library, method_name, None) if library is not None else None
    if method is None:
        return None

    try:
        return method(*args)
    except Exception:
        return None


def unreal_class_name(obj):
    try:
        return obj.get_class().get_name()
    except Exception:
        return type(obj).__name__


def result_value(result):
    if isinstance(result, tuple):
        for item in result:
            if item is not None and not isinstance(item, bool):
                return item
        return None
    return result


def material_parameter_names(material, method_name):
    result = material_library_call(method_name, material)
    if result is None:
        return []

    try:
        return [str(name) for name in result]
    except Exception:
        return []


def material_texture_parameter_value(material, name):
    parameter = unreal_name(name)
    value = result_value(material_library_call(
        "get_material_instance_texture_parameter_value",
        material,
        parameter,
    ))
    if value is not None:
        return value

    return result_value(material_library_call(
        "get_material_default_texture_parameter_value",
        material,
        parameter,
    ))


def material_scalar_parameter_value(material, name):
    parameter = unreal_name(name)
    value = result_value(material_library_call(
        "get_material_instance_scalar_parameter_value",
        material,
        parameter,
    ))
    if value is not None:
        return value

    return result_value(material_library_call(
        "get_material_default_scalar_parameter_value",
        material,
        parameter,
    ))


def material_vector_parameter_value(material, name):
    parameter = unreal_name(name)
    value = result_value(material_library_call(
        "get_material_instance_vector_parameter_value",
        material,
        parameter,
    ))
    if value is not None:
        return value

    return result_value(material_library_call(
        "get_material_default_vector_parameter_value",
        material,
        parameter,
    ))


def material_chain(material):
    chain = []
    current = material
    seen = set()
    while current is not None:
        path = current.get_path_name()
        if path in seen:
            break
        seen.add(path)
        chain.append(current)
        current = safe_property(current, "parent")
    return chain


def first_material_property(chain, property_name, default=None):
    for material in chain:
        value = safe_property(material, property_name)
        if value is not None:
            return value
    return default


def expression_textures(material, visited=None):
    if material is None:
        return []
    if visited is None:
        visited = set()

    try:
        material_path = material.get_path_name()
    except Exception:
        material_path = str(id(material))
    if material_path in visited:
        return []
    visited.add(material_path)

    expressions = material_library_call("get_material_expressions", material)
    if expressions is None:
        expressions = safe_property(material, "expressions", [])

    try:
        expressions = list(expressions)
    except Exception:
        return []

    records = []
    for index, expression in enumerate(expressions):
        texture = safe_property(expression, "texture")
        if texture is None:
            texture = safe_property(expression, "parameter_value")

        function_asset = safe_property(expression, "material_function")
        if function_asset is None:
            function_asset = safe_property(expression, "function")
        if function_asset is not None and hasattr(function_asset, "get_path_name"):
            records.extend(expression_textures(function_asset, visited))

        if texture is None or not hasattr(texture, "get_path_name"):
            continue

        name = ""
        for property_name in ("parameter_name", "desc", "name"):
            value = safe_property(expression, property_name)
            if value is not None and str(value).strip():
                name = str(value).strip()
                break
        if not name:
            try:
                name = expression.get_name()
            except Exception:
                name = f"TextureExpression{index}"

        class_name = unreal_class_name(expression)
        records.append({
            "name": name,
            "texture": texture,
            "usageHint": f"{class_name} {name}",
        })

    return records


def register_texture(texture, texture_records, texture_assets):
    if texture is None:
        return None

    asset_path = texture.get_path_name()
    key = texture_key(asset_path)
    texture_records[key] = {
        "key": key,
        "sourceAsset": asset_path,
        "file": f"Textures/{key}.png",
    }
    texture_assets[key] = texture
    return key


def add_texture_parameter(
    texture_params,
    name,
    texture,
    texture_records,
    texture_assets,
    usage_hint="",
    allow_override=True,
):
    texture_param_key = register_texture(
        texture,
        texture_records,
        texture_assets,
    )
    if texture_param_key is None:
        return

    parameter = str(name).strip() if name is not None else ""
    if not parameter:
        parameter = texture.get_name()

    if parameter in texture_params and not allow_override:
        if texture_params[parameter]["texture"] == texture_param_key:
            return

        base_name = parameter
        suffix = 2
        while parameter in texture_params:
            parameter = f"{base_name}_{suffix}"
            suffix += 1

    texture_params[parameter] = {
        "parameter": parameter,
        "texture": texture_param_key,
        "usageGuess": texture_usage_guess(
            f"{parameter} {usage_hint}",
            texture,
        ),
    }


def register_material(material, material_records, texture_records, texture_assets):
    if material is None:
        return None

    asset_path = material.get_path_name()
    key = material_key(asset_path)
    if key in material_records:
        return key

    chain = material_chain(material)
    parent = safe_property(material, "parent")
    texture_params = {}
    scalar_params = {}
    vector_params = {}

    for material_node in reversed(chain):
        for parameter in editor_array(material_node, "texture_parameter_values"):
            texture = safe_property(parameter, "parameter_value")
            if texture is None:
                continue

            name = parameter_name(parameter)
            add_texture_parameter(
                texture_params,
                name,
                texture,
                texture_records,
                texture_assets,
                allow_override=True,
            )

        for texture_record in expression_textures(material_node):
            add_texture_parameter(
                texture_params,
                texture_record["name"],
                texture_record["texture"],
                texture_records,
                texture_assets,
                texture_record["usageHint"],
                allow_override=False,
            )

        for parameter in editor_array(material_node, "scalar_parameter_values"):
            name = parameter_name(parameter)
            value = safe_property(parameter, "parameter_value")
            try:
                scalar_params[name] = round(float(value), 6)
            except Exception:
                pass

        for parameter in editor_array(material_node, "vector_parameter_values"):
            name = parameter_name(parameter)
            value = vector_value(safe_property(parameter, "parameter_value"))
            if value is not None:
                vector_params[name] = value

    for name in material_parameter_names(material, "get_texture_parameter_names"):
        texture = material_texture_parameter_value(material, name)
        texture_param_key = register_texture(
            texture,
            texture_records,
            texture_assets,
        )
        if texture_param_key is not None:
            texture_params[name] = {
                "parameter": name,
                "texture": texture_param_key,
                "usageGuess": texture_usage_guess(name, texture),
            }

    for name in material_parameter_names(material, "get_scalar_parameter_names"):
        value = material_scalar_parameter_value(material, name)
        try:
            scalar_params[name] = round(float(value), 6)
        except Exception:
            pass

    for name in material_parameter_names(material, "get_vector_parameter_names"):
        value = vector_value(material_vector_parameter_value(material, name))
        if value is not None:
            vector_params[name] = value

    material_records[key] = {
        "key": key,
        "sourceAsset": asset_path,
        "baseMaterial": parent.get_path_name() if parent else "",
        "blendMode": str(first_material_property(chain, "blend_mode", "")),
        "twoSided": bool(first_material_property(chain, "two_sided", False)),
        "textures": sorted(texture_params.values(), key=lambda item: item["parameter"]),
        "scalars": scalar_params,
        "vectors": vector_params,
    }
    return key


def unreal_package_path_from_umap(path):
    normalized = os.path.normpath(path)
    parts = normalized.split(os.sep)
    lowered = [part.lower() for part in parts]
    if "content" not in lowered:
        return path

    content_index = lowered.index("content")
    relative_parts = parts[content_index + 1:]
    if not relative_parts:
        return path

    relative_path = "/".join(relative_parts)
    if relative_path.lower().endswith(".umap"):
        relative_path = relative_path[:-5]
    return "/Game/" + relative_path


def load_requested_map(map_path):
    if not map_path:
        return

    package_path = (
        unreal_package_path_from_umap(map_path)
        if map_path.lower().endswith(".umap")
        else map_path
    )

    loading_utils = getattr(unreal, "EditorLoadingAndSavingUtils", None)
    if loading_utils is not None and hasattr(loading_utils, "load_map"):
        loading_utils.load_map(package_path)
        unreal.log(f"Loaded map for scene export: {package_path}")
        return

    level_subsystem_type = getattr(unreal, "LevelEditorSubsystem", None)
    if level_subsystem_type is not None:
        level_subsystem = unreal.get_editor_subsystem(level_subsystem_type)
        if level_subsystem is not None and hasattr(level_subsystem, "load_level"):
            level_subsystem.load_level(package_path)
            unreal.log(f"Loaded level for scene export: {package_path}")
            return

    unreal.log_warning(
        "Could not explicitly load map before export; exporting current editor world."
    )


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


def decal_component_material(component):
    material = safe_property(component, "decal_material")
    if material is not None:
        return material

    for method_name in ("get_decal_material", "get_material"):
        method = getattr(component, method_name, None)
        if method is None:
            continue

        try:
            return method(0)
        except TypeError:
            try:
                return method()
            except Exception:
                pass
        except Exception:
            pass

    return None


def decal_scale_meters(component, transform):
    scale = transform.scale3d
    decal_size = safe_property(component, "decal_size")
    if decal_size is not None and all(
        hasattr(decal_size, channel)
        for channel in ("x", "y", "z")
    ):
        return [
            round(float(decal_size.x) * 0.01 * float(scale.x), 6),
            round(float(decal_size.y) * 0.01 * float(scale.y), 6),
            round(float(decal_size.z) * 0.01 * float(scale.z), 6),
        ]

    return vec3(scale)


def decal_record(actor, component, material):
    transform = component.get_world_transform()
    scale = decal_scale_meters(component, transform)
    color = safe_property(
        component,
        "decal_color",
        safe_property(component, "color", unreal.LinearColor(1.0, 1.0, 1.0, 1.0)),
    )

    record = {
        "id": stable_id(component_identity(actor, component)),
        "name": actor.get_actor_label(),
        "actorClass": actor.get_class().get_name(),
        "component": component.get_name(),
        "type": "Decal",
        "material": material.get_path_name() if material else "None",
        "location": location_meters(transform.translation),
        "rotation": rotation_degrees(transform.rotation.rotator()),
        "scale": scale,
        "worldMatrix": world_matrix_rows(transform, scale),
        "color": linear_color(color),
        "visible": bool(safe_property(component, "visible", True)),
    }

    sort_order = safe_property(component, "sort_order")
    if sort_order is not None:
        try:
            record["sortOrder"] = int(sort_order)
        except Exception:
            pass

    return record


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


def export_static_mesh_assets(mesh_assets, output_file):
    if not EXPORT_MESHES:
        return 0

    output_directory = os.path.dirname(output_file)
    mesh_directory = os.path.join(output_directory, "Meshes")
    os.makedirs(mesh_directory, exist_ok=True)

    exported_count = 0
    for key, mesh in sorted(mesh_assets.items()):
        filename = os.path.join(mesh_directory, f"{key}.fbx")
        task = unreal.AssetExportTask()
        task.object = mesh
        task.filename = filename
        task.automated = True
        task.replace_identical = True
        task.prompt = False

        fbx_options_type = getattr(unreal, "FbxExportOption", None)
        if fbx_options_type is not None:
            task.options = fbx_options_type()

        if unreal.Exporter.run_asset_export_task(task):
            exported_count += 1
        else:
            unreal.log_warning(
                f"Failed to export static mesh FBX: {mesh.get_path_name()}"
            )

    return exported_count


def export_texture_assets(texture_assets, output_file):
    output_directory = os.path.dirname(output_file)
    texture_directory = os.path.join(output_directory, "Textures")
    os.makedirs(texture_directory, exist_ok=True)

    exported_count = 0
    for key, texture in sorted(texture_assets.items()):
        filename = os.path.join(texture_directory, f"{key}.png")
        task = unreal.AssetExportTask()
        task.object = texture
        task.filename = filename
        task.automated = True
        task.replace_identical = True
        task.prompt = False

        exporter_type = getattr(unreal, "TextureExporterPNG", None)
        if exporter_type is not None:
            task.exporter = exporter_type()

        if unreal.Exporter.run_asset_export_task(task):
            exported_count += 1
        else:
            unreal.log_warning(
                f"Failed to export texture PNG: {texture.get_path_name()}"
            )

    return exported_count


def material_metadata_path(output_file):
    lower_path = output_file.lower()
    if lower_path.endswith(".scene.json"):
        return output_file[:-len(".scene.json")] + ".materials.json"
    return os.path.splitext(output_file)[0] + ".materials.json"


def export_material_metadata(
    material_records,
    texture_records,
    texture_assets,
    output_file,
):
    exported_textures = export_texture_assets(texture_assets, output_file)
    metadata = {
        "version": 1,
        "materials": sorted(
            material_records.values(),
            key=lambda item: item["key"],
        ),
        "textures": sorted(
            texture_records.values(),
            key=lambda item: item["key"],
        ),
    }

    filename = material_metadata_path(output_file)
    output_directory = os.path.dirname(filename)
    if output_directory:
        os.makedirs(output_directory, exist_ok=True)

    with open(filename, "w", encoding="utf-8") as file:
        json.dump(metadata, file, ensure_ascii=False, indent=2)

    unreal.log(f"Material metadata exported: {filename}")
    return exported_textures


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

load_requested_map(MAP_PATH)

world = editor_system.get_editor_world()
loaded_actors = actor_system.get_all_level_actors()

placements = []
decal_records = []
environment = []
meshes = {}
mesh_assets = {}
material_records = {}
texture_records = {}
texture_assets = {}
skipped_unreal_sky_meshes = 0
decal_component_type = getattr(unreal, "DecalComponent", None)

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
        mesh_assets[key] = mesh

        materials = []
        for index in range(component.get_num_materials()):
            material = component.get_material(index)
            if material:
                register_material(
                    material,
                    material_records,
                    texture_records,
                    texture_assets,
                )
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

    if decal_component_type is not None:
        for component in actor.get_components_by_class(decal_component_type):
            material = decal_component_material(component)
            if material:
                register_material(
                    material,
                    material_records,
                    texture_records,
                    texture_assets,
                )
            decal_records.append(decal_record(actor, component, material))

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
    "decals": decal_records,
    "environment": environment,
}

output_directory = os.path.dirname(OUTPUT_FILE)
if output_directory:
    os.makedirs(output_directory, exist_ok=True)

exported_meshes = export_static_mesh_assets(mesh_assets, OUTPUT_FILE)
exported_textures = export_material_metadata(
    material_records,
    texture_records,
    texture_assets,
    OUTPUT_FILE,
)

with open(OUTPUT_FILE, "w", encoding="utf-8") as file:
    json.dump(manifest, file, ensure_ascii=False, indent=2)

unreal.log(f"Scene manifest exported: {OUTPUT_FILE}")
unreal.log(
    f"Meshes: {len(meshes)}, "
    f"exported FBX: {exported_meshes}, "
    f"materials: {len(material_records)}, "
    f"exported textures: {exported_textures}, "
    f"placements: {len(placements)}, "
    f"decals: {len(decal_records)}, "
    f"environment: {len(environment)}, "
    f"skipped sky meshes: {skipped_unreal_sky_meshes}"
)
