/*==========================================================
  HealthPulse AI
  Script: 004_Clinical_Schema.sql
  Purpose: Create the core Clinical schema tables.

  Tables:
    1. Clinical.Patient
    2. Clinical.PatientAddress
    3. Clinical.Encounter
    4. Clinical.Diagnosis
    5. Clinical.Procedure
    6. Clinical.Medication
    7. Clinical.MedicationOrder
    8. Clinical.Vitals

  Design standards:
    - INT IDENTITY surrogate primary keys
    - UTC audit timestamps (CreatedDateUTC / ModifiedDateUTC)
    - Referential integrity through foreign keys
    - Filtered unique indexes for nullable identifiers
    - Data-quality validation through CHECK constraints
    - Cross-hospital consistency enforcement where practical
    - No stored calculations (age, BMI, totals, averages)
==========================================================*/

USE HealthPulseAI;
GO

SET XACT_ABORT ON;
GO

/*==========================================================
  Schema: Clinical
  Created only if it does not already exist.
==========================================================*/
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'Clinical')
BEGIN
    EXEC ('CREATE SCHEMA Clinical;');
    PRINT 'Created schema Clinical.';
END
ELSE
BEGIN
    PRINT 'Skipped schema Clinical because it already exists.';
END;
GO


/*==========================================================
  1. Clinical.Patient
  Master Patient Index (MPI): the canonical identity record
  for every person receiving care across the enterprise.
==========================================================*/
IF OBJECT_ID('Clinical.Patient', 'U') IS NULL
BEGIN
    CREATE TABLE Clinical.Patient
    (
        PatientID            INT IDENTITY(1,1) NOT NULL,
        MedicalRecordNumber  VARCHAR(20) NOT NULL,

        FirstName            NVARCHAR(100) NOT NULL,
        MiddleName           NVARCHAR(100) NULL,
        LastName             NVARCHAR(100) NOT NULL,
        PreferredName        NVARCHAR(100) NULL,

        DateOfBirth          DATE NOT NULL,
        Gender               CHAR(1) NULL,
        MaritalStatus        VARCHAR(20) NULL,

        Email                NVARCHAR(150) NULL,
        PhoneNumber          VARCHAR(25) NULL,
        PreferredLanguage    NVARCHAR(50) NULL,
        BloodType            VARCHAR(3) NULL,
        DeceasedDate         DATE NULL,

        IsActive             BIT NOT NULL
            CONSTRAINT DF_Patient_IsActive
            DEFAULT (1),

        CreatedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_Patient_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC      DATETIME2(3) NOT NULL
            CONSTRAINT DF_Patient_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Patient
            PRIMARY KEY CLUSTERED (PatientID),

        CONSTRAINT UQ_Patient_MedicalRecordNumber
            UNIQUE (MedicalRecordNumber),

        CONSTRAINT CK_Patient_Gender
            CHECK
            (
                Gender IS NULL
                OR Gender IN ('M', 'F', 'O', 'U')
            ),

        CONSTRAINT CK_Patient_MaritalStatus
            CHECK
            (
                MaritalStatus IS NULL
                OR MaritalStatus IN
                (
                    'Single',
                    'Married',
                    'Divorced',
                    'Widowed',
                    'Separated',
                    'Partnered',
                    'Unknown'
                )
            ),

        CONSTRAINT CK_Patient_BloodType
            CHECK
            (
                BloodType IS NULL
                OR BloodType IN
                (
                    'A+', 'A-', 'B+', 'B-',
                    'AB+', 'AB-', 'O+', 'O-'
                )
            ),

        CONSTRAINT CK_Patient_DateOfBirth
            CHECK (DateOfBirth <= CAST(SYSUTCDATETIME() AS DATE)),

        CONSTRAINT CK_Patient_DeceasedDate
            CHECK
            (
                DeceasedDate IS NULL
                OR DeceasedDate >= DateOfBirth
            )
    );

    CREATE INDEX IX_Patient_LastName_FirstName
        ON Clinical.Patient (LastName, FirstName);

    CREATE INDEX IX_Patient_DateOfBirth
        ON Clinical.Patient (DateOfBirth);

    CREATE INDEX IX_Patient_IsActive
        ON Clinical.Patient (IsActive);

    PRINT 'Created Clinical.Patient.';
