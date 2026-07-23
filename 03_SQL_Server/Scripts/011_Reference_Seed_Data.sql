/*==========================================================
  HealthPulse AI
  Script: 011_Reference_Seed_Data.sql
  Purpose: Insert stable reference, configuration, and master
           data only. No large synthetic transactional volumes.

  Seeded areas:
    1. Hospital master data (hospitals, locations, departments,
       specialties, providers, provider specialties)
    2. Clinical reference data (medication drug master)
    3. Telehealth reference data (documented no-op)
    4. Insurance reference data (payers, insurance plans)
    5. Billing reference data (documented no-op)
    6. Marketing reference data (referral sources, audience segments)
    7. AI reference data (models, model versions, feature
       definitions, model-feature bridge)

  Design standards:
    - Fully rerunnable and idempotent (INSERT ... SELECT ... WHERE NOT EXISTS)
    - Rows matched by stable business keys, never identity values
    - Foreign keys resolved via lookups on stable codes/names
    - No MERGE, DELETE, TRUNCATE, or constraint disabling
    - Transactions per logical section with TRY/CATCH + THROW
    - Only values permitted by existing CHECK constraints
    - Realistic but fictional data; no real PHI
==========================================================*/

USE HealthPulseAI;
GO

SET XACT_ABORT ON;
GO


IF OBJECT_ID('Hospital.Hospital', 'U') IS NULL
   OR OBJECT_ID('Hospital.Location', 'U') IS NULL
   OR OBJECT_ID('Hospital.Department', 'U') IS NULL
   OR OBJECT_ID('Hospital.Specialty', 'U') IS NULL
   OR OBJECT_ID('Hospital.Provider', 'U') IS NULL
   OR OBJECT_ID('Hospital.ProviderSpecialty', 'U') IS NULL
   OR OBJECT_ID('Clinical.Medication', 'U') IS NULL
   OR OBJECT_ID('Insurance.Payer', 'U') IS NULL
   OR OBJECT_ID('Insurance.InsurancePlan', 'U') IS NULL
   OR OBJECT_ID('Marketing.ReferralSource', 'U') IS NULL
   OR OBJECT_ID('Marketing.AudienceSegment', 'U') IS NULL
   OR OBJECT_ID('AI.Model', 'U') IS NULL
   OR OBJECT_ID('AI.ModelVersion', 'U') IS NULL
   OR OBJECT_ID('AI.FeatureDefinition', 'U') IS NULL
   OR OBJECT_ID('AI.ModelFeature', 'U') IS NULL
BEGIN
    THROW 50001, 'Required HealthPulseAI schema tables are missing. Run scripts 003 through 010 first.', 1;
END;
GO


