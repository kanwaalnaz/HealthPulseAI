/*==========================================================
  HealthPulse AI
  Script: 009_Marketing_Schema.sql
  Purpose: Create the core Marketing schema tables.

  Tables:
    1. Marketing.Campaign
    2. Marketing.CampaignChannel
    3. Marketing.AudienceSegment
    4. Marketing.CampaignAudience
    5. Marketing.PatientCommunicationPreference
    6. Marketing.CampaignInteraction
    7. Marketing.ReferralSource
    8. Marketing.PatientAcquisition

  Design standards:
    - INT IDENTITY surrogate primary keys
    - UTC audit timestamps (CreatedDateUTC / ModifiedDateUTC)
    - DATETIME2(3) for timestamps
    - DECIMAL(18,2) for monetary values
    - Trusted foreign keys created WITH CHECK
    - Composite foreign keys prevent cross-patient, cross-campaign,
      cross-channel, and cross-hospital mismatches
    - Filtered unique indexes for nullable identifiers
    - No stored calculated KPIs (conversion rate, ROI, CPA, CTR, etc.)
==========================================================*/

USE HealthPulseAI;
GO

SET XACT_ABORT ON;
GO


/*==========================================================
  Prerequisite parent-table constraints
==========================================================*/

/*
  Allows child tables to verify that a provider belongs to
  the specified hospital.
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


/*==========================================================
  Create Marketing schema
==========================================================*/

IF NOT EXISTS
(
    SELECT 1
    FROM sys.schemas
    WHERE name = 'Marketing'
)
BEGIN
    EXEC ('CREATE SCHEMA Marketing;');

    PRINT 'Created schema Marketing.';
END
ELSE
BEGIN
    PRINT 'Skipped schema Marketing because it already exists.';
END;
GO


/*==========================================================
  1. Marketing.Campaign
==========================================================*/

IF OBJECT_ID('Marketing.Campaign', 'U') IS NULL
BEGIN
    CREATE TABLE Marketing.Campaign
    (
        CampaignID                 INT IDENTITY(1,1) NOT NULL,
        CampaignCode               VARCHAR(30) NOT NULL,
        CampaignName               NVARCHAR(200) NOT NULL,

        CampaignType               VARCHAR(30) NOT NULL,
        CampaignObjective          VARCHAR(30) NOT NULL,

        StartDate                  DATE NOT NULL,
        EndDate                    DATE NULL,

        BudgetAmount               DECIMAL(18,2) NULL,
        TargetAudienceDescription  NVARCHAR(500) NULL,

        CampaignStatus             VARCHAR(20) NOT NULL
            CONSTRAINT DF_Campaign_CampaignStatus
            DEFAULT ('Draft'),

        HospitalID                 INT NULL,
        OwnerProviderID            INT NULL,

        IsActive                   BIT NOT NULL
            CONSTRAINT DF_Campaign_IsActive
            DEFAULT (1),

        CreatedDateUTC             DATETIME2(3) NOT NULL
            CONSTRAINT DF_Campaign_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC            DATETIME2(3) NOT NULL
            CONSTRAINT DF_Campaign_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Campaign
            PRIMARY KEY CLUSTERED (CampaignID),

        CONSTRAINT UQ_Campaign_CampaignCode
            UNIQUE (CampaignCode),

        CONSTRAINT CK_Campaign_CampaignType
            CHECK
            (
                CampaignType IN
                (
                    'Awareness',
                    'Acquisition',
                    'Retention',
                    'Reactivation',
                    'Education',
                    'Engagement',
                    'Referral',
                    'Other'
                )
            ),

        CONSTRAINT CK_Campaign_CampaignObjective
            CHECK
            (
                CampaignObjective IN
                (
                    'Lead Generation',
                    'Appointment Booking',
                    'Brand Awareness',
                    'Patient Education',
                    'Retention',
                    'Reactivation',
                    'Survey',
                    'Other'
                )
            ),

        CONSTRAINT CK_Campaign_CampaignStatus
            CHECK
            (
                CampaignStatus IN
                (
                    'Draft',
                    'Scheduled',
                    'Active',
                    'Paused',
                    'Completed',
                    'Cancelled',
                    'Archived'
                )
            ),

        CONSTRAINT CK_Campaign_EndDate
            CHECK
            (
                EndDate IS NULL
                OR EndDate >= StartDate
            ),

        CONSTRAINT CK_Campaign_BudgetAmount
            CHECK
            (
                BudgetAmount IS NULL
                OR BudgetAmount >= 0
            )
    );

    ALTER TABLE Marketing.Campaign WITH CHECK
    ADD CONSTRAINT FK_Campaign_Hospital
        FOREIGN KEY (HospitalID)
        REFERENCES Hospital.Hospital (HospitalID);

    /*
      When both are supplied, the owning provider must belong
      to the specified hospital.
    */
    ALTER TABLE Marketing.Campaign WITH CHECK
    ADD CONSTRAINT FK_Campaign_Owner_Hospital
        FOREIGN KEY (OwnerProviderID, HospitalID)
        REFERENCES Hospital.Provider
        (
            ProviderID,
            HospitalID
        );

    ALTER TABLE Marketing.Campaign
        CHECK CONSTRAINT FK_Campaign_Hospital;

    ALTER TABLE Marketing.Campaign
        CHECK CONSTRAINT FK_Campaign_Owner_Hospital;

    CREATE INDEX IX_Campaign_HospitalID
        ON Marketing.Campaign (HospitalID);

    CREATE INDEX IX_Campaign_OwnerProviderID
        ON Marketing.Campaign (OwnerProviderID);

    CREATE INDEX IX_Campaign_CampaignStatus_StartDate
        ON Marketing.Campaign
        (
            CampaignStatus,
            StartDate
        );

    CREATE INDEX IX_Campaign_CampaignType
        ON Marketing.Campaign (CampaignType);

    PRINT 'Created Marketing.Campaign.';
