/*==========================================================
  HealthPulse AI
  Script: 010_AI_Schema.sql
  Purpose: Create the core AI / MLOps schema tables.

  Tables:
    1. AI.Model
    2. AI.ModelVersion
    3. AI.FeatureDefinition
    4. AI.ModelFeature
    5. AI.Prediction
    6. AI.PredictionOutcome
    7. AI.ModelPerformanceMetric
    8. AI.ModelMonitoringEvent

  Design standards:
    - INT IDENTITY keys for dimensions
    - BIGINT IDENTITY keys for high-volume prediction / event tables
    - UTC audit timestamps (CreatedDateUTC / ModifiedDateUTC)
    - DATETIME2(3) for timestamps
    - DECIMAL types for all model scores and metrics (never FLOAT)
    - Trusted foreign keys created WITH CHECK
    - Composite foreign keys prevent patient/encounter and
      provider/hospital mismatches
    - ISJSON checks for JSON columns
    - Filtered indexes for high-risk predictions and unresolved alerts
    - No PHI duplication (PatientID / EncounterID references only)
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
  Create AI schema
==========================================================*/

IF NOT EXISTS
(
    SELECT 1
    FROM sys.schemas
    WHERE name = 'AI'
)
BEGIN
    EXEC ('CREATE SCHEMA AI;');

    PRINT 'Created schema AI.';
END
ELSE
BEGIN
    PRINT 'Skipped schema AI because it already exists.';
END;
GO


/*==========================================================
  1. AI.Model
==========================================================*/

IF OBJECT_ID('AI.Model', 'U') IS NULL
BEGIN
    CREATE TABLE AI.Model
    (
        ModelID           INT IDENTITY(1,1) NOT NULL,
        ModelCode         VARCHAR(40) NOT NULL,
        ModelName         NVARCHAR(200) NOT NULL,
        ModelDescription  NVARCHAR(1000) NULL,

        ModelType         VARCHAR(40) NOT NULL,
        ClinicalUseCase   VARCHAR(100) NOT NULL,
        ProblemType       VARCHAR(30) NOT NULL,

        OwnerProviderID   INT NULL,
        OwningHospitalID  INT NULL,

        ModelStatus       VARCHAR(20) NOT NULL
            CONSTRAINT DF_Model_ModelStatus
            DEFAULT ('Development'),

        RiskLevel         VARCHAR(20) NOT NULL,

        IsRegulated       BIT NOT NULL
            CONSTRAINT DF_Model_IsRegulated
            DEFAULT (0),

        RepositoryURL     NVARCHAR(500) NULL,
        DocumentationURL  NVARCHAR(500) NULL,

        IsActive          BIT NOT NULL
            CONSTRAINT DF_Model_IsActive
            DEFAULT (1),

        CreatedDateUTC    DATETIME2(3) NOT NULL
            CONSTRAINT DF_Model_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC   DATETIME2(3) NOT NULL
            CONSTRAINT DF_Model_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Model
            PRIMARY KEY CLUSTERED (ModelID),

        CONSTRAINT UQ_Model_ModelCode
            UNIQUE (ModelCode),

        CONSTRAINT CK_Model_ModelType
            CHECK
            (
                ModelType IN
                (
                    'Machine Learning',
                    'Deep Learning',
                    'Statistical',
                    'Rule Based',
                    'Ensemble',
                    'Generative',
                    'Other'
                )
            ),

        CONSTRAINT CK_Model_ProblemType
            CHECK
            (
                ProblemType IN
                (
                    'Binary Classification',
                    'Multiclass Classification',
                    'Regression',
                    'Clustering',
                    'Time Series',
                    'Ranking',
                    'Survival',
                    'Other'
                )
            ),

        CONSTRAINT CK_Model_ModelStatus
            CHECK
            (
                ModelStatus IN
                (
                    'Development',
                    'Validation',
                    'Approved',
                    'Production',
                    'Shadow',
                    'Suspended',
                    'Retired'
                )
            ),

        CONSTRAINT CK_Model_RiskLevel
            CHECK
            (
                RiskLevel IN
                (
                    'Low',
                    'Medium',
                    'High',
                    'Critical'
                )
            ),

        /*
          A model owner cannot be recorded without the hospital
          needed to validate the provider/hospital relationship.
        */
        CONSTRAINT CK_Model_OwnerRequiresHospital
            CHECK
            (
                OwnerProviderID IS NULL
                OR OwningHospitalID IS NOT NULL
            )
    );

    ALTER TABLE AI.Model WITH CHECK
    ADD CONSTRAINT FK_Model_Hospital
        FOREIGN KEY (OwningHospitalID)
        REFERENCES Hospital.Hospital (HospitalID);

    /*
      When both are supplied, the owning provider must belong
      to the owning hospital.
    */
    ALTER TABLE AI.Model WITH CHECK
    ADD CONSTRAINT FK_Model_Owner_Hospital
        FOREIGN KEY (OwnerProviderID, OwningHospitalID)
        REFERENCES Hospital.Provider
        (
            ProviderID,
            HospitalID
        );

    ALTER TABLE AI.Model
        CHECK CONSTRAINT FK_Model_Hospital;

    ALTER TABLE AI.Model
        CHECK CONSTRAINT FK_Model_Owner_Hospital;

    CREATE INDEX IX_Model_OwningHospitalID
        ON AI.Model (OwningHospitalID);

    CREATE INDEX IX_Model_OwnerProviderID
        ON AI.Model (OwnerProviderID);

    CREATE INDEX IX_Model_ModelStatus
        ON AI.Model (ModelStatus);

    CREATE INDEX IX_Model_ModelType
        ON AI.Model (ModelType);

    PRINT 'Created AI.Model.';
