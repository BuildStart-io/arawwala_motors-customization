with open('/home/anuhas/programming/arawwala_motors-customization/db/04_superadmin.sql', 'r') as f:
    content = f.read()

content = content.replace(
    "INSERT INTO arawwala_motors_customization.user_roles (user_id, role) VALUES (new_user_id, 'super_admin') ON CONFLICT (user_id) DO UPDATE SET role = 'super_admin';",
    "UPDATE arawwala_motors_customization.user_roles SET role = 'super_admin' WHERE user_id = new_user_id;"
)
content = content.replace(
    "INSERT INTO arawwala_motors_customization.profiles (id, user_id, full_name, plan_tier) VALUES (new_user_id, new_user_id, 'Arawwala Motors Superadmin', 'enterprise') ON CONFLICT (id) DO UPDATE SET full_name = 'Arawwala Motors Superadmin', plan_tier = 'enterprise';",
    "UPDATE arawwala_motors_customization.profiles SET full_name = 'Arawwala Motors Superadmin', plan_tier = 'enterprise' WHERE id = new_user_id;"
)

with open('/home/anuhas/programming/arawwala_motors-customization/db/04_superadmin.sql', 'w') as f:
    f.write(content)
