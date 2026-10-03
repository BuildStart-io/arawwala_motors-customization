import os
import glob

def fix_multiline_clients():
    functions_dir = '/home/anuhas/programming/arawwala_motors-customization/supabase/functions'
    schema_str = "db: { schema: 'arawwala_motors_customization' }"
    
    for filepath in glob.glob(f'{functions_dir}/**/*.ts', recursive=True):
        with open(filepath, 'r') as f:
            content = f.read()
            
        content = content.replace(
            'createClient(\n      Deno.env.get("SUPABASE_URL")!,\n      Deno.env.get("SUPABASE_ANON_KEY")!\n    );',
            f'createClient(\n      Deno.env.get("SUPABASE_URL")!,\n      Deno.env.get("SUPABASE_ANON_KEY")!,\n      {{ {schema_str} }}\n    );'
        )
        content = content.replace(
            'createClient(\n      Deno.env.get("SUPABASE_URL")!,\n      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!\n    );',
            f'createClient(\n      Deno.env.get("SUPABASE_URL")!,\n      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,\n      {{ {schema_str} }}\n    );'
        )
        
        with open(filepath, 'w') as f:
            f.write(content)

fix_multiline_clients()
