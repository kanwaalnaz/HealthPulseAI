/*==========================================================
  HealthPulse AI
  Script: 007_Insurance_Schema.sql
  Purpose: Create the core Insurance schema tables.

  Tables:
    1. Insurance.Payer
    2. Insurance.InsurancePlan
    3. Insurance.PatientCoverage
    4. Insurance.PriorAuthorization
    5. Insurance.Claim
    6. Insurance.ClaimLine
    7. Insurance.ClaimStatusHistory

  Design standards:
    - INT IDENTITY surrogate primary keys
    - UTC audit timestamps
    - DATETIME2(3) for timestamps
    - Trusted foreign keys created WITH CHECK
    - Composite foreign keys enforce consistency
    - Filtered unique indexes for nullable identifiers
    - DECIMAL(18,2) for monetary values
    - No stored calculated totals, balances, or percentages
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
  Allows Claim to verify that a provider belongs to the
  specified hospital.
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
  Create Insurance schema
==========================================================*/

IF NOT EXISTS
(
    SELECT 1
    FROM sys.schemas
    WHERE name = 'Insurance'
)
BEGIN
    EXEC ('CREATE SCHEMA Insurance;');

    PRINT 'Created schema Insurance.';
END
ELSE
BEGIN
    PRINT 'Skipped schema Insurance because it already exists.';
END;
GO


/*==========================================================
  1. Insurance.Payer
==========================================================*/

IF OBJECT_ID('Insurance.Payer', 'U') IS NULL
BEGIN
    CREATE TABLE Insurance.Payer
    (
        PayerID            INT IDENTITY(1,1) NOT NULL,
        PayerCode          VARCHAR(20) NOT NULL,
        PayerName          NVARCHAR(200) NOT NULL,

        PayerType          VARCHAR(20) NOT NULL
            CONSTRAINT DF_Payer_PayerType
            DEFAULT ('Commercial'),

        TaxIdentifier      VARCHAR(20) NULL,
        PhoneNumber        VARCHAR(25) NULL,
        WebsiteURL         NVARCHAR(250) NULL,

        IsGovernmentPayer  BIT NOT NULL
            CONSTRAINT DF_Payer_IsGovernmentPayer
            DEFAULT (0),

        IsActive           BIT NOT NULL
            CONSTRAINT DF_Payer_IsActive
            DEFAULT (1),

        CreatedDateUTC     DATETIME2(3) NOT NULL
            CONSTRAINT DF_Payer_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC    DATETIME2(3) NOT NULL
            CONSTRAINT DF_Payer_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Payer
            PRIMARY KEY CLUSTERED (PayerID),

        CONSTRAINT UQ_Payer_PayerCode
            UNIQUE (PayerCode),

        CONSTRAINT CK_Payer_PayerType
            CHECK
            (
                PayerType IN
                (
                    'Commercial',
                    'Medicare',
                    'Medicaid',
                    'Government',
                    'Employer',
                    'Self-Pay',
                    'Other'
                )
            )
    );

    CREATE INDEX IX_Payer_PayerName
        ON Insurance.Payer (PayerName);

    CREATE INDEX IX_Payer_PayerType_IsActive
        ON Insurance.Payer (PayerType, IsActive);

    CREATE UNIQUE INDEX UX_Payer_TaxIdentifier
        ON Insurance.Payer (TaxIdentifier)
        WHERE TaxIdentifier IS NOT NULL;

    PRINT 'Created Insurance.Payer.';
END
ELSE
BEGIN
    PRINT 'Skipped Insurance.Payer because it already exists.';
END;
GO


/*==========================================================
  2. Insurance.InsurancePlan
==========================================================*/

