"""Rough area report: synthesise src/ with Yosys and print cells per module.

Needs Yosys (e.g.  pip install yowasp-yosys  ->  yowasp-yosys on PATH). Run from the repo root:
    python tools/area_report.py          # src/ and ./info.yaml
    python tools/area_report.py src1     # src1/ and src1/info.yaml
Numbers are generic gate counts (not um^2). Calibration from the real flow: 7,941 cells -> 450 % of a 1x1 tile, 2,815 cells -> 79.6 % of a 1x2,
1,350 cells -> ~83 % of a 1x1, i.e. about 9.4 .. 10.1 um^2 per generic cell (the small designs are less
efficient), and a tile core is ~16,500 um^2 x the number of tiles. 10.1 is used so that the estimate is not low. Aim for utilisation below ~80 % (set PL_TARGET_DENSITY_PCT to 80 in src/config.json).
"""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parent.parent
TILE_UM2, UM2_PER_CELL = 16500, 10.1
BS = chr(92)  # backslash, Yosys writes parametrised module names like  $paramod\ip_tick\DIV=...

# optional argument: a project folder such as src1 (sources and info.yaml inside it); default = src/ + ./info.yaml
SRC_DIR = ROOT / (sys.argv[1] if len(sys.argv) > 1 else 'src')
info = ((SRC_DIR / 'info.yaml') if len(sys.argv) > 1 else (ROOT / 'info.yaml')).read_text(encoding='utf-8')
files = re.findall(r'^\s*-\s*"([\w.]+\.v)"', info, re.M)
top = re.search(r'top_module:\s*"(\w+)"', info).group(1)
yosys = (shutil.which('yowasp-yosys') or shutil.which('yosys')
         or next((str(q) for n in ('yowasp-yosys.exe', 'yowasp-yosys') if (q := pathlib.Path(sys.executable).parent / n).exists()), None))
if not yosys:
    sys.exit('Yosys not found: pip install yowasp-yosys')

stat = pathlib.Path(tempfile.mkdtemp()) / 'stat.txt'
sources = ' '.join((SRC_DIR / f).as_posix() for f in files)
script = (f'read_verilog {sources}; hierarchy -top {top}; synth -top {top}; '
          f'abc -g AND,NAND,OR,NOR,XOR,XNOR,ANDNOT,ORNOT,MUX; opt_clean; tee -o {stat.as_posix()} stat')
subprocess.run([yosys, '-q', '-p', script], check=True, stdout=subprocess.DEVNULL)

text = stat.read_text()
hier = text[text.index('=== design hierarchy ==='):]
print('Cells per module (count includes its submodules; indented = inside the module above):')
for line in hier.splitlines():
    m = re.match(r'^(\s+)(\d+)\s+(\S+)\s*$', line)
    if not m or m.group(3).startswith('$_') or m.group(3) in ('wires', 'ports', 'cells', 'submodules'):
        continue
    name = m.group(3)
    if name.startswith('$paramod'):
        name = name.split(BS)[1] if BS in name else name   # keep the module name, drop the parameters
    print(f'  {m.group(2):>6}  {name}')

total = int(re.search(r'\n\s+(\d+) cells', hier).group(1))
ffs = sum(int(n) for n in re.findall(r'\n\s+(\d+)\s+\$_S?DFF\w*_', hier))
print(f'\nTOTAL {total} generic cells, {ffs} flip-flops')
for tile, n in [('1x1', 1), ('1x2', 2), ('2x2', 4), ('3x2', 6), ('4x2', 8), ('6x2', 12), ('8x2', 16)]:
    util = total * UM2_PER_CELL / (TILE_UM2 * n) * 100
    print(f'  {tile}: ~{util:5.0f} % utilisation' + ('   <-- fits' if util < 80 else ''))
