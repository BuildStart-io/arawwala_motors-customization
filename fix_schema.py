import os

def fix_file(filepath):
    if not os.path.exists(filepath):
        print(f"Skipping {filepath}, does not exist.")
        return
        
    with open(filepath, 'r') as f:
        content = f.read()
        
    # Replacements
    content = content.replace('CREATE SCHEMA public;', 'CREATE SCHEMA IF NOT EXISTS arawwala_motors_customization;')
    content = content.replace('COMMENT ON SCHEMA public', 'COMMENT ON SCHEMA arawwala_motors_customization')
    content = content.replace('public.', 'arawwala_motors_customization.')
    content = content.replace('SCHEMA public', 'SCHEMA arawwala_motors_customization')
    content = content.replace('SET search_path TO public;', 'SET search_path TO arawwala_motors_customization;')
    
    with open(filepath, 'w') as f:
        f.write(content)
    print(f"Fixed {filepath}")

fix_file('/home/anuhas/programming/arawwala_motors-customization/db/01_schema.sql')
fix_file('/home/anuhas/programming/arawwala_motors-customization/db/02_seed.sql')
fix_file('/home/anuhas/programming/arawwala_motors-customization/db/03_cron.sql')
