/*==========================================================
  HealthPulse AI
  Script: 006_Telehealth_Schema.sql
  Purpose: Create the core Telehealth schema tables.

  Tables:
    1. Telehealth.VirtualVisit
    2. Telehealth.SessionEvent
    3. Telehealth.Device
    4. Telehealth.DeviceReading
    5. Telehealth.WaitlistQueue

  Design standards:
    - INT IDENTITY surrogate primary keys
    - UTC audit timestamps
    - DATETIME2(3) for timestamps
    - Trusted foreign keys created WITH CHECK
    - Composite foreign keys enforce consistency
    - Filtered unique indexes for nullable identifiers
    - No stored calculated durations, averages, or percentages
==========================================================*/

USE HealthPulseAI;
GO

SET XACT_ABORT ON;
GO


/*==========================================================
  Prerequisite parent-table constraints
==========================================================*/

/*
  Allows child tables to verify that an encounter belongs
  to a specific patient.
*/
IF OBJECT_ID('Clinical.Encounter', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.key_constraints
       WHERE name = 'UQ_Encounter_EncounterID_PatientID'
         AND parent_object_id = OBJECT_ID('Clinical.Encounter')
   )
BEGIN
    ALTER TABLE Clinical.Encounter
    ADD CONSTRAINT UQ_Encounter_EncounterID_PatientID
        UNIQUE (EncounterID, PatientID);

    PRINT 'Added UQ_Encounter_EncounterID_PatientID.';
END
ELSE
BEGIN
    PRINT 'Skipped UQ_Encounter_EncounterID_PatientID because it already exists.';
END;
GO


/*
  Allows VirtualVisit to verify that a provider belongs
  to the specified hospital.
*/
IF OBJECT_ID('Hospital.Provider', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.key_constraints
       WHERE name = 'UQ_Provider_ProviderID_HospitalID'
         AND parent_object_id = OBJECT_ID('Hospital.Provider')
   )
BEGIN
    ALTER TABLE Hospital.Provider
    ADD CONSTRAINT UQ_Provider_ProviderID_HospitalID
        UNIQUE (ProviderID, HospitalID);

    PRINT 'Added UQ_Provider_ProviderID_HospitalID.';
END
ELSE
BEGIN
    PRINT 'Skipped UQ_Provider_ProviderID_HospitalID because it already exists.';
END;
GO


/*==========================================================
  Create Telehealth schema
==========================================================*/

IF NOT EXISTS
(
    SELECT 1
    FROM sys.schemas
    WHERE name = 'Telehealth'
)
BEGIN
    EXEC ('CREATE SCHEMA Telehealth;');

    PRINT 'Created schema Telehealth.';
END
ELSE
BEGIN
    PRINT 'Skipped schema Telehealth because it already exists.';
END;
GO


/*==========================================================
  1. Telehealth.VirtualVisit

  Represents a scheduled or completed virtual patient visit.
  Durations and waiting times are calculated from timestamps.
==========================================================*/

