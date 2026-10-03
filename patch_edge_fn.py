import os

def patch_edge_function():
    filepath = '/home/anuhas/programming/arawwala_motors-customization/supabase/functions/admin-manage-users-arawwala_motors_customization/index.ts'
    with open(filepath, 'r') as f:
        content = f.read()

    # Add console.log before role check
    old_role_check = '''    // Check super_admin role
    const { data: roleData } = await supabase
      .schema("arawwala_motors_customization").from("user_roles")
      .select("role")
      .eq("user_id", caller.id)
      .eq("role", "super_admin")
      .single();

    if (!roleData) {'''

    new_role_check = '''    // Check super_admin role
    console.log("Checking role for caller:", caller.id);
    const { data: roleData, error: roleError } = await supabase
      .schema("arawwala_motors_customization").from("user_roles")
      .select("role")
      .eq("user_id", caller.id)
      .eq("role", "super_admin")
      .single();
      
    console.log("Role Data:", roleData, "Role Error:", roleError);

    if (!roleData) {'''

    content = content.replace(old_role_check, new_role_check)

    with open(filepath, 'w') as f:
        f.write(content)

patch_edge_function()
