import os
import re

functions_dir = "supabase/functions"
suffix = "-arawwala_motors_customization"

for fn in os.listdir(functions_dir):
    if fn.endswith(suffix):
        fn_path = os.path.join(functions_dir, fn, "index.ts")
        if not os.path.exists(fn_path): continue
        with open(fn_path, "r") as f:
            text = f.read()
        
        # Replace createClient to include schema
        # This is a bit tricky, let's just add it where createClient is called
        # The easiest way is to use a regex to inject the schema option
        # Or, just replace `.from(` with `.schema('arawwala_motors_customization').from(`
        text = text.replace('.from(', '.schema("arawwala_motors_customization").from(')
        
        # For the function calls themselves, if any fetch URLs are hardcoded:
        # e.g., `${SUPABASE_URL}/functions/v1/something` -> `${SUPABASE_URL}/functions/v1/something-arawwala_motors_customization`
        text = re.sub(r'\/functions\/v1\/([^`"\'\?\&\s]+)', r'/functions/v1/\1' + suffix, text)

        with open(fn_path, "w") as f:
            f.write(text)