END
ELSE
BEGIN
    PRINT 'Skipped AI.Model because it already exists.';
END;
GO


/*==========================================================
  2. AI.ModelVersion
==========================================================*/

IF OBJECT_ID('AI.ModelVersion', 'U') IS NULL
BEGIN
    CREATE TABLE AI.ModelVersion
    (
        ModelVersionID             INT IDENTITY(1,1) NOT NULL,
        ModelID                    INT NOT NULL,

        VersionNumber              VARCHAR(30) NOT NULL,
        AlgorithmName              NVARCHAR(100) NOT NULL,
        FrameworkName              VARCHAR(50) NULL,
        FrameworkVersion           VARCHAR(30) NULL,

        TrainingDataStartDate      DATE NULL,
        TrainingDataEndDate        DATE NULL,
        TrainingRecordCount        BIGINT NULL,
        FeatureCount               INT NULL,

        HyperparametersJSON        NVARCHAR(MAX) NULL,
        ArtifactURI                NVARCHAR(1000) NULL,
        ModelHash                  VARCHAR(128) NULL,

        ApprovalStatus             VARCHAR(20) NOT NULL
            CONSTRAINT DF_ModelVersion_ApprovalStatus
            DEFAULT ('Pending'),

        ApprovedByProviderID       INT NULL,
        ApprovedDateTimeUTC        DATETIME2(3) NULL,

        EffectiveStartDateTimeUTC  DATETIME2(3) NULL,
        EffectiveEndDateTimeUTC    DATETIME2(3) NULL,

        CreatedDateUTC             DATETIME2(3) NOT NULL
            CONSTRAINT DF_ModelVersion_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_ModelVersion
            PRIMARY KEY CLUSTERED (ModelVersionID),

        CONSTRAINT UQ_ModelVersion_Model_VersionNumber
            UNIQUE (ModelID, VersionNumber),

        CONSTRAINT CK_ModelVersion_ApprovalStatus
            CHECK
            (
                ApprovalStatus IN
                (
                    'Pending',
                    'Approved',
                    'Rejected',
                    'Withdrawn'
                )
            ),

        CONSTRAINT CK_ModelVersion_TrainingDateRange
            CHECK
            (
                TrainingDataStartDate IS NULL
                OR TrainingDataEndDate IS NULL
                OR TrainingDataEndDate >= TrainingDataStartDate
            ),

        CONSTRAINT CK_ModelVersion_EffectiveDateRange
            CHECK
            (
                EffectiveStartDateTimeUTC IS NULL
                OR EffectiveEndDateTimeUTC IS NULL
                OR EffectiveEndDateTimeUTC >= EffectiveStartDateTimeUTC
            ),

        CONSTRAINT CK_ModelVersion_TrainingRecordCount
            CHECK
            (
                TrainingRecordCount IS NULL
                OR TrainingRecordCount >= 0
            ),

        CONSTRAINT CK_ModelVersion_FeatureCount
            CHECK
            (
                FeatureCount IS NULL
                OR FeatureCount >= 0
            ),

        CONSTRAINT CK_ModelVersion_HyperparametersJSON
            CHECK
            (
                HyperparametersJSON IS NULL
                OR ISJSON(HyperparametersJSON) = 1
            ),

        /*
          Approved versions require both approver and approval time.
          Non-approved versions must not retain approval metadata.
        */
        CONSTRAINT CK_ModelVersion_ApprovalConsistency
            CHECK
            (
                (
                    ApprovalStatus = 'Approved'
                    AND ApprovedByProviderID IS NOT NULL
                    AND ApprovedDateTimeUTC IS NOT NULL
                )
                OR
                (
                    ApprovalStatus <> 'Approved'
                    AND ApprovedByProviderID IS NULL
                    AND ApprovedDateTimeUTC IS NULL
                )
            )
    );

    ALTER TABLE AI.ModelVersion WITH CHECK
    ADD CONSTRAINT FK_ModelVersion_Model
        FOREIGN KEY (ModelID)
        REFERENCES AI.Model (ModelID);

    ALTER TABLE AI.ModelVersion WITH CHECK
    ADD CONSTRAINT FK_ModelVersion_ApprovedByProvider
        FOREIGN KEY (ApprovedByProviderID)
        REFERENCES Hospital.Provider (ProviderID);

    ALTER TABLE AI.ModelVersion
        CHECK CONSTRAINT FK_ModelVersion_Model;

    ALTER TABLE AI.ModelVersion
        CHECK CONSTRAINT FK_ModelVersion_ApprovedByProvider;

    CREATE INDEX IX_ModelVersion_ApprovalStatus
        ON AI.ModelVersion (ApprovalStatus);

    CREATE INDEX IX_ModelVersion_ApprovedByProviderID
        ON AI.ModelVersion (ApprovedByProviderID);

    CREATE UNIQUE INDEX UX_ModelVersion_ModelHash
        ON AI.ModelVersion (ModelHash)
        WHERE ModelHash IS NOT NULL;

    PRINT 'Created AI.ModelVersion.';
