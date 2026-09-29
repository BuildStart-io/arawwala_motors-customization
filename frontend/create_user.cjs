const { createClient } = require('@supabase/supabase-js');
const supabase = createClient('http://localhost:8000', 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q');
async function run() {
  const { data, error } = await supabase.auth.admin.createUser({
    email: 'test@arawwala.com',
    password: 'Password123!',
    email_confirm: true,
    user_metadata: { full_name: 'Test Customer' }
  });
  console.log(error ? error : data);
}
run();
