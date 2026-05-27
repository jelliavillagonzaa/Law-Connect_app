// Mock data models for UI development

class MockCase {
  final String id;
  final String title;
  final String type;
  final String status; // Active, Closed, Pending
  final String description;
  final String attorneyName;
  final DateTime createdAt;

  MockCase({
    required this.id,
    required this.title,
    required this.type,
    required this.status,
    required this.description,
    required this.attorneyName,
    required this.createdAt,
  });
}

class MockAppointment {
  final String id;
  final DateTime dateTime;
  final String attorneyName;
  final String type;
  final String status; // Upcoming, Completed, Cancelled

  MockAppointment({
    required this.id,
    required this.dateTime,
    required this.attorneyName,
    required this.type,
    required this.status,
  });
}

class MockMessage {
  final String id;
  final String userName;
  final String lastMessage;
  final DateTime timestamp;
  final int unreadCount;
  final String avatarUrl;

  MockMessage({
    required this.id,
    required this.userName,
    required this.lastMessage,
    required this.timestamp,
    required this.unreadCount,
    this.avatarUrl = '',
  });
}

class MockTimelineItem {
  final DateTime date;
  final String title;
  final String description;

  MockTimelineItem({
    required this.date,
    required this.title,
    required this.description,
  });
}

class MockDocument {
  final String id;
  final String name;
  final String size;
  final DateTime uploadedAt;

  MockDocument({
    required this.id,
    required this.name,
    required this.size,
    required this.uploadedAt,
  });
}

class MockStatusUpdate {
  final DateTime timestamp;
  final String description;

  MockStatusUpdate({
    required this.timestamp,
    required this.description,
  });
}

// Mock data service
class MockDataService {
  static List<MockCase> getCases() {
    return [
      MockCase(
        id: '1',
        title: 'Property Dispute Resolution',
        type: 'Real Estate Law',
        status: 'Active',
        description: 'Property dispute case',
        attorneyName: 'John Smith',
        createdAt: DateTime.now().subtract(const Duration(days: 30)),
      ),
      MockCase(
        id: '2',
        title: 'Employment Contract Review',
        type: 'Labor Law',
        status: 'Pending',
        description: 'Employment contract review',
        attorneyName: 'Sarah Johnson',
        createdAt: DateTime.now().subtract(const Duration(days: 15)),
      ),
      MockCase(
        id: '3',
        title: 'Estate Planning & Wills',
        type: 'Estate Law',
        status: 'Closed',
        description: 'Estate planning case',
        attorneyName: 'Michael Brown',
        createdAt: DateTime.now().subtract(const Duration(days: 120)),
      ),
      MockCase(
        id: '4',
        title: 'Business Partnership Agreement',
        type: 'Corporate Law',
        status: 'Active',
        description: 'Partnership agreement',
        attorneyName: 'Emily Davis',
        createdAt: DateTime.now().subtract(const Duration(days: 60)),
      ),
      MockCase(
        id: '5',
        title: 'Family Law Mediation',
        type: 'Family Law',
        status: 'Pending',
        description: 'Family law mediation',
        attorneyName: 'David Wilson',
        createdAt: DateTime.now().subtract(const Duration(days: 20)),
      ),
      MockCase(
        id: '6',
        title: 'Intellectual Property Protection',
        type: 'IP Law',
        status: 'Active',
        description: 'IP protection case',
        attorneyName: 'Lisa Anderson',
        createdAt: DateTime.now().subtract(const Duration(days: 45)),
      ),
      MockCase(
        id: '7',
        title: 'Personal Injury Claim',
        type: 'Civil Litigation',
        status: 'Pending',
        description: 'Personal injury claim',
        attorneyName: 'Robert Taylor',
        createdAt: DateTime.now().subtract(const Duration(days: 10)),
      ),
    ];
  }

