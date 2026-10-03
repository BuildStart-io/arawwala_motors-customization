DO $$
DECLARE
    new_user_id uuid := gen_random_uuid();
BEGIN
    INSERT INTO auth.users (
        instance_id, id, aud, role, email, encrypted_password, 
        email_confirmed_at, recovery_sent_at, last_sign_in_at, 
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at, 
        confirmation_token, email_change, email_change_token_new, recovery_token
    ) VALUES (
        '00000000-0000-0000-0000-000000000000', new_user_id, 'authenticated', 'authenticated', 'superadmin-arawwala-motors@buildstart.io', 
        crypt('fOKU%3QhtwT%Ta', gen_salt('bf')), 
        now(), now(), now(), 
        '{"provider":"email","providers":["email"]}', '{}', now(), now(), 
        '', '', '', ''
    );

    INSERT INTO auth.identities (
        id, user_id, identity_data, provider, provider_id, last_sign_in_at, created_at, updated_at
    ) VALUES (
        new_user_id, new_user_id, format('{"sub":"%s","email":"%s"}', new_user_id::text, 'superadmin-arawwala-motors@buildstart.io')::jsonb, 'email', new_user_id::text, now(), now(), now()
    );

    UPDATE arawwala_motors_customization.user_roles SET role = 'super_admin' WHERE user_id = new_user_id;
    
    UPDATE arawwala_motors_customization.profiles SET full_name = 'Arawwala Motors Superadmin', plan_tier = 'enterprise' WHERE id = new_user_id;
    
    INSERT INTO arawwala_motors_customization.staff_accounts (owner_id, staff_user_id, staff_email, permissions) VALUES (new_user_id, new_user_id, 'superadmin-arawwala-motors@buildstart.io', ARRAY['all']) ON CONFLICT (staff_user_id, owner_id) DO UPDATE SET permissions = ARRAY['all'];
END $$;
