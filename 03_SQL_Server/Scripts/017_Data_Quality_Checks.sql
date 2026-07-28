/*==========================================================
  HealthPulse AI
  Script: 017_Data_Quality_Checks.sql
  Purpose:
    Production-style data quality validation framework for
    the HealthPulseAI healthcare analytics platform.

  Prerequisites:
    013_Analytics_Views.sql
    014_Executive_KPI_Views.sql

  Execution:
    Run the full script in SSMS.
    The final result set provides one row per quality check.

  Status:
    PASS    = no issues found
    WARNING = issues found that require review
==========================================================*/

USE HealthPulseAI;
GO

SET NOCOUNT ON;
GO

DROP TABLE IF EXISTS #DataQualityResults;
GO

CREATE TABLE #DataQualityResults
(
    CheckID             INT IDENTITY(1,1) PRIMARY KEY,
    QualityArea         VARCHAR(50)  NOT NULL,
    CheckName           VARCHAR(150) NOT NULL,
    IssueCount          BIGINT       NOT NULL,
    QualityStatus       VARCHAR(20)  NOT NULL,
    CheckDescription    VARCHAR(500) NOT NULL
);
GO


/*==========================================================
  SECTION 1 — PATIENT DATA QUALITY
==========================================================*/

DECLARE @IssueCount BIGINT;

/* Q1: Duplicate Medical Record Numbers */
SELECT @IssueCount = COUNT_BIG(*)
FROM
(
    SELECT MedicalRecordNumber
    FROM Analytics.vw_Patient360
    WHERE MedicalRecordNumber IS NOT NULL
    GROUP BY MedicalRecordNumber
    HAVING COUNT_BIG(*) > 1
) d;

INSERT INTO #DataQualityResults
(
    QualityArea, CheckName, IssueCount,
    QualityStatus, CheckDescription
)
VALUES
(
    'Patient',
    'Duplicate medical record numbers',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Identifies medical record numbers assigned to more than one patient.'
);


/* Q2: Missing Medical Record Numbers */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_Patient360
WHERE MedicalRecordNumber IS NULL
   OR LTRIM(RTRIM(MedicalRecordNumber)) = '';

INSERT INTO #DataQualityResults
VALUES
(
    'Patient',
    'Missing medical record numbers',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Patients should have a populated medical record number.'
);


/* Q3: Missing Patient Names */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_Patient360
WHERE FirstName IS NULL
   OR LTRIM(RTRIM(FirstName)) = ''
   OR LastName IS NULL
   OR LTRIM(RTRIM(LastName)) = '';

INSERT INTO #DataQualityResults
VALUES
(
    'Patient',
    'Missing patient names',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Identifies patient records with a missing first or last name.'
);


/* Q4: Future Dates of Birth */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_Patient360
WHERE DateOfBirth > CAST(GETDATE() AS DATE);

INSERT INTO #DataQualityResults
VALUES
(
    'Patient',
    'Future dates of birth',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'A patient date of birth cannot occur in the future.'
);


/* Q5: Implausible Patient Ages */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_Patient360
WHERE DateOfBirth IS NOT NULL
  AND
  (
      DATEDIFF(YEAR, DateOfBirth, GETDATE()) < 0
      OR DATEDIFF(YEAR, DateOfBirth, GETDATE()) > 120
  );

INSERT INTO #DataQualityResults
VALUES
(
    'Patient',
    'Implausible patient ages',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Flags calculated ages below zero or above 120 years.'
);


/*==========================================================
  SECTION 2 — ENCOUNTER DATA QUALITY
==========================================================*/

/* Q6: Duplicate Encounter IDs */
SELECT @IssueCount = COUNT_BIG(*)
FROM
(
    SELECT EncounterID
    FROM Analytics.vw_EncounterDetails
    GROUP BY EncounterID
    HAVING COUNT_BIG(*) > 1
) d;