IF OBJECT_ID('Telehealth.VirtualVisit', 'U') IS NULL
BEGIN
    CREATE TABLE Telehealth.VirtualVisit
    (
        VirtualVisitID             INT IDENTITY(1,1) NOT NULL,
        EncounterID                INT NOT NULL,
        PatientID                  INT NOT NULL,
        ProviderID                 INT NOT NULL,
        HospitalID                 INT NOT NULL,
        DepartmentID               INT NOT NULL,

        VisitNumber                VARCHAR(30) NOT NULL,

        ScheduledStartDateTimeUTC  DATETIME2(3) NOT NULL,
        ScheduledEndDateTimeUTC    DATETIME2(3) NULL,
        ActualStartDateTimeUTC     DATETIME2(3) NULL,
        ActualEndDateTimeUTC       DATETIME2(3) NULL,

        VisitStatus                VARCHAR(20) NOT NULL
            CONSTRAINT DF_VirtualVisit_VisitStatus
            DEFAULT ('Scheduled'),

        VisitType                  VARCHAR(30) NOT NULL
            CONSTRAINT DF_VirtualVisit_VisitType
            DEFAULT ('Video'),

        PlatformName               NVARCHAR(100) NULL,
        MeetingIdentifier          NVARCHAR(200) NULL,
        PatientDeviceType          VARCHAR(30) NULL,
        PatientConnectionMethod    VARCHAR(30) NULL,

        PatientJoinedDateTimeUTC   DATETIME2(3) NULL,
        ProviderJoinedDateTimeUTC  DATETIME2(3) NULL,

        DisconnectReason           NVARCHAR(200) NULL,
        CancellationReason         NVARCHAR(200) NULL,

        IsInterpreterRequired      BIT NOT NULL
            CONSTRAINT DF_VirtualVisit_IsInterpreterRequired
            DEFAULT (0),

        InterpreterLanguage        NVARCHAR(50) NULL,

        CreatedDateUTC             DATETIME2(3) NOT NULL
            CONSTRAINT DF_VirtualVisit_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC            DATETIME2(3) NOT NULL
            CONSTRAINT DF_VirtualVisit_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_VirtualVisit
            PRIMARY KEY CLUSTERED (VirtualVisitID),

        CONSTRAINT UQ_VirtualVisit_VisitNumber
            UNIQUE (VisitNumber),

        /*
          One clinical encounter can map to no more than
          one virtual visit.
        */
        CONSTRAINT UQ_VirtualVisit_EncounterID
            UNIQUE (EncounterID),

        /*
          Composite keys support child-table consistency.
        */
        CONSTRAINT UQ_VirtualVisit_VisitID_PatientID
            UNIQUE (VirtualVisitID, PatientID),

        CONSTRAINT UQ_VirtualVisit_VisitID_ProviderID
            UNIQUE (VirtualVisitID, ProviderID),

        CONSTRAINT UQ_VirtualVisit_VisitID_DepartmentID
            UNIQUE (VirtualVisitID, DepartmentID),

        CONSTRAINT CK_VirtualVisit_VisitType
            CHECK
            (
                VisitType IN
                (
                    'Video',
                    'Audio',
                    'Chat',
                    'Remote Consultation',
                    'Follow-up'
                )
            ),

        CONSTRAINT CK_VirtualVisit_VisitStatus
            CHECK
            (
                VisitStatus IN
                (
                    'Scheduled',
                    'Waiting',
                    'In Progress',
                    'Completed',
                    'Cancelled',
                    'No Show',
                    'Disconnected'
                )
            ),

        CONSTRAINT CK_VirtualVisit_ScheduledTimes
            CHECK
            (
                ScheduledEndDateTimeUTC IS NULL
                OR ScheduledEndDateTimeUTC >= ScheduledStartDateTimeUTC
            ),

        CONSTRAINT CK_VirtualVisit_ActualTimes
            CHECK
            (
                ActualEndDateTimeUTC IS NULL
                OR ActualStartDateTimeUTC IS NULL
                OR ActualEndDateTimeUTC >= ActualStartDateTimeUTC
            ),

        CONSTRAINT CK_VirtualVisit_InterpreterLanguage
            CHECK
            (
                (
                    IsInterpreterRequired = 0
                    AND InterpreterLanguage IS NULL
                )
                OR
                (
                    IsInterpreterRequired = 1
                    AND NULLIF(LTRIM(RTRIM(InterpreterLanguage)), '') IS NOT NULL
                )
            )
    );


    ALTER TABLE Telehealth.VirtualVisit WITH CHECK
    ADD CONSTRAINT FK_VirtualVisit_Encounter_Patient
        FOREIGN KEY (EncounterID, PatientID)
        REFERENCES Clinical.Encounter (EncounterID, PatientID);


    ALTER TABLE Telehealth.VirtualVisit WITH CHECK
    ADD CONSTRAINT FK_VirtualVisit_Provider_Hospital
        FOREIGN KEY (ProviderID, HospitalID)
        REFERENCES Hospital.Provider (ProviderID, HospitalID);


    ALTER TABLE Telehealth.VirtualVisit WITH CHECK
    ADD CONSTRAINT FK_VirtualVisit_Department_Hospital
        FOREIGN KEY (DepartmentID, HospitalID)
        REFERENCES Hospital.Department (DepartmentID, HospitalID);


    ALTER TABLE Telehealth.VirtualVisit
        CHECK CONSTRAINT FK_VirtualVisit_Encounter_Patient;

    ALTER TABLE Telehealth.VirtualVisit
        CHECK CONSTRAINT FK_VirtualVisit_Provider_Hospital;

    ALTER TABLE Telehealth.VirtualVisit
        CHECK CONSTRAINT FK_VirtualVisit_Department_Hospital;


    CREATE INDEX IX_VirtualVisit_PatientID
        ON Telehealth.VirtualVisit (PatientID);

    CREATE INDEX IX_VirtualVisit_ProviderID
        ON Telehealth.VirtualVisit (ProviderID);

    CREATE INDEX IX_VirtualVisit_HospitalID_DepartmentID
        ON Telehealth.VirtualVisit (HospitalID, DepartmentID);

    CREATE INDEX IX_VirtualVisit_VisitStatus
        ON Telehealth.VirtualVisit (VisitStatus);

    CREATE INDEX IX_VirtualVisit_ScheduledStartDateTimeUTC
        ON Telehealth.VirtualVisit (ScheduledStartDateTimeUTC);

    CREATE INDEX IX_VirtualVisit_Patient_ScheduledStart
        ON Telehealth.VirtualVisit
        (
            PatientID,
            ScheduledStartDateTimeUTC
        );

    PRINT 'Created Telehealth.VirtualVisit.';