IF OBJECT_ID('Insurance.InsurancePlan', 'U') IS NULL
BEGIN
    CREATE TABLE Insurance.InsurancePlan
    (
        InsurancePlanID     INT IDENTITY(1,1) NOT NULL,
        PayerID             INT NOT NULL,
        PlanCode            VARCHAR(30) NOT NULL,
        PlanName            NVARCHAR(200) NOT NULL,

        PlanType            VARCHAR(30) NOT NULL
            CONSTRAINT DF_InsurancePlan_PlanType
            DEFAULT ('Medical'),

        NetworkType         VARCHAR(30) NOT NULL
            CONSTRAINT DF_InsurancePlan_NetworkType
            DEFAULT ('PPO'),

        EffectiveStartDate  DATE NOT NULL,
        EffectiveEndDate    DATE NULL,

        IsActive            BIT NOT NULL
            CONSTRAINT DF_InsurancePlan_IsActive
            DEFAULT (1),

        CreatedDateUTC      DATETIME2(3) NOT NULL
            CONSTRAINT DF_InsurancePlan_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC     DATETIME2(3) NOT NULL
            CONSTRAINT DF_InsurancePlan_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_InsurancePlan
            PRIMARY KEY CLUSTERED (InsurancePlanID),

        CONSTRAINT UQ_InsurancePlan_Payer_PlanCode
            UNIQUE (PayerID, PlanCode),

        CONSTRAINT CK_InsurancePlan_PlanType
            CHECK
            (
                PlanType IN
                (
                    'Medical',
                    'Dental',
                    'Vision',
                    'Pharmacy',
                    'Behavioral Health',
                    'Other'
                )
            ),

        CONSTRAINT CK_InsurancePlan_NetworkType
            CHECK
            (
                NetworkType IN
                (
                    'HMO',
                    'PPO',
                    'EPO',
                    'POS',
                    'HDHP',
                    'Medicare Advantage',
                    'Medicaid Managed Care',
                    'Other'
                )
            ),

        CONSTRAINT CK_InsurancePlan_EffectiveDates
            CHECK
            (
                EffectiveEndDate IS NULL
                OR EffectiveEndDate >= EffectiveStartDate
            )
    );

    ALTER TABLE Insurance.InsurancePlan WITH CHECK
    ADD CONSTRAINT FK_InsurancePlan_Payer
        FOREIGN KEY (PayerID)
        REFERENCES Insurance.Payer (PayerID);

    ALTER TABLE Insurance.InsurancePlan
        CHECK CONSTRAINT FK_InsurancePlan_Payer;

    CREATE INDEX IX_InsurancePlan_PlanType_NetworkType
        ON Insurance.InsurancePlan (PlanType, NetworkType);

    CREATE INDEX IX_InsurancePlan_IsActive
        ON Insurance.InsurancePlan (IsActive);

    PRINT 'Created Insurance.InsurancePlan.';
END
ELSE
BEGIN
    PRINT 'Skipped Insurance.InsurancePlan because it already exists.';
END;
GO


/*==========================================================
  3. Insurance.PatientCoverage
==========================================================*/