/*==========================================================
  SECTION 1: Hospital master data
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    /* ---- 1a. Hospitals ---- */
    INSERT INTO Hospital.Hospital
    (
        HospitalCode,
        HospitalName,
        LegalName,
        HospitalType,
        NumberOfBeds,
        IsActive
    )
    SELECT
        v.HospitalCode,
        v.HospitalName,
        v.LegalName,
        v.HospitalType,
        v.NumberOfBeds,
        1
    FROM
    (
        VALUES
            ('HOSP-NORTH', N'HealthPulse North Medical Center',    N'HealthPulse North Medical Center, LLC',    'Teaching',  450),
            ('HOSP-SOUTH', N'HealthPulse South Regional Hospital',  N'HealthPulse South Regional Hospital, LLC',  'General',   300),
            ('HOSP-WEST',  N'HealthPulse West Community Clinic',    N'HealthPulse West Community Clinic, LLC',    'Community',  50)
    ) AS v
    (
        HospitalCode, HospitalName, LegalName, HospitalType,
        NumberOfBeds
    )
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Hospital.Hospital h
        WHERE h.HospitalCode = v.HospitalCode
    );

    /* ---- 1b. Locations (one primary campus per hospital) ---- */
    INSERT INTO Hospital.Location
    (
        HospitalID,
        LocationCode,
        LocationName,
        AddressLine1,
        City,
        StateProvince,
        PostalCode,
        Country,
        IsPrimary,
        IsActive
    )
    SELECT
        h.HospitalID,
        v.LocationCode,
        v.LocationName,
        v.AddressLine1,
        v.City,
        v.StateProvince,
        v.PostalCode,
        v.Country,
        v.IsPrimary,
        1
    FROM
    (
        VALUES
            ('HOSP-NORTH', 'LOC-NORTH-MAIN', N'North Main Campus',   N'100 Cascade Avenue',  N'Seattle',  N'Washington', '98101', N'USA', 1),
            ('HOSP-SOUTH', 'LOC-SOUTH-MAIN', N'South Main Campus',   N'2200 Desert Parkway', N'Phoenix',  N'Arizona',    '85004', N'USA', 1),
            ('HOSP-WEST',  'LOC-WEST-MAIN',  N'West Community Site', N'55 Harbor Street',    N'Portland', N'Oregon',     '97201', N'USA', 1)
    ) AS v
    (
        HospitalCode, LocationCode, LocationName,
        AddressLine1, City, StateProvince, PostalCode, Country, IsPrimary
    )
    JOIN Hospital.Hospital h
        ON h.HospitalCode = v.HospitalCode
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Hospital.Location l
        WHERE l.HospitalID = h.HospitalID
          AND l.LocationCode = v.LocationCode
    );

    /* ---- 1c. Departments (composite: location belongs to hospital) ---- */
    INSERT INTO Hospital.Department
    (
        HospitalID,
        LocationID,
        DepartmentCode,
        DepartmentName,
        DepartmentType,
        IsActive
    )
    SELECT
        h.HospitalID,
        l.LocationID,
        v.DepartmentCode,
        v.DepartmentName,
        v.DepartmentType,
        1
    FROM
    (
        VALUES
            ('HOSP-NORTH', 'LOC-NORTH-MAIN', 'DEPT-CARD', N'Cardiology',        'Clinical'),
            ('HOSP-NORTH', 'LOC-NORTH-MAIN', 'DEPT-ED',   N'Emergency',         'Clinical'),
            ('HOSP-SOUTH', 'LOC-SOUTH-MAIN', 'DEPT-IM',   N'Internal Medicine', 'Clinical'),
            ('HOSP-SOUTH', 'LOC-SOUTH-MAIN', 'DEPT-RAD',  N'Radiology',         'Diagnostic'),
            ('HOSP-WEST',  'LOC-WEST-MAIN',  'DEPT-FM',   N'Family Medicine',   'Clinical'),
            ('HOSP-WEST',  'LOC-WEST-MAIN',  'DEPT-BH',   N'Behavioral Health', 'Clinical')
    ) AS v
    (
        HospitalCode, LocationCode, DepartmentCode, DepartmentName, DepartmentType
    )
    JOIN Hospital.Hospital h
        ON h.HospitalCode = v.HospitalCode
    JOIN Hospital.Location l
        ON l.HospitalID = h.HospitalID
       AND l.LocationCode = v.LocationCode
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Hospital.Department d
        WHERE d.HospitalID = h.HospitalID
          AND d.DepartmentCode = v.DepartmentCode
    );

    /* ---- 1d. Specialties (reference catalog) ---- */
    INSERT INTO Hospital.Specialty
    (
        SpecialtyCode,
        SpecialtyName,
        Description,
        IsActive
    )
    SELECT
        v.SpecialtyCode,
        v.SpecialtyName,
        v.Description,
        1
    FROM
    (
        VALUES
            ('CARD', N'Cardiology',          N'Diagnosis and treatment of heart conditions'),
            ('EM',   N'Emergency Medicine',  N'Acute and emergency care'),
            ('IM',   N'Internal Medicine',   N'Comprehensive adult medical care'),
            ('RAD',  N'Radiology',           N'Diagnostic and interventional imaging'),
            ('FM',   N'Family Medicine',     N'Primary care for all ages'),
            ('PSY',  N'Psychiatry',          N'Mental and behavioral health'),
            ('ENDO', N'Endocrinology',       N'Hormonal and metabolic disorders'),
            ('PED',  N'Pediatrics',          N'Medical care for infants and children')
    ) AS v
    (
        SpecialtyCode, SpecialtyName, Description
    )
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Hospital.Specialty s
        WHERE s.SpecialtyCode = v.SpecialtyCode
    );

    /* ---- 1e. Providers (composite: department belongs to hospital) ---- */
    INSERT INTO Hospital.Provider
    (
        HospitalID,
        DepartmentID,
        ProviderCode,
        NPINumber,
        FirstName,
        LastName,
        Title,
        Gender,
        ProviderType,
        IsActive
    )
    SELECT
        h.HospitalID,
        d.DepartmentID,
        v.ProviderCode,
        v.NPINumber,
        v.FirstName,
        v.LastName,
        v.Title,
        v.Gender,
        v.ProviderType,
        1
    FROM
    (
        VALUES
            ('HOSP-NORTH', 'DEPT-CARD', 'PRV-N001', '1000000001', N'Sarah',  N'Chen',    N'MD', 'F', 'Physician'),
            ('HOSP-NORTH', 'DEPT-ED',   'PRV-N002', '1000000002', N'Marcus', N'Lee',     N'MD', 'M', 'Physician'),
            ('HOSP-NORTH', 'DEPT-CARD', 'PRV-N003', '1000000003', N'Aisha',  N'Patel',   N'MD', 'F', 'Physician'),
            ('HOSP-SOUTH', 'DEPT-IM',   'PRV-S001', '1000000004', N'David',  N'Kim',     N'MD', 'M', 'Physician'),
            ('HOSP-SOUTH', 'DEPT-RAD',  'PRV-S002', '1000000005', N'Elena',  N'Rossi',   N'MD', 'F', 'Physician'),
            ('HOSP-SOUTH', 'DEPT-IM',   'PRV-S003', '1000000006', N'James',  N'Carter',  N'MD', 'M', 'Specialist'),
            ('HOSP-SOUTH', 'DEPT-RAD',  'PRV-S004', '1000000007', N'Nina',   N'Alvarez', N'MD', 'F', 'Physician'),
            ('HOSP-WEST',  'DEPT-FM',   'PRV-W001', '1000000008', N'Robert', N'Brooks',  N'MD', 'M', 'Physician'),
            ('HOSP-WEST',  'DEPT-BH',   'PRV-W002', '1000000009', N'Priya',  N'Nair',    N'MD', 'F', 'Physician'),
            ('HOSP-WEST',  'DEPT-FM',   'PRV-W003', '1000000010', N'Thomas', N'Wright',  N'MD', 'M', 'Physician')
    ) AS v
    (
        HospitalCode, DepartmentCode, ProviderCode, NPINumber,
        FirstName, LastName, Title, Gender, ProviderType
    )
    JOIN Hospital.Hospital h
        ON h.HospitalCode = v.HospitalCode
    JOIN Hospital.Department d
        ON d.HospitalID = h.HospitalID
       AND d.DepartmentCode = v.DepartmentCode
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Hospital.Provider p
        WHERE p.HospitalID = h.HospitalID
          AND p.ProviderCode = v.ProviderCode
    );

    /* ---- 1f. Provider specialties (one active primary per provider) ---- */
    INSERT INTO Hospital.ProviderSpecialty
    (
        ProviderID,
        SpecialtyID,
        IsPrimary,
        IsActive
    )
    SELECT
        p.ProviderID,
        s.SpecialtyID,
        v.IsPrimary,
        1
    FROM
    (
        VALUES
            ('PRV-N001', 'CARD', 1),
            ('PRV-N002', 'EM',   1),
            ('PRV-N003', 'CARD', 1),
            ('PRV-S001', 'IM',   1),
            ('PRV-S002', 'RAD',  1),
            ('PRV-S003', 'ENDO', 1),
            ('PRV-S004', 'RAD',  1),
            ('PRV-W001', 'FM',   1),
            ('PRV-W002', 'PSY',  1),
            ('PRV-W003', 'FM',   1)
    ) AS v
    (
        ProviderCode, SpecialtyCode, IsPrimary
    )
    JOIN Hospital.Provider p
        ON p.ProviderCode = v.ProviderCode
    JOIN Hospital.Specialty s
        ON s.SpecialtyCode = v.SpecialtyCode
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Hospital.ProviderSpecialty ps
        WHERE ps.ProviderID = p.ProviderID
          AND ps.SpecialtyID = s.SpecialtyID
    );

    COMMIT TRANSACTION;
    PRINT 'Section 1 complete: Hospital master data seeded.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    PRINT 'Section 1 failed: Hospital master data.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 2: Clinical reference data
  Only Clinical.Medication is a non-transactional reference
  catalog. Diagnosis / Procedure require encounters and are
  therefore out of scope for reference seeding. Encounter
  types are enforced as CHECK values, not data rows.
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    INSERT INTO Clinical.Medication
    (
        MedicationCode,
        MedicationName,
        GenericName,
        BrandName,
        DrugClass,
        Strength,
        DosageForm,
        Manufacturer,
        IsControlledSubstance,
        IsActive
    )
    SELECT
        v.MedicationCode,
        v.MedicationName,
        v.GenericName,
        v.BrandName,
        v.DrugClass,
        v.Strength,
        v.DosageForm,
        v.Manufacturer,
        v.IsControlledSubstance,
        1
    FROM
    (
        VALUES
            ('MED-LISINOPRIL-10', N'Lisinopril 10 mg',        N'Lisinopril',        N'Prinivil',  N'ACE Inhibitor',   N'10 mg',  N'Tablet',    N'Generic Pharma',   0),
            ('MED-METFORMIN-500', N'Metformin 500 mg',        N'Metformin',         N'Glucophage', N'Biguanide',      N'500 mg', N'Tablet',    N'Generic Pharma',   0),
            ('MED-ATORVA-20',     N'Atorvastatin 20 mg',      N'Atorvastatin',      N'Lipitor',   N'Statin',          N'20 mg',  N'Tablet',    N'Generic Pharma',   0),
            ('MED-AMLODIPINE-5',  N'Amlodipine 5 mg',         N'Amlodipine',        N'Norvasc',   N'Calcium Channel Blocker', N'5 mg', N'Tablet', N'Generic Pharma', 0),
            ('MED-METOPROLOL-50', N'Metoprolol 50 mg',        N'Metoprolol',        N'Lopressor', N'Beta Blocker',    N'50 mg',  N'Tablet',    N'Generic Pharma',   0),
            ('MED-INSULIN-GLAR',  N'Insulin Glargine',        N'Insulin Glargine',  N'Lantus',    N'Antidiabetic',    N'100 U/mL', N'Injection', N'Generic Pharma', 0),
            ('MED-ALBUTEROL-HFA', N'Albuterol HFA',           N'Albuterol',         N'ProAir',    N'Bronchodilator',  N'90 mcg', N'Inhaler',   N'Generic Pharma',   0),
            ('MED-SERTRALINE-50', N'Sertraline 50 mg',        N'Sertraline',        N'Zoloft',    N'SSRI',            N'50 mg',  N'Tablet',    N'Generic Pharma',   0),
            ('MED-WARFARIN-5',    N'Warfarin 5 mg',           N'Warfarin',          N'Coumadin',  N'Anticoagulant',   N'5 mg',   N'Tablet',    N'Generic Pharma',   0),
            ('MED-OMEPRAZOLE-20', N'Omeprazole 20 mg',        N'Omeprazole',        N'Prilosec',  N'Proton Pump Inhibitor', N'20 mg', N'Capsule', N'Generic Pharma', 0)
    ) AS v
    (
        MedicationCode, MedicationName, GenericName, BrandName, DrugClass,
        Strength, DosageForm, Manufacturer, IsControlledSubstance
    )
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Clinical.Medication m
        WHERE m.MedicationCode = v.MedicationCode
    );

    COMMIT TRANSACTION;
    PRINT 'Section 2 complete: Clinical reference data seeded.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    PRINT 'Section 2 failed: Clinical reference data.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 3: Telehealth reference data
  The Telehealth schema (VirtualVisit, SessionEvent, Device,
  DeviceReading, WaitlistQueue) contains only transactional
  tables that depend on patients, encounters, or visits.
  Visit types, modalities, and statuses are enforced as CHECK
  constraint values rather than stored reference rows, so there
  is no stable reference/master data to seed here.