END
ELSE
BEGIN
    PRINT 'Skipped Telehealth.VirtualVisit because it already exists.';
END;
GO


/*==========================================================
  2. Telehealth.SessionEvent

  Stores the ordered event history for a telehealth session.
==========================================================*/

IF OBJECT_ID('Telehealth.SessionEvent', 'U') IS NULL
BEGIN
    CREATE TABLE Telehealth.SessionEvent
    (
        SessionEventID         INT IDENTITY(1,1) NOT NULL,
        VirtualVisitID         INT NOT NULL,
        EventSequenceNumber    INT NOT NULL,

        EventType              VARCHAR(30) NOT NULL,

        EventDateTimeUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_SessionEvent_EventDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        ParticipantType        VARCHAR(20) NULL,
        ParticipantID          INT NULL,

        EventDescription       NVARCHAR(500) NULL,
        TechnicalErrorCode     VARCHAR(50) NULL,
        TechnicalErrorMessage  NVARCHAR(1000) NULL,

        CreatedDateUTC         DATETIME2(3) NOT NULL
            CONSTRAINT DF_SessionEvent_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_SessionEvent
            PRIMARY KEY CLUSTERED (SessionEventID),

        CONSTRAINT UQ_SessionEvent_Visit_Sequence
            UNIQUE (VirtualVisitID, EventSequenceNumber),

        CONSTRAINT CK_SessionEvent_EventSequenceNumber
            CHECK (EventSequenceNumber > 0),

        CONSTRAINT CK_SessionEvent_EventType
            CHECK
            (
                EventType IN
                (
                    'Session Created',
                    'Patient Joined',
                    'Provider Joined',
                    'Interpreter Joined',
                    'Connection Lost',
                    'Connection Restored',
                    'Session Started',
                    'Session Ended',
                    'Patient Left',
                    'Provider Left',
                    'Technical Error'
                )
            ),

        CONSTRAINT CK_SessionEvent_ParticipantType
            CHECK
            (
                ParticipantType IS NULL
                OR ParticipantType IN
                (
                    'Patient',
                    'Provider',
                    'Interpreter',
                    'System',
                    'Support'
                )
            ),

        CONSTRAINT CK_SessionEvent_TechnicalErrorDetails
            CHECK
            (
                EventType <> 'Technical Error'
                OR TechnicalErrorCode IS NOT NULL
                OR TechnicalErrorMessage IS NOT NULL
            )
    );


    ALTER TABLE Telehealth.SessionEvent WITH CHECK
    ADD CONSTRAINT FK_SessionEvent_VirtualVisit
        FOREIGN KEY (VirtualVisitID)
        REFERENCES Telehealth.VirtualVisit (VirtualVisitID);


    ALTER TABLE Telehealth.SessionEvent
        CHECK CONSTRAINT FK_SessionEvent_VirtualVisit;


    CREATE INDEX IX_SessionEvent_EventDateTimeUTC
        ON Telehealth.SessionEvent (EventDateTimeUTC);

    CREATE INDEX IX_SessionEvent_EventType
        ON Telehealth.SessionEvent (EventType);

    CREATE INDEX IX_SessionEvent_Visit_EventDateTime
        ON Telehealth.SessionEvent
        (
            VirtualVisitID,
            EventDateTimeUTC
        );

    PRINT 'Created Telehealth.SessionEvent.';
