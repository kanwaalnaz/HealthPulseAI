/*==========================================================
  HealthPulse AI
  Script: 005_Clinical_Integrity_Improvements.sql
  Purpose:
    Strengthen relationships between hospitals, providers,
    encounters, patients, diagnoses, procedures, medication
    orders, and vital-sign records.
==========================================================*/

USE HealthPulseAI;
GO

SET XACT_ABORT ON;
GO


/*==========================================================
  1. Support composite provider-to-hospital relationships
==========================================================*/

IF NOT EXISTS
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

    PRINT 'Added provider-hospital composite unique constraint.';
END
ELSE
BEGIN
    PRINT 'Provider-hospital composite unique constraint already exists.';
END;
GO


/*==========================================================
  2. Support encounter-patient composite relationships
==========================================================*/

IF NOT EXISTS
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

    PRINT 'Added encounter-patient composite unique constraint.';
END
ELSE
BEGIN
    PRINT 'Encounter-patient composite unique constraint already exists.';
END;
GO


/*==========================================================
  3. Ensure encounter provider belongs to encounter hospital
==========================================================*/

IF EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_Encounter_Provider'
      AND parent_object_id = OBJECT_ID('Clinical.Encounter')
)
BEGIN
    ALTER TABLE Clinical.Encounter
    DROP CONSTRAINT FK_Encounter_Provider;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_Encounter_Provider_Hospital'
      AND parent_object_id = OBJECT_ID('Clinical.Encounter')
)
BEGIN
    ALTER TABLE Clinical.Encounter WITH CHECK
    ADD CONSTRAINT FK_Encounter_Provider_Hospital
        FOREIGN KEY (ProviderID, HospitalID)
        REFERENCES Hospital.Provider (ProviderID, HospitalID);

    ALTER TABLE Clinical.Encounter
    CHECK CONSTRAINT FK_Encounter_Provider_Hospital;

    PRINT 'Added encounter provider-hospital consistency rule.';
END;
GO


/*==========================================================
  4. Diagnosis must belong to the same patient as encounter
==========================================================*/

IF EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_Diagnosis_Encounter'
      AND parent_object_id = OBJECT_ID('Clinical.Diagnosis')
)
BEGIN
    ALTER TABLE Clinical.Diagnosis
    DROP CONSTRAINT FK_Diagnosis_Encounter;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_Diagnosis_Encounter_Patient'
      AND parent_object_id = OBJECT_ID('Clinical.Diagnosis')
)
BEGIN
    ALTER TABLE Clinical.Diagnosis WITH CHECK
    ADD CONSTRAINT FK_Diagnosis_Encounter_Patient
        FOREIGN KEY (EncounterID, PatientID)
        REFERENCES Clinical.Encounter (EncounterID, PatientID);

    ALTER TABLE Clinical.Diagnosis
    CHECK CONSTRAINT FK_Diagnosis_Encounter_Patient;

    PRINT 'Added diagnosis encounter-patient consistency rule.';
END;
GO


USE HealthPulseAI;
GO

/*==========================================================
  Correct Procedure encounter-patient integrity
==========================================================*/

IF EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_Procedure_Encounter'
      AND parent_object_id = OBJECT_ID('Clinical.[Procedure]')
)
BEGIN
    ALTER TABLE Clinical.[Procedure]
    DROP CONSTRAINT FK_Procedure_Encounter;

    PRINT 'Removed old Procedure encounter foreign key.';
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_Procedure_Encounter_Patient'
      AND parent_object_id = OBJECT_ID('Clinical.[Procedure]')
)
BEGIN
    ALTER TABLE Clinical.[Procedure] WITH CHECK
    ADD CONSTRAINT FK_Procedure_Encounter_Patient
        FOREIGN KEY (EncounterID, PatientID)
        REFERENCES Clinical.Encounter (EncounterID, PatientID);

    ALTER TABLE Clinical.[Procedure]
    CHECK CONSTRAINT FK_Procedure_Encounter_Patient;

    PRINT 'Added procedure encounter-patient consistency rule.';
