import os

directory = r"C:\Users\Micro\.gemini\antigravity-ide\brain\d30ec264-5822-4c70-8ecd-073063168b3a"
paths = [
    "/C:/Users/Micro/.gemini/antigravity-ide/brain/d30ec264-5822-4c70-8ecd-073063168b3a/details_modal_screenshot_1781703145423.png",
    "/c:/Users/Micro/.gemini/antigravity-ide/brain/d30ec264-5822-4c70-8ecd-073063168b3a/details_modal_screenshot_1781703145423.png",
    "/C:\\Users\\Micro\\.gemini\\antigravity-ide\\brain\\d30ec264-5822-4c70-8ecd-073063168b3a\\details_modal_screenshot_1781703145423.png",
    "/Users/Micro/.gemini/antigravity-ide/brain/d30ec264-5822-4c70-8ecd-073063168b3a/details_modal_screenshot_1781703145423.png"
]

for p in paths:
    print(f"\nPath: {p}")
    stripped = p.lstrip('/')
    print(f"  lstrip('/'): {stripped}")
    
    # Try different resolution methods
    print(f"  abspath: {os.path.abspath(p)}")
    print(f"  normpath: {os.path.normpath(p)}")
    print(f"  abspath(lstrip): {os.path.abspath(stripped)}")
    print(f"  normpath(lstrip): {os.path.normpath(stripped)}")
    
    # Try to see if it is within directory
    abs_stripped = os.path.abspath(stripped)
    norm_dir = os.path.normpath(directory)
    print(f"  abs_stripped starts with norm_dir: {abs_stripped.startswith(norm_dir)}")
    try:
        rel = os.path.relpath(abs_stripped, norm_dir)
        print(f"  relpath: {rel}")
        print(f"  is_within (not starting with ..): {not rel.startswith('..')}")
    except Exception as e:
        print(f"  relpath error: {e}")