END
ELSE
BEGIN
    PRINT 'Skipped AI.ModelVersion because it already exists.';
END;
GO


/*==========================================================
  3. AI.FeatureDefinition
==========================================================*/

IF OBJECT_ID('AI.FeatureDefinition', 'U') IS NULL
BEGIN
    CREATE TABLE AI.FeatureDefinition
    (
        FeatureDefinitionID  INT IDENTITY(1,1) NOT NULL,
        FeatureCode          VARCHAR(80) NOT NULL,
        FeatureName          NVARCHAR(200) NOT NULL,
        FeatureDescription   NVARCHAR(1000) NOT NULL,

        DataType             VARCHAR(30) NOT NULL,

        SourceSchema         VARCHAR(50) NOT NULL,
        SourceTable          VARCHAR(128) NOT NULL,
        SourceColumn         VARCHAR(128) NULL,

        TransformationLogic  NVARCHAR(MAX) NULL,

        FeatureCategory      VARCHAR(40) NOT NULL,

        ContainsPHI          BIT NOT NULL
            CONSTRAINT DF_FeatureDefinition_ContainsPHI
            DEFAULT (0),

        IsSensitive          BIT NOT NULL
            CONSTRAINT DF_FeatureDefinition_IsSensitive
            DEFAULT (0),

        IsActive             BIT NOT NULL
            CONSTRAINT DF_FeatureDefinition_IsActive
            DEFAULT (1),

        CreatedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_FeatureDefinition_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC      DATETIME2(3) NOT NULL
            CONSTRAINT DF_FeatureDefinition_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_FeatureDefinition
            PRIMARY KEY CLUSTERED (FeatureDefinitionID),

        CONSTRAINT UQ_FeatureDefinition_FeatureCode
            UNIQUE (FeatureCode),

        CONSTRAINT CK_FeatureDefinition_DataType
            CHECK
            (
                DataType IN
                (
                    'Integer',
                    'Decimal',
                    'Boolean',
                    'String',
                    'Text',
                    'DateTime',
                    'Categorical',
                    'Binary',
                    'Other'
                )
            ),

        CONSTRAINT CK_FeatureDefinition_FeatureCategory
            CHECK
            (
                FeatureCategory IN
                (
                    'Demographic',
                    'Clinical',
                    'Lab',
                    'Vitals',
                    'Medication',
                    'Utilization',
                    'Financial',
                    'Behavioral',
                    'Temporal',
                    'Derived',
                    'Other'
                )
            ),

        CONSTRAINT CK_FeatureDefinition_SourceSchema
            CHECK
            (
                NULLIF(LTRIM(RTRIM(SourceSchema)), '') IS NOT NULL
            ),

        CONSTRAINT CK_FeatureDefinition_SourceTable
            CHECK
            (
                NULLIF(LTRIM(RTRIM(SourceTable)), '') IS NOT NULL
            )
    );

    CREATE INDEX IX_FeatureDefinition_FeatureCategory
        ON AI.FeatureDefinition (FeatureCategory);

    CREATE INDEX IX_FeatureDefinition_Source
        ON AI.FeatureDefinition
        (
            SourceSchema,
            SourceTable
        );

    PRINT 'Created AI.FeatureDefinition.';