==========================================================*/

PRINT 'Section 3 skipped: Telehealth has no reference/master tables to seed.';
GO


/*==========================================================
  SECTION 4: Insurance reference data
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    /* ---- 4a. Payers ---- */
    INSERT INTO Insurance.Payer
    (
        PayerCode,
        PayerName,
        PayerType,
        TaxIdentifier,
        PhoneNumber,
        WebsiteURL,
        IsGovernmentPayer,
        IsActive
    )
    SELECT
        v.PayerCode,
        v.PayerName,
        v.PayerType,
        v.TaxIdentifier,
        v.PhoneNumber,
        v.WebsiteURL,
        v.IsGovernmentPayer,
        1
    FROM
    (
        VALUES
            ('PAYER-AETNA',    N'Aetna Health',                'Commercial', '900000001', '800-555-0101', N'https://www.example-aetna.test',    0),
            ('PAYER-BCBS',     N'Blue Cross Blue Shield',      'Commercial', '900000002', '800-555-0102', N'https://www.example-bcbs.test',     0),
            ('PAYER-MEDICARE', N'Medicare',                    'Medicare',   '900000003', '800-555-0103', N'https://www.example-medicare.test', 1),
            ('PAYER-MEDICAID', N'State Medicaid Program',      'Medicaid',   '900000004', '800-555-0104', N'https://www.example-medicaid.test', 1)
    ) AS v
    (
        PayerCode, PayerName, PayerType, TaxIdentifier,
        PhoneNumber, WebsiteURL, IsGovernmentPayer
    )
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Insurance.Payer p
        WHERE p.PayerCode = v.PayerCode
    );

    /* ---- 4b. Insurance plans (PlanCode unique per payer) ---- */
    INSERT INTO Insurance.InsurancePlan
    (
        PayerID,
        PlanCode,
        PlanName,
        PlanType,
        NetworkType,
        EffectiveStartDate,
        IsActive
    )
    SELECT
        p.PayerID,
        v.PlanCode,
        v.PlanName,
        v.PlanType,
        v.NetworkType,
        v.EffectiveStartDate,
        1
    FROM
    (
        VALUES
            ('PAYER-AETNA',    'AET-PPO-GOLD',   N'Aetna PPO Gold',            'Medical', 'PPO',                   CAST('2024-01-01' AS DATE)),
            ('PAYER-AETNA',    'AET-HMO-SILVER', N'Aetna HMO Silver',          'Medical', 'HMO',                   CAST('2024-01-01' AS DATE)),
            ('PAYER-BCBS',     'BCBS-PPO-STD',   N'BCBS PPO Standard',         'Medical', 'PPO',                   CAST('2024-01-01' AS DATE)),
            ('PAYER-BCBS',     'BCBS-EPO-BASIC', N'BCBS EPO Basic',            'Medical', 'EPO',                   CAST('2024-01-01' AS DATE)),
            ('PAYER-MEDICARE', 'MCR-ADV-A',      N'Medicare Advantage Plan A', 'Medical', 'Medicare Advantage',    CAST('2024-01-01' AS DATE)),
            ('PAYER-MEDICAID', 'MCD-MGD-A',      N'Medicaid Managed Plan A',   'Medical', 'Medicaid Managed Care', CAST('2024-01-01' AS DATE))
    ) AS v
    (
        PayerCode, PlanCode, PlanName, PlanType, NetworkType, EffectiveStartDate
    )
    JOIN Insurance.Payer p
        ON p.PayerCode = v.PayerCode
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Insurance.InsurancePlan ip
        WHERE ip.PayerID = p.PayerID
          AND ip.PlanCode = v.PlanCode
    );

    COMMIT TRANSACTION;
    PRINT 'Section 4 complete: Insurance reference data seeded.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    PRINT 'Section 4 failed: Insurance reference data.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 5: Billing reference data
  The Billing schema (PatientAccount, Invoice, InvoiceLine,
  Payment, PaymentAllocation, Adjustment, Refund,
  AccountBalanceHistory) contains only transactional tables
  that depend on patients, accounts, claims, or invoices.
  There is no stable billing configuration/master table to
  seed, and patient invoices/payments are intentionally
  excluded from reference seeding.
