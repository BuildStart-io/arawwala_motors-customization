import os

def add_triggers():
    filepath = '/home/anuhas/programming/arawwala_motors-customization/db/01_schema.sql'
    with open(filepath, 'a') as f:
        f.write('''
-- Custom Triggers for Arawwala Motors
CREATE OR REPLACE FUNCTION arawwala_motors_customization.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.profiles (id, user_id, full_name, plan_tier)
  VALUES (NEW.id, NEW.id, NEW.raw_user_meta_data->>'full_name', 'free');
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION arawwala_motors_customization.handle_new_user_role()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.user_roles (user_id, role)
  VALUES (NEW.id, 'business');
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION arawwala_motors_customization.handle_new_user_settings()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO arawwala_motors_customization.settings (user_id, key, value)
  VALUES (NEW.id, 'whatsapp_notifications', '{"enabled": true}'::jsonb);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_arawwala ON auth.users;
CREATE TRIGGER on_auth_user_created_arawwala
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION arawwala_motors_customization.handle_new_user();

DROP TRIGGER IF EXISTS on_auth_user_created_role_arawwala ON auth.users;
CREATE TRIGGER on_auth_user_created_role_arawwala
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION arawwala_motors_customization.handle_new_user_role();

DROP TRIGGER IF EXISTS on_auth_user_created_settings_arawwala ON auth.users;
CREATE TRIGGER on_auth_user_created_settings_arawwala
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION arawwala_motors_customization.handle_new_user_settings();
''')

add_triggers()
