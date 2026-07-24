/*==========================================================
  HealthPulse AI
  Script: 014_Executive_KPI_Views.sql
  Purpose: Create dashboard-ready KPI views for executives,
           operations leaders, revenue-cycle teams, clinical
           leaders, telehealth teams, and AI governance.

  Prerequisite:
    013_Analytics_Views.sql completed successfully.
==========================================================*/

USE HealthPulseAI;
GO

SET NOCOUNT ON;
GO

IF SCHEMA_ID('Analytics') IS NULL
    EXEC('CREATE SCHEMA Analytics AUTHORIZATION dbo;');
GO


/*==========================================================
  KPI VIEW 1: Enterprise Executive Scorecard
  One row containing the major enterprise KPIs.
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_KPI_EnterpriseScorecard
AS
WITH EncounterKPI AS
(
    SELECT
        COUNT_BIG(*) AS TotalEncounters,
        COUNT(DISTINCT PatientID) AS UniquePatients,
        SUM(CASE WHEN IsTelehealth = 1 THEN 1 ELSE 0 END) AS TelehealthEncounters,
        SUM(CASE WHEN EncounterType = 'Emergency' THEN 1 ELSE 0 END) AS EmergencyEncounters,
        AVG(CAST(LengthOfStayMinutes AS DECIMAL(18,2))) AS AverageEncounterDurationMinutes
    FROM Analytics.vw_EncounterDetails
),
TelehealthKPI AS
(
    SELECT
        COUNT_BIG(*) AS TotalVirtualVisits,
        SUM(IsCompleted) AS CompletedVirtualVisits,
        SUM(IsNoShow) AS NoShowVirtualVisits,
        SUM(IsDisconnected) AS DisconnectedVirtualVisits,
        AVG(CAST(ActualVisitDurationMinutes AS DECIMAL(18,2))) AS AverageVirtualVisitMinutes
    FROM Analytics.vw_TelehealthPerformance
),
ClaimKPI AS
(
    SELECT
        COUNT_BIG(*) AS TotalClaims,
        SUM(IsDeniedClaim) AS DeniedClaims,
        SUM(TotalChargeAmount) AS TotalChargeAmount,
        SUM(TotalAllowedAmount) AS TotalAllowedAmount,
        SUM(TotalPaidAmount) AS TotalPaidAmount,
        SUM(TotalPatientResponsibilityAmount) AS TotalPatientResponsibilityAmount
    FROM Analytics.vw_ClaimFinancials
),
BillingKPI AS
(
    SELECT
        COUNT_BIG(*) AS TotalInvoices,
        SUM(InvoiceAmount) AS TotalInvoiceAmount,
        SUM(PaidAmount) AS TotalInvoicePaidAmount,
        SUM(OutstandingAmount) AS TotalOutstandingAmount,
        SUM(CASE WHEN DerivedPaymentStatus = 'Overdue' THEN 1 ELSE 0 END) AS OverdueInvoices
    FROM Analytics.vw_PatientBillingSummary
),
AIKPI AS
(
    SELECT
        COUNT_BIG(*) AS TotalPredictions,
        SUM(CASE WHEN PredictionOutcomeID IS NOT NULL THEN 1 ELSE 0 END) AS PredictionsWithOutcome,
        SUM(CASE WHEN IsCorrectPrediction = 1 THEN 1 ELSE 0 END) AS CorrectPredictions
    FROM Analytics.vw_AIPredictionPerformance
)
SELECT
    e.TotalEncounters,
    e.UniquePatients,
    e.TelehealthEncounters,
    e.EmergencyEncounters,
    e.AverageEncounterDurationMinutes,
    CASE WHEN e.TotalEncounters = 0 THEN NULL
         ELSE CAST(e.TelehealthEncounters * 100.0 / e.TotalEncounters AS DECIMAL(9,2))
    END AS TelehealthAdoptionRatePercent,

    t.TotalVirtualVisits,
    t.CompletedVirtualVisits,
    t.NoShowVirtualVisits,
    t.DisconnectedVirtualVisits,
    t.AverageVirtualVisitMinutes,
    CASE WHEN t.TotalVirtualVisits = 0 THEN NULL
         ELSE CAST(t.CompletedVirtualVisits * 100.0 / t.TotalVirtualVisits AS DECIMAL(9,2))
    END AS TelehealthCompletionRatePercent,
    CASE WHEN t.TotalVirtualVisits = 0 THEN NULL
         ELSE CAST(t.NoShowVirtualVisits * 100.0 / t.TotalVirtualVisits AS DECIMAL(9,2))
    END AS TelehealthNoShowRatePercent,

    c.TotalClaims,
    c.DeniedClaims,
    c.TotalChargeAmount,
    c.TotalAllowedAmount,
    c.TotalPaidAmount,
    c.TotalPatientResponsibilityAmount,
    CASE WHEN c.TotalClaims = 0 THEN NULL
         ELSE CAST(c.DeniedClaims * 100.0 / c.TotalClaims AS DECIMAL(9,2))
    END AS ClaimDenialRatePercent,
    CASE WHEN c.TotalChargeAmount = 0 THEN NULL
         ELSE CAST(c.TotalPaidAmount * 100.0 / c.TotalChargeAmount AS DECIMAL(9,2))
    END AS CollectionRatePercent,

    b.TotalInvoices,
    b.TotalInvoiceAmount,
    b.TotalInvoicePaidAmount,
    b.TotalOutstandingAmount,
    b.OverdueInvoices,
    CASE WHEN b.TotalInvoices = 0 THEN NULL
         ELSE CAST(b.OverdueInvoices * 100.0 / b.TotalInvoices AS DECIMAL(9,2))
    END AS OverdueInvoiceRatePercent,

    a.TotalPredictions,
    a.PredictionsWithOutcome,
    a.CorrectPredictions,
    CASE WHEN a.PredictionsWithOutcome = 0 THEN NULL
         ELSE CAST(a.CorrectPredictions * 100.0 / a.PredictionsWithOutcome AS DECIMAL(9,2))
    END AS PredictionAccuracyPercent
FROM EncounterKPI e
CROSS JOIN TelehealthKPI t
CROSS JOIN ClaimKPI c
CROSS JOIN BillingKPI b
CROSS JOIN AIKPI a;
GO


/*==========================================================
  KPI VIEW 2: Monthly Hospital Performance
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_KPI_HospitalMonthlyPerformance
AS
WITH EncounterMonthly AS
(
    SELECT
        DATEFROMPARTS(YEAR(AdmissionDateTimeUTC), MONTH(AdmissionDateTimeUTC), 1) AS KPI_Month,
        HospitalID,
        HospitalName,
        COUNT_BIG(*) AS TotalEncounters,
        COUNT(DISTINCT PatientID) AS UniquePatients,
        SUM(CASE WHEN IsTelehealth = 1 THEN 1 ELSE 0 END) AS TelehealthEncounters,
        SUM(CASE WHEN EncounterType = 'Emergency' THEN 1 ELSE 0 END) AS EmergencyEncounters,
        AVG(CAST(LengthOfStayMinutes AS DECIMAL(18,2))) AS AverageEncounterDurationMinutes
    FROM Analytics.vw_EncounterDetails
    GROUP BY
        DATEFROMPARTS(YEAR(AdmissionDateTimeUTC), MONTH(AdmissionDateTimeUTC), 1),
        HospitalID,
        HospitalName
),
ClaimMonthly AS
(
    SELECT
        DATEFROMPARTS(YEAR(ServiceStartDate), MONTH(ServiceStartDate), 1) AS KPI_Month,
        HospitalID,
        COUNT_BIG(*) AS TotalClaims,
        SUM(IsDeniedClaim) AS DeniedClaims,
        SUM(TotalChargeAmount) AS TotalChargeAmount,
        SUM(TotalPaidAmount) AS TotalPaidAmount
    FROM Analytics.vw_ClaimFinancials
    GROUP BY
        DATEFROMPARTS(YEAR(ServiceStartDate), MONTH(ServiceStartDate), 1),
        HospitalID
),
TelehealthMonthly AS
(
    SELECT
        DATEFROMPARTS(YEAR(ScheduledStartDateTimeUTC), MONTH(ScheduledStartDateTimeUTC), 1) AS KPI_Month,
        HospitalID,
        COUNT_BIG(*) AS TotalVirtualVisits,
        SUM(IsCompleted) AS CompletedVirtualVisits,
        SUM(IsNoShow) AS NoShowVirtualVisits
    FROM Analytics.vw_TelehealthPerformance
    GROUP BY
        DATEFROMPARTS(YEAR(ScheduledStartDateTimeUTC), MONTH(ScheduledStartDateTimeUTC), 1),
        HospitalID
)
SELECT
    e.KPI_Month,
    e.HospitalID,
    e.HospitalName,
    e.TotalEncounters,
    e.UniquePatients,
    e.TelehealthEncounters,
    e.EmergencyEncounters,
    e.AverageEncounterDurationMinutes,
    ISNULL(c.TotalClaims, 0) AS TotalClaims,
    ISNULL(c.DeniedClaims, 0) AS DeniedClaims,
    ISNULL(c.TotalChargeAmount, 0) AS TotalChargeAmount,
    ISNULL(c.TotalPaidAmount, 0) AS TotalPaidAmount,
    CASE WHEN ISNULL(c.TotalClaims, 0) = 0 THEN NULL
         ELSE CAST(c.DeniedClaims * 100.0 / c.TotalClaims AS DECIMAL(9,2))
    END AS ClaimDenialRatePercent,
    CASE WHEN ISNULL(c.TotalChargeAmount, 0) = 0 THEN NULL
         ELSE CAST(c.TotalPaidAmount * 100.0 / c.TotalChargeAmount AS DECIMAL(9,2))
    END AS CollectionRatePercent,
    ISNULL(t.TotalVirtualVisits, 0) AS TotalVirtualVisits,
    ISNULL(t.CompletedVirtualVisits, 0) AS CompletedVirtualVisits,
    ISNULL(t.NoShowVirtualVisits, 0) AS NoShowVirtualVisits,
    CASE WHEN ISNULL(t.TotalVirtualVisits, 0) = 0 THEN NULL
         ELSE CAST(t.NoShowVirtualVisits * 100.0 / t.TotalVirtualVisits AS DECIMAL(9,2))
    END AS TelehealthNoShowRatePercent
FROM EncounterMonthly e
LEFT JOIN ClaimMonthly c
  ON c.KPI_Month = e.KPI_Month
 AND c.HospitalID = e.HospitalID
LEFT JOIN TelehealthMonthly t
  ON t.KPI_Month = e.KPI_Month
 AND t.HospitalID = e.HospitalID;
GO


/*==========================================================
  KPI VIEW 3: Provider Productivity
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_KPI_ProviderProductivity
AS
WITH EncounterProvider AS
(
    SELECT
        ProviderID,
        ProviderCode,
        ProviderName,
        ProviderType,
        HospitalID,
        HospitalName,
        DepartmentID,
        DepartmentName,
        COUNT_BIG(*) AS TotalEncounters,
        COUNT(DISTINCT PatientID) AS UniquePatients,
        SUM(CASE WHEN IsTelehealth = 1 THEN 1 ELSE 0 END) AS TelehealthEncounters,
        SUM(CASE WHEN EncounterType = 'Emergency' THEN 1 ELSE 0 END) AS EmergencyEncounters,
        AVG(CAST(LengthOfStayMinutes AS DECIMAL(18,2))) AS AverageEncounterDurationMinutes,
        SUM(DiagnosisCount) AS TotalDiagnosesDocumented,
        SUM(ProcedureCount) AS TotalProceduresDocumented,
        SUM(MedicationOrderCount) AS TotalMedicationOrders
    FROM Analytics.vw_EncounterDetails
    GROUP BY
        ProviderID,
        ProviderCode,
        ProviderName,
        ProviderType,
        HospitalID,
        HospitalName,
        DepartmentID,
        DepartmentName
),
ClaimProvider AS
(
    SELECT
        ProviderID,
        COUNT_BIG(*) AS TotalClaims,
        SUM(IsDeniedClaim) AS DeniedClaims,
        SUM(TotalChargeAmount) AS TotalChargeAmount,
        SUM(TotalPaidAmount) AS TotalPaidAmount
    FROM Analytics.vw_ClaimFinancials
    GROUP BY ProviderID
)
SELECT
    ep.ProviderID,
    ep.ProviderCode,
    ep.ProviderName,
    ep.ProviderType,
    ep.HospitalID,
    ep.HospitalName,
    ep.DepartmentID,
    ep.DepartmentName,
    ep.TotalEncounters,
    ep.UniquePatients,
    ep.TelehealthEncounters,
    ep.EmergencyEncounters,
    ep.AverageEncounterDurationMinutes,
    ep.TotalDiagnosesDocumented,
    ep.TotalProceduresDocumented,
    ep.TotalMedicationOrders,
    ISNULL(cp.TotalClaims, 0) AS TotalClaims,
    ISNULL(cp.DeniedClaims, 0) AS DeniedClaims,
    ISNULL(cp.TotalChargeAmount, 0) AS TotalChargeAmount,
    ISNULL(cp.TotalPaidAmount, 0) AS TotalPaidAmount,
    CASE WHEN ISNULL(cp.TotalClaims, 0) = 0 THEN NULL
         ELSE CAST(cp.DeniedClaims * 100.0 / cp.TotalClaims AS DECIMAL(9,2))
    END AS ClaimDenialRatePercent,
    CASE WHEN ep.TotalEncounters = 0 THEN NULL
         ELSE CAST(ISNULL(cp.TotalPaidAmount, 0) / ep.TotalEncounters AS DECIMAL(18,2))
    END AS PaidAmountPerEncounter
FROM EncounterProvider ep
LEFT JOIN ClaimProvider cp
  ON cp.ProviderID = ep.ProviderID;
GO


/*==========================================================
  KPI VIEW 4: Monthly Telehealth Operations
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_KPI_TelehealthMonthly
AS
SELECT
    DATEFROMPARTS
    (
        YEAR(ScheduledStartDateTimeUTC),
        MONTH(ScheduledStartDateTimeUTC),
        1
    ) AS KPI_Month,
    HospitalID,
    HospitalName,
    DepartmentID,
    DepartmentName,
    PlatformName,
    PatientDeviceType,
    COUNT_BIG(*) AS TotalVirtualVisits,
    SUM(IsCompleted) AS CompletedVisits,
    SUM(IsNoShow) AS NoShowVisits,
    SUM(IsDisconnected) AS DisconnectedVisits,
    AVG(CAST(PatientJoinDelayMinutes AS DECIMAL(18,2))) AS AveragePatientJoinDelayMinutes,
    AVG(CAST(ProviderJoinDelayMinutes AS DECIMAL(18,2))) AS AverageProviderJoinDelayMinutes,
    AVG(CAST(ActualVisitDurationMinutes AS DECIMAL(18,2))) AS AverageVisitDurationMinutes,
    SUM(TechnicalErrorCount) AS TotalTechnicalErrors,
    SUM(CASE WHEN IsInterpreterRequired = 1 THEN 1 ELSE 0 END) AS InterpreterRequiredVisits,
    CASE WHEN COUNT_BIG(*) = 0 THEN NULL
         ELSE CAST(SUM(IsCompleted) * 100.0 / COUNT_BIG(*) AS DECIMAL(9,2))
    END AS CompletionRatePercent,
    CASE WHEN COUNT_BIG(*) = 0 THEN NULL
         ELSE CAST(SUM(IsNoShow) * 100.0 / COUNT_BIG(*) AS DECIMAL(9,2))
    END AS NoShowRatePercent,
    CASE WHEN COUNT_BIG(*) = 0 THEN NULL
         ELSE CAST(SUM(IsDisconnected) * 100.0 / COUNT_BIG(*) AS DECIMAL(9,2))
    END AS DisconnectionRatePercent
FROM Analytics.vw_TelehealthPerformance
GROUP BY
    DATEFROMPARTS
    (
        YEAR(ScheduledStartDateTimeUTC),
        MONTH(ScheduledStartDateTimeUTC),
        1
    ),
    HospitalID,
    HospitalName,
    DepartmentID,
    DepartmentName,
    PlatformName,
    PatientDeviceType;
GO


/*==========================================================
  KPI VIEW 5: Monthly Revenue Cycle
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_KPI_RevenueCycleMonthly
AS
WITH ClaimMonthly AS
(
    SELECT
        DATEFROMPARTS(YEAR(ServiceStartDate), MONTH(ServiceStartDate), 1) AS KPI_Month,
        COUNT_BIG(*) AS TotalClaims,
        SUM(IsDeniedClaim) AS DeniedClaims,
        SUM(TotalChargeAmount) AS TotalChargeAmount,
        SUM(TotalAllowedAmount) AS TotalAllowedAmount,
        SUM(TotalPaidAmount) AS InsurancePaidAmount,
        SUM(TotalPatientResponsibilityAmount) AS PatientResponsibilityAmount,
        AVG(CAST(SubmissionLagDays AS DECIMAL(18,2))) AS AverageSubmissionLagDays,
        AVG(CAST(AdjudicationDays AS DECIMAL(18,2))) AS AverageAdjudicationDays
    FROM Analytics.vw_ClaimFinancials
    GROUP BY
        DATEFROMPARTS(YEAR(ServiceStartDate), MONTH(ServiceStartDate), 1)
),
InvoiceMonthly AS
(
    SELECT
        DATEFROMPARTS(YEAR(InvoiceDate), MONTH(InvoiceDate), 1) AS KPI_Month,
        COUNT_BIG(*) AS TotalInvoices,
        SUM(InvoiceAmount) AS TotalInvoiceAmount,
        SUM(PaidAmount) AS PatientPaidAmount,
        SUM(OutstandingAmount) AS OutstandingAmount,
        SUM(CASE WHEN DerivedPaymentStatus = 'Overdue' THEN 1 ELSE 0 END) AS OverdueInvoices
    FROM Analytics.vw_PatientBillingSummary
    GROUP BY
        DATEFROMPARTS(YEAR(InvoiceDate), MONTH(InvoiceDate), 1)
)
SELECT
    c.KPI_Month,
    c.TotalClaims,
    c.DeniedClaims,
    c.TotalChargeAmount,
    c.TotalAllowedAmount,
    c.InsurancePaidAmount,
    c.PatientResponsibilityAmount,
    c.AverageSubmissionLagDays,
    c.AverageAdjudicationDays,
    CASE WHEN c.TotalClaims = 0 THEN NULL
         ELSE CAST(c.DeniedClaims * 100.0 / c.TotalClaims AS DECIMAL(9,2))
    END AS ClaimDenialRatePercent,
    CASE WHEN c.TotalChargeAmount = 0 THEN NULL
         ELSE CAST(c.InsurancePaidAmount * 100.0 / c.TotalChargeAmount AS DECIMAL(9,2))
    END AS InsuranceCollectionRatePercent,
    ISNULL(i.TotalInvoices, 0) AS TotalInvoices,
    ISNULL(i.TotalInvoiceAmount, 0) AS TotalInvoiceAmount,
    ISNULL(i.PatientPaidAmount, 0) AS PatientPaidAmount,
    ISNULL(i.OutstandingAmount, 0) AS OutstandingAmount,
    ISNULL(i.OverdueInvoices, 0) AS OverdueInvoices,
    CASE WHEN ISNULL(i.TotalInvoices, 0) = 0 THEN NULL
         ELSE CAST(i.OverdueInvoices * 100.0 / i.TotalInvoices AS DECIMAL(9,2))
    END AS OverdueInvoiceRatePercent,
    c.InsurancePaidAmount + ISNULL(i.PatientPaidAmount, 0) AS TotalCollectedAmount
FROM ClaimMonthly c
LEFT JOIN InvoiceMonthly i
  ON i.KPI_Month = c.KPI_Month;
GO


/*==========================================================
  KPI VIEW 6: Claim Denial Performance
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_KPI_ClaimDenialMonthly
AS
SELECT
    DATEFROMPARTS(YEAR(ServiceStartDate), MONTH(ServiceStartDate), 1) AS KPI_Month,
    HospitalName,
    PayerName,
    PlanName,
    ClaimType,
    PrimaryDenialReasonCode,
    COUNT_BIG(*) AS TotalClaims,
    SUM(IsDeniedClaim) AS DeniedClaims,
    SUM(TotalChargeAmount) AS TotalChargeAmount,
    SUM(CASE WHEN IsDeniedClaim = 1 THEN TotalChargeAmount ELSE 0 END) AS DeniedChargeAmount,
    SUM(TotalPaidAmount) AS TotalPaidAmount,
    CASE WHEN COUNT_BIG(*) = 0 THEN NULL
         ELSE CAST(SUM(IsDeniedClaim) * 100.0 / COUNT_BIG(*) AS DECIMAL(9,2))
    END AS DenialRatePercent,
    CASE WHEN SUM(TotalChargeAmount) = 0 THEN NULL
         ELSE CAST
         (
             SUM(CASE WHEN IsDeniedClaim = 1 THEN TotalChargeAmount ELSE 0 END)
             * 100.0 / SUM(TotalChargeAmount)
             AS DECIMAL(9,2)
         )
    END AS DeniedChargeRatePercent
FROM Analytics.vw_ClaimDenialAnalysis
GROUP BY
    DATEFROMPARTS(YEAR(ServiceStartDate), MONTH(ServiceStartDate), 1),
    HospitalName,
    PayerName,
    PlanName,
    ClaimType,
    PrimaryDenialReasonCode;
GO


/*==========================================================
  KPI VIEW 7: Patient Risk Population
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_KPI_PatientRiskPopulation
AS
WITH LatestPrediction AS
(
    SELECT
        ap.PatientID,
        ap.ModelName,
        ap.PredictedClass,
        ap.ProbabilityScore,
        ap.RiskScore,
        ap.PredictionDateTimeUTC,
        ROW_NUMBER() OVER
        (
            PARTITION BY ap.PatientID
            ORDER BY ap.PredictionDateTimeUTC DESC, ap.PredictionID DESC
        ) AS rn
    FROM Analytics.vw_AIPredictionPerformance ap
)
SELECT
    p.PatientID,
    p.MedicalRecordNumber,
    p.FirstName,
    p.LastName,
    p.AgeYears,
    p.Gender,
    p.City,
    p.StateProvince,
    p.TotalEncounters,
    p.TelehealthEncounters,
    p.EmergencyEncounters,
    p.TotalDiagnoses,
    p.DistinctDiagnosisCount,
    p.TotalBilledAmount,
    p.TotalPaidAmount,
    p.EstimatedOutstandingAmount,
    lp.ModelName,
    lp.PredictedClass AS LatestPredictedClass,
    lp.ProbabilityScore AS LatestProbabilityScore,
    lp.RiskScore AS LatestRiskScore,
    lp.PredictionDateTimeUTC AS LatestPredictionDateUTC,
    CASE
        WHEN lp.PredictedClass = N'High Risk' THEN 'High'
        WHEN p.EmergencyEncounters >= 2 OR p.DistinctDiagnosisCount >= 5 THEN 'Medium'
        ELSE 'Low'
    END AS DerivedPatientRiskTier,
    CASE
        WHEN lp.PredictedClass = N'High Risk' THEN 1
        WHEN p.EmergencyEncounters >= 2 OR p.DistinctDiagnosisCount >= 5 THEN 1
        ELSE 0
    END AS NeedsCareManagementReview
FROM Analytics.vw_Patient360 p
LEFT JOIN LatestPrediction lp
  ON lp.PatientID = p.PatientID
 AND lp.rn = 1;
GO


/*==========================================================
  KPI VIEW 8: AI Model Performance Summary
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_KPI_AIModelPerformance
AS
SELECT
    ModelID,
    ModelCode,
    ModelName,
    ModelVersionID,
    VersionNumber,
    AlgorithmName,
    COUNT_BIG(*) AS TotalPredictions,
    SUM(CASE WHEN PredictionOutcomeID IS NOT NULL THEN 1 ELSE 0 END) AS PredictionsWithOutcome,
    SUM(CASE WHEN IsCorrectPrediction = 1 THEN 1 ELSE 0 END) AS CorrectPredictions,
    SUM(CASE WHEN ConfusionMatrixCategory = 'True Positive' THEN 1 ELSE 0 END) AS TruePositives,
    SUM(CASE WHEN ConfusionMatrixCategory = 'False Positive' THEN 1 ELSE 0 END) AS FalsePositives,
    SUM(CASE WHEN ConfusionMatrixCategory = 'True Negative' THEN 1 ELSE 0 END) AS TrueNegatives,
    SUM(CASE WHEN ConfusionMatrixCategory = 'False Negative' THEN 1 ELSE 0 END) AS FalseNegatives,
    AVG(CAST(ProbabilityScore AS DECIMAL(18,8))) AS AverageProbabilityScore,
    AVG(CAST(RiskScore AS DECIMAL(18,6))) AS AverageRiskScore,
    CASE
        WHEN SUM(CASE WHEN PredictionOutcomeID IS NOT NULL THEN 1 ELSE 0 END) = 0
        THEN NULL
        ELSE CAST
        (
            SUM(CASE WHEN IsCorrectPrediction = 1 THEN 1 ELSE 0 END) * 100.0
            / SUM(CASE WHEN PredictionOutcomeID IS NOT NULL THEN 1 ELSE 0 END)
            AS DECIMAL(9,2)
        )
    END AS AccuracyPercent,
    CASE
        WHEN SUM(CASE WHEN ConfusionMatrixCategory IN ('True Positive','False Positive')
                      THEN 1 ELSE 0 END) = 0
        THEN NULL
        ELSE CAST
        (
            SUM(CASE WHEN ConfusionMatrixCategory = 'True Positive' THEN 1 ELSE 0 END) * 100.0
            / SUM(CASE WHEN ConfusionMatrixCategory IN ('True Positive','False Positive')
                       THEN 1 ELSE 0 END)
            AS DECIMAL(9,2)
        )
    END AS PrecisionPercent,
    CASE
        WHEN SUM(CASE WHEN ConfusionMatrixCategory IN ('True Positive','False Negative')
                      THEN 1 ELSE 0 END) = 0
        THEN NULL
        ELSE CAST
        (
            SUM(CASE WHEN ConfusionMatrixCategory = 'True Positive' THEN 1 ELSE 0 END) * 100.0
            / SUM(CASE WHEN ConfusionMatrixCategory IN ('True Positive','False Negative')
                       THEN 1 ELSE 0 END)
            AS DECIMAL(9,2)
        )
    END AS RecallPercent
FROM Analytics.vw_AIPredictionPerformance
GROUP BY
    ModelID,
    ModelCode,
    ModelName,
    ModelVersionID,
    VersionNumber,
    AlgorithmName;
GO


/*==========================================================
  VALIDATION
==========================================================*/
SELECT
    s.name AS SchemaName,
    v.name AS ViewName
FROM sys.views v
JOIN sys.schemas s
  ON s.schema_id = v.schema_id
WHERE s.name = 'Analytics'
  AND v.name LIKE 'vw_KPI_%'
ORDER BY v.name;
GO

SELECT * FROM Analytics.vw_KPI_EnterpriseScorecard;
SELECT TOP (20) * FROM Analytics.vw_KPI_HospitalMonthlyPerformance
ORDER BY KPI_Month, HospitalID;
SELECT TOP (20) * FROM Analytics.vw_KPI_ProviderProductivity
ORDER BY TotalEncounters DESC, ProviderID;
SELECT TOP (20) * FROM Analytics.vw_KPI_RevenueCycleMonthly
ORDER BY KPI_Month;
SELECT TOP (20) * FROM Analytics.vw_KPI_AIModelPerformance
ORDER BY ModelName, VersionNumber;
GO

PRINT 'Script 014 complete: Executive KPI views created and validated.';
GO