END
ELSE
BEGIN
    PRINT 'Skipped AI.FeatureDefinition because it already exists.';
END;
GO


/*==========================================================
  4. AI.ModelFeature
==========================================================*/

IF OBJECT_ID('AI.ModelFeature', 'U') IS NULL
BEGIN
    CREATE TABLE AI.ModelFeature
    (
        ModelFeatureID       INT IDENTITY(1,1) NOT NULL,
        ModelVersionID       INT NOT NULL,
        FeatureDefinitionID  INT NOT NULL,

        FeatureRole          VARCHAR(20) NOT NULL
            CONSTRAINT DF_ModelFeature_FeatureRole
            DEFAULT ('Input'),

        FeatureOrder         INT NULL,

        IsRequired           BIT NOT NULL
            CONSTRAINT DF_ModelFeature_IsRequired
            DEFAULT (1),

        DefaultValue         NVARCHAR(500) NULL,

        CreatedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_ModelFeature_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_ModelFeature
            PRIMARY KEY CLUSTERED (ModelFeatureID),

        CONSTRAINT UQ_ModelFeature_Version_Feature
            UNIQUE (ModelVersionID, FeatureDefinitionID),

        CONSTRAINT CK_ModelFeature_FeatureRole
            CHECK
            (
                FeatureRole IN
                (
                    'Input',
                    'Target',
                    'Identifier',
                    'Protected Attribute',
                    'Monitoring Only'
                )
            ),

        CONSTRAINT CK_ModelFeature_FeatureOrder
            CHECK
            (
                FeatureOrder IS NULL
                OR FeatureOrder > 0
            )
    );

    ALTER TABLE AI.ModelFeature WITH CHECK
    ADD CONSTRAINT FK_ModelFeature_ModelVersion
        FOREIGN KEY (ModelVersionID)
        REFERENCES AI.ModelVersion (ModelVersionID);

    ALTER TABLE AI.ModelFeature WITH CHECK
    ADD CONSTRAINT FK_ModelFeature_FeatureDefinition
        FOREIGN KEY (FeatureDefinitionID)
        REFERENCES AI.FeatureDefinition (FeatureDefinitionID);

    ALTER TABLE AI.ModelFeature
        CHECK CONSTRAINT FK_ModelFeature_ModelVersion;

    ALTER TABLE AI.ModelFeature
        CHECK CONSTRAINT FK_ModelFeature_FeatureDefinition;

    CREATE INDEX IX_ModelFeature_FeatureDefinitionID
        ON AI.ModelFeature (FeatureDefinitionID);

    PRINT 'Created AI.ModelFeature.';
END
ELSE
BEGIN
    PRINT 'Skipped AI.ModelFeature because it already exists.';
END;
GO


/*==========================================================
  5. AI.Prediction
==========================================================*/

