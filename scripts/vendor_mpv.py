#!/usr/bin/env python3
"""Copia mpv y el cierre transitivo de sus dylibs de Homebrew dentro del
bundle de la app, reescribiendo las rutas de enlazado (install_name_tool)
para que dyld las resuelva de forma relativa (@rpath) en vez de a rutas
absolutas de Homebrew (/opt/homebrew/..., /usr/local/...). Así el mpv
empaquetado funciona en máquinas sin Homebrew instalado.

Uso: vendor_mpv.py <mpv_source_path> <bundle_resources_dir> [codesign_identity]

`codesign_identity` es opcional (por defecto "-", ad-hoc); ver build.sh
(CODESIGN_IDENTITY) para por qué convendría pasar una identidad estable.
"""
import os
import re
import shutil
import subprocess
import sys

VENDORED_PREFIXES = ("/opt/homebrew/", "/usr/local/", "/opt/local/")


def otool_deps(path):
    out = subprocess.run(["otool", "-L", path], capture_output=True, text=True, check=True).stdout
    deps = []
    for line in out.splitlines()[1:]:
        match = re.match(r"\s+(\S+)", line)
        if match:
            deps.append(match.group(1))
    return deps


def discover_closure(mpv_path):
    """BFS por las dependencias de Homebrew, devuelve {real_path: basename}."""
    closure = {}
    queue = [mpv_path]
    seen = set()
    while queue:
        current = queue.pop()
        real = os.path.realpath(current)
        if real in seen:
            continue
        seen.add(real)
        for dep in otool_deps(real):
            if not dep.startswith(VENDORED_PREFIXES):
                continue
            dep_real = os.path.realpath(dep)
            closure[dep_real] = os.path.basename(dep_real)
            queue.append(dep_real)
    return closure


def rewrite(path, old_to_new, is_dylib, codesign_identity):
    for dep in otool_deps(path):
        if dep.startswith(VENDORED_PREFIXES):
            dep_real = os.path.realpath(dep)
            new_ref = old_to_new.get(dep_real)
            if new_ref is None:
                raise RuntimeError(f"Dependencia no vendorizada: {dep} (usado por {path})")
            subprocess.run(["install_name_tool", "-change", dep, new_ref, path], check=True)

    if is_dylib:
        basename = os.path.basename(path)
        subprocess.run(["install_name_tool", "-id", f"@rpath/{basename}", path], check=True)
        subprocess.run(["install_name_tool", "-add_rpath", "@loader_path", path],
                        check=False)  # ya puede existir
    else:
        subprocess.run(["install_name_tool", "-add_rpath", "@executable_path/../lib", path],
                        check=False)

    subprocess.run(["codesign", "--force", "--sign", codesign_identity, path], check=True)


def main():
    if len(sys.argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    mpv_source, resources_dir = sys.argv[1], sys.argv[2]
    codesign_identity = sys.argv[3] if len(sys.argv) == 4 else "-"
    mpv_source = os.path.realpath(mpv_source)

    bin_dir = os.path.join(resources_dir, "bin")
    lib_dir = os.path.join(resources_dir, "lib")
    for d in (bin_dir, lib_dir):
        shutil.rmtree(d, ignore_errors=True)
        os.makedirs(d, exist_ok=True)

    closure = discover_closure(mpv_source)
    old_to_new = {real: f"@rpath/{basename}" for real, basename in closure.items()}

    mpv_dest = os.path.join(bin_dir, "mpv")
    shutil.copy2(mpv_source, mpv_dest)
    os.chmod(mpv_dest, 0o755)

    for real, basename in closure.items():
        shutil.copy2(real, os.path.join(lib_dir, basename))

    for real, basename in closure.items():
        rewrite(os.path.join(lib_dir, basename), old_to_new, is_dylib=True, codesign_identity=codesign_identity)
    rewrite(mpv_dest, old_to_new, is_dylib=False, codesign_identity=codesign_identity)

    print(f"==> mpv vendorizado con {len(closure)} dylibs en {resources_dir}")


if __name__ == "__main__":
    main()
