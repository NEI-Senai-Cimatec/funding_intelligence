import sys
import subprocess

print("Python version:", sys.version)

for pkg in ['playwright', 'curl_cffi', 'requests', 'bs4', 'selenium', 'reticulate']:
    try:
        mod = __import__(pkg)
        print(f"Package '{pkg}': INSTALLED ({getattr(mod, '__file__', 'builtin')})")
    except ImportError:
        print(f"Package '{pkg}': NOT installed")