END
ELSE
BEGIN
    PRINT 'Skipped Clinical.Patient because it already exists.';
END;
GO


/*==========================================================
  2. Clinical.PatientAddress
  Historical and current addresses for a patient. Supports
  effective-dated history and a single active primary address.
==========================================================*/
IF OBJECT_ID('Clinical.PatientAddress', 'U') IS NULL
BEGIN
    CREATE TABLE Clinical.PatientAddress
    (
        PatientAddressID     INT IDENTITY(1,1) NOT NULL,
        PatientID            INT NOT NULL,

        AddressType          VARCHAR(20) NOT NULL
            CONSTRAINT DF_PatientAddress_AddressType
            DEFAULT ('Home'),

        AddressLine1         NVARCHAR(200) NOT NULL,
        AddressLine2         NVARCHAR(200) NULL,
        City                 NVARCHAR(100) NOT NULL,
        StateProvince        NVARCHAR(100) NOT NULL,
        PostalCode           VARCHAR(20) NOT NULL,
        Country              NVARCHAR(100) NOT NULL
            CONSTRAINT DF_PatientAddress_Country
            DEFAULT ('USA'),

        Latitude             DECIMAL(9,6) NULL,
        Longitude            DECIMAL(9,6) NULL,

        EffectiveStartDate   DATE NOT NULL
            CONSTRAINT DF_PatientAddress_EffectiveStartDate
            DEFAULT (CAST(SYSUTCDATETIME() AS DATE)),
        EffectiveEndDate     DATE NULL,

        IsPrimary            BIT NOT NULL
            CONSTRAINT DF_PatientAddress_IsPrimary
            DEFAULT (0),

        IsActive             BIT NOT NULL
            CONSTRAINT DF_PatientAddress_IsActive
            DEFAULT (1),

        CreatedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_PatientAddress_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC      DATETIME2(3) NOT NULL
            CONSTRAINT DF_PatientAddress_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_PatientAddress
            PRIMARY KEY CLUSTERED (PatientAddressID),

        CONSTRAINT FK_PatientAddress_Patient
            FOREIGN KEY (PatientID)
            REFERENCES Clinical.Patient (PatientID),

        CONSTRAINT CK_PatientAddress_AddressType
            CHECK
            (
                AddressType IN
                (
                    'Home',
                    'Mailing',
                    'Work',
                    'Temporary',
                    'Billing',
                    'Other'
                )
            ),

        CONSTRAINT CK_PatientAddress_Latitude
            CHECK
            (
                Latitude IS NULL
                OR Latitude BETWEEN -90 AND 90
            ),

        CONSTRAINT CK_PatientAddress_Longitude
            CHECK
            (
                Longitude IS NULL
                OR Longitude BETWEEN -180 AND 180
            ),

        CONSTRAINT CK_PatientAddress_Coordinates
            CHECK
            (
                (Latitude IS NULL AND Longitude IS NULL)
                OR
                (Latitude IS NOT NULL AND Longitude IS NOT NULL)
            ),

        CONSTRAINT CK_PatientAddress_EffectiveDates
            CHECK
            (
                EffectiveEndDate IS NULL
                OR EffectiveEndDate >= EffectiveStartDate
            )
    );

    CREATE INDEX IX_PatientAddress_PatientID
        ON Clinical.PatientAddress (PatientID);

    CREATE INDEX IX_PatientAddress_City_StateProvince
        ON Clinical.PatientAddress (City, StateProvince);

    /*
      Allows only one active primary address per patient.
    */
    CREATE UNIQUE INDEX UX_PatientAddress_OnePrimaryPerPatient
        ON Clinical.PatientAddress (PatientID)
        WHERE IsPrimary = 1
          AND IsActive = 1;

    PRINT 'Created Clinical.PatientAddress.';
END
ELSE
BEGIN
    PRINT 'Skipped Clinical.PatientAddress because it already exists.';
END;
GO