END
ELSE
BEGIN
    PRINT 'Skipped Marketing.Campaign because it already exists.';
END;
GO


/*==========================================================
  2. Marketing.CampaignChannel
==========================================================*/

IF OBJECT_ID('Marketing.CampaignChannel', 'U') IS NULL
BEGIN
    CREATE TABLE Marketing.CampaignChannel
    (
        CampaignChannelID   INT IDENTITY(1,1) NOT NULL,
        CampaignID          INT NOT NULL,

        ChannelType         VARCHAR(20) NOT NULL,
        ChannelName         NVARCHAR(100) NULL,

        PlannedSpendAmount  DECIMAL(18,2) NULL,
        ActualSpendAmount   DECIMAL(18,2) NULL,

        DestinationURL      NVARCHAR(500) NULL,
        TrackingCode        VARCHAR(100) NULL,

        IsActive            BIT NOT NULL
            CONSTRAINT DF_CampaignChannel_IsActive
            DEFAULT (1),

        CreatedDateUTC      DATETIME2(3) NOT NULL
            CONSTRAINT DF_CampaignChannel_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC     DATETIME2(3) NOT NULL
            CONSTRAINT DF_CampaignChannel_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_CampaignChannel
            PRIMARY KEY CLUSTERED (CampaignChannelID),

        /*
          Supports the composite FK from CampaignInteraction that
          verifies a channel belongs to the referenced campaign.
        */
        CONSTRAINT UQ_CampaignChannel_ChannelID_CampaignID
            UNIQUE (CampaignChannelID, CampaignID),

        CONSTRAINT CK_CampaignChannel_ChannelType
            CHECK
            (
                ChannelType IN
                (
                    'Email',
                    'SMS',
                    'Phone',
                    'Portal',
                    'Website',
                    'Social Media',
                    'Search',
                    'Display',
                    'Direct Mail',
                    'Referral',
                    'Event',
                    'Other'
                )
            ),

        CONSTRAINT CK_CampaignChannel_PlannedSpend
            CHECK
            (
                PlannedSpendAmount IS NULL
                OR PlannedSpendAmount >= 0
            ),

        CONSTRAINT CK_CampaignChannel_ActualSpend
            CHECK
            (
                ActualSpendAmount IS NULL
                OR ActualSpendAmount >= 0
            )
    );

    ALTER TABLE Marketing.CampaignChannel WITH CHECK
    ADD CONSTRAINT FK_CampaignChannel_Campaign
        FOREIGN KEY (CampaignID)
        REFERENCES Marketing.Campaign (CampaignID);

    ALTER TABLE Marketing.CampaignChannel
        CHECK CONSTRAINT FK_CampaignChannel_Campaign;

    CREATE INDEX IX_CampaignChannel_CampaignID
        ON Marketing.CampaignChannel (CampaignID);

    CREATE INDEX IX_CampaignChannel_ChannelType
        ON Marketing.CampaignChannel (ChannelType);

    /*
      Named channels are unique within a campaign and channel type.
    */
    CREATE UNIQUE INDEX UX_CampaignChannel_Campaign_Type_Name
        ON Marketing.CampaignChannel
        (
            CampaignID,
            ChannelType,
            ChannelName
        )
        WHERE ChannelName IS NOT NULL;

    CREATE UNIQUE INDEX UX_CampaignChannel_TrackingCode
        ON Marketing.CampaignChannel (TrackingCode)
        WHERE TrackingCode IS NOT NULL;

    PRINT 'Created Marketing.CampaignChannel.';