IF OBJECT_ID('AI.Prediction', 'U') IS NULL
BEGIN
    CREATE TABLE AI.Prediction
    (
        PredictionID           BIGINT IDENTITY(1,1) NOT NULL,
        ModelVersionID         INT NOT NULL,
        PatientID              INT NOT NULL,
        EncounterID            INT NULL,

        PredictionDateTimeUTC  DATETIME2(3) NOT NULL
            CONSTRAINT DF_Prediction_PredictionDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        PredictionType         VARCHAR(40) NOT NULL,

        PredictedClass         NVARCHAR(100) NULL,
        PredictedValue         DECIMAL(19,6) NULL,
        ProbabilityScore       DECIMAL(9,8) NULL,
        RiskScore              DECIMAL(9,6) NULL,
        ThresholdUsed          DECIMAL(9,8) NULL,

        PredictionStatus       VARCHAR(20) NOT NULL
            CONSTRAINT DF_Prediction_PredictionStatus
            DEFAULT ('Generated'),

        InputSnapshotJSON      NVARCHAR(MAX) NULL,
        ExplanationJSON        NVARCHAR(MAX) NULL,

        CorrelationID          UNIQUEIDENTIFIER NOT NULL
            CONSTRAINT DF_Prediction_CorrelationID
            DEFAULT (NEWSEQUENTIALID()),

        CreatedDateUTC         DATETIME2(3) NOT NULL
            CONSTRAINT DF_Prediction_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Prediction
            PRIMARY KEY CLUSTERED (PredictionID),

        CONSTRAINT UQ_Prediction_CorrelationID
            UNIQUE (CorrelationID),

        CONSTRAINT CK_Prediction_PredictionType
            CHECK
            (
                PredictionType IN
                (
                    'Classification',
                    'Regression',
                    'Risk Score',
                    'Probability',
                    'Forecast',
                    'Recommendation',
                    'Anomaly',
                    'Other'
                )
            ),

        CONSTRAINT CK_Prediction_PredictionStatus
            CHECK
            (
                PredictionStatus IN
                (
                    'Generated',
                    'Delivered',
                    'Consumed',
                    'Overridden',
                    'Suppressed',
                    'Failed'
                )
            ),

        CONSTRAINT CK_Prediction_ProbabilityScore
            CHECK
            (
                ProbabilityScore IS NULL
                OR ProbabilityScore BETWEEN 0 AND 1
            ),

        CONSTRAINT CK_Prediction_ThresholdUsed
            CHECK
            (
                ThresholdUsed IS NULL
                OR ThresholdUsed BETWEEN 0 AND 1
            ),

        CONSTRAINT CK_Prediction_RiskScore
            CHECK
            (
                RiskScore IS NULL
                OR RiskScore >= 0
            ),

        CONSTRAINT CK_Prediction_InputSnapshotJSON
            CHECK
            (
                InputSnapshotJSON IS NULL
                OR ISJSON(InputSnapshotJSON) = 1
            ),

        CONSTRAINT CK_Prediction_ExplanationJSON
            CHECK
            (
                ExplanationJSON IS NULL
                OR ISJSON(ExplanationJSON) = 1
            )
    );

    ALTER TABLE AI.Prediction WITH CHECK
    ADD CONSTRAINT FK_Prediction_ModelVersion
        FOREIGN KEY (ModelVersionID)
        REFERENCES AI.ModelVersion (ModelVersionID);

    ALTER TABLE AI.Prediction WITH CHECK
    ADD CONSTRAINT FK_Prediction_Patient
        FOREIGN KEY (PatientID)
        REFERENCES Clinical.Patient (PatientID);

    /*
      Enforced only when EncounterID is supplied; the encounter
      must belong to the same patient.
    */
    ALTER TABLE AI.Prediction WITH CHECK
    ADD CONSTRAINT FK_Prediction_Encounter_Patient
        FOREIGN KEY (EncounterID, PatientID)
        REFERENCES Clinical.Encounter
        (
            EncounterID,
            PatientID
        );

    ALTER TABLE AI.Prediction
        CHECK CONSTRAINT FK_Prediction_ModelVersion;

    ALTER TABLE AI.Prediction
        CHECK CONSTRAINT FK_Prediction_Patient;

    ALTER TABLE AI.Prediction
        CHECK CONSTRAINT FK_Prediction_Encounter_Patient;

    CREATE INDEX IX_Prediction_Patient_PredictionDateTime
        ON AI.Prediction
        (
            PatientID,
            PredictionDateTimeUTC
        );

    CREATE INDEX IX_Prediction_EncounterID
        ON AI.Prediction (EncounterID);

    CREATE INDEX IX_Prediction_ModelVersion_PredictionDateTime
        ON AI.Prediction
        (
            ModelVersionID,
            PredictionDateTimeUTC
        );

    CREATE INDEX IX_Prediction_PredictionStatus
        ON AI.Prediction (PredictionStatus);

    /*
      Supports high-risk prediction retrieval.
    */
    CREATE INDEX IX_Prediction_HighRisk
        ON AI.Prediction
        (
            RiskScore DESC,
            PredictionDateTimeUTC
        )
        INCLUDE
        (
            ModelVersionID,
            PatientID
        )
        WHERE RiskScore IS NOT NULL;

    PRINT 'Created AI.Prediction.';
END
ELSE
BEGIN
    PRINT 'Skipped AI.Prediction because it already exists.';
END;
GO


/*==========================================================
  6. AI.PredictionOutcome

  NOTE: SQL Server CHECK constraints cannot reference another
  table, so "outcome cannot predate its prediction" is enforced
  at the application/ETL layer rather than declaratively here.
==========================================================*/