INSERT INTO #DataQualityResults
VALUES
(
    'Encounter',
    'Duplicate encounter IDs',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Each healthcare encounter should have one unique encounter identifier.'
);


/* Q7: Missing Patient References */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_EncounterDetails
WHERE PatientID IS NULL;

INSERT INTO #DataQualityResults
VALUES
(
    'Encounter',
    'Missing patient references',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Every encounter should be associated with a patient.'
);


/* Q8: Missing Provider References */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_EncounterDetails
WHERE ProviderID IS NULL;

INSERT INTO #DataQualityResults
VALUES
(
    'Encounter',
    'Missing provider references',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Every encounter should be assigned to a provider.'
);


/* Q9: Missing Hospital References */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_EncounterDetails
WHERE HospitalID IS NULL;

INSERT INTO #DataQualityResults
VALUES
(
    'Encounter',
    'Missing hospital references',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Every encounter should be associated with a hospital.'
);


/* Q10: Future Encounter Dates */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_EncounterDetails
WHERE AdmissionDateTimeUTC > GETUTCDATE();

INSERT INTO #DataQualityResults
VALUES
(
    'Encounter',
    'Future encounter dates',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Historical encounter data should not contain future admission timestamps.'
);


/* Q11: Discharge Before Admission */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_EncounterDetails
WHERE DischargeDateTimeUTC IS NOT NULL
  AND DischargeDateTimeUTC < AdmissionDateTimeUTC;

INSERT INTO #DataQualityResults
VALUES
(
    'Encounter',
    'Discharge before admission',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Discharge timestamps must occur after admission timestamps.'
);


/*==========================================================
  SECTION 3 — CLAIM DATA QUALITY
==========================================================*/

/* Q12: Duplicate Claim IDs */
SELECT @IssueCount = COUNT_BIG(*)
FROM
(
    SELECT ClaimID
    FROM Analytics.vw_ClaimFinancials
    GROUP BY ClaimID
    HAVING COUNT_BIG(*) > 1
) d;

INSERT INTO #DataQualityResults
VALUES
(
    'Insurance',
    'Duplicate claim IDs',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Each insurance claim should have one unique claim identifier.'
);


/* Q13: Missing Payers */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_ClaimFinancials
WHERE PayerName IS NULL
   OR LTRIM(RTRIM(PayerName)) = '';

INSERT INTO #DataQualityResults
VALUES
(
    'Insurance',
    'Missing payer names',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Every insurance claim should identify its payer.'
);


/* Q14: Negative Claim Charges */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_ClaimFinancials
WHERE TotalChargeAmount < 0;

INSERT INTO #DataQualityResults
VALUES
(
    'Insurance',
    'Negative claim charges',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Claim charge amounts should not be negative.'
);


/* Q15: Paid Amount Exceeds Charge Amount */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_ClaimFinancials
WHERE ISNULL(TotalPaidAmount, 0) > ISNULL(TotalChargeAmount, 0);

INSERT INTO #DataQualityResults
VALUES
(
    'Insurance',
    'Claim payments exceed charges',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'The paid amount should not exceed the original claim charge without a documented adjustment.'
);


/* Q16: Denied Claims Missing Denial Reason */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_ClaimDenialAnalysis
WHERE IsDeniedClaim = 1
  AND
  (
      PrimaryDenialReasonCode IS NULL
      OR LTRIM(RTRIM(PrimaryDenialReasonCode)) = ''
  );

INSERT INTO #DataQualityResults
VALUES
(
    'Insurance',
    'Denied claims missing denial reason',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Denied claims should contain a denial reason code.'
);
/*==========================================================
  SECTION 4 — BILLING DATA QUALITY
==========================================================*/

/* Q17: Duplicate Invoice IDs */
SELECT @IssueCount = COUNT_BIG(*)
FROM
(
    SELECT InvoiceID
    FROM Analytics.vw_PatientBillingSummary
    GROUP BY InvoiceID
    HAVING COUNT_BIG(*) > 1
) d;