IF OBJECT_ID('Insurance.PatientCoverage', 'U') IS NULL
BEGIN
    CREATE TABLE Insurance.PatientCoverage
    (
        PatientCoverageID         INT IDENTITY(1,1) NOT NULL,
        PatientID                 INT NOT NULL,
        InsurancePlanID           INT NOT NULL,

        MemberNumber              VARCHAR(50) NOT NULL,
        GroupNumber               VARCHAR(50) NULL,
        SubscriberPatientID       INT NULL,

        RelationshipToSubscriber  VARCHAR(20) NOT NULL
            CONSTRAINT DF_PatientCoverage_Relationship
            DEFAULT ('Self'),

        CoveragePriority          VARCHAR(15) NOT NULL
            CONSTRAINT DF_PatientCoverage_CoveragePriority
            DEFAULT ('Primary'),

        EffectiveStartDate        DATE NOT NULL,
        EffectiveEndDate          DATE NULL,

        CoverageStatus            VARCHAR(15) NOT NULL
            CONSTRAINT DF_PatientCoverage_CoverageStatus
            DEFAULT ('Active'),

        IsActive                  BIT NOT NULL
            CONSTRAINT DF_PatientCoverage_IsActive
            DEFAULT (1),

        CreatedDateUTC            DATETIME2(3) NOT NULL
            CONSTRAINT DF_PatientCoverage_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC           DATETIME2(3) NOT NULL
            CONSTRAINT DF_PatientCoverage_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_PatientCoverage
            PRIMARY KEY CLUSTERED (PatientCoverageID),

        CONSTRAINT UQ_PatientCoverage_Plan_MemberNumber
            UNIQUE (InsurancePlanID, MemberNumber),

        CONSTRAINT UQ_PatientCoverage_CoverageID_PatientID
            UNIQUE (PatientCoverageID, PatientID),

        CONSTRAINT CK_PatientCoverage_Relationship
            CHECK
            (
                RelationshipToSubscriber IN
                (
                    'Self',
                    'Spouse',
                    'Child',
                    'Parent',
                    'Other'
                )
            ),

        CONSTRAINT CK_PatientCoverage_CoveragePriority
            CHECK
            (
                CoveragePriority IN
                (
                    'Primary',
                    'Secondary',
                    'Tertiary'
                )
            ),

        CONSTRAINT CK_PatientCoverage_CoverageStatus
            CHECK
            (
                CoverageStatus IN
                (
                    'Active',
                    'Inactive',
                    'Pending',
                    'Terminated',
                    'Expired'
                )
            ),

        CONSTRAINT CK_PatientCoverage_EffectiveDates
            CHECK
            (
                EffectiveEndDate IS NULL
                OR EffectiveEndDate >= EffectiveStartDate
            ),

        CONSTRAINT CK_PatientCoverage_SubscriberRelationship
            CHECK
            (
                (
                    RelationshipToSubscriber = 'Self'
                    AND
                    (
                        SubscriberPatientID IS NULL
                        OR SubscriberPatientID = PatientID
                    )
                )
                OR
                (
                    RelationshipToSubscriber <> 'Self'
                    AND SubscriberPatientID IS NOT NULL
                )
            )
    );

    ALTER TABLE Insurance.PatientCoverage WITH CHECK
    ADD CONSTRAINT FK_PatientCoverage_Patient
        FOREIGN KEY (PatientID)
        REFERENCES Clinical.Patient (PatientID);

    ALTER TABLE Insurance.PatientCoverage WITH CHECK
    ADD CONSTRAINT FK_PatientCoverage_InsurancePlan
        FOREIGN KEY (InsurancePlanID)
        REFERENCES Insurance.InsurancePlan (InsurancePlanID);

    ALTER TABLE Insurance.PatientCoverage WITH CHECK
    ADD CONSTRAINT FK_PatientCoverage_Subscriber
        FOREIGN KEY (SubscriberPatientID)
        REFERENCES Clinical.Patient (PatientID);

    ALTER TABLE Insurance.PatientCoverage
        CHECK CONSTRAINT FK_PatientCoverage_Patient;

    ALTER TABLE Insurance.PatientCoverage
        CHECK CONSTRAINT FK_PatientCoverage_InsurancePlan;

    ALTER TABLE Insurance.PatientCoverage
        CHECK CONSTRAINT FK_PatientCoverage_Subscriber;

    CREATE INDEX IX_PatientCoverage_Patient_EffectiveStart
        ON Insurance.PatientCoverage
        (
            PatientID,
            EffectiveStartDate
        );

    CREATE INDEX IX_PatientCoverage_SubscriberPatientID
        ON Insurance.PatientCoverage (SubscriberPatientID);

    CREATE INDEX IX_PatientCoverage_ActiveCoverage
        ON Insurance.PatientCoverage
        (
            PatientID,
            CoveragePriority
        )
        WHERE IsActive = 1
          AND CoverageStatus = 'Active';

    PRINT 'Created Insurance.PatientCoverage.';
END
ELSE
BEGIN
    PRINT 'Skipped Insurance.PatientCoverage because it already exists.';
END;
GO


/*==========================================================
  4. Insurance.PriorAuthorization
==========================================================*/

