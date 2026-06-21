#!/usr/bin/env python3
"""Generate Xcode project + build script for AltStore sideloading."""

import hashlib, os, re
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJ = ROOT / "ClaudeRemote.xcodeproj"

def sid(name: str) -> str:
    return hashlib.sha256(name.encode()).hexdigest()[:24].upper()

# ── Files ─────────────────────────────────────────────────────────
swift_files = sorted(
    str(p.relative_to(ROOT)) for p in (ROOT / "ClaudeRemote").rglob("*.swift")
)
test_files = sorted(
    str(p.relative_to(ROOT)) for p in (ROOT / "Tests").rglob("*.swift")
)

print("Swift sources:", len(swift_files))
for f in swift_files: print(f"  {f}")
print("Tests:", len(test_files))
for f in test_files: print(f"  {f}")

# ── UUIDs ─────────────────────────────────────────────────────────
F = {}  # file refs
B = {}  # build files
for f in swift_files:   F[f] = sid(f"fr-{f}"); B[f] = sid(f"bf-{f}")
for f in test_files:    F[f] = sid(f"fr-{f}"); B[f] = sid(f"bf-{f}")

FR_ASSETS   = sid("fr-assets")
FR_INFOPLIST = sid("fr-infoplist")
BF_ASSETS   = sid("bf-assets")
FR_APP      = sid("fr-app-product")
FR_TEST     = sid("fr-test-product")

# Groups
G_MAIN      = sid("g-main")
G_SRC       = sid("g-src")
G_MODELS    = sid("g-models")
G_SERVICES  = sid("g-services")
G_VM        = sid("g-viewmodels")
G_VIEWS     = sid("g-views")
G_TESTS     = sid("g-tests")
G_PRODUCTS  = sid("g-products")

# Phases
PH_SRC      = sid("ph-sources")
PH_TEST_SRC = sid("ph-test-sources")
PH_FW       = sid("ph-frameworks")
PH_RES      = sid("ph-resources")

# Targets
T_APP       = sid("t-app")
T_TEST      = sid("t-test")

# Config lists & configs
CL_PROJ     = sid("cl-proj")
CL_APP      = sid("cl-app")
CL_TEST     = sid("cl-test")
CFG_PD      = sid("cfg-proj-debug")
CFG_PR      = sid("cfg-proj-release")
CFG_AD      = sid("cfg-app-debug")
CFG_AR      = sid("cfg-app-release")
CFG_TD      = sid("cfg-test-debug")
CFG_TR      = sid("cfg-test-release")

# Project
P_ROOT      = sid("project")

# SPM
SPM_REMOTE  = sid("spm-remote")
SPM_PRODUCT = sid("spm-product")

# ── pbxproj helpers ───────────────────────────────────────────────
def q(s): return f'"{s}"'

def pobj(body, indent=2):
    """Format a PBX object dict as OpenStep plist.

    indent = indentation level for inner keys.
    Opening brace appears inline (no extra indent — standard pbxproj format).
    Closing brace is at indent-1 level (matches the key that opened it).
    """
    t = "\t" * indent
    lines = ["{"]  # inline, no indent
    # regex match for values that are safe without quotes
    SAFE_RE = re.compile(r'^[A-Za-z_][A-Za-z0-9_\.]*$')
    def val_str(v):
        """Format a value for pbxproj, auto-quoting if needed."""
        s = str(v)
        # already quoted (from q() helper) — use as-is
        if s.startswith('"') and s.endswith('"') and len(s) >= 2:
            return s
        # empty string
        if s == '':
            return '""'
        # safe identifier → no quotes needed
        if SAFE_RE.match(s):
            return s
        # everything else needs quoting
        return f'"{s}"'
    for k, v in body.items():
        if isinstance(v, dict):
            lines.append(f'{t}{k} = {pobj(v, indent+1)};')
        elif isinstance(v, list):
            if not v:
                lines.append(f'{t}{k} = ();')
            else:
                lines.append(f'{t}{k} = (')
                for item in v:
                    lines.append(f'{t}\t{val_str(item)},')
                lines.append(f'{t});')
        elif isinstance(v, bool):
            lines.append(f'{t}{k} = {"YES" if v else "NO"};')
        else:
            lines.append(f'{t}{k} = {val_str(v)};')
    lines.append("\t" * (indent - 1) + "}")  # closing at parent indent
    return "\n".join(lines)

def emit(obj_id, name, body):
    # obj_id at indent level 2, inner properties at level 3
    return f'\t\t{obj_id} /* {name} */ = {pobj(body, 3)};'