/*==========================================================
  3. Clinical.Encounter
  A single episode of care (inpatient stay, outpatient visit,
  ED visit, or telehealth session) tied to the patient and the
  organizational context (hospital, location, department,
  provider). Composite foreign keys ensure the referenced
  location and department belong to the same hospital.
==========================================================*/
IF OBJECT_ID('Clinical.Encounter', 'U') IS NULL
BEGIN
    CREATE TABLE Clinical.Encounter
    (
        EncounterID           INT IDENTITY(1,1) NOT NULL,
        PatientID             INT NOT NULL,
        HospitalID            INT NOT NULL,
        LocationID            INT NULL,
        DepartmentID          INT NULL,
        ProviderID            INT NULL,

        EncounterNumber       VARCHAR(30) NOT NULL,

        EncounterType         VARCHAR(30) NOT NULL
            CONSTRAINT DF_Encounter_EncounterType
            DEFAULT ('Outpatient'),

        EncounterStatus       VARCHAR(30) NOT NULL
            CONSTRAINT DF_Encounter_EncounterStatus
            DEFAULT ('Planned'),

        AdmissionDateTimeUTC  DATETIME2(3) NULL,
        DischargeDateTimeUTC  DATETIME2(3) NULL,

        ReasonForVisit        NVARCHAR(500) NULL,
        Disposition           VARCHAR(50) NULL,

        IsTelehealth          BIT NOT NULL
            CONSTRAINT DF_Encounter_IsTelehealth
            DEFAULT (0),

        CreatedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_Encounter_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_Encounter_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Encounter
            PRIMARY KEY CLUSTERED (EncounterID),

        CONSTRAINT UQ_Encounter_EncounterNumber
            UNIQUE (EncounterNumber),

        CONSTRAINT FK_Encounter_Patient
            FOREIGN KEY (PatientID)
            REFERENCES Clinical.Patient (PatientID),

        CONSTRAINT FK_Encounter_Hospital
            FOREIGN KEY (HospitalID)
            REFERENCES Hospital.Hospital (HospitalID),

        /*
          Composite FK: the location must belong to the same
          hospital as the encounter.
        */
        CONSTRAINT FK_Encounter_Location_Hospital
            FOREIGN KEY (LocationID, HospitalID)
            REFERENCES Hospital.Location (LocationID, HospitalID),

        /*
          Composite FK: the department must belong to the same
          hospital as the encounter.
        */
        CONSTRAINT FK_Encounter_Department_Hospital
            FOREIGN KEY (DepartmentID, HospitalID)
            REFERENCES Hospital.Department (DepartmentID, HospitalID),

        CONSTRAINT FK_Encounter_Provider
            FOREIGN KEY (ProviderID)
            REFERENCES Hospital.Provider (ProviderID),

        CONSTRAINT CK_Encounter_EncounterType
            CHECK
            (
                EncounterType IN
                (
                    'Inpatient',
                    'Outpatient',
                    'Emergency',
                    'Observation',
                    'Telehealth',
                    'Surgery',
                    'Urgent Care',
                    'Home Health'
                )
            ),

        CONSTRAINT CK_Encounter_EncounterStatus
            CHECK
            (
                EncounterStatus IN
                (
                    'Planned',
                    'Arrived',
                    'In Progress',
                    'Completed',
                    'Cancelled',
                    'No Show',
                    'Discharged'
                )
            ),

        CONSTRAINT CK_Encounter_DischargeAfterAdmission
            CHECK
            (
                DischargeDateTimeUTC IS NULL
                OR AdmissionDateTimeUTC IS NULL
                OR DischargeDateTimeUTC >= AdmissionDateTimeUTC
            )
    );

    CREATE INDEX IX_Encounter_PatientID
        ON Clinical.Encounter (PatientID);

    CREATE INDEX IX_Encounter_HospitalID
        ON Clinical.Encounter (HospitalID);

    CREATE INDEX IX_Encounter_LocationID
        ON Clinical.Encounter (LocationID);

    CREATE INDEX IX_Encounter_DepartmentID
        ON Clinical.Encounter (DepartmentID);

    CREATE INDEX IX_Encounter_ProviderID
        ON Clinical.Encounter (ProviderID);

    CREATE INDEX IX_Encounter_AdmissionDateTimeUTC
        ON Clinical.Encounter (AdmissionDateTimeUTC);

    CREATE INDEX IX_Encounter_EncounterType_Status
        ON Clinical.Encounter (EncounterType, EncounterStatus);

    PRINT 'Created Clinical.Encounter.';