IF OBJECT_ID('AI.PredictionOutcome', 'U') IS NULL
BEGIN
    CREATE TABLE AI.PredictionOutcome
    (
        PredictionOutcomeID   BIGINT IDENTITY(1,1) NOT NULL,
        PredictionID          BIGINT NOT NULL,

        OutcomeType           VARCHAR(40) NOT NULL,
        ActualClass           NVARCHAR(100) NULL,
        ActualValue           DECIMAL(19,6) NULL,

        OutcomeDateTimeUTC    DATETIME2(3) NOT NULL
            CONSTRAINT DF_PredictionOutcome_OutcomeDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        OutcomeSource         VARCHAR(50) NOT NULL,

        IsFinalOutcome        BIT NOT NULL
            CONSTRAINT DF_PredictionOutcome_IsFinalOutcome
            DEFAULT (0),

        VerifiedByProviderID  INT NULL,
        VerifiedDateTimeUTC   DATETIME2(3) NULL,

        Notes                 NVARCHAR(1000) NULL,

        CreatedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_PredictionOutcome_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_PredictionOutcome_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_PredictionOutcome
            PRIMARY KEY CLUSTERED (PredictionOutcomeID),

        CONSTRAINT UQ_PredictionOutcome_PredictionID
            UNIQUE (PredictionID),

        CONSTRAINT CK_PredictionOutcome_OutcomeType
            CHECK
            (
                OutcomeType IN
                (
                    'Confirmed',
                    'Refuted',
                    'Partial',
                    'Censored',
                    'Unknown',
                    'Other'
                )
            ),

        CONSTRAINT CK_PredictionOutcome_OutcomeSource
            CHECK
            (
                OutcomeSource IN
                (
                    'EHR',
                    'Manual Review',
                    'Claims',
                    'Lab',
                    'Registry',
                    'External',
                    'Other'
                )
            ),

        /* Verification requires both the provider and the timestamp. */
        CONSTRAINT CK_PredictionOutcome_VerificationConsistency
            CHECK
            (
                (
                    VerifiedByProviderID IS NULL
                    AND VerifiedDateTimeUTC IS NULL
                )
                OR
                (
                    VerifiedByProviderID IS NOT NULL
                    AND VerifiedDateTimeUTC IS NOT NULL
                )
            )
    );

    ALTER TABLE AI.PredictionOutcome WITH CHECK
    ADD CONSTRAINT FK_PredictionOutcome_Prediction
        FOREIGN KEY (PredictionID)
        REFERENCES AI.Prediction (PredictionID);

    ALTER TABLE AI.PredictionOutcome WITH CHECK
    ADD CONSTRAINT FK_PredictionOutcome_VerifiedByProvider
        FOREIGN KEY (VerifiedByProviderID)
        REFERENCES Hospital.Provider (ProviderID);

    ALTER TABLE AI.PredictionOutcome
        CHECK CONSTRAINT FK_PredictionOutcome_Prediction;

    ALTER TABLE AI.PredictionOutcome
        CHECK CONSTRAINT FK_PredictionOutcome_VerifiedByProvider;

    CREATE INDEX IX_PredictionOutcome_OutcomeDateTimeUTC
        ON AI.PredictionOutcome (OutcomeDateTimeUTC);

    CREATE INDEX IX_PredictionOutcome_VerifiedByProviderID
        ON AI.PredictionOutcome (VerifiedByProviderID);

    PRINT 'Created AI.PredictionOutcome.';
END
ELSE
BEGIN
    PRINT 'Skipped AI.PredictionOutcome because it already exists.';
END;
GO


/*==========================================================
  7. AI.ModelPerformanceMetric
==========================================================*/