END
ELSE
BEGIN
    PRINT 'Skipped Marketing.CampaignChannel because it already exists.';
END;
GO


/*==========================================================
  3. Marketing.AudienceSegment
==========================================================*/

IF OBJECT_ID('Marketing.AudienceSegment', 'U') IS NULL
BEGIN
    CREATE TABLE Marketing.AudienceSegment
    (
        AudienceSegmentID         INT IDENTITY(1,1) NOT NULL,
        SegmentCode               VARCHAR(30) NOT NULL,
        SegmentName               NVARCHAR(150) NOT NULL,
        SegmentDescription        NVARCHAR(500) NULL,

        SegmentType               VARCHAR(30) NOT NULL,

        DefinitionJSON            NVARCHAR(MAX) NULL,

        RefreshFrequency          VARCHAR(20) NULL,
        LastRefreshedDateTimeUTC  DATETIME2(3) NULL,
        EstimatedMemberCount      INT NULL,

        IsActive                  BIT NOT NULL
            CONSTRAINT DF_AudienceSegment_IsActive
            DEFAULT (1),

        CreatedDateUTC            DATETIME2(3) NOT NULL
            CONSTRAINT DF_AudienceSegment_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC           DATETIME2(3) NOT NULL
            CONSTRAINT DF_AudienceSegment_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_AudienceSegment
            PRIMARY KEY CLUSTERED (AudienceSegmentID),

        CONSTRAINT UQ_AudienceSegment_SegmentCode
            UNIQUE (SegmentCode),

        CONSTRAINT CK_AudienceSegment_SegmentType
            CHECK
            (
                SegmentType IN
                (
                    'Demographic',
                    'Clinical',
                    'Geographic',
                    'Behavioral',
                    'Payer',
                    'Custom',
                    'Other'
                )
            ),

        CONSTRAINT CK_AudienceSegment_RefreshFrequency
            CHECK
            (
                RefreshFrequency IS NULL
                OR RefreshFrequency IN
                (
                    'Manual',
                    'Daily',
                    'Weekly',
                    'Monthly',
                    'Quarterly',
                    'Annually'
                )
            ),

        CONSTRAINT CK_AudienceSegment_EstimatedMemberCount
            CHECK
            (
                EstimatedMemberCount IS NULL
                OR EstimatedMemberCount >= 0
            ),

        CONSTRAINT CK_AudienceSegment_DefinitionJSON
            CHECK
            (
                DefinitionJSON IS NULL
                OR ISJSON(DefinitionJSON) = 1
            )
    );

    CREATE INDEX IX_AudienceSegment_SegmentType
        ON Marketing.AudienceSegment (SegmentType);

    CREATE INDEX IX_AudienceSegment_IsActive
        ON Marketing.AudienceSegment (IsActive);

    PRINT 'Created Marketing.AudienceSegment.';
END
ELSE
BEGIN
    PRINT 'Skipped Marketing.AudienceSegment because it already exists.';
END;
GO


/*==========================================================
  4. Marketing.CampaignAudience
==========================================================*/