==========================================================*/

PRINT 'Section 5 skipped: Billing has no reference/master tables to seed.';
GO


/*==========================================================
  SECTION 6: Marketing reference data
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    /* ---- 6a. Referral sources ---- */
    INSERT INTO Marketing.ReferralSource
    (
        ReferralSourceCode,
        ReferralSourceName,
        ReferralSourceType,
        OrganizationName,
        ContactName,
        PhoneNumber,
        Email,
        IsActive
    )
    SELECT
        v.ReferralSourceCode,
        v.ReferralSourceName,
        v.ReferralSourceType,
        v.OrganizationName,
        v.ContactName,
        v.PhoneNumber,
        v.Email,
        1
    FROM
    (
        VALUES
            ('REF-PROVIDER-NET',  N'Community Physician Network', 'Provider',  N'Community Physician Network', N'Referral Desk',   '800-555-0201', N'referrals@example-cpn.test'),
            ('REF-WEB-SEARCH',    N'Organic Web Search',          'Digital',   NULL,                           NULL,               NULL,           NULL),
            ('REF-EMPLOYER-A',    N'Regional Employer Group',     'Employer',  N'Regional Employer Group',     N'Benefits Office', '800-555-0202', N'benefits@example-reg.test'),
            ('REF-COMMUNITY-EVT', N'Community Health Fair',       'Community', N'City Health Coalition',       N'Events Team',     '800-555-0203', N'events@example-chc.test')
    ) AS v
    (
        ReferralSourceCode, ReferralSourceName, ReferralSourceType,
        OrganizationName, ContactName, PhoneNumber, Email
    )
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Marketing.ReferralSource r
        WHERE r.ReferralSourceCode = v.ReferralSourceCode
    );

    /* ---- 6b. Audience segments (valid DefinitionJSON) ---- */
    INSERT INTO Marketing.AudienceSegment
    (
        SegmentCode,
        SegmentName,
        SegmentDescription,
        SegmentType,
        DefinitionJSON,
        RefreshFrequency,
        EstimatedMemberCount,
        IsActive
    )
    SELECT
        v.SegmentCode,
        v.SegmentName,
        v.SegmentDescription,
        v.SegmentType,
        v.DefinitionJSON,
        v.RefreshFrequency,
        v.EstimatedMemberCount,
        1
    FROM
    (
        VALUES
            ('SEG-DIABETES-ADULTS',  N'Adult Diabetes Population',   N'Adults with a diabetes diagnosis',        'Clinical',    N'{"condition":"diabetes","ageMin":18}',        'Monthly',   1200),
            ('SEG-HIGH-RISK-CARD',   N'High-Risk Cardiac Patients',  N'Patients flagged as high cardiac risk',   'Clinical',    N'{"condition":"cardiac","riskLevel":"high"}',  'Weekly',     450),
            ('SEG-WELLNESS-SENIORS', N'Senior Wellness Outreach',    N'Members aged 65 and older for wellness',  'Demographic', N'{"ageMin":65}',                               'Quarterly', 3000)
    ) AS v
    (
        SegmentCode, SegmentName, SegmentDescription, SegmentType,
        DefinitionJSON, RefreshFrequency, EstimatedMemberCount
    )
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM Marketing.AudienceSegment a
        WHERE a.SegmentCode = v.SegmentCode
    );

    COMMIT TRANSACTION;
    PRINT 'Section 6 complete: Marketing reference data seeded.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    PRINT 'Section 6 failed: Marketing reference data.';
    THROW;
