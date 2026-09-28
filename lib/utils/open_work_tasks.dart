import '../models/case_model.dart';
import '../models/task_model.dart';
import 'case_result.dart';
import 'case_status_filter.dart';

/// Staff live-work filters: hide tasks whose case is already closed.
class OpenWorkTasks {
  OpenWorkTasks._();

  static bool isCancelled(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    return s == 'cancelled' || s == 'canceled';
  }

  static bool isOpenStatus(String? status) {
    final s = (status ?? '').toLowerCase().trim();
    return s == 'pending' || s == 'in_progress' || s == 'in progress';
  }

  static bool isClosedCase(CaseModel c) {
    if (c.isArchived || CaseStatusFilter.isCompleted(c.status)) return true;
    return CaseResult.normalize(c.caseResult) != null;
  }

  static Set<String> closedCaseIds(Iterable<CaseModel> cases) {
    return cases.where(isClosedCase).map((c) => c.id).toSet();
  }

  static bool isLiveWork(TaskModel task, Set<String> closedCaseIds) {
    if (!isOpenStatus(task.status) || isCancelled(task.status)) return false;
    final caseId = task.caseId?.trim() ?? '';
    if (caseId.isEmpty) return true;
    return !closedCaseIds.contains(caseId);
  }

  static List<TaskModel> live(List<TaskModel> tasks, Set<String> closedCaseIds) {
    return tasks.where((t) => isLiveWork(t, closedCaseIds)).toList();
  }
}
