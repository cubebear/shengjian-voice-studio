#!/usr/bin/env python3
"""Build the self-contained Intel app on a Mac with Xcode and Python 3.
Python is a build dependency only; the delivered app does not use it.
"""
import argparse, hashlib, json, os, plistlib, shutil, subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REVISION = 'f1b6865713d12a2a2365282fc02e19a5a384a565'
def run(args, **kwargs):
    subprocess.run([str(x) for x in args], check=True, **kwargs)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine-source', type=Path, default=ROOT / 'Vendor/qwen3-tts')
    parser.add_argument('--engine-binary', type=Path, help='Use an already cross-compiled Intel engine')
    parser.add_argument('--fallback-binary', type=Path, help='Use an already compiled scalar Intel fallback')
    parser.add_argument('--output', type=Path, default=ROOT / 'dist/ShengJian-Intel.app')
    parser.add_argument('--qa', action='store_true', help='QA-only app: writes a startup report and exits')
    args = parser.parse_args()
    engine_source = args.engine_source.resolve()
    output = args.output.resolve()
    if output.suffix != '.app': raise SystemExit('Output must end with .app')
    if args.engine_binary:
        engine = args.engine_binary.resolve()
    else:
        if not (engine_source / 'PINNED_REVISION').exists():
            actual = subprocess.check_output(['git','-C',str(engine_source),'rev-parse','HEAD'], text=True).strip()
            if actual != REVISION: raise SystemExit('Engine revision differs from the reviewed pin')
        elif (engine_source / 'PINNED_REVISION').read_text().strip() != REVISION:
            raise SystemExit('Engine pin mismatch')
        run(['make','clean','CC=clang -target x86_64-apple-macos10.15'], cwd=engine_source)
        run(['make','clean','CC=clang -target x86_64-apple-macos10.15'], cwd=engine_source / 'third_party/ingot')
        flags = '-O3 -Wall -Wextra -mavx2 -mfma -Ivendor -DUSE_BLAS -DQWEN_GIT_REV=\\"' + REVISION + '\\" -DQWEN_SIMD_PROFILE=\\"intel-avx2\\"'
        run(['make','-j4','qwen_tts','CC=clang -target x86_64-apple-macos10.15','ARCH_FLAGS=-mavx2 -mfma','CFLAGS_BASE='+flags,'SIMD=portable'], cwd=engine_source)
        engine = engine_source / 'qwen_tts'
    if args.fallback_binary:
        fallback = args.fallback_binary.resolve()
    else:
        scalar_source = ROOT / '.build/scalar-source'
        if scalar_source.exists(): shutil.rmtree(scalar_source)
        shutil.copytree(engine_source, scalar_source, ignore=shutil.ignore_patterns('*.o','*.a','*.d','.git','qwen_tts'))
        scalar_flags = '-O3 -Wall -Wextra -Ivendor -DUSE_BLAS -DQWEN_FORCE_SCALAR -DQWEN_GIT_REV=\\"' + REVISION + '\\" -DQWEN_SIMD_PROFILE=\\"intel-compatible\\"'
        run(['make','-j4','qwen_tts','CC=clang -target x86_64-apple-macos10.15','ARCH_FLAGS=','CFLAGS_BASE='+scalar_flags,'SIMD=scalar'], cwd=scalar_source)
        fallback = scalar_source / 'qwen_tts'
    architecture = subprocess.check_output(['lipo','-archs',str(engine)], text=True).strip()
    if subprocess.check_output(['lipo','-archs',str(fallback)],text=True).strip() != 'x86_64': raise SystemExit('Fallback must be x86_64')
    if architecture != 'x86_64': raise SystemExit('Expected an x86_64-only engine, got '+architecture)
    if output.exists(): shutil.rmtree(output)
    contents = output / 'Contents'; resources = contents / 'Resources'; binary_dir = contents / 'MacOS'
    binary_dir.mkdir(parents=True); resources.mkdir()
    shutil.copytree(ROOT / 'Resources/ui', resources / 'ui')
    (resources / 'engine').mkdir(); shutil.copy2(engine, resources / 'engine/qwen_tts')
    run(['codesign','--force','--sign','-',resources / 'engine/qwen_tts'])
    shutil.copy2(fallback, resources / 'engine/qwen_tts_compatible')
    run(['codesign','--force','--sign','-',resources / 'engine/qwen_tts_compatible'])
    (resources / 'engine/compatible-sha256.txt').write_text(hashlib.sha256((resources / 'engine/qwen_tts_compatible').read_bytes()).hexdigest()+'\n')
    (resources / 'engine/sha256.txt').write_text(hashlib.sha256((resources / 'engine/qwen_tts').read_bytes()).hexdigest()+'\n')
    licenses = resources / 'Licenses'; licenses.mkdir()
    shutil.copy2(engine_source / 'LICENSE', licenses / 'qwen3-tts-MIT.txt')
    shutil.copy2(engine_source / 'third_party/ingot/LICENSE', licenses / 'ingot-MIT.txt')
    text = (engine_source / 'vendor/lz4.h').read_text()
    (licenses / 'lz4-BSD-2-Clause.txt').write_text(text[:text.index('*/')+2]+'\n')
    if (ROOT / 'LICENSE').exists(): shutil.copy2(ROOT / 'LICENSE', licenses / 'ShengJian-MIT.txt')
    shutil.copy2(ROOT / 'Licenses/llama.cpp-MIT.txt', licenses / 'llama.cpp-MIT.txt')
    shutil.copy2(engine_source / 'third_party/kleidiai/Apache-2.0.txt', licenses / 'KleidiAI-Apache-2.0.txt')
    shutil.copy2(engine_source / 'third_party/kleidiai/NOTICE.md', licenses / 'KleidiAI-NOTICE.md')
    if (ROOT / 'THIRD_PARTY_NOTICES.md').exists():
        shutil.copy2(ROOT / 'THIRD_PARTY_NOTICES.md', licenses / 'THIRD_PARTY_NOTICES.md')
    (resources / 'build-info.json').write_text(json.dumps({'version':'0.1.0','architecture':'x86_64','minimumCompilationTarget':'10.15','engineRevision':REVISION,'engineRepo':'https://github.com/gabriele-mastrapasqua/qwen3-tts','runtime':'CPU AVX2 + Accelerate; scalar compatible fallback','modelSources':['ModelScope','Hugging Face'],'qaBuild':args.qa},indent=2)+'\n')
    info = {'CFBundleName':'声笺','CFBundleDisplayName':'声笺 · 本地语音工作室','CFBundleIdentifier':'studio.shengjian.intel','CFBundleVersion':'1','CFBundleShortVersionString':'0.1.0','CFBundleExecutable':'ShengJian','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'10.15','NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication','NSHumanReadableCopyright':'ShengJian Studio · MIT; see bundled notices'}
    shutil.copy2(ROOT / 'Resources/AppIcon.icns', resources / 'AppIcon.icns')
    info['CFBundleIconFile'] = 'AppIcon'
    (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
    cache = ROOT / '.build/swift-module-cache'; cache.mkdir(parents=True,exist_ok=True)
    command = ['xcrun','swiftc','-swift-version','5','-O','-target','x86_64-apple-macos10.15','-module-cache-path',cache,'-framework','AppKit','-framework','WebKit','-framework','AVFoundation']
    if args.qa: command += ['-D','STUDIO_QA']
    command += ['-o',binary_dir / 'ShengJian'] + sorted((ROOT / 'Sources').glob('*.swift'))
    run(command)
    run(['codesign','--force','--sign','-',output])
    run(['codesign','--verify','--deep','--strict',output])
    print('Built:',output)
if __name__ == '__main__': main()