IF OBJECT_ID('Marketing.CampaignAudience', 'U') IS NULL
BEGIN
    CREATE TABLE Marketing.CampaignAudience
    (
        CampaignAudienceID  INT IDENTITY(1,1) NOT NULL,
        CampaignID          INT NOT NULL,
        AudienceSegmentID   INT NOT NULL,

        AudienceRole        VARCHAR(20) NOT NULL
            CONSTRAINT DF_CampaignAudience_AudienceRole
            DEFAULT ('Target'),

        PriorityRank        INT NULL,
        ExpectedReach       INT NULL,

        CreatedDateUTC      DATETIME2(3) NOT NULL
            CONSTRAINT DF_CampaignAudience_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_CampaignAudience
            PRIMARY KEY CLUSTERED (CampaignAudienceID),

        CONSTRAINT UQ_CampaignAudience_Campaign_Segment_Role
            UNIQUE (CampaignID, AudienceSegmentID, AudienceRole),

        CONSTRAINT CK_CampaignAudience_AudienceRole
            CHECK
            (
                AudienceRole IN
                (
                    'Target',
                    'Control',
                    'Exclusion',
                    'Test'
                )
            ),

        CONSTRAINT CK_CampaignAudience_PriorityRank
            CHECK
            (
                PriorityRank IS NULL
                OR PriorityRank > 0
            ),

        CONSTRAINT CK_CampaignAudience_ExpectedReach
            CHECK
            (
                ExpectedReach IS NULL
                OR ExpectedReach >= 0
            )
    );

    ALTER TABLE Marketing.CampaignAudience WITH CHECK
    ADD CONSTRAINT FK_CampaignAudience_Campaign
        FOREIGN KEY (CampaignID)
        REFERENCES Marketing.Campaign (CampaignID);

    ALTER TABLE Marketing.CampaignAudience WITH CHECK
    ADD CONSTRAINT FK_CampaignAudience_AudienceSegment
        FOREIGN KEY (AudienceSegmentID)
        REFERENCES Marketing.AudienceSegment (AudienceSegmentID);

    ALTER TABLE Marketing.CampaignAudience
        CHECK CONSTRAINT FK_CampaignAudience_Campaign;

    ALTER TABLE Marketing.CampaignAudience
        CHECK CONSTRAINT FK_CampaignAudience_AudienceSegment;

    CREATE INDEX IX_CampaignAudience_AudienceSegmentID
        ON Marketing.CampaignAudience (AudienceSegmentID);

    PRINT 'Created Marketing.CampaignAudience.';
END
ELSE
BEGIN
    PRINT 'Skipped Marketing.CampaignAudience because it already exists.';
END;
GO


/*==========================================================
  5. Marketing.PatientCommunicationPreference
==========================================================*/

IF OBJECT_ID('Marketing.PatientCommunicationPreference', 'U') IS NULL
BEGIN
    CREATE TABLE Marketing.PatientCommunicationPreference
    (
        PatientCommunicationPreferenceID  INT IDENTITY(1,1) NOT NULL,
        PatientID                         INT NOT NULL,

        ChannelType                       VARCHAR(20) NOT NULL,

        ConsentStatus                     VARCHAR(20) NOT NULL
            CONSTRAINT DF_PatientCommPref_ConsentStatus
            DEFAULT ('Pending'),

        ConsentSource                     VARCHAR(30) NULL,
        ConsentDateTimeUTC                DATETIME2(3) NULL,
        RevokedDateTimeUTC                DATETIME2(3) NULL,

        PreferredContactTime              VARCHAR(20) NULL,
        DoNotContactReason                NVARCHAR(300) NULL,

        IsActive                          BIT NOT NULL
            CONSTRAINT DF_PatientCommPref_IsActive
            DEFAULT (1),

        CreatedDateUTC                    DATETIME2(3) NOT NULL
            CONSTRAINT DF_PatientCommPref_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC                   DATETIME2(3) NOT NULL
            CONSTRAINT DF_PatientCommPref_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_PatientCommunicationPreference
            PRIMARY KEY CLUSTERED (PatientCommunicationPreferenceID),

        CONSTRAINT CK_PatientCommPref_ChannelType
            CHECK
            (
                ChannelType IN
                (
                    'Email',
                    'SMS',
                    'Phone',
                    'Portal',
                    'Direct Mail',
                    'Push Notification',
                    'Other'
                )
            ),

        CONSTRAINT CK_PatientCommPref_ConsentStatus
            CHECK
            (
                ConsentStatus IN
                (
                    'Opted In',
                    'Opted Out',
                    'Pending',
                    'Revoked'
                )
            ),

        CONSTRAINT CK_PatientCommPref_ConsentSource
            CHECK
            (
                ConsentSource IS NULL
                OR ConsentSource IN
                (
                    'Web Portal',
                    'Phone',
                    'In Person',
                    'Paper Form',
                    'SMS',
                    'Email',
                    'Import',
                    'Other'
                )
            ),

        CONSTRAINT CK_PatientCommPref_PreferredContactTime
            CHECK
            (
                PreferredContactTime IS NULL
                OR PreferredContactTime IN
                (
                    'Morning',
                    'Afternoon',
                    'Evening',
                    'Anytime'
                )
            ),

        /* Opted In consent must record when it was granted. */
        CONSTRAINT CK_PatientCommPref_OptedInRequiresConsent
            CHECK
            (
                ConsentStatus <> 'Opted In'
                OR ConsentDateTimeUTC IS NOT NULL
            ),

        /* Revoked consent must record when it was revoked. */
        CONSTRAINT CK_PatientCommPref_RevokedRequiresDate
            CHECK
            (
                ConsentStatus <> 'Revoked'
                OR RevokedDateTimeUTC IS NOT NULL
            ),

        CONSTRAINT CK_PatientCommPref_RevokedNotBeforeConsent
            CHECK
            (
                RevokedDateTimeUTC IS NULL
                OR ConsentDateTimeUTC IS NULL
                OR RevokedDateTimeUTC >= ConsentDateTimeUTC
            ),

        /* Opted-out and revoked preferences must not be active. */
        CONSTRAINT CK_PatientCommPref_InactiveConsistency
            CHECK
            (
                ConsentStatus NOT IN ('Opted Out', 'Revoked')
                OR IsActive = 0
            )
    );

    ALTER TABLE Marketing.PatientCommunicationPreference WITH CHECK
    ADD CONSTRAINT FK_PatientCommPref_Patient
        FOREIGN KEY (PatientID)
        REFERENCES Clinical.Patient (PatientID);

    ALTER TABLE Marketing.PatientCommunicationPreference
        CHECK CONSTRAINT FK_PatientCommPref_Patient;

    CREATE INDEX IX_PatientCommPref_ConsentStatus
        ON Marketing.PatientCommunicationPreference (ConsentStatus);

    /*
      Only one active preference per patient and channel type.
    */
    CREATE UNIQUE INDEX UX_PatientCommPref_ActivePatientChannel
        ON Marketing.PatientCommunicationPreference
        (
            PatientID,
            ChannelType
        )
        WHERE IsActive = 1;

    PRINT 'Created Marketing.PatientCommunicationPreference.';