INSERT INTO #DataQualityResults
VALUES
(
    'Billing',
    'Duplicate invoice IDs',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Each invoice should have one unique invoice identifier.'
);



/* Q18: Negative Invoice Amounts */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_PatientBillingSummary
WHERE InvoiceAmount < 0;

INSERT INTO #DataQualityResults
VALUES
(
    'Billing',
    'Negative invoice amounts',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Invoice amounts should not be negative.'
);


/* Q19: Negative Outstanding Balances */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_PatientBillingSummary
WHERE OutstandingAmount < 0;

INSERT INTO #DataQualityResults
VALUES
(
    'Billing',
    'Negative outstanding balances',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Outstanding balances should not be negative unless explicitly treated as credits.'
);


/* Q20: Paid Amount Exceeds Invoice Amount */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_PatientBillingSummary
WHERE ISNULL(PaidAmount, 0) > ISNULL(InvoiceAmount, 0);

INSERT INTO #DataQualityResults
VALUES
(
    'Billing',
    'Invoice payments exceed invoice amount',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Paid amounts should not exceed invoice totals without a refund or credit workflow.'
);

/* Q21: Outstanding Balance Reconciliation */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_PatientBillingSummary
WHERE ABS
(
    ISNULL(InvoiceAmount, 0)
    - ISNULL(PaidAmount, 0)
    - ISNULL(OutstandingAmount, 0)
) > 0.01;

INSERT INTO #DataQualityResults
VALUES
(
    'Billing',
    'Outstanding balance reconciliation',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Checks whether invoice amount minus payments equals the outstanding balance.'
);
/*==========================================================
  SECTION 5 — TELEHEALTH DATA QUALITY
==========================================================*/

/* Q22: Duplicate Virtual Visit IDs */
SELECT @IssueCount = COUNT_BIG(*)
FROM
(
    SELECT VirtualVisitID
    FROM Analytics.vw_TelehealthPerformance
    GROUP BY VirtualVisitID
    HAVING COUNT_BIG(*) > 1
) d;

INSERT INTO #DataQualityResults
VALUES
(
    'Telehealth',
    'Duplicate virtual visit IDs',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Each virtual visit should have one unique visit identifier.'
);


/* Q23: Negative Technical Error Counts */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_TelehealthPerformance
WHERE TechnicalErrorCount < 0;

INSERT INTO #DataQualityResults
VALUES
(
    'Telehealth',
    'Negative technical error counts',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Technical error counts cannot be negative.'
);


/* Q24: Missing Telehealth Platforms */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_TelehealthPerformance
WHERE PlatformName IS NULL
   OR LTRIM(RTRIM(PlatformName)) = '';

INSERT INTO #DataQualityResults
VALUES
(
    'Telehealth',
    'Missing telehealth platforms',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Virtual visits should record the platform used.'
);


/* Q25: Future Scheduled Telehealth Visits */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_TelehealthPerformance
WHERE ScheduledStartDateTimeUTC > DATEADD(YEAR, 1, GETUTCDATE());

INSERT INTO #DataQualityResults
VALUES
(
    'Telehealth',
    'Telehealth visits scheduled over one year ahead',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Flags virtual visits scheduled unusually far into the future.'
);


/*==========================================================
  SECTION 6 — AI DATA QUALITY
==========================================================*/

/* Q26: Duplicate Prediction IDs */
SELECT @IssueCount = COUNT_BIG(*)
FROM
(
    SELECT PredictionID
    FROM Analytics.vw_AIPredictionPerformance
    GROUP BY PredictionID
    HAVING COUNT_BIG(*) > 1
) d;

INSERT INTO #DataQualityResults
VALUES
(
    'AI',
    'Duplicate prediction IDs',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Each AI prediction should have one unique prediction identifier.'
);


/* Q27: Missing Model Names */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_AIPredictionPerformance
WHERE ModelName IS NULL
   OR LTRIM(RTRIM(ModelName)) = '';