END
ELSE
BEGIN
    PRINT 'Skipped Clinical.Encounter because it already exists.';
END;
GO


/*==========================================================
  4. Clinical.Diagnosis
  Coded diagnoses (ICD-10, etc.) recorded against an encounter
  and patient. Supports primary, secondary, admitting,
  discharge, and historical diagnosis types.
==========================================================*/
IF OBJECT_ID('Clinical.Diagnosis', 'U') IS NULL
BEGIN
    CREATE TABLE Clinical.Diagnosis
    (
        DiagnosisID           INT IDENTITY(1,1) NOT NULL,
        EncounterID           INT NOT NULL,
        PatientID             INT NOT NULL,

        DiagnosisCode         VARCHAR(20) NOT NULL,

        DiagnosisCodeSystem   VARCHAR(20) NOT NULL
            CONSTRAINT DF_Diagnosis_DiagnosisCodeSystem
            DEFAULT ('ICD-10-CM'),

        DiagnosisDescription  NVARCHAR(500) NULL,

        DiagnosisType         VARCHAR(20) NOT NULL
            CONSTRAINT DF_Diagnosis_DiagnosisType
            DEFAULT ('Secondary'),

        DiagnosisDateUTC      DATETIME2(3) NULL,

        PresentOnAdmission    CHAR(1) NULL,

        IsPrimary             BIT NOT NULL
            CONSTRAINT DF_Diagnosis_IsPrimary
            DEFAULT (0),

        CreatedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_Diagnosis_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_Diagnosis_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Diagnosis
            PRIMARY KEY CLUSTERED (DiagnosisID),

        CONSTRAINT FK_Diagnosis_Encounter
            FOREIGN KEY (EncounterID)
            REFERENCES Clinical.Encounter (EncounterID),

        CONSTRAINT FK_Diagnosis_Patient
            FOREIGN KEY (PatientID)
            REFERENCES Clinical.Patient (PatientID),

        CONSTRAINT CK_Diagnosis_DiagnosisType
            CHECK
            (
                DiagnosisType IN
                (
                    'Primary',
                    'Secondary',
                    'Admitting',
                    'Discharge',
                    'Historical'
                )
            ),

        CONSTRAINT CK_Diagnosis_PresentOnAdmission
            CHECK
            (
                PresentOnAdmission IS NULL
                OR PresentOnAdmission IN ('Y', 'N', 'U', 'W')
            )
    );

    CREATE INDEX IX_Diagnosis_EncounterID
        ON Clinical.Diagnosis (EncounterID);

    CREATE INDEX IX_Diagnosis_PatientID
        ON Clinical.Diagnosis (PatientID);

    CREATE INDEX IX_Diagnosis_DiagnosisCode
        ON Clinical.Diagnosis (DiagnosisCode, DiagnosisCodeSystem);

    CREATE INDEX IX_Diagnosis_Patient_Code
        ON Clinical.Diagnosis (PatientID, DiagnosisCode);

    PRINT 'Created Clinical.Diagnosis.';
END
ELSE
BEGIN
    PRINT 'Skipped Clinical.Diagnosis because it already exists.';
END;
GO


USE HealthPulseAI;
GO

/*==========================================================
  5. Clinical.Procedure
  Coded procedures performed during a patient encounter.
==========================================================*/

