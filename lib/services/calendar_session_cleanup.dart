import 'hearing_calendar_sync_service.dart';
import 'staff_service.dart';

/// Clears calendar singleton caches/listeners so logout → login gets fresh data.
abstract final class CalendarSessionCleanup {
  static void onLogout() {
    StaffService.clearCalendarStreamCaches();
    HearingCalendarSyncService.instance.resetForLogout();
  }
}