IF OBJECT_ID('Insurance.PriorAuthorization', 'U') IS NULL
BEGIN
    CREATE TABLE Insurance.PriorAuthorization
    (
        PriorAuthorizationID  INT IDENTITY(1,1) NOT NULL,
        AuthorizationNumber   VARCHAR(50) NULL,

        PatientID             INT NOT NULL,
        InsurancePlanID       INT NOT NULL,
        EncounterID           INT NULL,
        ProviderID            INT NULL,

        DiagnosisCode         VARCHAR(20) NULL,
        ProcedureCode         VARCHAR(20) NULL,

        RequestedDateTimeUTC  DATETIME2(3) NOT NULL
            CONSTRAINT DF_PriorAuth_RequestedDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        DecisionDateTimeUTC   DATETIME2(3) NULL,

        AuthorizationStatus   VARCHAR(20) NOT NULL
            CONSTRAINT DF_PriorAuth_AuthorizationStatus
            DEFAULT ('Submitted'),

        ApprovedStartDate     DATE NULL,
        ApprovedEndDate       DATE NULL,
        AuthorizedUnits       INT NULL,

        DenialReason          NVARCHAR(500) NULL,
        Notes                 NVARCHAR(1000) NULL,

        CreatedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_PriorAuth_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_PriorAuth_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_PriorAuthorization
            PRIMARY KEY CLUSTERED (PriorAuthorizationID),

        CONSTRAINT CK_PriorAuth_AuthorizationStatus
            CHECK
            (
                AuthorizationStatus IN
                (
                    'Submitted',
                    'Under Review',
                    'Approved',
                    'Partially Approved',
                    'Denied',
                    'Cancelled',
                    'Expired'
                )
            ),

        CONSTRAINT CK_PriorAuth_DecisionAfterRequested
            CHECK
            (
                DecisionDateTimeUTC IS NULL
                OR DecisionDateTimeUTC >= RequestedDateTimeUTC
            ),

        CONSTRAINT CK_PriorAuth_ApprovedDates
            CHECK
            (
                ApprovedEndDate IS NULL
                OR ApprovedStartDate IS NULL
                OR ApprovedEndDate >= ApprovedStartDate
            ),

        CONSTRAINT CK_PriorAuth_AuthorizedUnits
            CHECK
            (
                AuthorizedUnits IS NULL
                OR AuthorizedUnits > 0
            ),

        CONSTRAINT CK_PriorAuth_DenialReason
            CHECK
            (
                AuthorizationStatus <> 'Denied'
                OR NULLIF(LTRIM(RTRIM(DenialReason)), '') IS NOT NULL
            )
    );

    ALTER TABLE Insurance.PriorAuthorization WITH CHECK
    ADD CONSTRAINT FK_PriorAuth_Patient
        FOREIGN KEY (PatientID)
        REFERENCES Clinical.Patient (PatientID);

    ALTER TABLE Insurance.PriorAuthorization WITH CHECK
    ADD CONSTRAINT FK_PriorAuth_InsurancePlan
        FOREIGN KEY (InsurancePlanID)
        REFERENCES Insurance.InsurancePlan (InsurancePlanID);

    ALTER TABLE Insurance.PriorAuthorization WITH CHECK
    ADD CONSTRAINT FK_PriorAuth_Encounter_Patient
        FOREIGN KEY (EncounterID, PatientID)
        REFERENCES Clinical.Encounter (EncounterID, PatientID);

    ALTER TABLE Insurance.PriorAuthorization WITH CHECK
    ADD CONSTRAINT FK_PriorAuth_Provider
        FOREIGN KEY (ProviderID)
        REFERENCES Hospital.Provider (ProviderID);

    ALTER TABLE Insurance.PriorAuthorization
        CHECK CONSTRAINT FK_PriorAuth_Patient;

    ALTER TABLE Insurance.PriorAuthorization
        CHECK CONSTRAINT FK_PriorAuth_InsurancePlan;

    ALTER TABLE Insurance.PriorAuthorization
        CHECK CONSTRAINT FK_PriorAuth_Encounter_Patient;

    ALTER TABLE Insurance.PriorAuthorization
        CHECK CONSTRAINT FK_PriorAuth_Provider;

    CREATE UNIQUE INDEX UX_PriorAuth_AuthorizationNumber
        ON Insurance.PriorAuthorization (AuthorizationNumber)
        WHERE AuthorizationNumber IS NOT NULL;

    CREATE INDEX IX_PriorAuth_Patient_RequestedDateTime
        ON Insurance.PriorAuthorization
        (
            PatientID,
            RequestedDateTimeUTC
        );

    CREATE INDEX IX_PriorAuth_ProviderID
        ON Insurance.PriorAuthorization (ProviderID);

    CREATE INDEX IX_PriorAuth_InsurancePlanID
        ON Insurance.PriorAuthorization (InsurancePlanID);

    CREATE INDEX IX_PriorAuth_EncounterID
        ON Insurance.PriorAuthorization (EncounterID);

    CREATE INDEX IX_PriorAuth_Pending
        ON Insurance.PriorAuthorization
        (
            AuthorizationStatus,
            RequestedDateTimeUTC
        )
        WHERE AuthorizationStatus IN ('Submitted', 'Under Review');

    PRINT 'Created Insurance.PriorAuthorization.';
