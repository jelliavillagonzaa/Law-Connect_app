-- Grants + RLS for Firestore hybrid mirror tables (Flutter app writes).
-- Run in Supabase SQL Editor if tables already exist.

grant usage on schema public to anon, authenticated;

grant select, insert, update, delete on
  public.users,
  public.appointments,
  public.hearings,
  public.notifications,
  public.tasks,
  public.sms_requests,
  public.pending_signups,
  public.calendar_events,
  public.case_requests,
  public.system_logs,
  public.system_settings,
  public.notification_requests,
  public.hearing_notifications,
  public.hearing_reminder_jobs,
  public.email_verification_otps,
  public.email_requests,
  public.deadline_reminders_sent,
  public.court_email_queue,
  public.appointment_reminders,
  public.activity_logs
to anon, authenticated;

do $$
declare
  t text;
begin
  foreach t in array array[
    'users','appointments','hearings','notifications','tasks',
    'sms_requests','pending_signups','calendar_events','case_requests',
    'system_logs','system_settings','notification_requests',
    'hearing_notifications','hearing_reminder_jobs','email_verification_otps',
    'email_requests','deadline_reminders_sent','court_email_queue',
    'appointment_reminders','activity_logs'
  ]
  loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I_hybrid_sync on public.%I', t, t);
    execute format(
      'create policy %I_hybrid_sync on public.%I for all to anon, authenticated using (true) with check (true)',
      t, t
    );
  end loop;
exception
  when undefined_table then
    raise notice 'Some mirror tables are missing — create them first, then re-run.';
end $$;