END CATCH;
GO


/*==========================================================
  SECTION 7: AI reference data
==========================================================*/

BEGIN TRY
    BEGIN TRANSACTION;

    /* ---- 7a. Models (OwnerProviderID NULL keeps owner/hospital rule valid) ---- */
    INSERT INTO AI.Model
    (
        ModelCode,
        ModelName,
        ModelDescription,
        ModelType,
        ClinicalUseCase,
        ProblemType,
        OwningHospitalID,
        ModelStatus,
        RiskLevel,
        IsRegulated,
        IsActive
    )
    SELECT
        v.ModelCode,
        v.ModelName,
        v.ModelDescription,
        v.ModelType,
        v.ClinicalUseCase,
        v.ProblemType,
        h.HospitalID,
        v.ModelStatus,
        v.RiskLevel,
        v.IsRegulated,
        1
    FROM
    (
        VALUES
            ('MODEL-READMIT-30D', N'30-Day Readmission Risk',        N'Predicts risk of unplanned readmission within 30 days of discharge.', 'Machine Learning', 'Inpatient readmission prevention',   'Binary Classification', 'HOSP-NORTH', 'Development', 'High',   0),
            ('MODEL-NOSHOW',      N'Appointment No-Show Prediction', N'Predicts likelihood a patient will miss a scheduled appointment.',     'Machine Learning', 'Outpatient scheduling optimization', 'Binary Classification', 'HOSP-NORTH', 'Development', 'Medium', 0),
            ('MODEL-DENIAL',      N'Claim Denial Risk',              N'Predicts likelihood an insurance claim will be denied.',              'Machine Learning', 'Revenue cycle denial prevention',    'Binary Classification', 'HOSP-NORTH', 'Development', 'Medium', 0)
    ) AS v
    (
        ModelCode, ModelName, ModelDescription, ModelType, ClinicalUseCase,
        ProblemType, HospitalCode, ModelStatus, RiskLevel, IsRegulated
    )
    JOIN Hospital.Hospital h
        ON h.HospitalCode = v.HospitalCode
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM AI.Model m
        WHERE m.ModelCode = v.ModelCode
    );

    /* ---- 7b. Model versions (development: no approval metadata) ---- */
    INSERT INTO AI.ModelVersion
    (
        ModelID,
        VersionNumber,
        AlgorithmName,
        FrameworkName,
        FrameworkVersion,
        TrainingRecordCount,
        FeatureCount,
        HyperparametersJSON,
        ApprovalStatus
    )
    SELECT
        m.ModelID,
        v.VersionNumber,
        v.AlgorithmName,
        v.FrameworkName,
        v.FrameworkVersion,
        v.TrainingRecordCount,
        v.FeatureCount,
        v.HyperparametersJSON,
        'Pending'
    FROM
    (
        VALUES
            ('MODEL-READMIT-30D', '1.0.0', N'Gradient Boosted Trees', 'scikit-learn', '1.4.0', CAST(50000 AS BIGINT), 8, N'{"learning_rate":0.05,"max_depth":6,"n_estimators":300}'),
            ('MODEL-NOSHOW',      '1.0.0', N'Logistic Regression',    'scikit-learn', '1.4.0', CAST(80000 AS BIGINT), 5, N'{"penalty":"l2","C":1.0}'),
            ('MODEL-DENIAL',      '1.0.0', N'Random Forest',          'scikit-learn', '1.4.0', CAST(65000 AS BIGINT), 5, N'{"n_estimators":250,"max_depth":12}')
    ) AS v
    (
        ModelCode, VersionNumber, AlgorithmName, FrameworkName, FrameworkVersion,
        TrainingRecordCount, FeatureCount, HyperparametersJSON
    )
    JOIN AI.Model m
        ON m.ModelCode = v.ModelCode
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM AI.ModelVersion mv
        WHERE mv.ModelID = m.ModelID
          AND mv.VersionNumber = v.VersionNumber
    );

    /* ---- 7c. Feature definitions (reference real project schemas/tables/columns) ---- */
    INSERT INTO AI.FeatureDefinition
    (
        FeatureCode,
        FeatureName,
        FeatureDescription,
        DataType,
        SourceSchema,
        SourceTable,
        SourceColumn,
        TransformationLogic,
        FeatureCategory,
        ContainsPHI,
        IsSensitive,
        IsActive
    )
    SELECT
        v.FeatureCode,
        v.FeatureName,
        v.FeatureDescription,
        v.DataType,
        v.SourceSchema,
        v.SourceTable,
        v.SourceColumn,
        v.TransformationLogic,
        v.FeatureCategory,
        v.ContainsPHI,
        v.IsSensitive,
        1
    FROM
    (
        VALUES
            ('FEAT-PATIENT-AGE',      N'Patient Age',                N'Patient age in years at time of scoring',        'Integer',     'Clinical',  'Patient',        'DateOfBirth',           N'Derived from DateOfBirth',                       'Demographic', 1, 1),
            ('FEAT-PATIENT-GENDER',   N'Patient Gender',             N'Patient administrative gender',                  'Categorical', 'Clinical',  'Patient',        'Gender',                NULL,                                             'Demographic', 1, 1),
            ('FEAT-ENCOUNTER-TYPE',   N'Encounter Type',             N'Type of the associated encounter',               'Categorical', 'Clinical',  'Encounter',      'EncounterType',         NULL,                                             'Utilization', 0, 0),
            ('FEAT-ENCOUNTER-LOS',    N'Length of Stay',             N'Inpatient length of stay in days',               'Decimal',     'Clinical',  'Encounter',      NULL,                    N'Derived from AdmissionDateTimeUTC and DischargeDateTimeUTC', 'Utilization', 0, 0),
            ('FEAT-PRIOR-ADMITS',     N'Prior Admissions',           N'Count of prior inpatient encounters',            'Integer',     'Clinical',  'Encounter',      NULL,                    N'Count of prior inpatient encounters for patient', 'Utilization', 0, 0),
            ('FEAT-DIAG-COUNT',       N'Diagnosis Count',            N'Number of diagnoses on the encounter',           'Integer',     'Clinical',  'Diagnosis',      NULL,                    N'Count of diagnoses per encounter',              'Clinical',    0, 0),
            ('FEAT-MED-COUNT',        N'Active Medication Count',    N'Number of active medication orders',             'Integer',     'Clinical',  'MedicationOrder',NULL,                   N'Count of active medication orders',             'Medication',  0, 0),
            ('FEAT-SYSTOLIC-BP',      N'Systolic Blood Pressure',    N'Most recent systolic blood pressure',            'Integer',     'Clinical',  'Vitals',         'SystolicBloodPressure', NULL,                                             'Vitals',      0, 0),
            ('FEAT-BLOOD-GLUCOSE',    N'Blood Glucose',              N'Most recent blood glucose measurement',          'Decimal',     'Clinical',  'Vitals',         'BloodGlucoseMgDL',      NULL,                                             'Vitals',      0, 0),
            ('FEAT-PAYER-TYPE',       N'Payer Type',                 N'Payer category for the patient coverage',        'Categorical', 'Insurance', 'Payer',          'PayerType',             NULL,                                             'Financial',   0, 0),
            ('FEAT-PLAN-NETWORK',     N'Plan Network Type',          N'Network type of the insurance plan',             'Categorical', 'Insurance', 'InsurancePlan',  'NetworkType',           NULL,                                             'Financial',   0, 0),
            ('FEAT-APPT-LEAD-DAYS',   N'Appointment Lead Days',      N'Days between scheduling and appointment',        'Integer',     'Telehealth','VirtualVisit',   NULL,                    N'Derived from scheduling and appointment dates', 'Temporal',    0, 0),
            ('FEAT-CLAIM-AMOUNT',     N'Claim Charge Amount',        N'Aggregated charge amount from claim lines',      'Decimal',     'Insurance', 'ClaimLine',      'ChargeAmount',          N'SUM(ChargeAmount) by ClaimID',                  'Financial',   0, 0),
            ('FEAT-PATIENT-DISTANCE', N'Distance to Facility',       N'Distance from patient address to facility',      'Decimal',     'Clinical',  'PatientAddress', NULL,                    N'Derived from geocoded address coordinates',     'Derived',     0, 0)
    ) AS v
    (
        FeatureCode, FeatureName, FeatureDescription, DataType, SourceSchema,
        SourceTable, SourceColumn, TransformationLogic, FeatureCategory,
        ContainsPHI, IsSensitive
    )
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM AI.FeatureDefinition f
        WHERE f.FeatureCode = v.FeatureCode
    );

    /* ---- 7d. Model-feature bridge (unique ModelVersionID + FeatureDefinitionID) ---- */
    INSERT INTO AI.ModelFeature
    (
        ModelVersionID,
        FeatureDefinitionID,
        FeatureRole,
        FeatureOrder,
        IsRequired
    )
    SELECT
        mv.ModelVersionID,
        f.FeatureDefinitionID,
        v.FeatureRole,
        v.FeatureOrder,
        v.IsRequired
    FROM
    (
        VALUES
            /* 30-Day Readmission Risk */
            ('MODEL-READMIT-30D', '1.0.0', 'FEAT-PATIENT-AGE',     'Input',               1, 1),
            ('MODEL-READMIT-30D', '1.0.0', 'FEAT-PATIENT-GENDER',  'Protected Attribute', 2, 0),
            ('MODEL-READMIT-30D', '1.0.0', 'FEAT-ENCOUNTER-LOS',   'Input',               3, 1),
            ('MODEL-READMIT-30D', '1.0.0', 'FEAT-PRIOR-ADMITS',    'Input',               4, 1),
            ('MODEL-READMIT-30D', '1.0.0', 'FEAT-DIAG-COUNT',      'Input',               5, 1),
            ('MODEL-READMIT-30D', '1.0.0', 'FEAT-MED-COUNT',       'Input',               6, 1),
            ('MODEL-READMIT-30D', '1.0.0', 'FEAT-SYSTOLIC-BP',     'Input',               7, 0),
            ('MODEL-READMIT-30D', '1.0.0', 'FEAT-PAYER-TYPE',      'Input',               8, 0),
            /* Appointment No-Show Prediction */
            ('MODEL-NOSHOW',      '1.0.0', 'FEAT-PATIENT-AGE',     'Input',               1, 1),
            ('MODEL-NOSHOW',      '1.0.0', 'FEAT-APPT-LEAD-DAYS',  'Input',               2, 1),
            ('MODEL-NOSHOW',      '1.0.0', 'FEAT-ENCOUNTER-TYPE',  'Input',               3, 1),
            ('MODEL-NOSHOW',      '1.0.0', 'FEAT-PATIENT-DISTANCE','Input',               4, 0),
            ('MODEL-NOSHOW',      '1.0.0', 'FEAT-PAYER-TYPE',      'Input',               5, 0),
            /* Claim Denial Risk */
            ('MODEL-DENIAL',      '1.0.0', 'FEAT-CLAIM-AMOUNT',    'Input',               1, 1),
            ('MODEL-DENIAL',      '1.0.0', 'FEAT-PAYER-TYPE',      'Input',               2, 1),
            ('MODEL-DENIAL',      '1.0.0', 'FEAT-PLAN-NETWORK',    'Input',               3, 1),
            ('MODEL-DENIAL',      '1.0.0', 'FEAT-DIAG-COUNT',      'Input',               4, 0),
            ('MODEL-DENIAL',      '1.0.0', 'FEAT-ENCOUNTER-TYPE',  'Input',               5, 0)
    ) AS v
    (
        ModelCode, VersionNumber, FeatureCode, FeatureRole, FeatureOrder, IsRequired
    )
    JOIN AI.Model m
        ON m.ModelCode = v.ModelCode
    JOIN AI.ModelVersion mv
        ON mv.ModelID = m.ModelID
       AND mv.VersionNumber = v.VersionNumber
    JOIN AI.FeatureDefinition f
        ON f.FeatureCode = v.FeatureCode
    WHERE NOT EXISTS
    (
        SELECT 1
        FROM AI.ModelFeature xf
        WHERE xf.ModelVersionID = mv.ModelVersionID
          AND xf.FeatureDefinitionID = f.FeatureDefinitionID
    );

    COMMIT TRANSACTION;
    PRINT 'Section 7 complete: AI reference data seeded.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0
        ROLLBACK TRANSACTION;
    PRINT 'Section 7 failed: AI reference data.';
    THROW;
