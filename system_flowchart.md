# 3.4.4 System Flow/Functions

This section explains how the automation system works step-by-step, detailing the Input-Process-Output flow and User Interactions for each component. The following narrative describes the complete flow of activities inside the system.

## System Overview

The automation system processes email attachments through a sophisticated workflow that includes email monitoring, document extraction, text recognition, content analysis, automated actions, notifications, and calendar integration. The system operates as an end-to-end solution for handling PDF documents received via email.

## Detailed System Flow

### 1. Input Stage: Email Reception
**Input:** Email with PDF Attachment
- **Source:** External users or automated systems sending emails
- **Format:** Standard email format with PDF attachment
- **Trigger:** New email arrival in monitored inbox

**User Interaction:**
- User or external system composes and sends email containing PDF document
- Email is delivered to the designated Gmail inbox monitored by the system

### 2. Process Stage 1: Email Trigger & PDF Extraction
**Function:** Email Trigger
**Tool:** Gmail API
**Role:** Read email with PDF

**Process Flow:**
1. Gmail API continuously monitors the designated inbox for new emails
2. System applies filtering criteria to identify emails with PDF attachments
3. Upon detection, the email trigger activates the workflow
4. PDF attachment is extracted from the email message
5. Email metadata (sender, subject, timestamp) is captured for context

**Input:** Email message with PDF attachment
**Process:** Gmail API monitoring and extraction
**Output:** Extracted PDF file and email metadata

**Output Details:**
- PDF file ready for OCR processing
- Email context information (sender, subject, date)
- Trigger signal for next workflow stage

### 3. Process Stage 2: Optical Character Recognition (OCR)
**Function:** OCR
**Tool:** Tesseract OCR
**Role:** Convert PDF to text

**Process Flow:**
1. Extracted PDF is passed to Tesseract OCR engine
2. System determines if PDF contains text or scanned images
3. OCR processing converts image-based text to machine-readable text
4. Text extraction and formatting is performed
5. Quality validation ensures text accuracy

**Input:** PDF document (text or scanned images)
**Process:** Tesseract OCR text extraction
**Output:** Plain text document

**Output Details:**
- Clean, machine-readable text content
- Preserved document structure and formatting where possible
- Text ready for NLP analysis
- Confidence scores for OCR accuracy

### 4. Process Stage 3: Natural Language Processing (NLP)
**Function:** NLP
**Tool:** GPT-4o mini
**Role:** Analyze document

**Process Flow:**
1. Plain text from OCR is fed into GPT-4o mini model
2. Document content is analyzed for meaning and context
3. Key information extraction (entities, dates, names, locations)
4. Document classification and categorization
5. Sentiment analysis and intent recognition
6. Actionable insights identification

**Input:** Plain text document
**Process:** GPT-4o mini language analysis
**Output:** Structured analyzed data and insights

**Output Details:**
- Extracted key entities and information
- Document classification and tags
- Identified action items and deadlines
- Contextual understanding of document purpose
- Structured data for downstream processing

### 5. Process Stage 4: Automation & Workflow Orchestration
**Function:** Automation
**Tool:** n8n
**Role:** Connect all steps

**Process Flow:**
1. n8n workflow engine receives analyzed data from NLP stage
2. Conditional logic determines appropriate actions based on content
3. Workflow branches are executed based on document analysis
4. Integration with external systems and APIs is managed
5. Error handling and retry logic ensures reliability
6. Process monitoring and logging for audit trails

**Input:** Analyzed document data and insights
**Process:** n8n workflow orchestration
**Output:** Coordinated execution of downstream actions

**Output Details:**
- Triggered notifications to relevant users
- Calendar events creation or updates
- Database updates or record creation
- Integration with external business systems
- Process completion status and logs

### 6. Process Stage 5: Notification System
**Function:** Notification
**Tool:** Firebase Messaging
**Role:** Alert users

**Process Flow:**
1. System determines notification recipients based on document content
2. Notification messages are composed with relevant information
3. Firebase Messaging delivers push notifications to target devices
4. Notification tracking ensures delivery confirmation
5. User interaction with notifications is monitored

**Input:** Trigger events from n8n workflow
**Process:** Firebase Messaging notification delivery
**Output:** User alerts and notifications

**Output Details:**
- Real-time push notifications to mobile devices
- Email notifications for non-mobile users
- In-app notifications for active users
- Notification history and status tracking

**User Interaction:**
- Users receive alerts on their devices
- Users can interact with notifications (view, dismiss, action)
- System tracks notification engagement metrics

### 7. Process Stage 6: Calendar Integration
**Function:** Calendar
**Tool:** Google Calendar API
**Role:** Auto schedule

**Process Flow:**
1. System extracts scheduling information from analyzed document
2. Calendar events are created based on identified dates and times
3. Event details are populated with relevant document information
4. Attendees are determined and invited automatically
5. Calendar updates and synchronization are managed
6. Conflict resolution and rescheduling logic is applied

**Input:** Scheduling information extracted from document
**Process:** Google Calendar API event management
**Output:** Automated calendar events and updates

**Output Details:**
- New calendar events created with extracted information
- Existing events updated based on document changes
- Automatic attendee invitations and notifications
- Calendar synchronization across user accounts

**User Interaction:**
- Users receive calendar invitations
- Users can accept, decline, or modify events
- System updates event status based on user responses

## Complete System Flow Summary

### End-to-End Process Flow

1. **Input Reception:** Email with PDF arrives in monitored inbox
2. **Email Processing:** Gmail API triggers workflow and extracts PDF
3. **Text Extraction:** Tesseract OCR converts PDF to readable text
4. **Content Analysis:** GPT-4o mini analyzes and extracts key information
5. **Workflow Orchestration:** n8n coordinates downstream actions
6. **User Notification:** Firebase Messaging alerts relevant users
7. **Calendar Management:** Google Calendar API handles scheduling

### Data Flow Transformation

- **Email** (structured) + **PDF** (unstructured) 
- **PDF** (binary) + **OCR** (text extraction)
- **Text** (unstructured) + **NLP** (structured data)
- **Data** (structured) + **Automation** (actions)
- **Actions** (automated) + **Notifications** (user alerts)
- **Information** (contextual) + **Calendar** (scheduling)

### User Interaction Points

1. **Email Sending:** User initiates process by sending email
2. **Notification Reception:** User receives automated alerts
3. **Calendar Interaction:** User responds to calendar invitations
4. **System Monitoring:** Users can view processing status and logs

### System Benefits

- **Automation:** Eliminates manual document processing
- **Speed:** Real-time processing of incoming documents
- **Accuracy:** AI-powered analysis reduces human error
- **Integration:** Seamless connection with existing tools
- **Scalability:** Handles high volume of document processing
- **Audit Trail:** Complete logging of all processing steps

## Error Handling and Resilience

### Failure Points and Recovery

1. **Email Processing Failures:** Retry logic with exponential backoff
2. **OCR Quality Issues:** Manual review workflow for low-confidence results
3. **NLP Analysis Errors:** Fallback to basic text processing
4. **Notification Failures:** Alternative notification channels
5. **Calendar Conflicts:** Automatic rescheduling and conflict resolution

### Monitoring and Logging

- All processing steps are logged for audit purposes
- Performance metrics track system efficiency
- Error rates trigger automated alerts
- User interaction patterns are analyzed for optimization

This comprehensive system flow ensures reliable, automated processing of PDF documents from email reception through final user actions, providing a seamless experience for all stakeholders involved.