INSERT INTO #DataQualityResults
VALUES
(
    'AI',
    'Missing AI model names',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Every prediction should identify the model that generated it.'
);


/* Q28: Probability Outside 0–1 */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_AIPredictionPerformance
WHERE ProbabilityScore IS NOT NULL
  AND
  (
      ProbabilityScore < 0
      OR ProbabilityScore > 1
  );

INSERT INTO #DataQualityResults
VALUES
(
    'AI',
    'Probability scores outside valid range',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Prediction probabilities should be between zero and one.'
);


/* Q29: Risk Scores Outside Expected Range */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_AIPredictionPerformance
WHERE RiskScore IS NOT NULL
  AND
  (
      RiskScore < 0
      OR RiskScore > 100
  );

INSERT INTO #DataQualityResults
VALUES
(
    'AI',
    'Risk scores outside expected range',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Risk scores are expected to remain between zero and 100.'
);


/* Q30: Missing Predicted Classes */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_AIPredictionPerformance
WHERE PredictedClass IS NULL
   OR LTRIM(RTRIM(PredictedClass)) = '';

INSERT INTO #DataQualityResults
VALUES
(
    'AI',
    'Missing predicted classes',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Every AI prediction should have a predicted class.'
);


/* Q31: Missing Actual Classes for Evaluated Predictions */
SELECT @IssueCount = COUNT_BIG(*)
FROM Analytics.vw_AIPredictionPerformance
WHERE ConfusionMatrixCategory IS NOT NULL
  AND
  (
      ActualClass IS NULL
      OR LTRIM(RTRIM(ActualClass)) = ''
  );

INSERT INTO #DataQualityResults
VALUES
(
    'AI',
    'Missing actual classes for evaluated predictions',
    @IssueCount,
    CASE WHEN @IssueCount = 0 THEN 'PASS' ELSE 'WARNING' END,
    'Evaluated predictions should include an actual observed class.'
);


/*==========================================================
  SECTION 7 — ENTERPRISE DATA QUALITY SUMMARY
==========================================================*/

SELECT
    CheckID,
    QualityArea,
    CheckName,
    IssueCount,
    QualityStatus,
    CheckDescription
FROM #DataQualityResults
ORDER BY
    CASE QualityStatus
        WHEN 'WARNING' THEN 1
        ELSE 2
    END,
    QualityArea,
    CheckID;


/* Summary by quality area */
SELECT
    QualityArea,
    COUNT(*) AS TotalChecks,
    SUM(CASE WHEN QualityStatus = 'PASS' THEN 1 ELSE 0 END) AS PassedChecks,
    SUM(CASE WHEN QualityStatus = 'WARNING' THEN 1 ELSE 0 END) AS WarningChecks,
    SUM(IssueCount) AS TotalIssues,
    CAST
    (
        SUM(CASE WHEN QualityStatus = 'PASS' THEN 1.0 ELSE 0.0 END)
        * 100.0 / COUNT(*)
        AS DECIMAL(10,2)
    ) AS PassRatePercent
FROM #DataQualityResults
GROUP BY QualityArea
ORDER BY QualityArea;


/* Overall enterprise quality score */
SELECT
    COUNT(*) AS TotalChecks,
    SUM(CASE WHEN QualityStatus = 'PASS' THEN 1 ELSE 0 END) AS PassedChecks,
    SUM(CASE WHEN QualityStatus = 'WARNING' THEN 1 ELSE 0 END) AS WarningChecks,
    SUM(IssueCount) AS TotalIssues,
    CAST
    (
        SUM(CASE WHEN QualityStatus = 'PASS' THEN 1.0 ELSE 0.0 END)
        * 100.0 / COUNT(*)
        AS DECIMAL(10,2)
    ) AS EnterpriseDataQualityScorePercent
FROM #DataQualityResults;

PRINT 'Script 017 complete: Data quality framework executed.';
GO