END
ELSE
BEGIN
    PRINT 'Skipped Insurance.PriorAuthorization because it already exists.';
END;
GO


/*==========================================================
  5. Insurance.Claim
==========================================================*/

IF OBJECT_ID('Insurance.Claim', 'U') IS NULL
BEGIN
    CREATE TABLE Insurance.Claim
    (
        ClaimID                  INT IDENTITY(1,1) NOT NULL,
        ClaimNumber              VARCHAR(40) NOT NULL,

        PatientID                INT NOT NULL,
        PatientCoverageID        INT NOT NULL,
        EncounterID              INT NULL,
        ProviderID               INT NULL,
        HospitalID               INT NOT NULL,

        ClaimType                VARCHAR(20) NOT NULL
            CONSTRAINT DF_Claim_ClaimType
            DEFAULT ('Professional'),

        ServiceStartDate         DATE NOT NULL,
        ServiceEndDate           DATE NULL,

        SubmissionDateTimeUTC    DATETIME2(3) NULL,
        AdjudicationDateTimeUTC  DATETIME2(3) NULL,

        ClaimStatus              VARCHAR(20) NOT NULL
            CONSTRAINT DF_Claim_ClaimStatus
            DEFAULT ('Draft'),

        OriginalClaimID          INT NULL,

        CreatedDateUTC           DATETIME2(3) NOT NULL
            CONSTRAINT DF_Claim_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC          DATETIME2(3) NOT NULL
            CONSTRAINT DF_Claim_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Claim
            PRIMARY KEY CLUSTERED (ClaimID),

        CONSTRAINT UQ_Claim_ClaimNumber
            UNIQUE (ClaimNumber),

        CONSTRAINT CK_Claim_ClaimType
            CHECK
            (
                ClaimType IN
                (
                    'Professional',
                    'Institutional',
                    'Pharmacy',
                    'Dental',
                    'Vision',
                    'Other'
                )
            ),

        CONSTRAINT CK_Claim_ClaimStatus
            CHECK
            (
                ClaimStatus IN
                (
                    'Draft',
                    'Submitted',
                    'Received',
                    'In Review',
                    'Approved',
                    'Partially Approved',
                    'Denied',
                    'Rejected',
                    'Paid',
                    'Voided'
                )
            ),

        CONSTRAINT CK_Claim_ServiceDates
            CHECK
            (
                ServiceEndDate IS NULL
                OR ServiceEndDate >= ServiceStartDate
            ),

        CONSTRAINT CK_Claim_AdjudicationAfterSubmission
            CHECK
            (
                AdjudicationDateTimeUTC IS NULL
                OR SubmissionDateTimeUTC IS NULL
                OR AdjudicationDateTimeUTC >= SubmissionDateTimeUTC
            ),

        CONSTRAINT CK_Claim_OriginalClaimNotSelf
            CHECK
            (
                OriginalClaimID IS NULL
                OR OriginalClaimID <> ClaimID
            )
    );

    ALTER TABLE Insurance.Claim WITH CHECK
    ADD CONSTRAINT FK_Claim_Patient
        FOREIGN KEY (PatientID)
        REFERENCES Clinical.Patient (PatientID);

    ALTER TABLE Insurance.Claim WITH CHECK
    ADD CONSTRAINT FK_Claim_Coverage_Patient
        FOREIGN KEY (PatientCoverageID, PatientID)
        REFERENCES Insurance.PatientCoverage
        (
            PatientCoverageID,
            PatientID
        );

    ALTER TABLE Insurance.Claim WITH CHECK
    ADD CONSTRAINT FK_Claim_Encounter_Patient
        FOREIGN KEY (EncounterID, PatientID)
        REFERENCES Clinical.Encounter
        (
            EncounterID,
            PatientID
        );

    ALTER TABLE Insurance.Claim WITH CHECK
    ADD CONSTRAINT FK_Claim_Provider_Hospital
        FOREIGN KEY (ProviderID, HospitalID)
        REFERENCES Hospital.Provider
        (
            ProviderID,
            HospitalID
        );

    ALTER TABLE Insurance.Claim WITH CHECK
    ADD CONSTRAINT FK_Claim_Hospital
        FOREIGN KEY (HospitalID)
        REFERENCES Hospital.Hospital (HospitalID);

    ALTER TABLE Insurance.Claim WITH CHECK
    ADD CONSTRAINT FK_Claim_OriginalClaim
        FOREIGN KEY (OriginalClaimID)
        REFERENCES Insurance.Claim (ClaimID);

    ALTER TABLE Insurance.Claim
        CHECK CONSTRAINT FK_Claim_Patient;

    ALTER TABLE Insurance.Claim
        CHECK CONSTRAINT FK_Claim_Coverage_Patient;

    ALTER TABLE Insurance.Claim
        CHECK CONSTRAINT FK_Claim_Encounter_Patient;

    ALTER TABLE Insurance.Claim
        CHECK CONSTRAINT FK_Claim_Provider_Hospital;

    ALTER TABLE Insurance.Claim
        CHECK CONSTRAINT FK_Claim_Hospital;

    ALTER TABLE Insurance.Claim
        CHECK CONSTRAINT FK_Claim_OriginalClaim;

    CREATE INDEX IX_Claim_PatientID
        ON Insurance.Claim (PatientID);

    CREATE INDEX IX_Claim_PatientCoverageID
        ON Insurance.Claim (PatientCoverageID);

    CREATE INDEX IX_Claim_EncounterID
        ON Insurance.Claim (EncounterID);

    CREATE INDEX IX_Claim_ProviderID
        ON Insurance.Claim (ProviderID);

    CREATE INDEX IX_Claim_HospitalID
        ON Insurance.Claim (HospitalID);

    CREATE INDEX IX_Claim_OriginalClaimID
        ON Insurance.Claim (OriginalClaimID);

    CREATE INDEX IX_Claim_ClaimStatus_ServiceStart
        ON Insurance.Claim
        (
            ClaimStatus,
            ServiceStartDate
        );

    CREATE INDEX IX_Claim_SubmissionDateTimeUTC
        ON Insurance.Claim (SubmissionDateTimeUTC);

    PRINT 'Created Insurance.Claim.';