END CATCH;
GO


/*==========================================================
  VALIDATION: Row counts by seeded table
==========================================================*/

SELECT 'Hospital.Hospital'            AS TableName, COUNT(*) AS RowCount_ FROM Hospital.Hospital
UNION ALL SELECT 'Hospital.Location',           COUNT(*) FROM Hospital.Location
UNION ALL SELECT 'Hospital.Department',         COUNT(*) FROM Hospital.Department
UNION ALL SELECT 'Hospital.Specialty',          COUNT(*) FROM Hospital.Specialty
UNION ALL SELECT 'Hospital.Provider',           COUNT(*) FROM Hospital.Provider
UNION ALL SELECT 'Hospital.ProviderSpecialty',  COUNT(*) FROM Hospital.ProviderSpecialty
UNION ALL SELECT 'Clinical.Medication',         COUNT(*) FROM Clinical.Medication
UNION ALL SELECT 'Insurance.Payer',             COUNT(*) FROM Insurance.Payer
UNION ALL SELECT 'Insurance.InsurancePlan',     COUNT(*) FROM Insurance.InsurancePlan
UNION ALL SELECT 'Marketing.ReferralSource',    COUNT(*) FROM Marketing.ReferralSource
UNION ALL SELECT 'Marketing.AudienceSegment',   COUNT(*) FROM Marketing.AudienceSegment
UNION ALL SELECT 'AI.Model',                    COUNT(*) FROM AI.Model
UNION ALL SELECT 'AI.ModelVersion',             COUNT(*) FROM AI.ModelVersion
UNION ALL SELECT 'AI.FeatureDefinition',        COUNT(*) FROM AI.FeatureDefinition
UNION ALL SELECT 'AI.ModelFeature',             COUNT(*) FROM AI.ModelFeature
ORDER BY TableName;
GO


