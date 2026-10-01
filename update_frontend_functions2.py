import os
import re

frontend_dir = "frontend/src"
suffix = "-arawwala_motors_customization"

for root, dirs, files in os.walk(frontend_dir):
    for file in files:
        if file.endswith(".tsx") or file.endswith(".ts"):
            path = os.path.join(root, file)
            with open(path, "r") as f:
                text = f.read()
            
            # Replace /functions/v1/something with /functions/v1/something-suffix
            # Allow word characters and hyphens in the function name
            text = re.sub(r'\/functions\/v1\/([\w\-]+)', r'/functions/v1/\1' + suffix, text)
            
            with open(path, "w") as f:
                f.write(text)