IF OBJECT_ID('Clinical.[Procedure]', 'U') IS NULL
BEGIN
    CREATE TABLE Clinical.[Procedure]
    (
        ProcedureID           INT IDENTITY(1,1) NOT NULL,
        EncounterID           INT NOT NULL,
        PatientID             INT NOT NULL,
        ProviderID            INT NULL,

        ProcedureCode         VARCHAR(20) NOT NULL,

        ProcedureCodeSystem   VARCHAR(20) NOT NULL
            CONSTRAINT DF_Procedure_ProcedureCodeSystem
            DEFAULT ('CPT'),

        ProcedureDescription  NVARCHAR(500) NULL,

        ProcedureDateTimeUTC  DATETIME2(3) NULL,

        ProcedureStatus       VARCHAR(20) NOT NULL
            CONSTRAINT DF_Procedure_ProcedureStatus
            DEFAULT ('Completed'),

        Quantity              INT NOT NULL
            CONSTRAINT DF_Procedure_Quantity
            DEFAULT (1),

        CreatedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_Procedure_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_Procedure_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Procedure
            PRIMARY KEY CLUSTERED (ProcedureID),

        CONSTRAINT FK_Procedure_Encounter
            FOREIGN KEY (EncounterID)
            REFERENCES Clinical.Encounter (EncounterID),

        CONSTRAINT FK_Procedure_Patient
            FOREIGN KEY (PatientID)
            REFERENCES Clinical.Patient (PatientID),

        CONSTRAINT FK_Procedure_Provider
            FOREIGN KEY (ProviderID)
            REFERENCES Hospital.Provider (ProviderID),

        CONSTRAINT CK_Procedure_ProcedureStatus
            CHECK
            (
                ProcedureStatus IN
                (
                    'Scheduled',
                    'In Progress',
                    'Completed',
                    'Cancelled',
                    'Aborted'
                )
            ),

        CONSTRAINT CK_Procedure_Quantity
            CHECK (Quantity > 0)
    );

    CREATE INDEX IX_Procedure_EncounterID
        ON Clinical.[Procedure] (EncounterID);

    CREATE INDEX IX_Procedure_PatientID
        ON Clinical.[Procedure] (PatientID);

    CREATE INDEX IX_Procedure_ProviderID
        ON Clinical.[Procedure] (ProviderID);

    CREATE INDEX IX_Procedure_ProcedureCode
        ON Clinical.[Procedure] (ProcedureCode, ProcedureCodeSystem);

    PRINT 'Created Clinical.Procedure.';
END
ELSE
BEGIN
    PRINT 'Skipped Clinical.Procedure because it already exists.';
END;
GO
/*==========================================================
  6. Clinical.Medication
  Reference catalog of medications (drug master). Referenced
  by medication orders; not patient-specific.
==========================================================*/
IF OBJECT_ID('Clinical.Medication', 'U') IS NULL
BEGIN
    CREATE TABLE Clinical.Medication
    (
        MedicationID          INT IDENTITY(1,1) NOT NULL,

        MedicationCode        VARCHAR(30) NOT NULL,
        MedicationName        NVARCHAR(200) NOT NULL,
        GenericName           NVARCHAR(200) NULL,
        BrandName             NVARCHAR(200) NULL,
        DrugClass             NVARCHAR(100) NULL,
        Strength              NVARCHAR(50) NULL,
        DosageForm            NVARCHAR(50) NULL,
        Manufacturer          NVARCHAR(150) NULL,

        IsControlledSubstance BIT NOT NULL
            CONSTRAINT DF_Medication_IsControlledSubstance
            DEFAULT (0),

        IsActive              BIT NOT NULL
            CONSTRAINT DF_Medication_IsActive
            DEFAULT (1),

        CreatedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_Medication_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_Medication_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Medication
            PRIMARY KEY CLUSTERED (MedicationID),

        CONSTRAINT UQ_Medication_MedicationCode
            UNIQUE (MedicationCode)
    );

    CREATE INDEX IX_Medication_MedicationName
        ON Clinical.Medication (MedicationName);

    CREATE INDEX IX_Medication_DrugClass
        ON Clinical.Medication (DrugClass);

    CREATE INDEX IX_Medication_IsActive
        ON Clinical.Medication (IsActive);

    PRINT 'Created Clinical.Medication.';
END
ELSE
BEGIN
    PRINT 'Skipped Clinical.Medication because it already exists.';
END;
GO