END
ELSE
BEGIN
    PRINT 'Skipped Marketing.PatientCommunicationPreference because it already exists.';
END;
GO


/*==========================================================
  6. Marketing.CampaignInteraction
==========================================================*/

IF OBJECT_ID('Marketing.CampaignInteraction', 'U') IS NULL
BEGIN
    CREATE TABLE Marketing.CampaignInteraction
    (
        CampaignInteractionID  INT IDENTITY(1,1) NOT NULL,
        CampaignID             INT NOT NULL,
        CampaignChannelID      INT NOT NULL,
        PatientID              INT NOT NULL,
        EncounterID            INT NULL,

        InteractionType        VARCHAR(30) NOT NULL,

        InteractionDateTimeUTC DATETIME2(3) NOT NULL
            CONSTRAINT DF_CampaignInteraction_InteractionDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        InteractionStatus      VARCHAR(20) NOT NULL
            CONSTRAINT DF_CampaignInteraction_InteractionStatus
            DEFAULT ('Pending'),

        ExternalMessageID      VARCHAR(100) NULL,
        SourceSystem           VARCHAR(50) NULL,
        DeviceType             VARCHAR(30) NULL,
        DestinationURL         NVARCHAR(500) NULL,
        ResponseCode           VARCHAR(30) NULL,
        ResponseText           NVARCHAR(1000) NULL,

        CreatedDateUTC         DATETIME2(3) NOT NULL
            CONSTRAINT DF_CampaignInteraction_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_CampaignInteraction
            PRIMARY KEY CLUSTERED (CampaignInteractionID),

        /*
          Supports the composite FK from PatientAcquisition that
          verifies an interaction belongs to the same patient and
          campaign.
        */
        CONSTRAINT UQ_CampaignInteraction_Interaction_Patient_Campaign
            UNIQUE (CampaignInteractionID, PatientID, CampaignID),

        CONSTRAINT CK_CampaignInteraction_InteractionType
            CHECK
            (
                InteractionType IN
                (
                    'Sent',
                    'Delivered',
                    'Opened',
                    'Clicked',
                    'Replied',
                    'Called',
                    'Viewed',
                    'Registered',
                    'Attended',
                    'Converted',
                    'Unsubscribed',
                    'Bounced',
                    'Failed'
                )
            ),

        CONSTRAINT CK_CampaignInteraction_InteractionStatus
            CHECK
            (
                InteractionStatus IN
                (
                    'Pending',
                    'Queued',
                    'Success',
                    'Failed',
                    'Bounced',
                    'Rejected',
                    'Cancelled'
                )
            )
    );

    /*
      The channel must belong to the referenced campaign.
    */
    ALTER TABLE Marketing.CampaignInteraction WITH CHECK
    ADD CONSTRAINT FK_CampaignInteraction_Channel_Campaign
        FOREIGN KEY (CampaignChannelID, CampaignID)
        REFERENCES Marketing.CampaignChannel
        (
            CampaignChannelID,
            CampaignID
        );

    ALTER TABLE Marketing.CampaignInteraction WITH CHECK
    ADD CONSTRAINT FK_CampaignInteraction_Patient
        FOREIGN KEY (PatientID)
        REFERENCES Clinical.Patient (PatientID);

    /*
      Enforced only when EncounterID is supplied.
    */
    ALTER TABLE Marketing.CampaignInteraction WITH CHECK
    ADD CONSTRAINT FK_CampaignInteraction_Encounter_Patient
        FOREIGN KEY (EncounterID, PatientID)
        REFERENCES Clinical.Encounter
        (
            EncounterID,
            PatientID
        );

    ALTER TABLE Marketing.CampaignInteraction
        CHECK CONSTRAINT FK_CampaignInteraction_Channel_Campaign;

    ALTER TABLE Marketing.CampaignInteraction
        CHECK CONSTRAINT FK_CampaignInteraction_Patient;

    ALTER TABLE Marketing.CampaignInteraction
        CHECK CONSTRAINT FK_CampaignInteraction_Encounter_Patient;

    CREATE INDEX IX_CampaignInteraction_Campaign_InteractionDateTime
        ON Marketing.CampaignInteraction
        (
            CampaignID,
            InteractionDateTimeUTC
        );

    CREATE INDEX IX_CampaignInteraction_Patient_InteractionDateTime
        ON Marketing.CampaignInteraction
        (
            PatientID,
            InteractionDateTimeUTC
        );

    CREATE INDEX IX_CampaignInteraction_CampaignChannelID
        ON Marketing.CampaignInteraction (CampaignChannelID);

    CREATE INDEX IX_CampaignInteraction_EncounterID
        ON Marketing.CampaignInteraction (EncounterID);

    CREATE INDEX IX_CampaignInteraction_InteractionType
        ON Marketing.CampaignInteraction (InteractionType);

    /*
      Targeted index for conversion analysis.
    */
    CREATE INDEX IX_CampaignInteraction_Conversions
        ON Marketing.CampaignInteraction
        (
            CampaignID,
            InteractionDateTimeUTC
        )
        WHERE InteractionType = 'Converted';

    /*
      External message identifiers are unique within a source
      system when both are present.
    */
    CREATE UNIQUE INDEX UX_CampaignInteraction_Source_ExternalMessage
        ON Marketing.CampaignInteraction
        (
            SourceSystem,
            ExternalMessageID
        )
        WHERE ExternalMessageID IS NOT NULL
          AND SourceSystem IS NOT NULL;

    PRINT 'Created Marketing.CampaignInteraction.';