END
ELSE
BEGIN
    PRINT 'Skipped Insurance.Claim because it already exists.';
END;
GO


/*==========================================================
  6. Insurance.ClaimLine
==========================================================*/

IF OBJECT_ID('Insurance.ClaimLine', 'U') IS NULL
BEGIN
    CREATE TABLE Insurance.ClaimLine
    (
        ClaimLineID                  INT IDENTITY(1,1) NOT NULL,
        ClaimID                      INT NOT NULL,
        LineNumber                   INT NOT NULL,

        ProcedureCode                VARCHAR(20) NULL,
        RevenueCode                  VARCHAR(20) NULL,
        DiagnosisPointer             VARCHAR(20) NULL,

        ServiceDate                  DATE NULL,

        Units                        DECIMAL(12,3) NOT NULL
            CONSTRAINT DF_ClaimLine_Units
            DEFAULT (1),

        ChargeAmount                 DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_ClaimLine_ChargeAmount
            DEFAULT (0),

        AllowedAmount                DECIMAL(18,2) NULL,
        PaidAmount                   DECIMAL(18,2) NULL,
        PatientResponsibilityAmount  DECIMAL(18,2) NULL,
        AdjustmentAmount             DECIMAL(18,2) NULL,

        LineStatus                   VARCHAR(20) NOT NULL
            CONSTRAINT DF_ClaimLine_LineStatus
            DEFAULT ('Submitted'),

        DenialReasonCode             VARCHAR(20) NULL,

        CreatedDateUTC               DATETIME2(3) NOT NULL
            CONSTRAINT DF_ClaimLine_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC              DATETIME2(3) NOT NULL
            CONSTRAINT DF_ClaimLine_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_ClaimLine
            PRIMARY KEY CLUSTERED (ClaimLineID),

        CONSTRAINT UQ_ClaimLine_Claim_LineNumber
            UNIQUE (ClaimID, LineNumber),

        CONSTRAINT CK_ClaimLine_Units
            CHECK (Units > 0),

        CONSTRAINT CK_ClaimLine_MonetaryValues
            CHECK
            (
                ChargeAmount >= 0
                AND
                (
                    AllowedAmount IS NULL
                    OR AllowedAmount >= 0
                )
                AND
                (
                    PaidAmount IS NULL
                    OR PaidAmount >= 0
                )
                AND
                (
                    PatientResponsibilityAmount IS NULL
                    OR PatientResponsibilityAmount >= 0
                )
                AND
                (
                    AdjustmentAmount IS NULL
                    OR AdjustmentAmount >= 0
                )
            ),

        CONSTRAINT CK_ClaimLine_LineStatus
            CHECK
            (
                LineStatus IN
                (
                    'Submitted',
                    'Approved',
                    'Partially Approved',
                    'Denied',
                    'Paid',
                    'Adjusted',
                    'Voided'
                )
            ),

        CONSTRAINT CK_ClaimLine_DenialReason
            CHECK
            (
                LineStatus <> 'Denied'
                OR NULLIF(LTRIM(RTRIM(DenialReasonCode)), '') IS NOT NULL
            )
    );

    ALTER TABLE Insurance.ClaimLine WITH CHECK
    ADD CONSTRAINT FK_ClaimLine_Claim
        FOREIGN KEY (ClaimID)
        REFERENCES Insurance.Claim (ClaimID);

    ALTER TABLE Insurance.ClaimLine
        CHECK CONSTRAINT FK_ClaimLine_Claim;

    CREATE INDEX IX_ClaimLine_ProcedureCode
        ON Insurance.ClaimLine (ProcedureCode)
        WHERE ProcedureCode IS NOT NULL;

    CREATE INDEX IX_ClaimLine_LineStatus
        ON Insurance.ClaimLine (LineStatus);

    CREATE INDEX IX_ClaimLine_DenialReasonCode
        ON Insurance.ClaimLine (DenialReasonCode)
        WHERE DenialReasonCode IS NOT NULL;

    PRINT 'Created Insurance.ClaimLine.';