/*==========================================================
  7. Clinical.MedicationOrder
  A prescription / medication order placed for a patient during
  an encounter, linked to the ordering provider and the drug
  master record.
==========================================================*/
IF OBJECT_ID('Clinical.MedicationOrder', 'U') IS NULL
BEGIN
    CREATE TABLE Clinical.MedicationOrder
    (
        MedicationOrderID     INT IDENTITY(1,1) NOT NULL,
        PatientID             INT NOT NULL,
        EncounterID           INT NULL,
        ProviderID            INT NULL,
        MedicationID          INT NOT NULL,

        OrderDateTimeUTC      DATETIME2(3) NOT NULL
            CONSTRAINT DF_MedicationOrder_OrderDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        StartDate             DATE NULL,
        EndDate               DATE NULL,

        Dose                  DECIMAL(10,3) NULL,
        DoseUnit              VARCHAR(20) NULL,
        Route                 VARCHAR(30) NULL,
        Frequency             VARCHAR(50) NULL,

        Quantity              DECIMAL(10,2) NULL,
        Refills               INT NULL,

        OrderStatus           VARCHAR(20) NOT NULL
            CONSTRAINT DF_MedicationOrder_OrderStatus
            DEFAULT ('Active'),

        Instructions          NVARCHAR(500) NULL,

        CreatedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_MedicationOrder_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_MedicationOrder_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_MedicationOrder
            PRIMARY KEY CLUSTERED (MedicationOrderID),

        CONSTRAINT FK_MedicationOrder_Patient
            FOREIGN KEY (PatientID)
            REFERENCES Clinical.Patient (PatientID),

        CONSTRAINT FK_MedicationOrder_Encounter
            FOREIGN KEY (EncounterID)
            REFERENCES Clinical.Encounter (EncounterID),

        CONSTRAINT FK_MedicationOrder_Provider
            FOREIGN KEY (ProviderID)
            REFERENCES Hospital.Provider (ProviderID),

        CONSTRAINT FK_MedicationOrder_Medication
            FOREIGN KEY (MedicationID)
            REFERENCES Clinical.Medication (MedicationID),

        CONSTRAINT CK_MedicationOrder_OrderStatus
            CHECK
            (
                OrderStatus IN
                (
                    'Active',
                    'Completed',
                    'Discontinued',
                    'On Hold',
                    'Cancelled'
                )
            ),

        CONSTRAINT CK_MedicationOrder_EndAfterStart
            CHECK
            (
                EndDate IS NULL
                OR StartDate IS NULL
                OR EndDate >= StartDate
            ),

        CONSTRAINT CK_MedicationOrder_Quantity
            CHECK
            (
                Quantity IS NULL
                OR Quantity >= 0
            ),

        CONSTRAINT CK_MedicationOrder_Refills
            CHECK
            (
                Refills IS NULL
                OR Refills >= 0
            )
    );

    CREATE INDEX IX_MedicationOrder_PatientID
        ON Clinical.MedicationOrder (PatientID);

    CREATE INDEX IX_MedicationOrder_EncounterID
        ON Clinical.MedicationOrder (EncounterID);

    CREATE INDEX IX_MedicationOrder_ProviderID
        ON Clinical.MedicationOrder (ProviderID);

    CREATE INDEX IX_MedicationOrder_MedicationID
        ON Clinical.MedicationOrder (MedicationID);

    CREATE INDEX IX_MedicationOrder_OrderStatus
        ON Clinical.MedicationOrder (OrderStatus);

    PRINT 'Created Clinical.MedicationOrder.';
END
ELSE
BEGIN
    PRINT 'Skipped Clinical.MedicationOrder because it already exists.';
END;
GO


