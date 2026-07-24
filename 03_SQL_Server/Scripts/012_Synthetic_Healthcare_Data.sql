/*==========================================================
  HealthPulse AI
  Script: 012_Synthetic_Healthcare_Data.sql
  Purpose: Generate realistic, high-volume synthetic
           transactional data across every operational schema
           (Clinical, Telehealth, Insurance, Billing, Marketing,
           AI). Reference / master data is seeded by script 011
           and is NOT recreated here.

  Design standards:
    - Fully rerunnable and idempotent
        (INSERT ... SELECT ... WHERE NOT EXISTS on business keys)
    - Deterministic generation (no RAND / NEWID for data values)
        so repeated runs produce identical rows
    - Business keys only for matching; never identity values
    - Foreign keys resolved via lookups / row-number indexing
    - Only values permitted by existing CHECK constraints
    - Cross-entity consistency respected
        (provider/hospital, encounter/patient, coverage/patient)
    - Transactions per logical section with TRY/CATCH + THROW
    - No MERGE, DELETE, TRUNCATE, or constraint disabling
    - Realistic but fictional data; no real PHI

  Target volumes (approximate, per clean run):
    Clinical.Patient .................. 500
    Clinical.PatientAddress ........... 500
    Clinical.Encounter ................ 1,500
    Clinical.Diagnosis ................ ~2,600
    Clinical.Procedure ................ ~1,150
    Clinical.MedicationOrder .......... ~1,900
    Clinical.Vitals ................... 1,500
    Telehealth.VirtualVisit ........... ~214
    Telehealth.SessionEvent ........... ~840
    Telehealth.Device ................. ~150
    Telehealth.DeviceReading .......... ~1,050
    Telehealth.WaitlistQueue .......... ~210
    Insurance.PatientCoverage ......... 500
    Insurance.PriorAuthorization ...... not populated in this script
    Insurance.Claim ................... ~1,000
    Insurance.ClaimLine ............... ~2,500
    Insurance.ClaimStatusHistory ...... not populated in this script
    Billing.PatientAccount ............ 500
    Billing.Invoice ................... ~1,000
    Billing.InvoiceLine ............... ~2,000
    Billing.Payment ................... ~800
    Billing.PaymentAllocation ......... ~800
    Billing.Adjustment ................ not populated in this script
    Marketing.PatientCommunicationPreference ~500
    Marketing.Campaign ................ 3
    Marketing.CampaignChannel ......... 3
    Marketing.CampaignAudience ........ not populated in this script
    Marketing.CampaignInteraction ..... 500
    Marketing.PatientAcquisition ...... 500
    AI.Prediction ..................... 1,500
    AI.PredictionOutcome .............. ~800
    AI.ModelPerformanceMetric ......... ~18
    AI.ModelMonitoringEvent ........... 3
==========================================================*/

USE HealthPulseAI;
GO

SET XACT_ABORT ON;
SET NOCOUNT ON;
GO


/*==========================================================
  Prerequisite check: all schema tables and reference data
  must already exist (scripts 003 - 011).
==========================================================*/
IF OBJECT_ID('Clinical.Patient', 'U') IS NULL
   OR OBJECT_ID('Clinical.Encounter', 'U') IS NULL
   OR OBJECT_ID('Clinical.Diagnosis', 'U') IS NULL
   OR OBJECT_ID('Clinical.[Procedure]', 'U') IS NULL
   OR OBJECT_ID('Clinical.MedicationOrder', 'U') IS NULL
   OR OBJECT_ID('Clinical.Vitals', 'U') IS NULL
   OR OBJECT_ID('Telehealth.VirtualVisit', 'U') IS NULL
   OR OBJECT_ID('Insurance.PatientCoverage', 'U') IS NULL
   OR OBJECT_ID('Insurance.Claim', 'U') IS NULL
   OR OBJECT_ID('Billing.PatientAccount', 'U') IS NULL
   OR OBJECT_ID('Billing.Invoice', 'U') IS NULL
   OR OBJECT_ID('Marketing.Campaign', 'U') IS NULL
   OR OBJECT_ID('AI.ModelVersion', 'U') IS NULL
BEGIN
    THROW 50010, 'Required HealthPulseAI schema tables are missing. Run scripts 003 through 011 first.', 1;
END;
GO

IF NOT EXISTS (SELECT 1 FROM Hospital.Provider)
   OR NOT EXISTS (SELECT 1 FROM Clinical.Medication)
   OR NOT EXISTS (SELECT 1 FROM Insurance.InsurancePlan)
   OR NOT EXISTS (SELECT 1 FROM Marketing.ReferralSource)
   OR NOT EXISTS (SELECT 1 FROM AI.ModelVersion)
BEGIN
    THROW 50011, 'Reference/master data is missing. Run script 011 (Reference Seed Data) first.', 1;
END;
GO