END
ELSE
BEGIN
    PRINT 'Skipped Telehealth.SessionEvent because it already exists.';
END;
GO


/*==========================================================
  3. Telehealth.Device

  Stores remote monitoring devices assigned to patients.
==========================================================*/

IF OBJECT_ID('Telehealth.Device', 'U') IS NULL
BEGIN
    CREATE TABLE Telehealth.Device
    (
        DeviceID           INT IDENTITY(1,1) NOT NULL,
        PatientID          INT NOT NULL,

        DeviceIdentifier   VARCHAR(100) NOT NULL,
        DeviceType         VARCHAR(30) NOT NULL,
        Manufacturer       NVARCHAR(150) NULL,
        ModelNumber        NVARCHAR(100) NULL,
        SerialNumber       VARCHAR(100) NULL,
        FirmwareVersion    NVARCHAR(50) NULL,

        AssignedDate       DATE NULL,
        ActivatedDate      DATE NULL,
        DeactivatedDate    DATE NULL,

        DeviceStatus       VARCHAR(20) NOT NULL
            CONSTRAINT DF_Device_DeviceStatus
            DEFAULT ('Assigned'),

        IsActive           BIT NOT NULL
            CONSTRAINT DF_Device_IsActive
            DEFAULT (1),

        CreatedDateUTC     DATETIME2(3) NOT NULL
            CONSTRAINT DF_Device_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC    DATETIME2(3) NOT NULL
            CONSTRAINT DF_Device_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Device
            PRIMARY KEY CLUSTERED (DeviceID),

        CONSTRAINT UQ_Device_DeviceIdentifier
            UNIQUE (DeviceIdentifier),

        CONSTRAINT UQ_Device_DeviceID_PatientID
            UNIQUE (DeviceID, PatientID),

        CONSTRAINT CK_Device_DeviceType
            CHECK
            (
                DeviceType IN
                (
                    'Blood Pressure Monitor',
                    'Glucose Meter',
                    'Pulse Oximeter',
                    'Weight Scale',
                    'Thermometer',
                    'Heart Rate Monitor',
                    'Wearable',
                    'Other'
                )
            ),

        CONSTRAINT CK_Device_DeviceStatus
            CHECK
            (
                DeviceStatus IN
                (
                    'Assigned',
                    'Active',
                    'Inactive',
                    'Returned',
                    'Lost',
                    'Damaged',
                    'Maintenance'
                )
            ),

        CONSTRAINT CK_Device_ActivatedAfterAssigned
            CHECK
            (
                ActivatedDate IS NULL
                OR AssignedDate IS NULL
                OR ActivatedDate >= AssignedDate
            ),

        CONSTRAINT CK_Device_DeactivatedAfterActivated
            CHECK
            (
                DeactivatedDate IS NULL
                OR ActivatedDate IS NULL
                OR DeactivatedDate >= ActivatedDate
            )
    );


    ALTER TABLE Telehealth.Device WITH CHECK
    ADD CONSTRAINT FK_Device_Patient
        FOREIGN KEY (PatientID)
        REFERENCES Clinical.Patient (PatientID);


    ALTER TABLE Telehealth.Device
        CHECK CONSTRAINT FK_Device_Patient;


    CREATE INDEX IX_Device_PatientID
        ON Telehealth.Device (PatientID);

    CREATE INDEX IX_Device_DeviceType_DeviceStatus
        ON Telehealth.Device (DeviceType, DeviceStatus);

    CREATE INDEX IX_Device_IsActive
        ON Telehealth.Device (IsActive);


    CREATE UNIQUE INDEX UX_Device_SerialNumber
        ON Telehealth.Device (SerialNumber)
        WHERE SerialNumber IS NOT NULL;

    PRINT 'Created Telehealth.Device.';