IF OBJECT_ID('AI.ModelPerformanceMetric', 'U') IS NULL
BEGIN
    CREATE TABLE AI.ModelPerformanceMetric
    (
        ModelPerformanceMetricID  BIGINT IDENTITY(1,1) NOT NULL,
        ModelVersionID            INT NOT NULL,

        MetricName                VARCHAR(50) NOT NULL,
        MetricDescription         NVARCHAR(500) NULL,
        MetricValue               DECIMAL(19,8) NOT NULL,

        EvaluationDataset         VARCHAR(50) NOT NULL,
        EvaluationStartDate       DATE NULL,
        EvaluationEndDate         DATE NULL,
        PatientPopulationSegment  NVARCHAR(200) NULL,

        ThresholdValue            DECIMAL(9,8) NULL,
        SampleSize                BIGINT NULL,

        CalculatedDateTimeUTC     DATETIME2(3) NOT NULL
            CONSTRAINT DF_ModelPerformanceMetric_CalculatedDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        CreatedDateUTC            DATETIME2(3) NOT NULL
            CONSTRAINT DF_ModelPerformanceMetric_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_ModelPerformanceMetric
            PRIMARY KEY CLUSTERED (ModelPerformanceMetricID),

        CONSTRAINT CK_ModelPerformanceMetric_MetricName
            CHECK
            (
                MetricName IN
                (
                    'AUROC',
                    'AUPRC',
                    'Accuracy',
                    'Precision',
                    'Recall',
                    'Sensitivity',
                    'Specificity',
                    'F1 Score',
                    'Log Loss',
                    'Brier Score',
                    'RMSE',
                    'MAE',
                    'MAPE',
                    'R2',
                    'Calibration Slope',
                    'Calibration Intercept',
                    'Other'
                )
            ),

        CONSTRAINT CK_ModelPerformanceMetric_OtherDescription
            CHECK
            (
                MetricName <> 'Other'
                OR NULLIF(LTRIM(RTRIM(MetricDescription)), '') IS NOT NULL
            ),

        CONSTRAINT CK_ModelPerformanceMetric_EvaluationDataset
            CHECK
            (
                EvaluationDataset IN
                (
                    'Training',
                    'Validation',
                    'Test',
                    'Holdout',
                    'Production',
                    'Shadow',
                    'Other'
                )
            ),

        CONSTRAINT CK_ModelPerformanceMetric_EvaluationDateRange
            CHECK
            (
                EvaluationStartDate IS NULL
                OR EvaluationEndDate IS NULL
                OR EvaluationEndDate >= EvaluationStartDate
            ),

        CONSTRAINT CK_ModelPerformanceMetric_ThresholdValue
            CHECK
            (
                ThresholdValue IS NULL
                OR ThresholdValue BETWEEN 0 AND 1
            ),

        CONSTRAINT CK_ModelPerformanceMetric_SampleSize
            CHECK
            (
                SampleSize IS NULL
                OR SampleSize >= 0
            )
    );

    ALTER TABLE AI.ModelPerformanceMetric WITH CHECK
    ADD CONSTRAINT FK_ModelPerformanceMetric_ModelVersion
        FOREIGN KEY (ModelVersionID)
        REFERENCES AI.ModelVersion (ModelVersionID);

    ALTER TABLE AI.ModelPerformanceMetric
        CHECK CONSTRAINT FK_ModelPerformanceMetric_ModelVersion;

    /*
      A metric is unique for a version, dataset, evaluation window,
      and population segment. A unique index treats NULLs as equal,
      which correctly prevents duplicate rows that share NULL bounds
      or a NULL segment.
    */
    CREATE UNIQUE INDEX UX_ModelPerformanceMetric_Version_Metric_Window
        ON AI.ModelPerformanceMetric
        (
            ModelVersionID,
            MetricName,
            EvaluationDataset,
            EvaluationStartDate,
            EvaluationEndDate,
            PatientPopulationSegment
        );

    CREATE INDEX IX_ModelPerformanceMetric_Version_CalculatedDateTime
        ON AI.ModelPerformanceMetric
        (
            ModelVersionID,
            CalculatedDateTimeUTC
        );

    PRINT 'Created AI.ModelPerformanceMetric.';
END
ELSE
BEGIN
    PRINT 'Skipped AI.ModelPerformanceMetric because it already exists.';
END;
GO


/*==========================================================
  8. AI.ModelMonitoringEvent
==========================================================*/

