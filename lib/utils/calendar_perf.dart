import '../models/appointment_model.dart';

/// Shared tuning for attorney + staff calendar grids (same data, same style).
abstract final class CalendarPerf {
  /// Batches the first calendar_events + appointments snapshots on open.
  static const int openingCoalesceMs = 48;

  /// Subsequent Firestore churn only.
  static const int dataDebounceMs = 420;

  /// Subscribe to hearing streams after the grid has painted.
  static const int hearingStreamDeferMs = 500;

  /// Defer calendar_events backfill — display uses live hearings overlay only.
  static const int attachSyncDeferMs = 8000;

  /// Coalesce rapid hearing overlay projections after the first paint.
  static const int hearingOverlayDebounceMs = dataDebounceMs;

  /// Batch index rebuilds so Firestore bursts do not block frames.
  static const int entriesIndexDebounceMs = 380;

  /// One-shot global hearings supplement (no live 500-doc listener).
  static const int hearingGlobalOneShotDeferMs = 3200;

  /// Scoped hearing refresh — bootstrap handles the first load.
  static const int hearingScopedRefreshDeferMs = 5500;

  /// Defer client profile lookups until the grid is interactive.
  static const int clientNamesLoadDeferMs = 5000;

  /// Project hearings off the UI thread in smaller chunks above this count.
  static const int projectionAsyncThreshold = 8;

  /// Docs projected per frame when hydrating hearings (smooth like appointments).
  static const int hearingProjectionChunkSize = 12;

  /// Background scoped/global hearing supplements (after grid is interactive).
  static const int hearingSupplementDeferMs = 8000;
  /// Match legacy grid: up to three two-line chips per day cell.
  static const int maxEntriesInMonthCell = 3;

  /// Space reserved for the day-of-month label row in each cell.
  static const double monthCellHeaderReserve = 30.0;

  /// One two-line chip (time row + label row), including bottom margin.
  static const double monthCellChipHeight = 26.0;

  /// "+N more" row under the chips.
  static const double monthCellMoreRowHeight = 12.0;

  /// How many chips fit in the day-cell body (below the day-of-month header).
  static int maxChipsForBodyHeight(double bodyHeight) {
    if (bodyHeight < 18) return 0;
    for (var cap = maxEntriesInMonthCell; cap >= 1; cap--) {
      final chipsHeight = cap * monthCellChipHeight;
      if (chipsHeight <= bodyHeight) return cap;
      if (chipsHeight + monthCellMoreRowHeight <= bodyHeight) return cap;
    }
    return bodyHeight >= monthCellMoreRowHeight ? 1 : 0;
  }

  /// Chip height + shown count for a day cell body area (prevents bottom overflow).
  static ({int shown, double chipHeight, bool showMore}) layoutDayCellEntries({
    required double bodyHeight,
    required int totalEntries,
  }) {
    if (totalEntries <= 0 || bodyHeight < 12) {
      return (shown: 0, chipHeight: 0, showMore: false);
    }
    final maxByHeight = maxChipsForBodyHeight(bodyHeight);
    if (maxByHeight <= 0) {
      return (shown: 0, chipHeight: 0, showMore: totalEntries > 0);
    }

    var shown = totalEntries;
    if (shown > maxEntriesInMonthCell) shown = maxEntriesInMonthCell;
    if (shown > maxByHeight) shown = maxByHeight;

    var showMore = totalEntries > shown;
    var moreReserve = showMore ? monthCellMoreRowHeight : 0.0;
    var chipHeight = shown > 0
        ? ((bodyHeight - moreReserve) / shown).clamp(20.0, monthCellChipHeight)
        : 0.0;

    while (shown > 0 &&
        shown * chipHeight + moreReserve > bodyHeight + 0.5) {
      shown--;
      showMore = totalEntries > shown;
      moreReserve = showMore ? monthCellMoreRowHeight : 0.0;
      if (shown == 0) {
        return (shown: 0, chipHeight: 0, showMore: totalEntries > 0);
      }
      chipHeight = ((bodyHeight - moreReserve) / shown).clamp(
        20.0,
        monthCellChipHeight,
      );
    }

    return (shown: shown, chipHeight: chipHeight, showMore: showMore);
  }

  /// How many two-line chips fit in the remaining day-cell height.
  static int maxChipsForHeight(double height) {
    return maxChipsForBodyHeight(height - monthCellHeaderReserve);
  }

  /// One layout pass for the whole month grid (not per cell).
  static int maxChipsForMonthGrid({
    required double gridHeight,
    required bool isCompact,
  }) {
    return maxChipsForHeight(monthGridCellBodyHeight(
      gridHeight: gridHeight,
      isCompact: isCompact,
    ) + monthCellHeaderReserve);
  }

  /// Chip body height for every day cell — computed once per month grid.
  static double monthGridCellBodyHeight({
    required double gridHeight,
    required bool isCompact,
  }) {
    final pad = isCompact ? 8.0 : 16.0;
    final gap = isCompact ? 4.0 : 8.0;
    final rowHeight = (gridHeight - pad * 2 - gap * 5) / 6;
    return (rowHeight - monthCellHeaderReserve).clamp(0.0, double.infinity);
  }

  /// Cheap change detection — avoids hashing hundreds of Firestore rows each flush.
  static String eventsFingerprint(List<Map<String, dynamic>> events) {
    if (events.isEmpty) return '0';
    var hash = events.length;
    for (var i = 0; i < events.length; i++) {
      if (i == 0 || i == events.length - 1 || i % 23 == 0) {
        hash = Object.hash(
          hash,
          events[i]['id'],
          events[i]['eventDate'],
          events[i]['hearingDocId'],
        );
      }
    }
    return hash.toString();
  }

  static String appointmentsFingerprint(List<AppointmentModel> apps) {
    if (apps.isEmpty) return '0';
    var hash = apps.length;
    for (var i = 0; i < apps.length; i++) {
      if (i == 0 || i == apps.length - 1 || i % 23 == 0) {
        hash = Object.hash(
          hash,
          apps[i].id,
          apps[i].updatedAt.millisecondsSinceEpoch,
        );
      }
    }
    return hash.toString();
  }
}