END
ELSE
BEGIN
    PRINT 'Skipped Marketing.CampaignInteraction because it already exists.';
END;
GO


/*==========================================================
  7. Marketing.ReferralSource
==========================================================*/

IF OBJECT_ID('Marketing.ReferralSource', 'U') IS NULL
BEGIN
    CREATE TABLE Marketing.ReferralSource
    (
        ReferralSourceID     INT IDENTITY(1,1) NOT NULL,
        ReferralSourceCode   VARCHAR(30) NOT NULL,
        ReferralSourceName   NVARCHAR(200) NOT NULL,
        ReferralSourceType   VARCHAR(30) NOT NULL,

        ReferringProviderID  INT NULL,
        ReferringHospitalID  INT NULL,

        OrganizationName     NVARCHAR(200) NULL,
        ContactName          NVARCHAR(150) NULL,
        PhoneNumber          VARCHAR(25) NULL,
        Email                NVARCHAR(150) NULL,

        IsActive             BIT NOT NULL
            CONSTRAINT DF_ReferralSource_IsActive
            DEFAULT (1),

        CreatedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_ReferralSource_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC      DATETIME2(3) NOT NULL
            CONSTRAINT DF_ReferralSource_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_ReferralSource
            PRIMARY KEY CLUSTERED (ReferralSourceID),

        CONSTRAINT UQ_ReferralSource_ReferralSourceCode
            UNIQUE (ReferralSourceCode),

        CONSTRAINT CK_ReferralSource_ReferralSourceType
            CHECK
            (
                ReferralSourceType IN
                (
                    'Provider',
                    'Hospital',
                    'Health Plan',
                    'Employer',
                    'Patient',
                    'Digital',
                    'Community',
                    'Event',
                    'Internal',
                    'Other'
                )
            )
    );

    ALTER TABLE Marketing.ReferralSource WITH CHECK
    ADD CONSTRAINT FK_ReferralSource_Hospital
        FOREIGN KEY (ReferringHospitalID)
        REFERENCES Hospital.Hospital (HospitalID);

    /*
      When both are supplied, the referring provider must belong
      to the referring hospital.
    */
    ALTER TABLE Marketing.ReferralSource WITH CHECK
    ADD CONSTRAINT FK_ReferralSource_Provider_Hospital
        FOREIGN KEY (ReferringProviderID, ReferringHospitalID)
        REFERENCES Hospital.Provider
        (
            ProviderID,
            HospitalID
        );

    ALTER TABLE Marketing.ReferralSource
        CHECK CONSTRAINT FK_ReferralSource_Hospital;

    ALTER TABLE Marketing.ReferralSource
        CHECK CONSTRAINT FK_ReferralSource_Provider_Hospital;

    CREATE INDEX IX_ReferralSource_ReferralSourceType
        ON Marketing.ReferralSource (ReferralSourceType);

    CREATE INDEX IX_ReferralSource_ReferringProviderID
        ON Marketing.ReferralSource (ReferringProviderID);

    CREATE INDEX IX_ReferralSource_ReferringHospitalID
        ON Marketing.ReferralSource (ReferringHospitalID);

    PRINT 'Created Marketing.ReferralSource.';
