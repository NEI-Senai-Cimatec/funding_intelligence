import subprocess
import glob

r_paths = glob.glob("C:/Program Files/R/R-*/bin/Rscript.exe") + glob.glob("C:/Users/*/AppData/Local/Programs/R/R-*/bin/Rscript.exe")
rscript_bin = r_paths[0] if r_paths else "Rscript"

print(f"Executing scratch/test_new_dispatches.R using: {rscript_bin}")
try:
    res = subprocess.run([rscript_bin, "scratch/test_new_dispatches.R"], capture_output=True, text=True, encoding='utf-8', errors='ignore', timeout=180)
    print("STDOUT:\n", res.stdout)
    print("STDERR:\n", res.stderr)
    print("Return code:", res.returncode)
except Exception as e:
    print("Execution Error:", e)
