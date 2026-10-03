with open('/home/anuhas/programming/arawwala_motors-customization/db/04_superadmin.sql', 'r') as f:
    content = f.read()

content = content.replace(
    "INSERT INTO arawwala_motors_customization.user_roles (user_id, role) VALUES (new_user_id, 'super_admin');",
    "INSERT INTO arawwala_motors_customization.user_roles (user_id, role) VALUES (new_user_id, 'super_admin') ON CONFLICT (user_id) DO UPDATE SET role = 'super_admin';"
)
content = content.replace(
    "INSERT INTO arawwala_motors_customization.profiles (id, user_id, full_name, plan_tier) VALUES (new_user_id, new_user_id, 'Arawwala Motors Superadmin', 'enterprise');",
    "INSERT INTO arawwala_motors_customization.profiles (id, user_id, full_name, plan_tier) VALUES (new_user_id, new_user_id, 'Arawwala Motors Superadmin', 'enterprise') ON CONFLICT (id) DO UPDATE SET full_name = 'Arawwala Motors Superadmin', plan_tier = 'enterprise';"
)
content = content.replace(
    "INSERT INTO arawwala_motors_customization.staff_accounts (owner_id, staff_user_id, staff_email, permissions) VALUES (new_user_id, new_user_id, 'superadmin-arawwala-motors@buildstart.io', ARRAY['all']);",
    "INSERT INTO arawwala_motors_customization.staff_accounts (owner_id, staff_user_id, staff_email, permissions) VALUES (new_user_id, new_user_id, 'superadmin-arawwala-motors@buildstart.io', ARRAY['all']) ON CONFLICT (staff_user_id, owner_id) DO UPDATE SET permissions = ARRAY['all'];"
)

with open('/home/anuhas/programming/arawwala_motors-customization/db/04_superadmin.sql', 'w') as f:
    f.write(content)
