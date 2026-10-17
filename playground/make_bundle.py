"""Rebuild playground/project_all.v (single file for vga-playground) from src/.
Run from the repo root:  python playground/make_bundle.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
ORDER = ['project.v', 'game_core.v', 'vga_shell.v', 'ip_debounce.v', 'ip_tick.v',
         'ip_div.v', 'ip_bin2bcd.v', 'ip_font.v', 'ip_polar.v', 'ip_puff.v', 'ip_smoke.v', 'pwm.v']

out = '// Single-file bundle of src/ for pasting into vga-playground. Generated - edit src/, not this.\n'
for f in ORDER:
    t = (ROOT / 'src' / f).read_text(encoding='utf-8').replace('\r\n', '\n')
    t = t.replace('`default_nettype none\n', '')
    out += f'// ===== {f} =====\n{t}\n'
(ROOT / 'playground' / 'project_all.v').write_text(out, encoding='utf-8', newline='\n')
print('wrote playground/project_all.v')