END
ELSE
BEGIN
    PRINT 'Skipped Telehealth.Device because it already exists.';
END;
GO


/*==========================================================
  4. Telehealth.DeviceReading

  Stores remote patient-monitoring measurements.
==========================================================*/

IF OBJECT_ID('Telehealth.DeviceReading', 'U') IS NULL
BEGIN
    CREATE TABLE Telehealth.DeviceReading
    (
        DeviceReadingID          INT IDENTITY(1,1) NOT NULL,
        DeviceID                 INT NOT NULL,
        PatientID                INT NOT NULL,
        EncounterID              INT NULL,

        ReadingDateTimeUTC       DATETIME2(3) NOT NULL,
        ReadingType              VARCHAR(30) NOT NULL,

        NumericValue             DECIMAL(12,3) NULL,
        UnitOfMeasure            VARCHAR(20) NULL,

        SecondaryNumericValue    DECIMAL(12,3) NULL,
        SecondaryUnitOfMeasure   VARCHAR(20) NULL,

        TextValue                NVARCHAR(500) NULL,

        IsAbnormal               BIT NOT NULL
            CONSTRAINT DF_DeviceReading_IsAbnormal
            DEFAULT (0),

        DataSource               VARCHAR(20) NULL,

        ReceivedDateTimeUTC      DATETIME2(3) NOT NULL
            CONSTRAINT DF_DeviceReading_ReceivedDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        CreatedDateUTC           DATETIME2(3) NOT NULL
            CONSTRAINT DF_DeviceReading_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_DeviceReading
            PRIMARY KEY CLUSTERED (DeviceReadingID),

        CONSTRAINT CK_DeviceReading_ReadingType
            CHECK
            (
                ReadingType IN
                (
                    'Systolic Blood Pressure',
                    'Diastolic Blood Pressure',
                    'Blood Pressure',
                    'Blood Glucose',
                    'Oxygen Saturation',
                    'Weight',
                    'Temperature',
                    'Heart Rate',
                    'Steps',
                    'Sleep',
                    'Other'
                )
            ),

        CONSTRAINT CK_DeviceReading_DataSource
            CHECK
            (
                DataSource IS NULL
                OR DataSource IN
                (
                    'Bluetooth',
                    'Cellular',
                    'Wi-Fi',
                    'Manual',
                    'API',
                    'File Import'
                )
            ),

        /*
          At least one usable measurement value must exist.
        */
        CONSTRAINT CK_DeviceReading_ValuePresent
            CHECK
            (
                NumericValue IS NOT NULL
                OR SecondaryNumericValue IS NOT NULL
                OR NULLIF(LTRIM(RTRIM(TextValue)), '') IS NOT NULL
            ),

        CONSTRAINT CK_DeviceReading_NumericValue
            CHECK
            (
                NumericValue IS NULL
                OR NumericValue >= 0
            ),

        CONSTRAINT CK_DeviceReading_SecondaryNumericValue
            CHECK
            (
                SecondaryNumericValue IS NULL
                OR SecondaryNumericValue >= 0
            ),

        /*
          Secondary units should only be supplied when a
          secondary numeric value exists.
        */
        CONSTRAINT CK_DeviceReading_SecondaryUnit
            CHECK
            (
                SecondaryNumericValue IS NOT NULL
                OR SecondaryUnitOfMeasure IS NULL
            ),

        /*
          Allows five minutes of clock skew between the device
          and the receiving system.
        */
        CONSTRAINT CK_DeviceReading_ReceivedNotBeforeReading
            CHECK
            (
                ReceivedDateTimeUTC >=
                DATEADD(MINUTE, -5, ReadingDateTimeUTC)
            )
    );


    ALTER TABLE Telehealth.DeviceReading WITH CHECK
    ADD CONSTRAINT FK_DeviceReading_Device_Patient
        FOREIGN KEY (DeviceID, PatientID)
        REFERENCES Telehealth.Device (DeviceID, PatientID);


    ALTER TABLE Telehealth.DeviceReading WITH CHECK
    ADD CONSTRAINT FK_DeviceReading_Encounter_Patient
        FOREIGN KEY (EncounterID, PatientID)
        REFERENCES Clinical.Encounter (EncounterID, PatientID);


    ALTER TABLE Telehealth.DeviceReading
        CHECK CONSTRAINT FK_DeviceReading_Device_Patient;

    ALTER TABLE Telehealth.DeviceReading
        CHECK CONSTRAINT FK_DeviceReading_Encounter_Patient;


    CREATE INDEX IX_DeviceReading_Patient_ReadingDateTimeUTC
        ON Telehealth.DeviceReading
        (
            PatientID,
            ReadingDateTimeUTC
        );

    CREATE INDEX IX_DeviceReading_Device_ReadingDateTimeUTC
        ON Telehealth.DeviceReading
        (
            DeviceID,
            ReadingDateTimeUTC
        );

    CREATE INDEX IX_DeviceReading_ReadingType_ReadingDateTimeUTC
        ON Telehealth.DeviceReading
        (
            ReadingType,
            ReadingDateTimeUTC
        );

    CREATE INDEX IX_DeviceReading_EncounterID
        ON Telehealth.DeviceReading (EncounterID);


    CREATE INDEX IX_DeviceReading_Abnormal
        ON Telehealth.DeviceReading
        (
            PatientID,
            ReadingDateTimeUTC
        )
        INCLUDE
        (
            DeviceID,
            ReadingType,
            NumericValue,
            SecondaryNumericValue,
            UnitOfMeasure
        )
        WHERE IsAbnormal = 1;

    PRINT 'Created Telehealth.DeviceReading.';