IF OBJECT_ID('AI.ModelMonitoringEvent', 'U') IS NULL
BEGIN
    CREATE TABLE AI.ModelMonitoringEvent
    (
        ModelMonitoringEventID  BIGINT IDENTITY(1,1) NOT NULL,
        ModelVersionID          INT NOT NULL,

        EventDateTimeUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_ModelMonitoringEvent_EventDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        EventType               VARCHAR(40) NOT NULL,
        Severity                VARCHAR(15) NOT NULL,

        MetricName              VARCHAR(50) NULL,
        ObservedValue           DECIMAL(19,8) NULL,
        ExpectedMinimum         DECIMAL(19,8) NULL,
        ExpectedMaximum         DECIMAL(19,8) NULL,
        PopulationSegment       NVARCHAR(200) NULL,

        EventDescription        NVARCHAR(2000) NOT NULL,

        ResolutionStatus        VARCHAR(20) NOT NULL
            CONSTRAINT DF_ModelMonitoringEvent_ResolutionStatus
            DEFAULT ('Open'),

        ResolvedByProviderID    INT NULL,
        ResolvedDateTimeUTC     DATETIME2(3) NULL,
        ResolutionNotes         NVARCHAR(2000) NULL,

        CreatedDateUTC          DATETIME2(3) NOT NULL
            CONSTRAINT DF_ModelMonitoringEvent_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC         DATETIME2(3) NOT NULL
            CONSTRAINT DF_ModelMonitoringEvent_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_ModelMonitoringEvent
            PRIMARY KEY CLUSTERED (ModelMonitoringEventID),

        CONSTRAINT CK_ModelMonitoringEvent_EventType
            CHECK
            (
                EventType IN
                (
                    'Data Drift',
                    'Concept Drift',
                    'Performance Degradation',
                    'Bias Alert',
                    'Missing Data',
                    'Latency',
                    'Availability',
                    'Security',
                    'Safety',
                    'Compliance',
                    'Other'
                )
            ),

        CONSTRAINT CK_ModelMonitoringEvent_Severity
            CHECK
            (
                Severity IN
                (
                    'Info',
                    'Low',
                    'Medium',
                    'High',
                    'Critical'
                )
            ),

        CONSTRAINT CK_ModelMonitoringEvent_ResolutionStatus
            CHECK
            (
                ResolutionStatus IN
                (
                    'Open',
                    'Acknowledged',
                    'Investigating',
                    'Resolved',
                    'Dismissed'
                )
            ),

        CONSTRAINT CK_ModelMonitoringEvent_ExpectedRange
            CHECK
            (
                ExpectedMinimum IS NULL
                OR ExpectedMaximum IS NULL
                OR ExpectedMaximum >= ExpectedMinimum
            ),

        /*
          Closed events require resolver and resolution time.
          Open workflow states must not carry resolution metadata.
        */
        CONSTRAINT CK_ModelMonitoringEvent_ResolutionConsistency
            CHECK
            (
                (
                    ResolutionStatus IN ('Resolved', 'Dismissed')
                    AND ResolvedByProviderID IS NOT NULL
                    AND ResolvedDateTimeUTC IS NOT NULL
                )
                OR
                (
                    ResolutionStatus IN ('Open', 'Acknowledged', 'Investigating')
                    AND ResolvedByProviderID IS NULL
                    AND ResolvedDateTimeUTC IS NULL
                )
            )
    );

    ALTER TABLE AI.ModelMonitoringEvent WITH CHECK
    ADD CONSTRAINT FK_ModelMonitoringEvent_ModelVersion
        FOREIGN KEY (ModelVersionID)
        REFERENCES AI.ModelVersion (ModelVersionID);

    ALTER TABLE AI.ModelMonitoringEvent WITH CHECK
    ADD CONSTRAINT FK_ModelMonitoringEvent_ResolvedByProvider
        FOREIGN KEY (ResolvedByProviderID)
        REFERENCES Hospital.Provider (ProviderID);

    ALTER TABLE AI.ModelMonitoringEvent
        CHECK CONSTRAINT FK_ModelMonitoringEvent_ModelVersion;

    ALTER TABLE AI.ModelMonitoringEvent
        CHECK CONSTRAINT FK_ModelMonitoringEvent_ResolvedByProvider;

    CREATE INDEX IX_ModelMonitoringEvent_Version_EventDateTime
        ON AI.ModelMonitoringEvent
        (
            ModelVersionID,
            EventDateTimeUTC
        );

    CREATE INDEX IX_ModelMonitoringEvent_ResolvedByProviderID
        ON AI.ModelMonitoringEvent (ResolvedByProviderID);

    /*
      Supports retrieval of unresolved, actionable alerts.
    */
    CREATE INDEX IX_ModelMonitoringEvent_Unresolved
        ON AI.ModelMonitoringEvent
        (
            Severity,
            EventDateTimeUTC
        )
        INCLUDE
        (
            ModelVersionID,
            EventType
        )
        WHERE ResolutionStatus IN ('Open', 'Acknowledged', 'Investigating');

    PRINT 'Created AI.ModelMonitoringEvent.';
END
ELSE
BEGIN
    PRINT 'Skipped AI.ModelMonitoringEvent because it already exists.';
END;
GO


PRINT 'All AI schema tables were processed successfully.';
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
WHERE s.name = 'AI'
ORDER BY t.name;
GO

SELECT COUNT(*) AS AITableCount
FROM sys.tables AS t
INNER JOIN sys.schemas AS s
    ON s.schema_id = t.schema_id
WHERE s.name = 'AI';
GO

SELECT
    OBJECT_NAME(fk.parent_object_id) AS TableName,
    fk.name AS ForeignKeyName,
    fk.is_disabled AS IsDisabled,
    fk.is_not_trusted AS IsNotTrusted
FROM sys.foreign_keys AS fk
WHERE OBJECT_SCHEMA_NAME(fk.parent_object_id) = 'AI'
ORDER BY TableName, ForeignKeyName;
GO