/*==========================================================
  SECTION 1: Clinical.Patient  (Master Patient Index)
  500 canonical patients with deterministic demographics.
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @PatientCount INT = 500;

    ;WITH Nums AS
    (
        SELECT TOP (@PatientCount)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    ),
    FirstNames AS
    (
        SELECT i, nm
        FROM (VALUES
            (0,N'James'),(1,N'Mary'),(2,N'Robert'),(3,N'Patricia'),
            (4,N'John'),(5,N'Jennifer'),(6,N'Michael'),(7,N'Linda'),
            (8,N'David'),(9,N'Elizabeth'),(10,N'William'),(11,N'Barbara'),
            (12,N'Richard'),(13,N'Susan'),(14,N'Joseph'),(15,N'Jessica'),
            (16,N'Thomas'),(17,N'Sarah'),(18,N'Carlos'),(19,N'Maria')
        ) AS f(i, nm)
    ),
    LastNames AS
    (
        SELECT i, nm
        FROM (VALUES
            (0,N'Smith'),(1,N'Johnson'),(2,N'Williams'),(3,N'Brown'),
            (4,N'Jones'),(5,N'Garcia'),(6,N'Miller'),(7,N'Davis'),
            (8,N'Rodriguez'),(9,N'Martinez'),(10,N'Hernandez'),(11,N'Lopez'),
            (12,N'Gonzalez'),(13,N'Wilson'),(14,N'Anderson'),(15,N'Thomas'),
            (16,N'Taylor'),(17,N'Moore'),(18,N'Jackson'),(19,N'Martin')
        ) AS l(i, nm)
    )
    INSERT INTO Clinical.Patient
    (
        MedicalRecordNumber, FirstName, LastName,
        DateOfBirth, Gender, MaritalStatus,
        Email, PhoneNumber, PreferredLanguage, BloodType, IsActive
    )
    SELECT
        'MRN-' + RIGHT('000000' + CAST(nm.n AS VARCHAR(10)), 6),
        fn.nm,
        ln.nm,
        DATEADD(DAY, (nm.n % 360),
            DATEADD(YEAR, -((nm.n % 88) + 1), CAST('2007-01-01' AS DATE))),
        CASE nm.n % 2 WHEN 0 THEN 'M' ELSE 'F' END,
        CASE nm.n % 5
            WHEN 0 THEN 'Single'
            WHEN 1 THEN 'Married'
            WHEN 2 THEN 'Divorced'
            WHEN 3 THEN 'Widowed'
            ELSE 'Partnered'
        END,
        LOWER(fn.nm) + '.' + LOWER(ln.nm)
            + CAST(nm.n AS VARCHAR(10)) + '@example-patient.test',
        '206-555-' + RIGHT('0000' + CAST(nm.n AS VARCHAR(10)), 4),
        CASE WHEN nm.n % 6 = 0 THEN N'Spanish' ELSE N'English' END,
        CASE nm.n % 8
            WHEN 0 THEN 'O+' WHEN 1 THEN 'A+' WHEN 2 THEN 'B+' WHEN 3 THEN 'AB+'
            WHEN 4 THEN 'O-' WHEN 5 THEN 'A-' WHEN 6 THEN 'B-' ELSE 'AB-'
        END,
        1
    FROM Nums nm
    JOIN FirstNames fn ON fn.i = nm.n % 20
    JOIN LastNames  ln ON ln.i = (nm.n / 20) % 20
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Clinical.Patient p
        WHERE p.MedicalRecordNumber =
              'MRN-' + RIGHT('000000' + CAST(nm.n AS VARCHAR(10)), 6)
    );

    COMMIT TRANSACTION;
    PRINT 'Section 1 complete: Clinical.Patient generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 1 failed: Clinical.Patient.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 2: Clinical.PatientAddress
  One active primary home address per patient.
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH Cities AS
    (
        SELECT i, City, StateProvince, PostalCode
        FROM (VALUES
            (0, N'Seattle',  N'Washington', '98101'),
            (1, N'Phoenix',  N'Arizona',    '85004'),
            (2, N'Portland', N'Oregon',     '97201'),
            (3, N'Tacoma',   N'Washington', '98402'),
            (4, N'Mesa',     N'Arizona',    '85201'),
            (5, N'Salem',    N'Oregon',     '97301'),
            (6, N'Spokane',  N'Washington', '99201'),
            (7, N'Tucson',   N'Arizona',    '85701')
        ) AS c(i, City, StateProvince, PostalCode)
    ),
    P AS
    (
        SELECT
            PatientID,
            ROW_NUMBER() OVER (ORDER BY PatientID) - 1 AS rn
        FROM Clinical.Patient
    )
    INSERT INTO Clinical.PatientAddress
    (
        PatientID, AddressType, AddressLine1, City, StateProvince,
        PostalCode, Country, EffectiveStartDate, IsPrimary, IsActive
    )
    SELECT
        P.PatientID,
        'Home',
        CAST(((P.rn % 900) + 100) AS VARCHAR(10)) + N' '
            + CASE P.rn % 5
                WHEN 0 THEN N'Main St'
                WHEN 1 THEN N'Oak Ave'
                WHEN 2 THEN N'Cedar Blvd'
                WHEN 3 THEN N'Pine Way'
                ELSE N'Maple Dr'
              END,
        c.City,
        c.StateProvince,
        c.PostalCode,
        N'USA',
        DATEADD(DAY, -(P.rn % 1000), CAST('2024-01-01' AS DATE)),
        1,
        1
    FROM P
    JOIN Cities c ON c.i = P.rn % 8
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Clinical.PatientAddress a
        WHERE a.PatientID = P.PatientID
          AND a.IsPrimary = 1
          AND a.IsActive = 1
    );

    COMMIT TRANSACTION;
    PRINT 'Section 2 complete: Clinical.PatientAddress generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 2 failed: Clinical.PatientAddress.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 3: Clinical.Encounter
  1,500 encounters. Provider drives HospitalID + DepartmentID
  so provider/hospital and department/hospital composite FKs
  are always satisfied. Telehealth flag is kept consistent
  with EncounterType (CK_Encounter_TelehealthConsistency).
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    DECLARE @EncounterCount INT = 1500;

    ;WITH Nums AS
    (
        SELECT TOP (@EncounterCount)
            ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM sys.all_objects a
        CROSS JOIN sys.all_objects b
    ),
    PatientMap AS
    (
        SELECT PatientID,
               ROW_NUMBER() OVER (ORDER BY PatientID) - 1 AS rn,
               COUNT(*) OVER () AS cnt
        FROM Clinical.Patient
    ),
    ProvMap AS
    (
        SELECT ProviderID, HospitalID, DepartmentID,
               ROW_NUMBER() OVER (ORDER BY ProviderID) - 1 AS rn,
               COUNT(*) OVER () AS cnt
        FROM Hospital.Provider
    ),
    Enc AS
    (
        SELECT
            nm.n,
            'ENC-' + RIGHT('000000' + CAST(nm.n AS VARCHAR(10)), 6) AS EncounterNumber,
            CASE WHEN nm.n % 7 = 0 THEN 'Telehealth'
                 ELSE CASE nm.n % 6
                        WHEN 0 THEN 'Outpatient'
                        WHEN 1 THEN 'Inpatient'
                        WHEN 2 THEN 'Emergency'
                        WHEN 3 THEN 'Observation'
                        WHEN 4 THEN 'Surgery'
                        ELSE 'Urgent Care'
                      END
            END AS EncounterType,
            DATEADD(HOUR, (nm.n % 24),
                DATEADD(DAY, -((nm.n * 3) % 900),
                        CAST('2024-12-31T08:00:00' AS DATETIME2(3)))) AS AdmitUTC
        FROM Nums nm
    )
    INSERT INTO Clinical.Encounter
    (
        PatientID, HospitalID, DepartmentID, ProviderID,
        EncounterNumber, EncounterType, EncounterStatus,
        AdmissionDateTimeUTC, DischargeDateTimeUTC,
        ReasonForVisit, Disposition, IsTelehealth
    )
    SELECT
        pm.PatientID,
        prov.HospitalID,
        prov.DepartmentID,
        prov.ProviderID,
        e.EncounterNumber,
        e.EncounterType,
        CASE e.EncounterType
            WHEN 'Inpatient'   THEN 'Discharged'
            WHEN 'Observation' THEN 'Discharged'
            ELSE 'Completed'
        END,
        e.AdmitUTC,
        DATEADD(HOUR,
            CASE e.EncounterType
                WHEN 'Inpatient' THEN 24 + (e.n % 96)
                WHEN 'Surgery'   THEN 4 + (e.n % 12)
                ELSE 1 + (e.n % 6)
            END,
            e.AdmitUTC),
        CASE e.n % 8
            WHEN 0 THEN N'Chest pain evaluation'
            WHEN 1 THEN N'Routine follow-up'
            WHEN 2 THEN N'Shortness of breath'
            WHEN 3 THEN N'Diabetes management'
            WHEN 4 THEN N'Hypertension check'
            WHEN 5 THEN N'Abdominal pain'
            WHEN 6 THEN N'Medication review'
            ELSE N'Preventive wellness visit'
        END,
        CASE WHEN e.EncounterType IN ('Inpatient','Observation')
             THEN 'Home' ELSE 'Routine' END,
        CASE WHEN e.EncounterType = 'Telehealth' THEN 1 ELSE 0 END
    FROM Enc e
    JOIN PatientMap pm ON pm.rn = (e.n - 1) % pm.cnt
    JOIN ProvMap  prov ON prov.rn = (e.n - 1) % prov.cnt
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Clinical.Encounter en
        WHERE en.EncounterNumber = e.EncounterNumber
    );

    COMMIT TRANSACTION;
    PRINT 'Section 3 complete: Clinical.Encounter generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 3 failed: Clinical.Encounter.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 4: Clinical.Diagnosis
  1 to 3 coded diagnoses per encounter. Slot 0 is the primary
  diagnosis. Codes differ per slot so (EncounterID,
  DiagnosisCode) is a stable idempotency key.
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH Slots AS
    (
        SELECT slot FROM (VALUES (0),(1),(2)) s(slot)
    ),
    ICD AS
    (
        SELECT i, code, descr
        FROM (VALUES
            (0, 'E11.9',   N'Type 2 diabetes mellitus without complications'),
            (1, 'I10',     N'Essential (primary) hypertension'),
            (2, 'E78.5',   N'Hyperlipidemia, unspecified'),
            (3, 'J45.909', N'Unspecified asthma, uncomplicated'),
            (4, 'N18.3',   N'Chronic kidney disease, stage 3'),
            (5, 'I25.10',  N'Atherosclerotic heart disease of native coronary artery'),
            (6, 'K21.9',   N'Gastro-esophageal reflux disease without esophagitis'),
            (7, 'F41.9',   N'Anxiety disorder, unspecified'),
            (8, 'M54.5',   N'Low back pain'),
            (9, 'J44.9',   N'Chronic obstructive pulmonary disease, unspecified'),
            (10,'E66.9',   N'Obesity, unspecified'),
            (11,'R07.9',   N'Chest pain, unspecified')
        ) AS d(i, code, descr)
    ),
    Enc AS
    (
        SELECT
            EncounterID, PatientID, EncounterType, AdmissionDateTimeUTC,
            ROW_NUMBER() OVER (ORDER BY EncounterID) - 1 AS rn
        FROM Clinical.Encounter
    )
    INSERT INTO Clinical.Diagnosis
    (
        EncounterID, PatientID, DiagnosisCode, DiagnosisCodeSystem,
        DiagnosisDescription, DiagnosisType, DiagnosisDateUTC,
        PresentOnAdmission, IsPrimary
    )
    SELECT
        e.EncounterID,
        e.PatientID,
        icd.code,
        'ICD-10-CM',
        icd.descr,
        CASE WHEN s.slot = 0 THEN 'Primary' ELSE 'Secondary' END,
        e.AdmissionDateTimeUTC,
        CASE WHEN e.EncounterType IN ('Inpatient','Observation','Emergency')
             THEN 'Y' ELSE NULL END,
        CASE WHEN s.slot = 0 THEN 1 ELSE 0 END
    FROM Enc e
    JOIN Slots s ON s.slot <= (e.rn % 3)
    JOIN ICD icd ON icd.i = (e.rn * 3 + s.slot) % 12
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Clinical.Diagnosis dg
        WHERE dg.EncounterID = e.EncounterID
          AND dg.DiagnosisCode = icd.code
    );

    COMMIT TRANSACTION;
    PRINT 'Section 4 complete: Clinical.Diagnosis generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 4 failed: Clinical.Diagnosis.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 5: Clinical.Procedure
  One procedure for roughly three quarters of encounters.
  Idempotency key: (EncounterID, ProcedureCode).
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH CPT AS
    (
        SELECT i, code, descr
        FROM (VALUES
            (0, '99213', N'Office/outpatient visit, established patient'),
            (1, '99283', N'Emergency department visit, moderate'),
            (2, '93000', N'Electrocardiogram, complete'),
            (3, '80053', N'Comprehensive metabolic panel'),
            (4, '85025', N'Complete blood count with differential'),
            (5, '71046', N'Chest X-ray, 2 views'),
            (6, '99396', N'Preventive visit, established patient'),
            (7, '36415', N'Routine venipuncture'),
            (8, '93306', N'Echocardiography, complete'),
            (9, '99284', N'Emergency department visit, high')
        ) AS c(i, code, descr)
    ),
    Enc AS
    (
        SELECT
            EncounterID, PatientID, ProviderID, AdmissionDateTimeUTC,
            ROW_NUMBER() OVER (ORDER BY EncounterID) - 1 AS rn
        FROM Clinical.Encounter
    )
    INSERT INTO Clinical.[Procedure]
    (
        EncounterID, PatientID, ProviderID, ProcedureCode,
        ProcedureCodeSystem, ProcedureDescription, ProcedureDateTimeUTC,
        ProcedureStatus, Quantity
    )
    SELECT
        e.EncounterID,
        e.PatientID,
        e.ProviderID,
        cpt.code,
        'CPT',
        cpt.descr,
        DATEADD(HOUR, 1, e.AdmissionDateTimeUTC),
        'Completed',
        1
    FROM Enc e
    JOIN CPT cpt ON cpt.i = e.rn % 10
    WHERE e.rn % 4 <> 3
      AND NOT EXISTS
      (
        SELECT 1
        FROM Clinical.[Procedure] pr
        WHERE pr.EncounterID = e.EncounterID
          AND pr.ProcedureCode = cpt.code
      );

    COMMIT TRANSACTION;
    PRINT 'Section 5 complete: Clinical.Procedure generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 5 failed: Clinical.Procedure.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 6: Clinical.MedicationOrder
  1 to 2 orders per encounter, drawn from the drug master.
  Idempotency key: (EncounterID, MedicationID).
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH Slots AS
    (
        SELECT slot FROM (VALUES (0),(1)) s(slot)
    ),
    Meds AS
    (
        SELECT MedicationID,
               ROW_NUMBER() OVER (ORDER BY MedicationID) - 1 AS mrn,
               COUNT(*) OVER () AS cnt
        FROM Clinical.Medication
    ),
    Enc AS
    (
        SELECT
            EncounterID, PatientID, ProviderID, AdmissionDateTimeUTC,
            ROW_NUMBER() OVER (ORDER BY EncounterID) - 1 AS rn
        FROM Clinical.Encounter
    )
    INSERT INTO Clinical.MedicationOrder
    (
        PatientID, EncounterID, ProviderID, MedicationID,
        OrderDateTimeUTC, StartDate, EndDate,
        Dose, DoseUnit, Route, Frequency,
        Quantity, Refills, OrderStatus, Instructions
    )
    SELECT
        e.PatientID,
        e.EncounterID,
        e.ProviderID,
        m.MedicationID,
        e.AdmissionDateTimeUTC,
        CAST(e.AdmissionDateTimeUTC AS DATE),
        DATEADD(DAY, 30 + (e.rn % 60), CAST(e.AdmissionDateTimeUTC AS DATE)),
        CAST(((e.rn % 4) + 1) * 5 AS DECIMAL(10,3)),
        'mg',
        CASE (e.rn + s.slot) % 3 WHEN 0 THEN 'Oral' WHEN 1 THEN 'IV' ELSE 'Subcutaneous' END,
        CASE (e.rn + s.slot) % 4
            WHEN 0 THEN 'Once daily'
            WHEN 1 THEN 'Twice daily'
            WHEN 2 THEN 'Every 8 hours'
            ELSE 'As needed'
        END,
        CAST(30 + (e.rn % 60) AS DECIMAL(10,2)),
        e.rn % 4,
        CASE WHEN e.rn % 5 = 0 THEN 'Completed' ELSE 'Active' END,
        N'Take as directed by provider.'
    FROM Enc e
    JOIN Slots s ON s.slot <= (e.rn % 2)
    JOIN Meds m ON m.mrn = (e.rn * 2 + s.slot) % m.cnt
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Clinical.MedicationOrder mo
        WHERE mo.EncounterID = e.EncounterID
          AND mo.MedicationID = m.MedicationID
    );

    COMMIT TRANSACTION;
    PRINT 'Section 6 complete: Clinical.MedicationOrder generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 6 failed: Clinical.MedicationOrder.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 7: Clinical.Vitals
  One vitals record per encounter. All values fall within the
  schema CHECK ranges; systolic >= diastolic is guaranteed.
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH Enc AS
    (
        SELECT
            EncounterID, PatientID, ProviderID, AdmissionDateTimeUTC,
            ROW_NUMBER() OVER (ORDER BY EncounterID) - 1 AS rn
        FROM Clinical.Encounter
    )
    INSERT INTO Clinical.Vitals
    (
        PatientID, EncounterID, RecordedByProviderID, RecordedDateTimeUTC,
        HeightCM, WeightKG, TemperatureCelsius, HeartRateBPM,
        RespiratoryRate, SystolicBloodPressure, DiastolicBloodPressure,
        OxygenSaturationPercent, BloodGlucoseMgDL, PainScore
    )
    SELECT
        e.PatientID,
        e.EncounterID,
        e.ProviderID,
        DATEADD(MINUTE, 15, e.AdmissionDateTimeUTC),
        CAST(150 + (e.rn % 45) AS DECIMAL(5,2)),
        CAST(55 + (e.rn % 60) AS DECIMAL(6,2)),
        CAST(36.4 + ((e.rn % 20) * 0.1) AS DECIMAL(4,1)),
        60 + (e.rn % 45),
        12 + (e.rn % 12),
        110 + (e.rn % 45),
        70 + (e.rn % 20),
        CAST(94 + (e.rn % 6) AS DECIMAL(5,2)),
        CAST(80 + (e.rn % 120) AS DECIMAL(6,2)),
        e.rn % 11
    FROM Enc e
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Clinical.Vitals vt
        WHERE vt.EncounterID = e.EncounterID
    );

    COMMIT TRANSACTION;
    PRINT 'Section 7 complete: Clinical.Vitals generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 7 failed: Clinical.Vitals.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 8: Telehealth.VirtualVisit
  One visit for every generated telehealth encounter.
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH E AS
    (
        SELECT
            EncounterID, PatientID, ProviderID, HospitalID, DepartmentID,
            AdmissionDateTimeUTC, DischargeDateTimeUTC,
            ROW_NUMBER() OVER (ORDER BY EncounterID) AS rn
        FROM Clinical.Encounter
        WHERE EncounterType = 'Telehealth'
    )
    INSERT INTO Telehealth.VirtualVisit
    (
        EncounterID, PatientID, ProviderID, HospitalID, DepartmentID,
        VisitNumber, ScheduledStartDateTimeUTC, ScheduledEndDateTimeUTC,
        ActualStartDateTimeUTC, ActualEndDateTimeUTC, VisitStatus,
        VisitType, PlatformName, MeetingIdentifier,
        PatientDeviceType, PatientConnectionMethod,
        PatientJoinedDateTimeUTC, ProviderJoinedDateTimeUTC,
        IsInterpreterRequired, InterpreterLanguage
    )
    SELECT
        e.EncounterID, e.PatientID, e.ProviderID, e.HospitalID, e.DepartmentID,
        'VV-' + RIGHT('000000' + CAST(e.rn AS VARCHAR(10)), 6),
        e.AdmissionDateTimeUTC,
        DATEADD(MINUTE, 30, e.AdmissionDateTimeUTC),
        CASE WHEN e.rn % 10 = 0 THEN NULL ELSE e.AdmissionDateTimeUTC END,
        CASE WHEN e.rn % 10 = 0 THEN NULL ELSE e.DischargeDateTimeUTC END,
        CASE WHEN e.rn % 10 = 0 THEN 'No Show'
             WHEN e.rn % 17 = 0 THEN 'Disconnected'
             ELSE 'Completed' END,
        CASE e.rn % 5
            WHEN 0 THEN 'Video'
            WHEN 1 THEN 'Audio'
            WHEN 2 THEN 'Chat'
            WHEN 3 THEN 'Remote Consultation'
            ELSE 'Follow-up'
        END,
        N'HealthPulse Virtual Care',
        N'MTG-' + RIGHT('000000' + CAST(e.rn AS VARCHAR(10)), 6),
        CASE e.rn % 3 WHEN 0 THEN 'Mobile' WHEN 1 THEN 'Desktop' ELSE 'Tablet' END,
        CASE e.rn % 3 WHEN 0 THEN 'Wi-Fi' WHEN 1 THEN 'Cellular' ELSE 'Broadband' END,
        CASE WHEN e.rn % 10 = 0 THEN NULL ELSE DATEADD(MINUTE, -3, e.AdmissionDateTimeUTC) END,
        CASE WHEN e.rn % 10 = 0 THEN NULL ELSE DATEADD(MINUTE, -1, e.AdmissionDateTimeUTC) END,
        CASE WHEN e.rn % 12 = 0 THEN 1 ELSE 0 END,
        CASE WHEN e.rn % 12 = 0 THEN N'Spanish' ELSE NULL END
    FROM E e
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Telehealth.VirtualVisit v
        WHERE v.EncounterID = e.EncounterID
    );

    COMMIT TRANSACTION;
    PRINT 'Section 8 complete: Telehealth.VirtualVisit generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 8 failed: Telehealth.VirtualVisit.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 9: Telehealth.SessionEvent
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH Slots AS
    (
        SELECT SequenceNumber, EventType, MinuteOffset, ParticipantType
        FROM (VALUES
            (1, 'Session Created',  -10, 'System'),
            (2, 'Patient Joined',    -3, 'Patient'),
            (3, 'Provider Joined',   -1, 'Provider'),
            (4, 'Session Started',    0, 'System'),
            (5, 'Session Ended',     25, 'System')
        ) s(SequenceNumber, EventType, MinuteOffset, ParticipantType)
    )
    INSERT INTO Telehealth.SessionEvent
    (
        VirtualVisitID, EventSequenceNumber, EventType,
        EventDateTimeUTC, ParticipantType, ParticipantID,
        EventDescription
    )
    SELECT
        v.VirtualVisitID,
        s.SequenceNumber,
        CASE
            WHEN v.VisitStatus = 'No Show' AND s.SequenceNumber > 1 THEN 'Session Ended'
            ELSE s.EventType
        END,
        DATEADD(MINUTE,
            CASE WHEN v.VisitStatus = 'No Show' AND s.SequenceNumber > 1
                 THEN 5 ELSE s.MinuteOffset END,
            v.ScheduledStartDateTimeUTC),
        CASE WHEN v.VisitStatus = 'No Show' AND s.SequenceNumber > 1
             THEN 'System' ELSE s.ParticipantType END,
        CASE
            WHEN s.ParticipantType = 'Patient' THEN v.PatientID
            WHEN s.ParticipantType = 'Provider' THEN v.ProviderID
            ELSE NULL
        END,
        N'Deterministic synthetic telehealth session event'
    FROM Telehealth.VirtualVisit v
    CROSS JOIN Slots s
    WHERE (v.VisitStatus <> 'No Show' OR s.SequenceNumber IN (1,2))
      AND NOT EXISTS
      (
          SELECT 1
          FROM Telehealth.SessionEvent se
          WHERE se.VirtualVisitID = v.VirtualVisitID
            AND se.EventSequenceNumber = s.SequenceNumber
      );

    COMMIT TRANSACTION;
    PRINT 'Section 9 complete: Telehealth.SessionEvent generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 9 failed: Telehealth.SessionEvent.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 10: Telehealth.Device
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH P AS
    (
        SELECT TOP (150)
            PatientID,
            ROW_NUMBER() OVER (ORDER BY PatientID) AS rn
        FROM Clinical.Patient
        ORDER BY PatientID
    )
    INSERT INTO Telehealth.Device
    (
        PatientID, DeviceIdentifier, DeviceType, Manufacturer,
        ModelNumber, SerialNumber, FirmwareVersion,
        AssignedDate, ActivatedDate, DeviceStatus, IsActive
    )
    SELECT
        p.PatientID,
        'DEV-' + RIGHT('000000' + CAST(p.rn AS VARCHAR(10)), 6),
        CASE p.rn % 5
            WHEN 0 THEN 'Blood Pressure Monitor'
            WHEN 1 THEN 'Glucose Meter'
            WHEN 2 THEN 'Pulse Oximeter'
            WHEN 3 THEN 'Weight Scale'
            ELSE 'Wearable'
        END,
        N'HealthPulse Devices',
        N'HP-' + CAST((p.rn % 5) + 100 AS NVARCHAR(10)),
        'SN-' + RIGHT('000000' + CAST(p.rn AS VARCHAR(10)), 6),
        N'1.0.' + CAST(p.rn % 10 AS NVARCHAR(10)),
        DATEADD(DAY, -(p.rn % 300), CAST('2024-01-01' AS DATE)),
        DATEADD(DAY, 1 - (p.rn % 300), CAST('2024-01-01' AS DATE)),
        'Active',
        1
    FROM P p
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Telehealth.Device d
        WHERE d.DeviceIdentifier =
              'DEV-' + RIGHT('000000' + CAST(p.rn AS VARCHAR(10)), 6)
    );

    COMMIT TRANSACTION;
    PRINT 'Section 10 complete: Telehealth.Device generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 10 failed: Telehealth.Device.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 11: Telehealth.DeviceReading
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH Slots AS
    (
        SELECT slot FROM (VALUES (0),(1),(2),(3),(4),(5),(6)) s(slot)
    ),
    D AS
    (
        SELECT DeviceID, PatientID, DeviceType,
               ROW_NUMBER() OVER (ORDER BY DeviceID) AS rn
        FROM Telehealth.Device
    )
    INSERT INTO Telehealth.DeviceReading
    (
        DeviceID, PatientID, EncounterID, ReadingDateTimeUTC,
        ReadingType, NumericValue, UnitOfMeasure,
        SecondaryNumericValue, SecondaryUnitOfMeasure,
        IsAbnormal, DataSource, ReceivedDateTimeUTC
    )
    SELECT
        d.DeviceID,
        d.PatientID,
        NULL,
        DATEADD(DAY, -s.slot, CAST('2024-12-31T10:00:00' AS DATETIME2(3))),
        CASE d.DeviceType
            WHEN 'Blood Pressure Monitor' THEN 'Blood Pressure'
            WHEN 'Glucose Meter' THEN 'Blood Glucose'
            WHEN 'Pulse Oximeter' THEN 'Oxygen Saturation'
            WHEN 'Weight Scale' THEN 'Weight'
            ELSE 'Heart Rate'
        END,
        CASE d.DeviceType
            WHEN 'Blood Pressure Monitor' THEN CAST(110 + ((d.rn + s.slot) % 45) AS DECIMAL(12,3))
            WHEN 'Glucose Meter' THEN CAST(80 + ((d.rn + s.slot) % 150) AS DECIMAL(12,3))
            WHEN 'Pulse Oximeter' THEN CAST(92 + ((d.rn + s.slot) % 8) AS DECIMAL(12,3))
            WHEN 'Weight Scale' THEN CAST(55 + ((d.rn + s.slot) % 60) AS DECIMAL(12,3))
            ELSE CAST(60 + ((d.rn + s.slot) % 50) AS DECIMAL(12,3))
        END,
        CASE d.DeviceType
            WHEN 'Blood Pressure Monitor' THEN 'mmHg'
            WHEN 'Glucose Meter' THEN 'mg/dL'
            WHEN 'Pulse Oximeter' THEN '%'
            WHEN 'Weight Scale' THEN 'kg'
            ELSE 'bpm'
        END,
        CASE WHEN d.DeviceType = 'Blood Pressure Monitor'
             THEN CAST(70 + ((d.rn + s.slot) % 25) AS DECIMAL(12,3))
             ELSE NULL END,
        CASE WHEN d.DeviceType = 'Blood Pressure Monitor' THEN 'mmHg' ELSE NULL END,
        CASE
            WHEN d.DeviceType = 'Glucose Meter' AND 80 + ((d.rn + s.slot) % 150) >= 180 THEN 1
            WHEN d.DeviceType = 'Pulse Oximeter' AND 92 + ((d.rn + s.slot) % 8) < 94 THEN 1
            WHEN d.DeviceType = 'Blood Pressure Monitor' AND 110 + ((d.rn + s.slot) % 45) >= 140 THEN 1
            ELSE 0
        END,
        'Bluetooth',
        DATEADD(MINUTE, 2,
            DATEADD(DAY, -s.slot, CAST('2024-12-31T10:00:00' AS DATETIME2(3))))
    FROM D d
    CROSS JOIN Slots s
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Telehealth.DeviceReading r
        WHERE r.DeviceID = d.DeviceID
          AND r.ReadingDateTimeUTC =
              DATEADD(DAY, -s.slot, CAST('2024-12-31T10:00:00' AS DATETIME2(3)))
    );

    COMMIT TRANSACTION;
    PRINT 'Section 11 complete: Telehealth.DeviceReading generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 11 failed: Telehealth.DeviceReading.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 12: Telehealth.WaitlistQueue
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO Telehealth.WaitlistQueue
    (
        VirtualVisitID, PatientID, ProviderID, DepartmentID,
        QueueEnteredDateTimeUTC, QueueCalledDateTimeUTC,
        QueueExitedDateTimeUTC, QueueStatus, PriorityLevel, ExitReason
    )
    SELECT
        v.VirtualVisitID,
        v.PatientID,
        v.ProviderID,
        v.DepartmentID,
        DATEADD(MINUTE, -10, v.ScheduledStartDateTimeUTC),
        CASE WHEN v.VisitStatus = 'No Show' THEN NULL
             ELSE DATEADD(MINUTE, -2, v.ScheduledStartDateTimeUTC) END,
        CASE WHEN v.VisitStatus = 'No Show'
             THEN DATEADD(MINUTE, 15, v.ScheduledStartDateTimeUTC)
             ELSE DATEADD(MINUTE, 1, v.ScheduledStartDateTimeUTC) END,
        CASE WHEN v.VisitStatus = 'No Show' THEN 'No Show' ELSE 'Completed' END,
        CASE WHEN v.VirtualVisitID % 20 = 0 THEN 'High' ELSE 'Normal' END,
        CASE WHEN v.VisitStatus = 'No Show' THEN N'Patient did not join' ELSE N'Admitted to visit' END
    FROM Telehealth.VirtualVisit v
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Telehealth.WaitlistQueue q
        WHERE q.VirtualVisitID = v.VirtualVisitID
    );

    COMMIT TRANSACTION;
    PRINT 'Section 12 complete: Telehealth.WaitlistQueue generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 12 failed: Telehealth.WaitlistQueue.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 13: Insurance.PatientCoverage
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH P AS
    (
        SELECT PatientID,
               ROW_NUMBER() OVER (ORDER BY PatientID) AS rn
        FROM Clinical.Patient
    ),
    Plans AS
    (
        SELECT InsurancePlanID,
               ROW_NUMBER() OVER (ORDER BY InsurancePlanID) - 1 AS rn,
               COUNT(*) OVER () AS cnt
        FROM Insurance.InsurancePlan
    )
    INSERT INTO Insurance.PatientCoverage
    (
        PatientID, InsurancePlanID, MemberNumber, GroupNumber,
        SubscriberPatientID, RelationshipToSubscriber,
        CoveragePriority, EffectiveStartDate, CoverageStatus, IsActive
    )
    SELECT
        p.PatientID,
        pl.InsurancePlanID,
        'MEM-' + RIGHT('000000' + CAST(p.rn AS VARCHAR(10)), 6),
        'GRP-' + RIGHT('000' + CAST((p.rn % 25) + 1 AS VARCHAR(10)), 3),
        p.PatientID,
        'Self',
        'Primary',
        CAST('2024-01-01' AS DATE),
        'Active',
        1
    FROM P p
    JOIN Plans pl ON pl.rn = (p.rn - 1) % pl.cnt
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Insurance.PatientCoverage pc
        WHERE pc.InsurancePlanID = pl.InsurancePlanID
          AND pc.MemberNumber =
              'MEM-' + RIGHT('000000' + CAST(p.rn AS VARCHAR(10)), 6)
    );

    COMMIT TRANSACTION;
    PRINT 'Section 13 complete: Insurance.PatientCoverage generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 13 failed: Insurance.PatientCoverage.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 14: Insurance.Claim
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH E AS
    (
        SELECT TOP (1000)
            e.EncounterID, e.PatientID, e.ProviderID, e.HospitalID,
            e.AdmissionDateTimeUTC, e.DischargeDateTimeUTC,
            ROW_NUMBER() OVER (ORDER BY e.EncounterID) AS rn
        FROM Clinical.Encounter e
        ORDER BY e.EncounterID
    )
    INSERT INTO Insurance.Claim
    (
        ClaimNumber, PatientID, PatientCoverageID, EncounterID,
        ProviderID, HospitalID, ClaimType,
        ServiceStartDate, ServiceEndDate,
        SubmissionDateTimeUTC, AdjudicationDateTimeUTC, ClaimStatus
    )
    SELECT
        'CLM-' + RIGHT('000000' + CAST(e.rn AS VARCHAR(10)), 6),
        e.PatientID,
        pc.PatientCoverageID,
        e.EncounterID,
        e.ProviderID,
        e.HospitalID,
        CASE WHEN e.rn % 5 = 0 THEN 'Institutional' ELSE 'Professional' END,
        CAST(e.AdmissionDateTimeUTC AS DATE),
        CAST(e.DischargeDateTimeUTC AS DATE),
        DATEADD(DAY, 2, e.DischargeDateTimeUTC),
        DATEADD(DAY, 12, e.DischargeDateTimeUTC),
        CASE e.rn % 10
            WHEN 0 THEN 'Denied'
            WHEN 1 THEN 'Partially Approved'
            WHEN 2 THEN 'Submitted'
            ELSE 'Approved'
        END
    FROM E e
    CROSS APPLY
    (
        SELECT TOP (1) pc.PatientCoverageID
        FROM Insurance.PatientCoverage pc
        WHERE pc.PatientID = e.PatientID
          AND pc.IsActive = 1
        ORDER BY pc.CoveragePriority, pc.PatientCoverageID
    ) pc
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Insurance.Claim c
        WHERE c.ClaimNumber =
              'CLM-' + RIGHT('000000' + CAST(e.rn AS VARCHAR(10)), 6)
    );

    COMMIT TRANSACTION;
    PRINT 'Section 14 complete: Insurance.Claim generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 14 failed: Insurance.Claim.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 15: Insurance.ClaimLine
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH Slots AS
    (
        SELECT slot FROM (VALUES (1),(2)) s(slot)
    ),
    C AS
    (
        SELECT ClaimID, ClaimNumber, ServiceStartDate, ClaimStatus,
               ROW_NUMBER() OVER (ORDER BY ClaimID) AS rn
        FROM Insurance.Claim
    )
    INSERT INTO Insurance.ClaimLine
    (
        ClaimID, LineNumber, ProcedureCode, DiagnosisPointer,
        ServiceDate, Units, ChargeAmount, AllowedAmount,
        PaidAmount, PatientResponsibilityAmount, AdjustmentAmount,
        LineStatus, DenialReasonCode
    )
    SELECT
        c.ClaimID,
        s.slot,
        CASE (c.rn + s.slot) % 6
            WHEN 0 THEN '99213'
            WHEN 1 THEN '99283'
            WHEN 2 THEN '93000'
            WHEN 3 THEN '80053'
            WHEN 4 THEN '85025'
            ELSE '36415'
        END,
        '1',
        c.ServiceStartDate,
        CAST(1 AS DECIMAL(12,3)),
        CAST(100 + ((c.rn + s.slot) % 400) AS DECIMAL(18,2)),
        CAST(80 + ((c.rn + s.slot) % 250) AS DECIMAL(18,2)),
        CASE WHEN c.ClaimStatus = 'Denied' THEN CAST(0 AS DECIMAL(18,2))
             ELSE CAST(60 + ((c.rn + s.slot) % 180) AS DECIMAL(18,2)) END,
        CAST(20 + ((c.rn + s.slot) % 70) AS DECIMAL(18,2)),
        CAST(5 + ((c.rn + s.slot) % 30) AS DECIMAL(18,2)),
        CASE WHEN c.ClaimStatus = 'Denied' THEN 'Denied'
             WHEN c.ClaimStatus = 'Partially Approved' THEN 'Partially Approved'
             ELSE 'Approved' END,
        CASE WHEN c.ClaimStatus = 'Denied' THEN 'CO-50' ELSE NULL END
    FROM C c
    CROSS JOIN Slots s
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Insurance.ClaimLine cl
        WHERE cl.ClaimID = c.ClaimID
          AND cl.LineNumber = s.slot
    );

    COMMIT TRANSACTION;
    PRINT 'Section 15 complete: Insurance.ClaimLine generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 15 failed: Insurance.ClaimLine.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 16: Billing.PatientAccount
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH P AS
    (
        SELECT PatientID,
               ROW_NUMBER() OVER (ORDER BY PatientID) AS rn
        FROM Clinical.Patient
    )
    INSERT INTO Billing.PatientAccount
    (
        AccountNumber, PatientID, AccountStatus, BillingPreference,
        PreferredCommunicationMethod,
        IsFinancialAssistanceEligible, IsActive
    )
    SELECT
        'ACCT-' + RIGHT('000000' + CAST(p.rn AS VARCHAR(10)), 6),
        p.PatientID,
        'Active',
        CASE p.rn % 3 WHEN 0 THEN 'Paper' WHEN 1 THEN 'Electronic' ELSE 'Both' END,
        CASE p.rn % 5
            WHEN 0 THEN 'Mail'
            WHEN 1 THEN 'Email'
            WHEN 2 THEN 'SMS'
            WHEN 3 THEN 'Portal'
            ELSE 'Phone'
        END,
        CASE WHEN p.rn % 8 = 0 THEN 1 ELSE 0 END,
        1
    FROM P p
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Billing.PatientAccount pa
        WHERE pa.AccountNumber =
              'ACCT-' + RIGHT('000000' + CAST(p.rn AS VARCHAR(10)), 6)
    );

    COMMIT TRANSACTION;
    PRINT 'Section 16 complete: Billing.PatientAccount generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 16 failed: Billing.PatientAccount.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 17: Billing.Invoice
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH C AS
    (
        SELECT TOP (1000)
            c.ClaimID, c.ClaimNumber, c.PatientID, c.EncounterID,
            c.ServiceEndDate, c.ClaimStatus,
            ROW_NUMBER() OVER (ORDER BY c.ClaimID) AS rn
        FROM Insurance.Claim c
        ORDER BY c.ClaimID
    )
    INSERT INTO Billing.Invoice
    (
        InvoiceNumber, PatientAccountID, PatientID,
        EncounterID, ClaimID, InvoiceDate, DueDate,
        InvoiceStatus, StatementCycle
    )
    SELECT
        'INV-' + RIGHT('000000' + CAST(c.rn AS VARCHAR(10)), 6),
        pa.PatientAccountID,
        c.PatientID,
        c.EncounterID,
        c.ClaimID,
        DATEADD(DAY, 1, c.ServiceEndDate),
        DATEADD(DAY, 31, c.ServiceEndDate),
        CASE
            WHEN c.rn % 10 = 0 THEN 'Overdue'
            WHEN c.rn % 4 = 0 THEN 'Partially Paid'
            ELSE 'Issued'
        END,
        CASE WHEN c.rn % 10 = 0 THEN 'First Reminder' ELSE 'Initial' END
    FROM C c
    JOIN Billing.PatientAccount pa
      ON pa.PatientID = c.PatientID
     AND pa.IsActive = 1
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Billing.Invoice i
        WHERE i.InvoiceNumber =
              'INV-' + RIGHT('000000' + CAST(c.rn AS VARCHAR(10)), 6)
    );

    COMMIT TRANSACTION;
    PRINT 'Section 17 complete: Billing.Invoice generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 17 failed: Billing.Invoice.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 18: Billing.InvoiceLine
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO Billing.InvoiceLine
    (
        InvoiceID, LineNumber, ClaimLineID, EncounterID,
        ServiceDate, LineType, [Description], ProcedureCode,
        Quantity, UnitAmount, LineAmount
    )
    SELECT
        i.InvoiceID,
        cl.LineNumber,
        cl.ClaimLineID,
        i.EncounterID,
        cl.ServiceDate,
        'Charge',
        N'Healthcare service charge',
        cl.ProcedureCode,
        cl.Units,
        cl.ChargeAmount,
        cl.ChargeAmount * cl.Units
    FROM Billing.Invoice i
    JOIN Insurance.ClaimLine cl
      ON cl.ClaimID = i.ClaimID
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Billing.InvoiceLine il
        WHERE il.InvoiceID = i.InvoiceID
          AND il.LineNumber = cl.LineNumber
    );

    COMMIT TRANSACTION;
    PRINT 'Section 18 complete: Billing.InvoiceLine generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 18 failed: Billing.InvoiceLine.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 19: Billing.Payment and PaymentAllocation
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH I AS
    (
        SELECT TOP (800)
            i.InvoiceID, i.PatientAccountID, i.PatientID, i.InvoiceDate,
            ROW_NUMBER() OVER (ORDER BY i.InvoiceID) AS rn,
            SUM(il.LineAmount) AS InvoiceAmount
        FROM Billing.Invoice i
        JOIN Billing.InvoiceLine il ON il.InvoiceID = i.InvoiceID
        GROUP BY i.InvoiceID, i.PatientAccountID, i.PatientID, i.InvoiceDate
        ORDER BY i.InvoiceID
    )
    INSERT INTO Billing.Payment
    (
        PaymentNumber, PatientAccountID, PatientID,
        PaymentDateTimeUTC, PaymentAmount, PaymentSource,
        PaymentMethod, PaymentStatus, TransactionReference
    )
    SELECT
        'PAY-' + RIGHT('000000' + CAST(i.rn AS VARCHAR(10)), 6),
        i.PatientAccountID,
        i.PatientID,
        DATEADD(DAY, 10, CAST(i.InvoiceDate AS DATETIME2(3))),
        CAST(CASE WHEN i.rn % 4 = 0 THEN i.InvoiceAmount * 0.50
                  ELSE i.InvoiceAmount * 0.80 END AS DECIMAL(18,2)),
        'Patient',
        CASE i.rn % 4
            WHEN 0 THEN 'Credit Card'
            WHEN 1 THEN 'Debit Card'
            WHEN 2 THEN 'ACH'
            ELSE 'Portal'
        END,
        'Posted',
        'TXN-' + RIGHT('000000' + CAST(i.rn AS VARCHAR(10)), 6)
    FROM I i
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Billing.Payment p
        WHERE p.PaymentNumber =
              'PAY-' + RIGHT('000000' + CAST(i.rn AS VARCHAR(10)), 6)
    );

    INSERT INTO Billing.PaymentAllocation
    (
        PaymentID, InvoiceID, AllocationSequenceNumber,
        AllocatedAmount, AllocationDateTimeUTC, AllocationStatus
    )
    SELECT
        p.PaymentID,
        i.InvoiceID,
        1,
        p.PaymentAmount,
        p.PaymentDateTimeUTC,
        'Posted'
    FROM Billing.Payment p
    JOIN Billing.Invoice i
      ON i.PatientAccountID = p.PatientAccountID
     AND i.PatientID = p.PatientID
    WHERE p.PaymentNumber LIKE 'PAY-%'
      AND i.InvoiceID =
          (
              SELECT MIN(i2.InvoiceID)
              FROM Billing.Invoice i2
              WHERE i2.PatientAccountID = p.PatientAccountID
                AND i2.PatientID = p.PatientID
          )
      AND NOT EXISTS
      (
          SELECT 1
          FROM Billing.PaymentAllocation pa
          WHERE pa.PaymentID = p.PaymentID
            AND pa.AllocationSequenceNumber = 1
      );

    COMMIT TRANSACTION;
    PRINT 'Section 19 complete: Billing.Payment and PaymentAllocation generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 19 failed: Billing.Payment or PaymentAllocation.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 20: Marketing preferences and campaigns
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO Marketing.PatientCommunicationPreference
    (
        PatientID, ChannelType, ConsentStatus, ConsentSource,
        ConsentDateTimeUTC, PreferredContactTime, IsActive
    )
    SELECT
        p.PatientID,
        'Email',
        'Opted In',
        'Web Portal',
        CAST('2024-01-01T10:00:00' AS DATETIME2(3)),
        CASE p.PatientID % 4
            WHEN 0 THEN 'Morning'
            WHEN 1 THEN 'Afternoon'
            WHEN 2 THEN 'Evening'
            ELSE 'Anytime'
        END,
        1
    FROM Clinical.Patient p
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Marketing.PatientCommunicationPreference pref
        WHERE pref.PatientID = p.PatientID
          AND pref.ChannelType = 'Email'
          AND pref.IsActive = 1
    );

    ;WITH H AS
    (
        SELECT TOP (1) HospitalID FROM Hospital.Hospital ORDER BY HospitalID
    )
    INSERT INTO Marketing.Campaign
    (
        CampaignCode, CampaignName, CampaignType, CampaignObjective,
        StartDate, EndDate, BudgetAmount,
        TargetAudienceDescription, CampaignStatus, HospitalID, IsActive
    )
    SELECT *
    FROM
    (
        SELECT 'CMP-DIABETES', N'Diabetes Education Outreach', 'Education',
               'Patient Education', CAST('2024-01-01' AS DATE), CAST('2024-03-31' AS DATE),
               CAST(25000 AS DECIMAL(18,2)), N'Adults with diabetes', 'Completed', h.HospitalID, 1
        FROM H h
        UNION ALL
        SELECT 'CMP-WELLNESS', N'Senior Wellness Campaign', 'Engagement',
               'Appointment Booking', CAST('2024-04-01' AS DATE), CAST('2024-06-30' AS DATE),
               CAST(18000 AS DECIMAL(18,2)), N'Adults age 65 and older', 'Completed', h.HospitalID, 1
        FROM H h
        UNION ALL
        SELECT 'CMP-CARDIAC', N'Cardiac Risk Awareness', 'Awareness',
               'Patient Education', CAST('2024-07-01' AS DATE), CAST('2024-09-30' AS DATE),
               CAST(30000 AS DECIMAL(18,2)), N'High-risk cardiac population', 'Completed', h.HospitalID, 1
        FROM H h
    ) v(CampaignCode, CampaignName, CampaignType, CampaignObjective,
        StartDate, EndDate, BudgetAmount, TargetAudienceDescription,
        CampaignStatus, HospitalID, IsActive)
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Marketing.Campaign c
        WHERE c.CampaignCode = v.CampaignCode
    );

    INSERT INTO Marketing.CampaignChannel
    (
        CampaignID, ChannelType, ChannelName,
        PlannedSpendAmount, ActualSpendAmount,
        DestinationURL, TrackingCode, IsActive
    )
    SELECT
        c.CampaignID,
        'Email',
        N'Primary Email',
        CAST(5000 AS DECIMAL(18,2)),
        CAST(4500 AS DECIMAL(18,2)),
        N'https://healthpulse.example/campaign',
        c.CampaignCode + '-EMAIL',
        1
    FROM Marketing.Campaign c
    WHERE c.CampaignCode LIKE 'CMP-%'
      AND NOT EXISTS
      (
          SELECT 1
          FROM Marketing.CampaignChannel cc
          WHERE cc.CampaignID = c.CampaignID
            AND cc.ChannelType = 'Email'
            AND cc.ChannelName = N'Primary Email'
      );

    COMMIT TRANSACTION;
    PRINT 'Section 20 complete: Marketing preferences and campaigns generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 20 failed: Marketing preferences or campaigns.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 21: Marketing interactions and acquisitions
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH P AS
    (
        SELECT PatientID,
               ROW_NUMBER() OVER (ORDER BY PatientID) AS rn
        FROM Clinical.Patient
    ),
    C AS
    (
        SELECT c.CampaignID, cc.CampaignChannelID, c.StartDate,
               ROW_NUMBER() OVER (ORDER BY c.CampaignID) - 1 AS rn,
               COUNT(*) OVER () AS cnt
        FROM Marketing.Campaign c
        JOIN Marketing.CampaignChannel cc
          ON cc.CampaignID = c.CampaignID
        WHERE c.CampaignCode LIKE 'CMP-%'
    )
    INSERT INTO Marketing.CampaignInteraction
    (
        CampaignID, CampaignChannelID, PatientID, EncounterID,
        InteractionType, InteractionDateTimeUTC,
        InteractionStatus, ExternalMessageID, SourceSystem
    )
    SELECT
        c.CampaignID,
        c.CampaignChannelID,
        p.PatientID,
        NULL,
        CASE p.rn % 10
            WHEN 0 THEN 'Converted'
            WHEN 1 THEN 'Clicked'
            WHEN 2 THEN 'Opened'
            ELSE 'Delivered'
        END,
        DATEADD(DAY, p.rn % 60, CAST(c.StartDate AS DATETIME2(3))),
        'Success',
        'MSG-' + RIGHT('000000' + CAST(p.rn AS VARCHAR(10)), 6),
        'SyntheticGenerator'
    FROM P p
    JOIN C c ON c.rn = (p.rn - 1) % c.cnt
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Marketing.CampaignInteraction ci
        WHERE ci.SourceSystem = 'SyntheticGenerator'
          AND ci.ExternalMessageID =
              'MSG-' + RIGHT('000000' + CAST(p.rn AS VARCHAR(10)), 6)
    );

    INSERT INTO Marketing.PatientAcquisition
    (
        PatientID, ReferralSourceID, CampaignID,
        CampaignInteractionID, FirstEncounterID,
        AcquisitionDate, AcquisitionChannel,
        AttributionModel, AcquisitionStatus,
        AcquisitionCost, ExternalLeadID
    )
    SELECT
        p.PatientID,
        rs.ReferralSourceID,
        ci.CampaignID,
        ci.CampaignInteractionID,
        fe.EncounterID,
        CAST(ci.InteractionDateTimeUTC AS DATE),
        'Email',
        'First Touch',
        CASE WHEN ci.InteractionType = 'Converted' THEN 'Converted' ELSE 'Qualified' END,
        CAST(25 + (p.PatientID % 75) AS DECIMAL(18,2)),
        'LEAD-' + RIGHT('000000' + CAST(p.PatientID AS VARCHAR(10)), 6)
    FROM Clinical.Patient p
    CROSS APPLY
    (
        SELECT TOP (1) rs.ReferralSourceID
        FROM Marketing.ReferralSource rs
        ORDER BY rs.ReferralSourceID
    ) rs
    CROSS APPLY
    (
        SELECT TOP (1) ci.CampaignInteractionID, ci.CampaignID,
                       ci.InteractionDateTimeUTC, ci.InteractionType
        FROM Marketing.CampaignInteraction ci
        WHERE ci.PatientID = p.PatientID
        ORDER BY ci.InteractionDateTimeUTC, ci.CampaignInteractionID
    ) ci
    OUTER APPLY
    (
        SELECT TOP (1) e.EncounterID
        FROM Clinical.Encounter e
        WHERE e.PatientID = p.PatientID
        ORDER BY e.AdmissionDateTimeUTC, e.EncounterID
    ) fe
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Marketing.PatientAcquisition pa
        WHERE pa.PatientID = p.PatientID
    );

    COMMIT TRANSACTION;
    PRINT 'Section 21 complete: Marketing interactions and acquisitions generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 21 failed: Marketing interactions or acquisitions.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 22: AI.Prediction
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH E AS
    (
        SELECT TOP (1500)
            e.EncounterID, e.PatientID, e.DischargeDateTimeUTC,
            ROW_NUMBER() OVER (ORDER BY e.EncounterID) AS rn
        FROM Clinical.Encounter e
        ORDER BY e.EncounterID
    ),
    MV AS
    (
        SELECT mv.ModelVersionID,
               ROW_NUMBER() OVER (ORDER BY mv.ModelVersionID) - 1 AS rn,
               COUNT(*) OVER () AS cnt
        FROM AI.ModelVersion mv
    )
    INSERT INTO AI.Prediction
    (
        ModelVersionID, PatientID, EncounterID,
        PredictionDateTimeUTC, PredictionType,
        PredictedClass, ProbabilityScore, RiskScore,
        ThresholdUsed, PredictionStatus,
        InputSnapshotJSON, ExplanationJSON
    )
    SELECT
        mv.ModelVersionID,
        e.PatientID,
        e.EncounterID,
        DATEADD(HOUR, 1, e.DischargeDateTimeUTC),
        'Classification',
        CASE WHEN (e.rn % 100) / 100.0 >= 0.50 THEN N'High Risk' ELSE N'Low Risk' END,
        CAST((e.rn % 100) / 100.0 AS DECIMAL(9,8)),
        CAST((e.rn % 100) / 10.0 AS DECIMAL(9,6)),
        CAST(0.50000000 AS DECIMAL(9,8)),
        'Generated',
        N'{"source":"synthetic","featureCount":5}',
        N'{"method":"deterministic-demo","topFeature":"prior_utilization"}'
    FROM E e
    JOIN MV mv ON mv.rn = (e.rn - 1) % mv.cnt
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM AI.Prediction p
        WHERE p.ModelVersionID = mv.ModelVersionID
          AND p.EncounterID = e.EncounterID
          AND p.PredictionDateTimeUTC = DATEADD(HOUR, 1, e.DischargeDateTimeUTC)
    );

    COMMIT TRANSACTION;
    PRINT 'Section 22 complete: AI.Prediction generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 22 failed: AI.Prediction.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 23: AI outcomes, metrics, and monitoring
==========================================================*/
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH P AS
    (
        SELECT TOP (800)
            PredictionID, PredictionDateTimeUTC, PredictedClass,
            ROW_NUMBER() OVER (ORDER BY PredictionID) AS rn
        FROM AI.Prediction
        WHERE PredictionStatus = 'Generated'
        ORDER BY PredictionID
    )
    INSERT INTO AI.PredictionOutcome
    (
        PredictionID, OutcomeType, ActualClass,
        OutcomeDateTimeUTC, OutcomeSource, IsFinalOutcome, Notes
    )
    SELECT
        p.PredictionID,
        CASE WHEN p.rn % 5 = 0 THEN 'Refuted' ELSE 'Confirmed' END,
        CASE WHEN p.rn % 5 = 0
             THEN CASE WHEN p.PredictedClass = N'High Risk' THEN N'Low Risk' ELSE N'High Risk' END
             ELSE p.PredictedClass END,
        DATEADD(DAY, 30, p.PredictionDateTimeUTC),
        'EHR',
        1,
        N'Synthetic validation outcome'
    FROM P p
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM AI.PredictionOutcome po
        WHERE po.PredictionID = p.PredictionID
    );

    ;WITH Metrics AS
    (
        SELECT MetricName, MetricValue
        FROM (VALUES
            ('AUROC', CAST(0.84000000 AS DECIMAL(19,8))),
            ('Accuracy', CAST(0.79000000 AS DECIMAL(19,8))),
            ('Precision', CAST(0.76000000 AS DECIMAL(19,8))),
            ('Recall', CAST(0.73000000 AS DECIMAL(19,8))),
            ('F1 Score', CAST(0.74500000 AS DECIMAL(19,8))),
            ('Brier Score', CAST(0.16000000 AS DECIMAL(19,8)))
        ) m(MetricName, MetricValue)
    )
    INSERT INTO AI.ModelPerformanceMetric
    (
        ModelVersionID, MetricName, MetricValue,
        EvaluationDataset, EvaluationStartDate,
        EvaluationEndDate, PatientPopulationSegment,
        ThresholdValue, SampleSize, CalculatedDateTimeUTC
    )
    SELECT
        mv.ModelVersionID,
        m.MetricName,
        m.MetricValue,
        'Production',
        CAST('2024-01-01' AS DATE),
        CAST('2024-12-31' AS DATE),
        N'All Patients',
        CASE WHEN m.MetricName IN ('Precision','Recall','F1 Score')
             THEN CAST(0.50000000 AS DECIMAL(9,8)) ELSE NULL END,
        1500,
        CAST('2025-01-05T00:00:00' AS DATETIME2(3))
    FROM AI.ModelVersion mv
    CROSS JOIN Metrics m
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM AI.ModelPerformanceMetric pm
        WHERE pm.ModelVersionID = mv.ModelVersionID
          AND pm.MetricName = m.MetricName
          AND pm.EvaluationDataset = 'Production'
          AND pm.EvaluationStartDate = CAST('2024-01-01' AS DATE)
          AND pm.EvaluationEndDate = CAST('2024-12-31' AS DATE)
          AND pm.PatientPopulationSegment = N'All Patients'
    );

    INSERT INTO AI.ModelMonitoringEvent
    (
        ModelVersionID, EventDateTimeUTC, EventType, Severity,
        MetricName, ObservedValue, ExpectedMinimum, ExpectedMaximum,
        PopulationSegment, EventDescription, ResolutionStatus
    )
    SELECT
        mv.ModelVersionID,
        DATEADD(DAY, ROW_NUMBER() OVER (ORDER BY mv.ModelVersionID),
                CAST('2025-01-10T00:00:00' AS DATETIME2(3))),
        CASE ROW_NUMBER() OVER (ORDER BY mv.ModelVersionID) % 3
            WHEN 0 THEN 'Data Drift'
            WHEN 1 THEN 'Performance Degradation'
            ELSE 'Bias Alert'
        END,
        CASE WHEN ROW_NUMBER() OVER (ORDER BY mv.ModelVersionID) % 2 = 0
             THEN 'High' ELSE 'Medium' END,
        'AUROC',
        CAST(0.70 AS DECIMAL(19,8)),
        CAST(0.75 AS DECIMAL(19,8)),
        CAST(1.00 AS DECIMAL(19,8)),
        N'All Patients',
        N'Synthetic monitoring alert for portfolio demonstration',
        'Open'
    FROM AI.ModelVersion mv
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM AI.ModelMonitoringEvent me
        WHERE me.ModelVersionID = mv.ModelVersionID
          AND me.EventDescription =
              N'Synthetic monitoring alert for portfolio demonstration'
    );

    COMMIT TRANSACTION;
    PRINT 'Section 23 complete: AI outcomes, metrics, and monitoring generated.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT 'Section 23 failed: AI outcomes, metrics, or monitoring.';
    THROW;
