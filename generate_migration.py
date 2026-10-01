import re

with open("/tmp/schema.sql", "r") as f:
    schema = f.read()

with open("/tmp/data.sql", "r") as f:
    data = f.read()

# Replace public with arawwala_motors_customization
schema = schema.replace('SCHEMA public', 'SCHEMA arawwala_motors_customization')
schema = schema.replace(' SCHEMA public ', ' SCHEMA arawwala_motors_customization ')
schema = schema.replace(' public.', ' arawwala_motors_customization.')
schema = schema.replace('SET search_path = public,', 'SET search_path = arawwala_motors_customization,')
# For default permissions
schema = schema.replace('GRANT ALL ON SCHEMA public TO', 'GRANT ALL ON SCHEMA arawwala_motors_customization TO')

data = data.replace(' public.', ' arawwala_motors_customization.')

migration = """
-- 1. Create the new schema
CREATE SCHEMA IF NOT EXISTS arawwala_motors_customization;

-- 2. Grant usage
GRANT USAGE ON SCHEMA arawwala_motors_customization TO anon, authenticated, service_role;
GRANT ALL ON SCHEMA arawwala_motors_customization TO postgres;

-- 3. Schema dump
""" + schema + """

-- 4. Data dump
""" + data + """

-- 5. Add custom triggers for auth.users
CREATE OR REPLACE FUNCTION arawwala_motors_customization.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.profiles (user_id, email, phone)
  VALUES (new.id, new.email, new.phone);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION arawwala_motors_customization.handle_new_user_role()
RETURNS trigger AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.user_roles (user_id, role)
  VALUES (new.id, 'owner');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION arawwala_motors_customization.handle_new_user_settings()
RETURNS trigger AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.settings (user_id, key, value)
  VALUES (new.id, 'leads_auto_assign', '{"enabled": false}'::jsonb);
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created_arawwala ON auth.users;
CREATE TRIGGER on_auth_user_created_arawwala
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.handle_new_user();

DROP TRIGGER IF EXISTS on_auth_user_created_role_arawwala ON auth.users;
CREATE TRIGGER on_auth_user_created_role_arawwala
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.handle_new_user_role();

DROP TRIGGER IF EXISTS on_auth_user_created_settings_arawwala ON auth.users;
CREATE TRIGGER on_auth_user_created_settings_arawwala
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION arawwala_motors_customization.handle_new_user_settings();
"""

with open("supabase/migrations/00000000000000_init_customization.sql", "w") as f:
    f.write(migration)