# ── Build objects ─────────────────────────────────────────────────
objects = []

def add(obj_id, name, body):
    objects.append(emit(obj_id, name, body))

# PBXBuildFile
for f, bid in B.items():
    add(bid, os.path.basename(f), {"isa": "PBXBuildFile", "fileRef": F[f]})
add(BF_ASSETS, "Assets.xcassets in Resources", {"isa": "PBXBuildFile", "fileRef": FR_ASSETS})
add(sid("bf-spm"), "SwiftTerm", {"isa": "PBXBuildFile", "productRef": SPM_PRODUCT})

# PBXFileReference
for f, fid in F.items():
    add(fid, os.path.basename(f), {
        "isa": "PBXFileReference",
        "lastKnownFileType": "sourcecode.swift",
        "path": os.path.basename(f),
        "sourceTree": q("<group>"),
    })
add(FR_ASSETS, "Assets.xcassets", {
    "isa": "PBXFileReference",
    "lastKnownFileType": "folder.assetcatalog",
    "path": "Assets.xcassets",
    "sourceTree": q("<group>"),
})
add(FR_INFOPLIST, "Info.plist", {
    "isa": "PBXFileReference",
    "lastKnownFileType": "text.plist.xml",
    "path": "Info.plist",
    "sourceTree": q("<group>"),
})
add(FR_APP, "ClaudeRemote.app", {
    "isa": "PBXFileReference",
    "explicitFileType": "wrapper.application",
    "includeInIndex": "0",
    "path": "ClaudeRemote.app",
    "sourceTree": q("BUILT_PRODUCTS_DIR"),
})
add(FR_TEST, "ClaudeRemoteTests.xctest", {
    "isa": "PBXFileReference",
    "explicitFileType": "wrapper.cfbundle",
    "includeInIndex": "0",
    "path": "ClaudeRemoteTests.xctest",
    "sourceTree": q("BUILT_PRODUCTS_DIR"),
})

# PBXGroup — build children lists from file paths
def children_for(dir_prefix):
    return [F[f] for f in swift_files if f.startswith(dir_prefix) and "/" not in f.replace(dir_prefix, "", 1).lstrip("/")]

models_kids   = [F[f] for f in swift_files if "/Models/" in f]
services_kids = [F[f] for f in swift_files if "/Services/" in f]
vm_kids       = [F[f] for f in swift_files if "/ViewModels/" in f]
views_kids    = [F[f] for f in swift_files if "/Views/" in f]
root_swift    = [F[f] for f in swift_files if f == "ClaudeRemote/ClaudeRemoteApp.swift"]

add(G_MODELS, "Models", {
    "isa": "PBXGroup", "children": models_kids,
    "path": "Models", "sourceTree": q("<group>"),
})
add(G_SERVICES, "Services", {
    "isa": "PBXGroup", "children": services_kids,
    "path": "Services", "sourceTree": q("<group>"),
})
add(G_VM, "ViewModels", {
    "isa": "PBXGroup", "children": vm_kids,
    "path": "ViewModels", "sourceTree": q("<group>"),
})
add(G_VIEWS, "Views", {
    "isa": "PBXGroup", "children": views_kids,
    "path": "Views", "sourceTree": q("<group>"),
})
add(G_SRC, "ClaudeRemote", {
    "isa": "PBXGroup",
    "children": [FR_INFOPLIST, FR_ASSETS] + root_swift + [G_MODELS, G_SERVICES, G_VM, G_VIEWS],
    "path": "ClaudeRemote", "sourceTree": q("<group>"),
})
add(G_TESTS, "Tests", {
    "isa": "PBXGroup",
    "children": [F[f] for f in test_files],
    "path": "Tests", "sourceTree": q("<group>"),
})
add(G_PRODUCTS, "Products", {
    "isa": "PBXGroup",
    "children": [FR_APP, FR_TEST],
    "name": "Products", "sourceTree": q("<group>"),
})
add(G_MAIN, "Root", {
    "isa": "PBXGroup",
    "children": [G_SRC, G_TESTS, G_PRODUCTS],
    "sourceTree": q("<group>"),
})