END
ELSE
BEGIN
    PRINT 'Procedure encounter-patient consistency rule already exists.';
END;
GO

/*==========================================================
  6. Medication order encounter must belong to patient
     EncounterID is nullable, so non-encounter prescriptions
     are still allowed.
==========================================================*/

IF EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_MedicationOrder_Encounter'
      AND parent_object_id = OBJECT_ID('Clinical.MedicationOrder')
)
BEGIN
    ALTER TABLE Clinical.MedicationOrder
    DROP CONSTRAINT FK_MedicationOrder_Encounter;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_MedicationOrder_Encounter_Patient'
      AND parent_object_id = OBJECT_ID('Clinical.MedicationOrder')
)
BEGIN
    ALTER TABLE Clinical.MedicationOrder WITH CHECK
    ADD CONSTRAINT FK_MedicationOrder_Encounter_Patient
        FOREIGN KEY (EncounterID, PatientID)
        REFERENCES Clinical.Encounter (EncounterID, PatientID);

    ALTER TABLE Clinical.MedicationOrder
    CHECK CONSTRAINT FK_MedicationOrder_Encounter_Patient;

    PRINT 'Added medication-order encounter-patient consistency rule.';
END;
GO


/*==========================================================
  7. Vitals encounter must belong to patient
==========================================================*/

IF EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_Vitals_Encounter'
      AND parent_object_id = OBJECT_ID('Clinical.Vitals')
)
BEGIN
    ALTER TABLE Clinical.Vitals
    DROP CONSTRAINT FK_Vitals_Encounter;
END;
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.foreign_keys
    WHERE name = 'FK_Vitals_Encounter_Patient'
      AND parent_object_id = OBJECT_ID('Clinical.Vitals')
)
BEGIN
    ALTER TABLE Clinical.Vitals WITH CHECK
    ADD CONSTRAINT FK_Vitals_Encounter_Patient
        FOREIGN KEY (EncounterID, PatientID)
        REFERENCES Clinical.Encounter (EncounterID, PatientID);

    ALTER TABLE Clinical.Vitals
    CHECK CONSTRAINT FK_Vitals_Encounter_Patient;

    PRINT 'Added vitals encounter-patient consistency rule.';
END;
GO


/*==========================================================
  8. Medication dose must be positive when provided
==========================================================*/

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_MedicationOrder_Dose'
      AND parent_object_id = OBJECT_ID('Clinical.MedicationOrder')
)
BEGIN
    ALTER TABLE Clinical.MedicationOrder
    ADD CONSTRAINT CK_MedicationOrder_Dose
        CHECK (Dose IS NULL OR Dose > 0);

    PRINT 'Added positive medication-dose rule.';
END;
GO


/*==========================================================
  9. Improve quantity validation
==========================================================*/

IF EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_MedicationOrder_Quantity'
      AND parent_object_id = OBJECT_ID('Clinical.MedicationOrder')
)
BEGIN
    ALTER TABLE Clinical.MedicationOrder
    DROP CONSTRAINT CK_MedicationOrder_Quantity;
END;
GO

ALTER TABLE Clinical.MedicationOrder
ADD CONSTRAINT CK_MedicationOrder_Quantity
    CHECK (Quantity IS NULL OR Quantity > 0);
GO


/*==========================================================
  10. Keep telehealth fields logically consistent
==========================================================*/

IF NOT EXISTS
(
    SELECT 1
    FROM sys.check_constraints
    WHERE name = 'CK_Encounter_TelehealthConsistency'
      AND parent_object_id = OBJECT_ID('Clinical.Encounter')
)
BEGIN
    ALTER TABLE Clinical.Encounter
    ADD CONSTRAINT CK_Encounter_TelehealthConsistency
        CHECK
        (
            (EncounterType = 'Telehealth' AND IsTelehealth = 1)
            OR
            (EncounterType <> 'Telehealth' AND IsTelehealth = 0)
        );

    PRINT 'Added telehealth encounter consistency rule.';
END;
GO


PRINT 'Clinical integrity improvements completed successfully.';
GO