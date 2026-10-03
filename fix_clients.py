import os
import glob

def fix_clients():
    functions_dir = '/home/anuhas/programming/arawwala_motors-customization/supabase/functions'
    schema_str = "db: { schema: 'arawwala_motors_customization' }"
    
    for filepath in glob.glob(f'{functions_dir}/**/*.ts', recursive=True):
        with open(filepath, 'r') as f:
            content = f.read()
            
        # Variations of createClient
        content = content.replace(
            'createClient(supabaseUrl, supabaseServiceKey);',
            f"createClient(supabaseUrl, supabaseServiceKey, {{ {schema_str} }});"
        )
        content = content.replace(
            'createClient(supabaseUrl, serviceKey);',
            f"createClient(supabaseUrl, serviceKey, {{ {schema_str} }});"
        )
        content = content.replace(
            'createClient(SUPABASE_URL, SUPABASE_ANON_KEY);',
            f"createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {{ {schema_str} }});"
        )
        content = content.replace(
            'createClient(SUPABASE_URL, SERVICE_KEY);',
            f"createClient(SUPABASE_URL, SERVICE_KEY, {{ {schema_str} }});"
        )
        
        # Variations with multi-line or existing options
        content = content.replace(
            'createClient(supabaseUrl, supabaseAnonKey, {',
            f"createClient(supabaseUrl, supabaseAnonKey, {{ {schema_str},"
        )
        content = content.replace(
            'createClient(\n      supabaseUrl,\n      supabaseAnonKey,\n      {',
            f"createClient(\n      supabaseUrl,\n      supabaseAnonKey,\n      {{\n        {schema_str},"
        )
        content = content.replace(
            'createClient(\n    supabaseUrl,\n    supabaseAnonKey,\n    {',
            f"createClient(\n    supabaseUrl,\n    supabaseAnonKey,\n    {{\n      {schema_str},"
        )
        
        # register-device special formatting
        content = content.replace(
            'createClient(\n      supabaseUrl,\n      supabaseAnonKey\n    );',
            f"createClient(\n      supabaseUrl,\n      supabaseAnonKey,\n      {{ {schema_str} }}\n    );"
        )
        content = content.replace(
            'createClient(\n      supabaseUrl,\n      supabaseServiceKey\n    );',
            f"createClient(\n      supabaseUrl,\n      supabaseServiceKey,\n      {{ {schema_str} }}\n    );"
        )
        
        with open(filepath, 'w') as f:
            f.write(content)

fix_clients()