END
ELSE
BEGIN
    PRINT 'Skipped Telehealth.DeviceReading because it already exists.';
END;
GO


/*==========================================================
  5. Telehealth.WaitlistQueue

  Stores queue-entry history for telehealth visits.
  A patient may re-enter a queue after disconnecting.
==========================================================*/

IF OBJECT_ID('Telehealth.WaitlistQueue', 'U') IS NULL
BEGIN
    CREATE TABLE Telehealth.WaitlistQueue
    (
        WaitlistQueueID           INT IDENTITY(1,1) NOT NULL,
        VirtualVisitID            INT NOT NULL,
        PatientID                 INT NOT NULL,
        ProviderID                INT NULL,
        DepartmentID              INT NOT NULL,

        QueueEnteredDateTimeUTC   DATETIME2(3) NOT NULL
            CONSTRAINT DF_WaitlistQueue_QueueEnteredDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        QueueCalledDateTimeUTC    DATETIME2(3) NULL,
        QueueExitedDateTimeUTC    DATETIME2(3) NULL,

        QueueStatus               VARCHAR(20) NOT NULL
            CONSTRAINT DF_WaitlistQueue_QueueStatus
            DEFAULT ('Waiting'),

        PriorityLevel             VARCHAR(10) NOT NULL
            CONSTRAINT DF_WaitlistQueue_PriorityLevel
            DEFAULT ('Normal'),

        ExitReason                NVARCHAR(200) NULL,

        CreatedDateUTC            DATETIME2(3) NOT NULL
            CONSTRAINT DF_WaitlistQueue_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC           DATETIME2(3) NOT NULL
            CONSTRAINT DF_WaitlistQueue_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_WaitlistQueue
            PRIMARY KEY CLUSTERED (WaitlistQueueID),

        /*
          A visit may have multiple queue records, but cannot
          have duplicate entries at the same timestamp.
        */
        CONSTRAINT UQ_WaitlistQueue_Visit_EnteredTime
            UNIQUE
            (
                VirtualVisitID,
                QueueEnteredDateTimeUTC
            ),

        CONSTRAINT CK_WaitlistQueue_QueueStatus
            CHECK
            (
                QueueStatus IN
                (
                    'Waiting',
                    'Called',
                    'Admitted',
                    'Completed',
                    'Cancelled',
                    'No Show',
                    'Removed'
                )
            ),

        CONSTRAINT CK_WaitlistQueue_PriorityLevel
            CHECK
            (
                PriorityLevel IN
                (
                    'Low',
                    'Normal',
                    'High',
                    'Urgent'
                )
            ),

        CONSTRAINT CK_WaitlistQueue_CalledAfterEntered
            CHECK
            (
                QueueCalledDateTimeUTC IS NULL
                OR QueueCalledDateTimeUTC >= QueueEnteredDateTimeUTC
            ),

        CONSTRAINT CK_WaitlistQueue_ExitedAfterEntered
            CHECK
            (
                QueueExitedDateTimeUTC IS NULL
                OR QueueExitedDateTimeUTC >= QueueEnteredDateTimeUTC
            ),

        CONSTRAINT CK_WaitlistQueue_ExitedAfterCalled
            CHECK
            (
                QueueExitedDateTimeUTC IS NULL
                OR QueueCalledDateTimeUTC IS NULL
                OR QueueExitedDateTimeUTC >= QueueCalledDateTimeUTC
            ),

        CONSTRAINT CK_WaitlistQueue_ExitReason
            CHECK
            (
                QueueExitedDateTimeUTC IS NULL
                OR QueueStatus IN
                (
                    'Admitted',
                    'Completed',
                    'Cancelled',
                    'No Show',
                    'Removed'
                )
            )
    );


    ALTER TABLE Telehealth.WaitlistQueue WITH CHECK
    ADD CONSTRAINT FK_WaitlistQueue_Visit_Patient
        FOREIGN KEY (VirtualVisitID, PatientID)
        REFERENCES Telehealth.VirtualVisit
        (
            VirtualVisitID,
            PatientID
        );


    ALTER TABLE Telehealth.WaitlistQueue WITH CHECK
    ADD CONSTRAINT FK_WaitlistQueue_Visit_Provider
        FOREIGN KEY (VirtualVisitID, ProviderID)
        REFERENCES Telehealth.VirtualVisit
        (
            VirtualVisitID,
            ProviderID
        );


    ALTER TABLE Telehealth.WaitlistQueue WITH CHECK
    ADD CONSTRAINT FK_WaitlistQueue_Visit_Department
        FOREIGN KEY (VirtualVisitID, DepartmentID)
        REFERENCES Telehealth.VirtualVisit
        (
            VirtualVisitID,
            DepartmentID
        );


    ALTER TABLE Telehealth.WaitlistQueue
        CHECK CONSTRAINT FK_WaitlistQueue_Visit_Patient;

    ALTER TABLE Telehealth.WaitlistQueue
        CHECK CONSTRAINT FK_WaitlistQueue_Visit_Provider;

    ALTER TABLE Telehealth.WaitlistQueue
        CHECK CONSTRAINT FK_WaitlistQueue_Visit_Department;


    CREATE INDEX IX_WaitlistQueue_QueueStatus_Priority
        ON Telehealth.WaitlistQueue
        (
            QueueStatus,
            PriorityLevel
        );

    CREATE INDEX IX_WaitlistQueue_QueueEnteredDateTimeUTC
        ON Telehealth.WaitlistQueue
        (
            QueueEnteredDateTimeUTC
        );

    CREATE INDEX IX_WaitlistQueue_ProviderID
        ON Telehealth.WaitlistQueue
        (
            ProviderID
        );

    CREATE INDEX IX_WaitlistQueue_PatientID
        ON Telehealth.WaitlistQueue
        (
            PatientID
        );

    PRINT 'Created Telehealth.WaitlistQueue.';
END
ELSE
BEGIN
    PRINT 'Skipped Telehealth.WaitlistQueue because it already exists.';
END;
GO


PRINT 'All Telehealth schema tables were processed successfully.';
GO