END
ELSE
BEGIN
    PRINT 'Skipped Marketing.ReferralSource because it already exists.';
END;
GO


/*==========================================================
  8. Marketing.PatientAcquisition
==========================================================*/

IF OBJECT_ID('Marketing.PatientAcquisition', 'U') IS NULL
BEGIN
    CREATE TABLE Marketing.PatientAcquisition
    (
        PatientAcquisitionID   INT IDENTITY(1,1) NOT NULL,
        PatientID              INT NOT NULL,
        ReferralSourceID       INT NOT NULL,
        CampaignID             INT NULL,
        CampaignInteractionID  INT NULL,
        FirstEncounterID       INT NULL,

        AcquisitionDate        DATE NOT NULL,

        AcquisitionChannel     VARCHAR(30) NOT NULL,
        AttributionModel       VARCHAR(30) NOT NULL
            CONSTRAINT DF_PatientAcquisition_AttributionModel
            DEFAULT ('First Touch'),

        AcquisitionStatus      VARCHAR(20) NOT NULL
            CONSTRAINT DF_PatientAcquisition_AcquisitionStatus
            DEFAULT ('Lead'),

        AcquisitionCost        DECIMAL(18,2) NULL,
        ExternalLeadID         VARCHAR(100) NULL,

        CreatedDateUTC         DATETIME2(3) NOT NULL
            CONSTRAINT DF_PatientAcquisition_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_PatientAcquisition_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_PatientAcquisition
            PRIMARY KEY CLUSTERED (PatientAcquisitionID),

        /* One canonical acquisition record per patient. */
        CONSTRAINT UQ_PatientAcquisition_PatientID
            UNIQUE (PatientID),

        CONSTRAINT CK_PatientAcquisition_AcquisitionChannel
            CHECK
            (
                AcquisitionChannel IN
                (
                    'Email',
                    'SMS',
                    'Phone',
                    'Portal',
                    'Website',
                    'Social Media',
                    'Search',
                    'Display',
                    'Direct Mail',
                    'Referral',
                    'Event',
                    'Other'
                )
            ),

        CONSTRAINT CK_PatientAcquisition_AttributionModel
            CHECK
            (
                AttributionModel IN
                (
                    'First Touch',
                    'Last Touch',
                    'Linear',
                    'Time Decay',
                    'Position Based',
                    'Data Driven',
                    'Other'
                )
            ),

        CONSTRAINT CK_PatientAcquisition_AcquisitionStatus
            CHECK
            (
                AcquisitionStatus IN
                (
                    'Lead',
                    'Qualified',
                    'Converted',
                    'Lost',
                    'Inactive'
                )
            ),

        CONSTRAINT CK_PatientAcquisition_AcquisitionCost
            CHECK
            (
                AcquisitionCost IS NULL
                OR AcquisitionCost >= 0
            ),

        /*
          A campaign interaction cannot be recorded without
          identifying the related campaign.
        */
        CONSTRAINT CK_PatientAcquisition_InteractionRequiresCampaign
            CHECK
            (
                CampaignInteractionID IS NULL
                OR CampaignID IS NOT NULL
            )
    );

    ALTER TABLE Marketing.PatientAcquisition WITH CHECK
    ADD CONSTRAINT FK_PatientAcquisition_Patient
        FOREIGN KEY (PatientID)
        REFERENCES Clinical.Patient (PatientID);

    ALTER TABLE Marketing.PatientAcquisition WITH CHECK
    ADD CONSTRAINT FK_PatientAcquisition_ReferralSource
        FOREIGN KEY (ReferralSourceID)
        REFERENCES Marketing.ReferralSource (ReferralSourceID);

    ALTER TABLE Marketing.PatientAcquisition WITH CHECK
    ADD CONSTRAINT FK_PatientAcquisition_Campaign
        FOREIGN KEY (CampaignID)
        REFERENCES Marketing.Campaign (CampaignID);

    /*
      When supplied, the interaction must belong to the same
      patient and campaign as this acquisition record.
    */
    ALTER TABLE Marketing.PatientAcquisition WITH CHECK
    ADD CONSTRAINT FK_PatientAcquisition_Interaction
        FOREIGN KEY (CampaignInteractionID, PatientID, CampaignID)
        REFERENCES Marketing.CampaignInteraction
        (
            CampaignInteractionID,
            PatientID,
            CampaignID
        );

    /*
      Enforced only when FirstEncounterID is supplied.
    */
    ALTER TABLE Marketing.PatientAcquisition WITH CHECK
    ADD CONSTRAINT FK_PatientAcquisition_FirstEncounter_Patient
        FOREIGN KEY (FirstEncounterID, PatientID)
        REFERENCES Clinical.Encounter
        (
            EncounterID,
            PatientID
        );

    ALTER TABLE Marketing.PatientAcquisition
        CHECK CONSTRAINT FK_PatientAcquisition_Patient;

    ALTER TABLE Marketing.PatientAcquisition
        CHECK CONSTRAINT FK_PatientAcquisition_ReferralSource;

    ALTER TABLE Marketing.PatientAcquisition
        CHECK CONSTRAINT FK_PatientAcquisition_Campaign;

    ALTER TABLE Marketing.PatientAcquisition
        CHECK CONSTRAINT FK_PatientAcquisition_Interaction;

    ALTER TABLE Marketing.PatientAcquisition
        CHECK CONSTRAINT FK_PatientAcquisition_FirstEncounter_Patient;

    CREATE INDEX IX_PatientAcquisition_ReferralSourceID
        ON Marketing.PatientAcquisition (ReferralSourceID);

    CREATE INDEX IX_PatientAcquisition_CampaignID
        ON Marketing.PatientAcquisition (CampaignID);

    CREATE INDEX IX_PatientAcquisition_CampaignInteractionID
        ON Marketing.PatientAcquisition (CampaignInteractionID);

    CREATE INDEX IX_PatientAcquisition_FirstEncounterID
        ON Marketing.PatientAcquisition (FirstEncounterID);

    CREATE INDEX IX_PatientAcquisition_AcquisitionDate
        ON Marketing.PatientAcquisition (AcquisitionDate);

    CREATE INDEX IX_PatientAcquisition_AcquisitionStatus
        ON Marketing.PatientAcquisition (AcquisitionStatus);

    CREATE UNIQUE INDEX UX_PatientAcquisition_ExternalLeadID
        ON Marketing.PatientAcquisition (ExternalLeadID)
        WHERE ExternalLeadID IS NOT NULL;

    PRINT 'Created Marketing.PatientAcquisition.';
END
ELSE
BEGIN
    PRINT 'Skipped Marketing.PatientAcquisition because it already exists.';
END;
GO


PRINT 'All Marketing schema tables were processed successfully.';
GO


/*==========================================================
  Verification queries
==========================================================*/

SELECT
    s.name AS SchemaName,
    t.name AS TableName
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE s.name = 'Marketing'
ORDER BY t.name;
GO

SELECT COUNT(*) AS MarketingTableCount
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE s.name = 'Marketing';
GO

SELECT
    OBJECT_NAME(fk.parent_object_id) AS TableName,
    fk.name AS ForeignKeyName,
    fk.is_disabled AS IsDisabled,
    fk.is_not_trusted AS IsNotTrusted
FROM sys.foreign_keys AS fk
WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = 'Marketing'
ORDER BY TableName, ForeignKeyName;
GO