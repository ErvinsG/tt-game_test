"""Rebuild a single file for vga-playground from a source folder.
Run from the repo root:
    python playground/make_bundle.py          # src/  -> playground/project_all.v   (the project that is pushed)
    python playground/make_bundle.py src1     # src1/ -> playground/src1_all.v      (the older gear project)
project.v goes first, the other .v files follow. The top module is renamed to tt_um_vga_example,
the name the playground expects.
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
folder = sys.argv[1] if len(sys.argv) > 1 else 'src'
files = sorted((ROOT / folder).glob('*.v'), key=lambda p: (p.name != 'project.v', p.name))

out = f'// Single-file bundle of {folder}/ for pasting into vga-playground. Generated - edit {folder}/, not this.\n'
for f in files:
    t = f.read_text(encoding='utf-8').replace('\r\n', '\n')
    t = t.replace('`default_nettype none\n', '')
    t = t.replace('module tt_um_ervinsg_game_test', 'module tt_um_vga_example')
    out += f'// ===== {f.name} =====\n{t}\n'
name = 'project_all.v' if folder == 'src' else f'{folder}_all.v'
(ROOT / 'playground' / name).write_text(out, encoding='utf-8', newline='\n')
print(f'wrote playground/{name} from {len(files)} files: ' + ', '.join(f.name for f in files))
