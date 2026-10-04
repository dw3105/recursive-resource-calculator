# Must fail on base code: proof-checked baseline writer is missing. 2026-10-04
import pathlib, subprocess, tempfile
script=pathlib.Path('tools/bytes_baseline.py')
with tempfile.TemporaryDirectory() as d:
 p=pathlib.Path(d); gate=p/'gate'; proof=p/'proof'; old=p/'old'; out=p/'out'
 gate.write_text('ROW case=a pack=layered ticks=1 worst_ms=2 cpu_s=1 sha=aaaaaaaa valid=ok main_cpu_s=1 main_sha=bbbbbbbb verdict=DIFF\n')
 proof.write_text(''); old.write_text('BYTES b cccccccc\n')
 r=subprocess.run(['python3',str(script),str(gate),str(proof),str(old),str(out)],text=True,capture_output=True)
 assert r.returncode==1 and 'a' in r.stderr, 'BB1'
 gate.write_text('ROW case=b pack=layered ticks=1 worst_ms=2 cpu_s=1 sha=aaaaaaaa valid=ok main_cpu_s=1 main_sha=aaaaaaaa verdict=SAME\n')
 subprocess.run(['python3',str(script),str(gate),str(proof),str(old),str(out)],check=True); assert 'BYTES b aaaaaaaa' in out.read_text(); print('BB1 BB2')
 gate.write_text('ROW case=c pack=layered ticks=1 worst_ms=2 cpu_s=1 sha=dddddddd valid=ok main_cpu_s=1 main_sha=bbbbbbbb verdict=DIFF\n')
 proof.write_text('PROOF case=c pack=layered sha=dddddddd validate=ok lane_sim=0 lab=1/1 parity=same\n')
 subprocess.run(['python3',str(script),str(gate),str(proof),str(old),str(out)],check=True); assert 'BYTES c ' in out.read_text(); print('BB3')