END
ELSE
BEGIN
    PRINT 'Skipped Insurance.ClaimLine because it already exists.';
END;
GO


/*==========================================================
  7. Insurance.ClaimStatusHistory
==========================================================*/

IF OBJECT_ID('Insurance.ClaimStatusHistory', 'U') IS NULL
BEGIN
    CREATE TABLE Insurance.ClaimStatusHistory
    (
        ClaimStatusHistoryID  INT IDENTITY(1,1) NOT NULL,
        ClaimID               INT NOT NULL,
        StatusSequenceNumber  INT NOT NULL,

        ClaimStatus           VARCHAR(20) NOT NULL,

        StatusDateTimeUTC     DATETIME2(3) NOT NULL
            CONSTRAINT DF_ClaimStatusHistory_StatusDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        StatusReason          NVARCHAR(500) NULL,
        SourceSystem          NVARCHAR(100) NULL,

        CreatedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_ClaimStatusHistory_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_ClaimStatusHistory
            PRIMARY KEY CLUSTERED (ClaimStatusHistoryID),

        CONSTRAINT UQ_ClaimStatusHistory_Claim_Sequence
            UNIQUE (ClaimID, StatusSequenceNumber),

        CONSTRAINT CK_ClaimStatusHistory_SequenceNumber
            CHECK (StatusSequenceNumber > 0),

        CONSTRAINT CK_ClaimStatusHistory_ClaimStatus
            CHECK
            (
                ClaimStatus IN
                (
                    'Draft',
                    'Submitted',
                    'Received',
                    'In Review',
                    'Approved',
                    'Partially Approved',
                    'Denied',
                    'Rejected',
                    'Paid',
                    'Voided'
                )
            )
    );

    ALTER TABLE Insurance.ClaimStatusHistory WITH CHECK
    ADD CONSTRAINT FK_ClaimStatusHistory_Claim
        FOREIGN KEY (ClaimID)
        REFERENCES Insurance.Claim (ClaimID);

    ALTER TABLE Insurance.ClaimStatusHistory
        CHECK CONSTRAINT FK_ClaimStatusHistory_Claim;

    CREATE INDEX IX_ClaimStatusHistory_Claim_StatusDateTime
        ON Insurance.ClaimStatusHistory
        (
            ClaimID,
            StatusDateTimeUTC
        );

    CREATE INDEX IX_ClaimStatusHistory_ClaimStatus
        ON Insurance.ClaimStatusHistory (ClaimStatus);

    PRINT 'Created Insurance.ClaimStatusHistory.';
END
ELSE
BEGIN
    PRINT 'Skipped Insurance.ClaimStatusHistory because it already exists.';
END;
GO


PRINT 'All Insurance schema tables were processed successfully.';
GO