/// Firestore collection name → Supabase `public` table name.
class SupabaseMirrorTables {
  SupabaseMirrorTables._();

  static const Map<String, String> collectionToTable = {
    'users': 'users',
    'appointments': 'appointments',
    'hearings': 'hearings',
    'notifications': 'notifications',
    'tasks': 'tasks',
    'sms_requests': 'sms_requests',
    'pending_signups': 'pending_signups',
    'calendar_events': 'calendar_events',
    'case_requests': 'case_requests',
    'system_logs': 'system_logs',
    'system_settings': 'system_settings',
    'notification_requests': 'notification_requests',
    'hearing_notifications': 'hearing_notifications',
    'hearing_reminder_jobs': 'hearing_reminder_jobs',
    'email_verification_otps': 'email_verification_otps',
    'email_requests': 'email_requests',
    'deadline_reminders_sent': 'deadline_reminders_sent',
    'court_email_queue': 'court_email_queue',
    'appointment_reminders': 'appointment_reminders',
    'activity_logs': 'activity_logs',
  };

  /// Document ID is the email address (no `id` column in Supabase).
  static const Set<String> emailPrimaryKeyCollections = {
    'pending_signups',
    'email_verification_otps',
  };

  static String? tableFor(String collection) => collectionToTable[collection];

  static bool usesEmailPrimaryKey(String collection) =>
      emailPrimaryKeyCollections.contains(collection);
}