# Build phases
add(PH_SRC, "Sources", {
    "isa": "PBXSourcesBuildPhase",
    "buildActionMask": "2147483647",
    "files": [B[f] for f in swift_files],
    "runOnlyForDeploymentPostprocessing": "0",
})
add(PH_TEST_SRC, "TestSources", {
    "isa": "PBXSourcesBuildPhase",
    "buildActionMask": "2147483647",
    "files": [B[f] for f in test_files],
    "runOnlyForDeploymentPostprocessing": "0",
})
add(PH_FW, "Frameworks", {
    "isa": "PBXFrameworksBuildPhase",
    "buildActionMask": "2147483647",
    "files": [sid("bf-spm")],
    "runOnlyForDeploymentPostprocessing": "0",
})
add(PH_RES, "Resources", {
    "isa": "PBXResourcesBuildPhase",
    "buildActionMask": "2147483647",
    "files": [BF_ASSETS],
    "runOnlyForDeploymentPostprocessing": "0",
})

# Targets
add(T_APP, "ClaudeRemote", {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": CL_APP,
    "buildPhases": [PH_SRC, PH_FW, PH_RES],
    "buildRules": [],
    "dependencies": [],
    "name": "ClaudeRemote",
    "productName": "ClaudeRemote",
    "productReference": FR_APP,
    "productType": q("com.apple.product-type.application"),
    "packageProductDependencies": [SPM_PRODUCT],
})

test_target_dep = sid("dep-test")
add(test_target_dep, "PBXTargetDependency", {
    "isa": "PBXTargetDependency",
    "target": T_APP,
})

add(T_TEST, "ClaudeRemoteTests", {
    "isa": "PBXNativeTarget",
    "buildConfigurationList": CL_TEST,
    "buildPhases": [PH_TEST_SRC],
    "buildRules": [],
    "dependencies": [test_target_dep],
    "name": "ClaudeRemoteTests",
    "productName": "ClaudeRemoteTests",
    "productReference": FR_TEST,
    "productType": q("com.apple.product-type.bundle.unit-test"),
})

# SPM
add(SPM_REMOTE, "SwiftTerm", {
    "isa": "XCRemoteSwiftPackageReference",
    "repositoryURL": "https://github.com/migueldeicaza/SwiftTerm.git",
    "requirement": {
        "kind": "upToNextMajorVersion",
        "minimumVersion": "1.0.0",
    },
})
add(SPM_PRODUCT, "SwiftTerm", {
    "isa": "XCSwiftPackageProductDependency",
    "package": SPM_REMOTE,
    "productName": "SwiftTerm",
})

# Project
add(P_ROOT, "Project object", {
    "isa": "PBXProject",
    "attributes": {
        "BuildIndependentTargetsInParallel": "1",
        "LastSwiftUpdateCheck": "1600",
        "LastUpgradeCheck": "1600",
        "TargetAttributes": {
            T_APP: {"CreatedOnToolsVersion": "16.0"},
            T_TEST: {"CreatedOnToolsVersion": "16.0", "TestTargetID": T_APP},
        },
    },
    "buildConfigurationList": CL_PROJ,
    "compatibilityVersion": q("Xcode 14.0"),
    "developmentRegion": "en",
    "hasScannedForEncodings": "0",
    "knownRegions": ["en", "Base"],
    "mainGroup": G_MAIN,
    "packageReferences": [SPM_REMOTE],
    "productRefGroup": G_PRODUCTS,
    "projectDirPath": q(""),
    "projectRoot": q(""),
    "targets": [T_APP, T_TEST],
})

# Configurations
BASE = {
    "ALWAYS_SEARCH_USER_PATHS": "NO",
    "CLANG_ANALYZER_NONNULL": "YES",
    "CLANG_CXX_LANGUAGE_STANDARD": q("gnu++20"),
    "CLANG_ENABLE_MODULES": "YES",
    "CLANG_ENABLE_OBJC_ARC": "YES",
    "COPY_PHASE_STRIP": "NO",
    "ENABLE_STRICT_OBJC_MSGSEND": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "NO",
    "GCC_OPTIMIZATION_LEVEL": "0",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    "ONLY_ACTIVE_ARCH": "YES",
    "SDKROOT": "iphoneos",
    "SWIFT_VERSION": "5.0",
}

add(CFG_PD, "Debug", {"isa": "XCBuildConfiguration", "buildSettings": {
    **BASE, "DEBUG_INFORMATION_FORMAT": "dwarf",
    "ENABLE_TESTABILITY": "YES",
    "GCC_DYNAMIC_NO_PIC": "NO",
    "GCC_PREPROCESSOR_DEFINITIONS": [q('DEBUG=1'), q('$(inherited)')],
    "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
    "SWIFT_OPTIMIZATION_LEVEL": q("-Onone"),
}, "name": "Debug"})