  static List<MockAppointment> getAppointments() {
    return [
      MockAppointment(
        id: '1',
        dateTime: DateTime(2024, 7, 25, 10, 0),
        attorneyName: 'Alice Johnson',
        type: 'Case Review',
        status: 'Upcoming',
      ),
      MockAppointment(
        id: '2',
        dateTime: DateTime(2024, 7, 20, 14, 30),
        attorneyName: 'Bob Williams',
        type: 'Discovery Meeting',
        status: 'Completed',
      ),
      MockAppointment(
        id: '3',
        dateTime: DateTime(2024, 7, 18, 9, 0),
        attorneyName: 'Charlie Davis',
        type: 'Consultation',
        status: 'Cancelled',
      ),
      MockAppointment(
        id: '4',
        dateTime: DateTime(2024, 7, 28, 13, 0),
        attorneyName: 'Alice Johnson',
        type: 'Client Update',
        status: 'Upcoming',
      ),
      MockAppointment(
        id: '5',
        dateTime: DateTime(2024, 8, 1, 11, 0),
        attorneyName: 'David Miller',
        type: 'Document Review',
        status: 'Upcoming',
      ),
    ];
  }

  static List<MockMessage> getMessages() {
    final now = DateTime.now();
    return [
      MockMessage(
        id: '1',
        userName: 'Sarah Chen',
        lastMessage: 'Not at the moment. We will nc',
        timestamp: DateTime(now.year, now.month, now.day, 9, 40),
        unreadCount: 2,
      ),
      MockMessage(
        id: '2',
        userName: 'David Lee',
        lastMessage: 'Hello, your appointment for t',
        timestamp: now.subtract(const Duration(days: 1)),
        unreadCount: 0,
      ),
      MockMessage(
        id: '3',
        userName: 'Emily White',
        lastMessage: 'Just a reminder about the docume',
        timestamp: now.subtract(const Duration(days: 2)),
        unreadCount: 1,
      ),
      MockMessage(
        id: '4',
        userName: 'Michael Brown',
        lastMessage: 'Regarding the settlement offer, w',
        timestamp: now.subtract(const Duration(days: 3)),
        unreadCount: 0,
      ),
    ];
  }

  static List<MockTimelineItem> getTimelineItems() {
    return [
      MockTimelineItem(
        date: DateTime(2023, 10, 26),
        title: 'Initial Consultation',
        description: 'Met with client to discuss the estate details and preliminary legal strategy.',
      ),
      MockTimelineItem(
        date: DateTime(2023, 11, 15),
        title: 'Will Validation Filed',
        description: 'Submitted the deceased\'s last will and testament to the probate court for validation.',
      ),
      MockTimelineItem(
        date: DateTime(2023, 12, 1),
        title: 'Asset Appraisal Initiated',
        description: 'Engaged a third-party appraiser to value real estate and significant assets.',
      ),
      MockTimelineItem(
        date: DateTime(2024, 1, 20),
        title: 'Creditor Notification Period',
        description: 'Public notice issued for potential creditors to file claims against the estate.',
      ),
      MockTimelineItem(
        date: DateTime(2024, 2, 5),
        title: 'Probate Hearing Scheduled',
        description: 'Court date set for formal review of the will and estate distribution plan.',
      ),
    ];
  }

  static List<MockDocument> getDocuments() {
    return [
      MockDocument(
        id: '1',
        name: 'Last Will & Testament.pdf',
        size: '2.4 MB',
        uploadedAt: DateTime(2023, 11, 1),
      ),
      MockDocument(
        id: '2',
        name: 'Property Appraisal.doc',
        size: '1.8 MB',
        uploadedAt: DateTime(2023, 12, 15),
      ),
      MockDocument(
        id: '3',
        name: 'Family Photos.zip',
        size: '15.2 MB',
        uploadedAt: DateTime(2024, 1, 5),
      ),
      MockDocument(
        id: '4',
        name: 'Court Order.pdf',
        size: '3.1 MB',
        uploadedAt: DateTime(2024, 2, 10),
      ),
    ];
  }

  static List<MockStatusUpdate> getStatusUpdates() {
    return [
      MockStatusUpdate(
        timestamp: DateTime(2024, 2, 12),
        description: 'Preparing for the final probate hearing. All documents submitted.',
      ),
      MockStatusUpdate(
        timestamp: DateTime(2024, 1, 28),
        description: 'Successfully navigated creditor claims, no significant liabilities found.',
      ),
      MockStatusUpdate(
        timestamp: DateTime(2024, 1, 10),
        description: 'Asset valuation finalized and added to estate inventory.',
      ),
    ];
  }

  static String getAttorneyNotes() {
    return 'Client was cooperative during asset declaration. Noted potential complications with one distant relative\'s claim, advised client on strategy. Ensure all communication is documented for future reference.';
  }
}