/*==========================================================
  8. Clinical.Vitals
  Discrete vital-sign measurements captured for a patient,
  optionally within an encounter and recorded by a provider.
  BMI is intentionally NOT stored; it is derived from
  HeightCM and WeightKG at query/analysis time.
==========================================================*/
IF OBJECT_ID('Clinical.Vitals', 'U') IS NULL
BEGIN
    CREATE TABLE Clinical.Vitals
    (
        VitalID                 INT IDENTITY(1,1) NOT NULL,
        PatientID               INT NOT NULL,
        EncounterID             INT NULL,
        RecordedByProviderID    INT NULL,

        RecordedDateTimeUTC     DATETIME2(3) NOT NULL
            CONSTRAINT DF_Vitals_RecordedDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        HeightCM                DECIMAL(5,2) NULL,
        WeightKG                DECIMAL(6,2) NULL,
        TemperatureCelsius      DECIMAL(4,1) NULL,
        HeartRateBPM            INT NULL,
        RespiratoryRate         INT NULL,
        SystolicBloodPressure   INT NULL,
        DiastolicBloodPressure  INT NULL,
        OxygenSaturationPercent DECIMAL(5,2) NULL,
        BloodGlucoseMgDL        DECIMAL(6,2) NULL,
        PainScore               TINYINT NULL,

        CreatedDateUTC          DATETIME2(3) NOT NULL
            CONSTRAINT DF_Vitals_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC         DATETIME2(3) NOT NULL
            CONSTRAINT DF_Vitals_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Vitals
            PRIMARY KEY CLUSTERED (VitalID),

        CONSTRAINT FK_Vitals_Patient
            FOREIGN KEY (PatientID)
            REFERENCES Clinical.Patient (PatientID),

        CONSTRAINT FK_Vitals_Encounter
            FOREIGN KEY (EncounterID)
            REFERENCES Clinical.Encounter (EncounterID),

        CONSTRAINT FK_Vitals_Provider
            FOREIGN KEY (RecordedByProviderID)
            REFERENCES Hospital.Provider (ProviderID),

        CONSTRAINT CK_Vitals_HeightCM
            CHECK (HeightCM IS NULL OR HeightCM BETWEEN 20 AND 300),

        CONSTRAINT CK_Vitals_WeightKG
            CHECK (WeightKG IS NULL OR WeightKG BETWEEN 0.2 AND 700),

        CONSTRAINT CK_Vitals_TemperatureCelsius
            CHECK (TemperatureCelsius IS NULL OR TemperatureCelsius BETWEEN 25 AND 45),

        CONSTRAINT CK_Vitals_HeartRateBPM
            CHECK (HeartRateBPM IS NULL OR HeartRateBPM BETWEEN 0 AND 300),

        CONSTRAINT CK_Vitals_RespiratoryRate
            CHECK (RespiratoryRate IS NULL OR RespiratoryRate BETWEEN 0 AND 100),

        CONSTRAINT CK_Vitals_SystolicBloodPressure
            CHECK (SystolicBloodPressure IS NULL OR SystolicBloodPressure BETWEEN 40 AND 300),

        CONSTRAINT CK_Vitals_DiastolicBloodPressure
            CHECK (DiastolicBloodPressure IS NULL OR DiastolicBloodPressure BETWEEN 20 AND 200),

        CONSTRAINT CK_Vitals_OxygenSaturationPercent
            CHECK (OxygenSaturationPercent IS NULL OR OxygenSaturationPercent BETWEEN 0 AND 100),

        CONSTRAINT CK_Vitals_BloodGlucoseMgDL
            CHECK (BloodGlucoseMgDL IS NULL OR BloodGlucoseMgDL BETWEEN 10 AND 2000),

        CONSTRAINT CK_Vitals_PainScore
            CHECK (PainScore IS NULL OR PainScore BETWEEN 0 AND 10),

        CONSTRAINT CK_Vitals_BloodPressureConsistency
            CHECK
            (
                SystolicBloodPressure IS NULL
                OR DiastolicBloodPressure IS NULL
                OR SystolicBloodPressure >= DiastolicBloodPressure
            )
    );

    CREATE INDEX IX_Vitals_PatientID
        ON Clinical.Vitals (PatientID);

    CREATE INDEX IX_Vitals_EncounterID
        ON Clinical.Vitals (EncounterID);

    CREATE INDEX IX_Vitals_RecordedByProviderID
        ON Clinical.Vitals (RecordedByProviderID);

    CREATE INDEX IX_Vitals_Patient_RecordedDateTimeUTC
        ON Clinical.Vitals (PatientID, RecordedDateTimeUTC);

    PRINT 'Created Clinical.Vitals.';
END
ELSE
BEGIN
    PRINT 'Skipped Clinical.Vitals because it already exists.';
END;
GO


PRINT 'All Clinical schema tables were processed successfully.';
GO