add(CFG_PR, "Release", {"isa": "XCBuildConfiguration", "buildSettings": {
    **BASE, "COPY_PHASE_STRIP": "NO",
    "DEBUG_INFORMATION_FORMAT": q("dwarf-with-dsym"),
    "ENABLE_NS_ASSERTIONS": "NO",
    "GCC_OPTIMIZATION_LEVEL": "s",
    "MTL_ENABLE_DEBUG_INFO": "NO",
    "SWIFT_COMPILATION_MODE": "wholemodule",
    "SWIFT_OPTIMIZATION_LEVEL": q("-O"),
    "VALIDATE_PRODUCT": "YES",
}, "name": "Release"})

APP_SETTINGS = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "9P8WJR9KG9",
    "ENABLE_PREVIEWS": "YES",
    "GENERATE_INFOPLIST_FILE": "NO",
    "INFOPLIST_FILE": "ClaudeRemote/Info.plist",
    "INFOPLIST_KEY_CFBundleDisplayName": "Claude Remote",
    "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationPortraitUpsideDown", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    "INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"],
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.deejay.clauderemote",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "PROVISIONING_PROFILE_SPECIFIER": q(""),
    "SWIFT_EMIT_LOC_STRINGS": "YES",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1,2",
}

add(CFG_AD, "Debug", {"isa": "XCBuildConfiguration", "buildSettings": APP_SETTINGS, "name": "Debug"})
add(CFG_AR, "Release", {"isa": "XCBuildConfiguration", "buildSettings": APP_SETTINGS, "name": "Release"})

TEST_SETTINGS = {
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "CODE_SIGN_STYLE": "Automatic",
    "CURRENT_PROJECT_VERSION": "1",
    "DEVELOPMENT_TEAM": "9P8WJR9KG9",
    "GENERATE_INFOPLIST_FILE": "YES",
    "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "MARKETING_VERSION": "1.0",
    "PRODUCT_BUNDLE_IDENTIFIER": "com.deejay.clauderemote.tests",
    "PRODUCT_NAME": "$(TARGET_NAME)",
    "PROVISIONING_PROFILE_SPECIFIER": q(""),
    "SWIFT_EMIT_LOC_STRINGS": "NO",
    "SWIFT_VERSION": "5.0",
    "TARGETED_DEVICE_FAMILY": "1,2",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/ClaudeRemote.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/ClaudeRemote",
}

add(CFG_TD, "Debug", {"isa": "XCBuildConfiguration", "buildSettings": TEST_SETTINGS, "name": "Debug"})
add(CFG_TR, "Release", {"isa": "XCBuildConfiguration", "buildSettings": TEST_SETTINGS, "name": "Release"})

# Config lists
add(CL_PROJ, "Project config", {
    "isa": "XCConfigurationList",
    "buildConfigurations": [CFG_PD, CFG_PR],
    "defaultConfigurationIsVisible": "0",
    "defaultConfigurationName": "Release",
})
add(CL_APP, "App config", {
    "isa": "XCConfigurationList",
    "buildConfigurations": [CFG_AD, CFG_AR],
    "defaultConfigurationIsVisible": "0",
    "defaultConfigurationName": "Release",
})
add(CL_TEST, "Test config", {
    "isa": "XCConfigurationList",
    "buildConfigurations": [CFG_TD, CFG_TR],
    "defaultConfigurationIsVisible": "0",
    "defaultConfigurationName": "Release",
})

# ── Assemble pbxproj ──────────────────────────────────────────────
# Xcode 26+ requires consistent tab indentation (no space/tab mixing)
T = "\t"
pbxproj = f"""// !$*UTF8*$!
{{
{T}archiveVersion = 1;
{T}classes = {{
{T}}};
{T}objectVersion = 56;
{T}objects = {{
{chr(10).join(objects)}
{T}}};
{T}rootObject = {P_ROOT} /* Project object */;
}}
"""

PROJ.mkdir(parents=True, exist_ok=True)
(PROJ / "project.pbxproj").write_text(pbxproj)
print(f"\nCreated xcodeproj ({len(pbxproj)} bytes)")

# ── Verify structure ──────────────────────────────────────────────
# Check all swift files are referenced
for f in swift_files:
    assert F[f] in pbxproj, f"Missing file ref: {f}"
    assert B[f] in pbxproj, f"Missing build file: {f}"
for f in test_files:
    assert F[f] in pbxproj, f"Missing test ref: {f}"
print("All files referenced ✓")
