import os

def fix_webhook():
    filepath = '/home/anuhas/programming/arawwala_motors-customization/supabase/functions/wsender-sessions-arawwala_motors_customization/index.ts'
    with open(filepath, 'r') as f:
        content = f.read()
        
    old_code = 'const webhookUrl = Deno.env.get("WEBHOOK_URL_OVERRIDE") || `${supabaseUrl}/functions/v1/webhook-wsender-arawwala_motors_customization`;'
    new_code = '''let override = Deno.env.get("WEBHOOK_URL_OVERRIDE");
    if (override && !override.includes("-arawwala_motors_customization")) {
      override = override.replace("webhook-wsender", "webhook-wsender-arawwala_motors_customization");
    }
    const webhookUrl = override || `${supabaseUrl}/functions/v1/webhook-wsender-arawwala_motors_customization`;'''
    
    content = content.replace(old_code, new_code)
    
    with open(filepath, 'w') as f:
        f.write(content)

fix_webhook()
