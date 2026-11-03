"""Prove previous snake modules/artifacts are unchanged and legacy scene behavior agrees."""
from pathlib import Path
import hashlib,json,subprocess
root=Path(__file__).resolve().parents[1]; out=root/'migration/2026-11-02-tetris'
baseline=json.loads((out/'snake-baseline.json').read_text(encoding='utf-8'))
preserved=[p for p in baseline if p.startswith('migration/') or p.endswith(('vx_snake.c','vx_snake.h','proj_engine.v'))]
for p in preserved:
    assert hashlib.sha256((root/p).read_bytes()).hexdigest()==baseline[p],p
test=root/'tests/host/trace_legacy.c'; traces=[]
for label,source in [('before',out/'baseline/software/brush_app'),('after',root/'software/brush_app')]:
    exe=out/'evidence'/f'legacy_trace_{label}.exe'
    args=['gcc','-std=c11','-Wall','-Wextra','-Werror','-O2',f'-I{source}',str(test),str(source/'vx_brush.c'),str(source/'vx_snake.c')]
    if label=='after': args.append(str(source/'vx_tetris.c'))
    subprocess.run([*args,'-o',str(exe)],check=True)
    trace=subprocess.run([str(exe)],check=True,capture_output=True,timeout=15).stdout
    (out/'evidence'/f'legacy_trace_{label}.txt').write_bytes(trace);traces.append(trace)
assert traces[0]==traces[1],'Legacy brush/snake/DEMO behavior changed'
result={'preserved':preserved,'legacy_trace_steps':3000,'exact_trace_match':True,'trace_sha256':hashlib.sha256(traces[0]).hexdigest()}
(out/'evidence/snake-preservation.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print('PRESERVATION_PASS: snake files, previous delivery, projection unchanged; 3000-step legacy trace byte-identical')