/*==========================================================
  VALIDATION: Integrity checks (each must return zero rows)
==========================================================*/

/* 1. Orphaned providers (hospital missing) */
SELECT p.ProviderID, p.ProviderCode, p.HospitalID
FROM Hospital.Provider p
WHERE NOT EXISTS
(
    SELECT 1
    FROM Hospital.Hospital h
    WHERE h.HospitalID = p.HospitalID
);
GO

/* 2. Invalid provider/hospital combinations (department in another hospital) */
SELECT p.ProviderID, p.ProviderCode, p.HospitalID, d.DepartmentID, d.HospitalID AS DepartmentHospitalID
FROM Hospital.Provider p
JOIN Hospital.Department d
    ON d.DepartmentID = p.DepartmentID
WHERE d.HospitalID <> p.HospitalID;
GO

/* 3. Orphaned departments (hospital missing) */
SELECT d.DepartmentID, d.DepartmentCode, d.HospitalID
FROM Hospital.Department d
WHERE NOT EXISTS
(
    SELECT 1
    FROM Hospital.Hospital h
    WHERE h.HospitalID = d.HospitalID
);
GO

/* 4. Orphaned insurance plans (payer missing) */
SELECT ip.InsurancePlanID, ip.PlanCode, ip.PayerID
FROM Insurance.InsurancePlan ip
WHERE NOT EXISTS
(
    SELECT 1
    FROM Insurance.Payer p
    WHERE p.PayerID = ip.PayerID
);
GO

/* 5. Orphaned model versions (model missing) */
SELECT mv.ModelVersionID, mv.ModelID, mv.VersionNumber
FROM AI.ModelVersion mv
WHERE NOT EXISTS
(
    SELECT 1
    FROM AI.Model m
    WHERE m.ModelID = mv.ModelID
);
GO

/* 6. Orphaned model features (version or feature missing) */
SELECT mf.ModelFeatureID, mf.ModelVersionID, mf.FeatureDefinitionID
FROM AI.ModelFeature mf
WHERE NOT EXISTS
      (
          SELECT 1
          FROM AI.ModelVersion mv
          WHERE mv.ModelVersionID = mf.ModelVersionID
      )
   OR NOT EXISTS
      (
          SELECT 1
          FROM AI.FeatureDefinition f
          WHERE f.FeatureDefinitionID = mf.FeatureDefinitionID
      );
GO


PRINT 'Reference and master seed data processed successfully.';
GO