END CATCH;
GO


/*==========================================================
  FINAL VALIDATION
==========================================================*/
USE HealthPulseAI;
GO

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    SUM(p.rows) AS [RowCount]
FROM sys.tables t
JOIN sys.schemas s
    ON s.schema_id = t.schema_id
JOIN sys.partitions p
    ON p.object_id = t.object_id
   AND p.index_id IN (0,1)
WHERE s.name IN
(
    'Clinical',
    'Telehealth',
    'Insurance',
    'Billing',
    'Marketing',
    'AI'
)
GROUP BY
    s.name,
    t.name
ORDER BY
    s.name,
    t.name;
GO

SELECT
    OBJECT_SCHEMA_NAME(parent_object_id) AS SchemaName,
    OBJECT_NAME(parent_object_id) AS TableName,
    name AS ForeignKeyName,
    is_disabled,
    is_not_trusted
FROM sys.foreign_keys
WHERE is_disabled = 1
   OR is_not_trusted = 1;
GO

SELECT
    (SELECT COUNT(*) FROM Clinical.Patient) AS Patients,
    (SELECT COUNT(*) FROM Clinical.Encounter) AS Encounters,
    (SELECT COUNT(*) FROM Telehealth.VirtualVisit) AS TelehealthVisits,
    (SELECT COUNT(*) FROM Insurance.Claim) AS Claims,
    (SELECT COUNT(*) FROM Billing.Invoice) AS Invoices,
    (SELECT COUNT(*) FROM Billing.Payment) AS Payments,
    (SELECT COUNT(*) FROM Marketing.Campaign) AS Campaigns,
    (SELECT COUNT(*) FROM Marketing.CampaignInteraction) AS Interactions,
    (SELECT COUNT(*) FROM AI.Prediction) AS Predictions,
    (SELECT COUNT(*) FROM AI.PredictionOutcome) AS Outcomes;
GO

PRINT 'Synthetic healthcare data processed successfully.';
GO