/*==========================================================
  HealthPulse AI
  Script: 013_Analytics_Views.sql
  Purpose: Create reusable analytics views for SQL analysis,
           Power BI, Tableau, Python, and executive reporting.

  Prerequisite:
    Scripts 001 through 012 completed successfully.
==========================================================*/

USE HealthPulseAI;
GO

SET NOCOUNT ON;
GO

/* Create the Analytics schema once. */
IF SCHEMA_ID('Analytics') IS NULL
    EXEC('CREATE SCHEMA Analytics AUTHORIZATION dbo;');
GO


/*==========================================================
  VIEW 1: Analytics.vw_Patient360
  One row per patient with demographic, utilization,
  insurance, billing, telehealth, and AI indicators.
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_Patient360
AS
WITH EncounterSummary AS
(
    SELECT
        e.PatientID,
        COUNT_BIG(*) AS TotalEncounters,
        SUM(CASE WHEN e.IsTelehealth = 1 THEN 1 ELSE 0 END) AS TelehealthEncounters,
        SUM(CASE WHEN e.EncounterType = 'Emergency' THEN 1 ELSE 0 END) AS EmergencyEncounters,
        MAX(e.AdmissionDateTimeUTC) AS MostRecentEncounterDateUTC
    FROM Clinical.Encounter e
    GROUP BY e.PatientID
),
DiagnosisSummary AS
(
    SELECT
        d.PatientID,
        COUNT_BIG(*) AS TotalDiagnoses,
        COUNT(DISTINCT d.DiagnosisCode) AS DistinctDiagnosisCount
    FROM Clinical.Diagnosis d
    GROUP BY d.PatientID
),
CoverageSummary AS
(
    SELECT
        pc.PatientID,
        COUNT_BIG(*) AS ActiveCoverageCount,
        MAX(CASE WHEN pc.CoveragePriority = 'Primary' THEN p.PayerName END) AS PrimaryPayerName,
        MAX(CASE WHEN pc.CoveragePriority = 'Primary' THEN ip.PlanName END) AS PrimaryPlanName
    FROM Insurance.PatientCoverage pc
    JOIN Insurance.InsurancePlan ip
      ON ip.InsurancePlanID = pc.InsurancePlanID
    JOIN Insurance.Payer p
      ON p.PayerID = ip.PayerID
    WHERE pc.IsActive = 1
    GROUP BY pc.PatientID
),
BillingSummary AS
(
    SELECT
        i.PatientID,
        SUM(il.LineAmount) AS TotalBilledAmount,
        SUM(ISNULL(pa.AllocatedAmount, 0)) AS TotalPaidAmount
    FROM Billing.Invoice i
    JOIN Billing.InvoiceLine il
      ON il.InvoiceID = i.InvoiceID
    LEFT JOIN
    (
        SELECT
            InvoiceID,
            SUM(AllocatedAmount) AS AllocatedAmount
        FROM Billing.PaymentAllocation
        WHERE AllocationStatus = 'Posted'
        GROUP BY InvoiceID
    ) pa
      ON pa.InvoiceID = i.InvoiceID
    GROUP BY i.PatientID
),
PredictionSummary AS
(
    SELECT
        pr.PatientID,
        COUNT_BIG(*) AS PredictionCount,
        MAX(pr.ProbabilityScore) AS MaximumProbabilityScore,
        MAX(pr.PredictionDateTimeUTC) AS MostRecentPredictionDateUTC
    FROM AI.Prediction pr
    GROUP BY pr.PatientID
)
SELECT
    p.PatientID,
    p.MedicalRecordNumber,
    p.FirstName,
    p.LastName,
    p.DateOfBirth,
    DATEDIFF(YEAR, p.DateOfBirth, CAST(GETUTCDATE() AS DATE))
      - CASE
            WHEN DATEADD
                 (
                    YEAR,
                    DATEDIFF(YEAR, p.DateOfBirth, CAST(GETUTCDATE() AS DATE)),
                    p.DateOfBirth
                 ) > CAST(GETUTCDATE() AS DATE)
            THEN 1 ELSE 0
        END AS AgeYears,
    p.Gender,
    p.MaritalStatus,
    p.PreferredLanguage,
    p.BloodType,
    a.City,
    a.StateProvince,
    a.PostalCode,
    ISNULL(es.TotalEncounters, 0) AS TotalEncounters,
    ISNULL(es.TelehealthEncounters, 0) AS TelehealthEncounters,
    ISNULL(es.EmergencyEncounters, 0) AS EmergencyEncounters,
    es.MostRecentEncounterDateUTC,
    ISNULL(ds.TotalDiagnoses, 0) AS TotalDiagnoses,
    ISNULL(ds.DistinctDiagnosisCount, 0) AS DistinctDiagnosisCount,
    ISNULL(cs.ActiveCoverageCount, 0) AS ActiveCoverageCount,
    cs.PrimaryPayerName,
    cs.PrimaryPlanName,
    ISNULL(bs.TotalBilledAmount, 0) AS TotalBilledAmount,
    ISNULL(bs.TotalPaidAmount, 0) AS TotalPaidAmount,
    ISNULL(bs.TotalBilledAmount, 0) - ISNULL(bs.TotalPaidAmount, 0) AS EstimatedOutstandingAmount,
    ISNULL(ps.PredictionCount, 0) AS PredictionCount,
    ps.MaximumProbabilityScore,
    ps.MostRecentPredictionDateUTC,
    p.IsActive
FROM Clinical.Patient p
LEFT JOIN Clinical.PatientAddress a
  ON a.PatientID = p.PatientID
 AND a.IsPrimary = 1
 AND a.IsActive = 1
LEFT JOIN EncounterSummary es
  ON es.PatientID = p.PatientID
LEFT JOIN DiagnosisSummary ds
  ON ds.PatientID = p.PatientID
LEFT JOIN CoverageSummary cs
  ON cs.PatientID = p.PatientID
LEFT JOIN BillingSummary bs
  ON bs.PatientID = p.PatientID
LEFT JOIN PredictionSummary ps
  ON ps.PatientID = p.PatientID;
GO


/*==========================================================
  VIEW 2: Analytics.vw_EncounterDetails
  Encounter-level clinical and organizational details.
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_EncounterDetails
AS
SELECT
    e.EncounterID,
    e.EncounterNumber,
    e.PatientID,
    p.MedicalRecordNumber,
    p.FirstName + N' ' + p.LastName AS PatientName,
    e.HospitalID,
    h.HospitalCode,
    h.HospitalName,
    e.DepartmentID,
    d.DepartmentCode,
    d.DepartmentName,
    e.ProviderID,
    pr.ProviderCode,
    pr.FirstName + N' ' + pr.LastName AS ProviderName,
    pr.ProviderType,
    e.EncounterType,
    e.EncounterStatus,
    e.AdmissionDateTimeUTC,
    e.DischargeDateTimeUTC,
    DATEDIFF(MINUTE, e.AdmissionDateTimeUTC, e.DischargeDateTimeUTC) AS LengthOfStayMinutes,
    CAST(DATEDIFF(MINUTE, e.AdmissionDateTimeUTC, e.DischargeDateTimeUTC) / 60.0
         AS DECIMAL(12,2)) AS LengthOfStayHours,
    e.ReasonForVisit,
    e.Disposition,
    e.IsTelehealth,
    COUNT(DISTINCT dg.DiagnosisID) AS DiagnosisCount,
    COUNT(DISTINCT pc.ProcedureID) AS ProcedureCount,
    COUNT(DISTINCT mo.MedicationOrderID) AS MedicationOrderCount
FROM Clinical.Encounter e
JOIN Clinical.Patient p
  ON p.PatientID = e.PatientID
JOIN Hospital.Hospital h
  ON h.HospitalID = e.HospitalID
JOIN Hospital.Department d
  ON d.DepartmentID = e.DepartmentID
JOIN Hospital.Provider pr
  ON pr.ProviderID = e.ProviderID
LEFT JOIN Clinical.Diagnosis dg
  ON dg.EncounterID = e.EncounterID
LEFT JOIN Clinical.[Procedure] pc
  ON pc.EncounterID = e.EncounterID
LEFT JOIN Clinical.MedicationOrder mo
  ON mo.EncounterID = e.EncounterID
GROUP BY
    e.EncounterID,
    e.EncounterNumber,
    e.PatientID,
    p.MedicalRecordNumber,
    p.FirstName,
    p.LastName,
    e.HospitalID,
    h.HospitalCode,
    h.HospitalName,
    e.DepartmentID,
    d.DepartmentCode,
    d.DepartmentName,
    e.ProviderID,
    pr.ProviderCode,
    pr.FirstName,
    pr.LastName,
    pr.ProviderType,
    e.EncounterType,
    e.EncounterStatus,
    e.AdmissionDateTimeUTC,
    e.DischargeDateTimeUTC,
    e.ReasonForVisit,
    e.Disposition,
    e.IsTelehealth;
GO


/*==========================================================
  VIEW 3: Analytics.vw_ClinicalUtilizationMonthly
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_ClinicalUtilizationMonthly
AS
SELECT
    DATEFROMPARTS
    (
        YEAR(e.AdmissionDateTimeUTC),
        MONTH(e.AdmissionDateTimeUTC),
        1
    ) AS EncounterMonth,
    e.HospitalID,
    h.HospitalName,
    e.DepartmentID,
    d.DepartmentName,
    e.EncounterType,
    COUNT_BIG(*) AS EncounterCount,
    COUNT(DISTINCT e.PatientID) AS UniquePatientCount,
    SUM(CASE WHEN e.IsTelehealth = 1 THEN 1 ELSE 0 END) AS TelehealthEncounterCount,
    AVG(CAST(DATEDIFF(MINUTE, e.AdmissionDateTimeUTC, e.DischargeDateTimeUTC)
        AS DECIMAL(18,2))) AS AverageLengthOfStayMinutes
FROM Clinical.Encounter e
JOIN Hospital.Hospital h
  ON h.HospitalID = e.HospitalID
JOIN Hospital.Department d
  ON d.DepartmentID = e.DepartmentID
GROUP BY
    DATEFROMPARTS
    (
        YEAR(e.AdmissionDateTimeUTC),
        MONTH(e.AdmissionDateTimeUTC),
        1
    ),
    e.HospitalID,
    h.HospitalName,
    e.DepartmentID,
    d.DepartmentName,
    e.EncounterType;
GO


/*==========================================================
  VIEW 4: Analytics.vw_TelehealthPerformance
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_TelehealthPerformance
AS
WITH SessionSummary AS
(
    SELECT
        se.VirtualVisitID,
        COUNT_BIG(*) AS SessionEventCount,
        SUM(CASE WHEN se.TechnicalErrorCode IS NOT NULL THEN 1 ELSE 0 END) AS TechnicalErrorCount
    FROM Telehealth.SessionEvent se
    GROUP BY se.VirtualVisitID
)
SELECT
    vv.VirtualVisitID,
    vv.VisitNumber,
    vv.EncounterID,
    vv.PatientID,
    p.MedicalRecordNumber,
    vv.ProviderID,
    pr.FirstName + N' ' + pr.LastName AS ProviderName,
    vv.HospitalID,
    h.HospitalName,
    vv.DepartmentID,
    d.DepartmentName,
    vv.VisitType,
    vv.VisitStatus,
    vv.PlatformName,
    vv.PatientDeviceType,
    vv.PatientConnectionMethod,
    vv.ScheduledStartDateTimeUTC,
    vv.ActualStartDateTimeUTC,
    vv.ActualEndDateTimeUTC,
    DATEDIFF
    (
        MINUTE,
        vv.ScheduledStartDateTimeUTC,
        vv.PatientJoinedDateTimeUTC
    ) AS PatientJoinDelayMinutes,
    DATEDIFF
    (
        MINUTE,
        vv.ScheduledStartDateTimeUTC,
        vv.ProviderJoinedDateTimeUTC
    ) AS ProviderJoinDelayMinutes,
    DATEDIFF
    (
        MINUTE,
        vv.ActualStartDateTimeUTC,
        vv.ActualEndDateTimeUTC
    ) AS ActualVisitDurationMinutes,
    CASE WHEN vv.VisitStatus = 'Completed' THEN 1 ELSE 0 END AS IsCompleted,
    CASE WHEN vv.VisitStatus = 'No Show' THEN 1 ELSE 0 END AS IsNoShow,
    CASE WHEN vv.VisitStatus = 'Disconnected' THEN 1 ELSE 0 END AS IsDisconnected,
    ISNULL(ss.SessionEventCount, 0) AS SessionEventCount,
    ISNULL(ss.TechnicalErrorCount, 0) AS TechnicalErrorCount,
    vv.IsInterpreterRequired,
    vv.InterpreterLanguage
FROM Telehealth.VirtualVisit vv
JOIN Clinical.Patient p
  ON p.PatientID = vv.PatientID
JOIN Hospital.Provider pr
  ON pr.ProviderID = vv.ProviderID
JOIN Hospital.Hospital h
  ON h.HospitalID = vv.HospitalID
JOIN Hospital.Department d
  ON d.DepartmentID = vv.DepartmentID
LEFT JOIN SessionSummary ss
  ON ss.VirtualVisitID = vv.VirtualVisitID;
GO


/*==========================================================
  VIEW 5: Analytics.vw_ClaimFinancials
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_ClaimFinancials
AS
WITH LineSummary AS
(
    SELECT
        cl.ClaimID,
        COUNT_BIG(*) AS ClaimLineCount,
        SUM(cl.ChargeAmount) AS TotalChargeAmount,
        SUM(cl.AllowedAmount) AS TotalAllowedAmount,
        SUM(cl.PaidAmount) AS TotalPaidAmount,
        SUM(cl.PatientResponsibilityAmount) AS TotalPatientResponsibilityAmount,
        SUM(cl.AdjustmentAmount) AS TotalAdjustmentAmount,
        SUM(CASE WHEN cl.LineStatus = 'Denied' THEN 1 ELSE 0 END) AS DeniedLineCount
    FROM Insurance.ClaimLine cl
    GROUP BY cl.ClaimID
)
SELECT
    c.ClaimID,
    c.ClaimNumber,
    c.PatientID,
    p.MedicalRecordNumber,
    c.EncounterID,
    c.ProviderID,
    pr.FirstName + N' ' + pr.LastName AS ProviderName,
    c.HospitalID,
    h.HospitalName,
    py.PayerID,
    py.PayerName,
    ip.InsurancePlanID,
    ip.PlanName,
    ip.PlanType,
    c.ClaimType,
    c.ServiceStartDate,
    c.ServiceEndDate,
    c.SubmissionDateTimeUTC,
    c.AdjudicationDateTimeUTC,
    DATEDIFF(DAY, c.ServiceEndDate, CAST(c.SubmissionDateTimeUTC AS DATE)) AS SubmissionLagDays,
    DATEDIFF(DAY, CAST(c.SubmissionDateTimeUTC AS DATE),
             CAST(c.AdjudicationDateTimeUTC AS DATE)) AS AdjudicationDays,
    c.ClaimStatus,
    ISNULL(ls.ClaimLineCount, 0) AS ClaimLineCount,
    ISNULL(ls.TotalChargeAmount, 0) AS TotalChargeAmount,
    ISNULL(ls.TotalAllowedAmount, 0) AS TotalAllowedAmount,
    ISNULL(ls.TotalPaidAmount, 0) AS TotalPaidAmount,
    ISNULL(ls.TotalPatientResponsibilityAmount, 0) AS TotalPatientResponsibilityAmount,
    ISNULL(ls.TotalAdjustmentAmount, 0) AS TotalAdjustmentAmount,
    ISNULL(ls.DeniedLineCount, 0) AS DeniedLineCount,
    CASE WHEN c.ClaimStatus = 'Denied' OR ISNULL(ls.DeniedLineCount, 0) > 0
         THEN 1 ELSE 0 END AS IsDeniedClaim,
    CASE WHEN ISNULL(ls.TotalChargeAmount, 0) = 0 THEN NULL
         ELSE CAST(ls.TotalPaidAmount * 100.0 / ls.TotalChargeAmount AS DECIMAL(9,2))
    END AS PaidToChargePercent
FROM Insurance.Claim c
JOIN Clinical.Patient p
  ON p.PatientID = c.PatientID
JOIN Hospital.Provider pr
  ON pr.ProviderID = c.ProviderID
JOIN Hospital.Hospital h
  ON h.HospitalID = c.HospitalID
JOIN Insurance.PatientCoverage pc
  ON pc.PatientCoverageID = c.PatientCoverageID
JOIN Insurance.InsurancePlan ip
  ON ip.InsurancePlanID = pc.InsurancePlanID
JOIN Insurance.Payer py
  ON py.PayerID = ip.PayerID
LEFT JOIN LineSummary ls
  ON ls.ClaimID = c.ClaimID;
GO


/*==========================================================
  VIEW 6: Analytics.vw_ClaimDenialAnalysis
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_ClaimDenialAnalysis
AS
SELECT
    cf.ClaimID,
    cf.ClaimNumber,
    cf.PatientID,
    cf.MedicalRecordNumber,
    cf.HospitalName,
    cf.ProviderName,
    cf.PayerName,
    cf.PlanName,
    cf.ClaimType,
    cf.ServiceStartDate,
    cf.ClaimStatus,
    cf.TotalChargeAmount,
    cf.TotalAllowedAmount,
    cf.TotalPaidAmount,
    cf.TotalPatientResponsibilityAmount,
    cf.DeniedLineCount,
    cf.IsDeniedClaim,
    MAX(cl.DenialReasonCode) AS PrimaryDenialReasonCode,
    COUNT(DISTINCT CASE WHEN cl.LineStatus = 'Denied'
                        THEN cl.ClaimLineID END) AS DeniedClaimLineCount
FROM Analytics.vw_ClaimFinancials cf
LEFT JOIN Insurance.ClaimLine cl
  ON cl.ClaimID = cf.ClaimID
GROUP BY
    cf.ClaimID,
    cf.ClaimNumber,
    cf.PatientID,
    cf.MedicalRecordNumber,
    cf.HospitalName,
    cf.ProviderName,
    cf.PayerName,
    cf.PlanName,
    cf.ClaimType,
    cf.ServiceStartDate,
    cf.ClaimStatus,
    cf.TotalChargeAmount,
    cf.TotalAllowedAmount,
    cf.TotalPaidAmount,
    cf.TotalPatientResponsibilityAmount,
    cf.DeniedLineCount,
    cf.IsDeniedClaim;
GO


/*==========================================================
  VIEW 7: Analytics.vw_PatientBillingSummary
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_PatientBillingSummary
AS
WITH InvoiceTotals AS
(
    SELECT
        i.InvoiceID,
        i.PatientAccountID,
        i.PatientID,
        i.InvoiceNumber,
        i.InvoiceDate,
        i.DueDate,
        i.InvoiceStatus,
        SUM(il.LineAmount) AS InvoiceAmount
    FROM Billing.Invoice i
    JOIN Billing.InvoiceLine il
      ON il.InvoiceID = i.InvoiceID
    GROUP BY
        i.InvoiceID,
        i.PatientAccountID,
        i.PatientID,
        i.InvoiceNumber,
        i.InvoiceDate,
        i.DueDate,
        i.InvoiceStatus
),
AllocationTotals AS
(
    SELECT
        pa.InvoiceID,
        SUM(CASE WHEN pa.AllocationStatus = 'Posted'
                 THEN pa.AllocatedAmount ELSE 0 END) AS AllocatedAmount
    FROM Billing.PaymentAllocation pa
    GROUP BY pa.InvoiceID
)
SELECT
    it.InvoiceID,
    it.InvoiceNumber,
    it.PatientAccountID,
    pa.AccountNumber,
    it.PatientID,
    p.MedicalRecordNumber,
    p.FirstName + N' ' + p.LastName AS PatientName,
    it.InvoiceDate,
    it.DueDate,
    it.InvoiceStatus,
    it.InvoiceAmount,
    ISNULL(at.AllocatedAmount, 0) AS PaidAmount,
    it.InvoiceAmount - ISNULL(at.AllocatedAmount, 0) AS OutstandingAmount,
    CASE
        WHEN it.InvoiceAmount - ISNULL(at.AllocatedAmount, 0) <= 0 THEN 'Paid'
        WHEN it.DueDate < CAST(GETUTCDATE() AS DATE) THEN 'Overdue'
        WHEN ISNULL(at.AllocatedAmount, 0) > 0 THEN 'Partially Paid'
        ELSE 'Open'
    END AS DerivedPaymentStatus,
    CASE
        WHEN it.InvoiceAmount - ISNULL(at.AllocatedAmount, 0) <= 0 THEN 0
        WHEN DATEDIFF(DAY, it.DueDate, CAST(GETUTCDATE() AS DATE)) <= 0 THEN 0
        ELSE DATEDIFF(DAY, it.DueDate, CAST(GETUTCDATE() AS DATE))
    END AS DaysPastDue,
    pa.IsFinancialAssistanceEligible
FROM InvoiceTotals it
JOIN Billing.PatientAccount pa
  ON pa.PatientAccountID = it.PatientAccountID
JOIN Clinical.Patient p
  ON p.PatientID = it.PatientID
LEFT JOIN AllocationTotals at
  ON at.InvoiceID = it.InvoiceID;
GO


/*==========================================================
  VIEW 8: Analytics.vw_MarketingCampaignPerformance
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_MarketingCampaignPerformance
AS
WITH ChannelSpend AS
(
    SELECT
        cc.CampaignID,
        COUNT_BIG(*) AS ChannelCount,
        SUM(cc.PlannedSpendAmount) AS PlannedSpendAmount,
        SUM(cc.ActualSpendAmount) AS ActualSpendAmount
    FROM Marketing.CampaignChannel cc
    GROUP BY cc.CampaignID
),
InteractionSummary AS
(
    SELECT
        ci.CampaignID,
        COUNT_BIG(*) AS TotalInteractions,
        COUNT(DISTINCT ci.PatientID) AS ReachedPatients,
        SUM(CASE WHEN ci.InteractionType = 'Delivered' THEN 1 ELSE 0 END) AS DeliveredCount,
        SUM(CASE WHEN ci.InteractionType = 'Opened' THEN 1 ELSE 0 END) AS OpenedCount,
        SUM(CASE WHEN ci.InteractionType = 'Clicked' THEN 1 ELSE 0 END) AS ClickedCount,
        SUM(CASE WHEN ci.InteractionType = 'Converted' THEN 1 ELSE 0 END) AS ConvertedCount
    FROM Marketing.CampaignInteraction ci
    GROUP BY ci.CampaignID
),
AcquisitionSummary AS
(
    SELECT
        pa.CampaignID,
        COUNT_BIG(*) AS AcquiredPatientCount,
        SUM(pa.AcquisitionCost) AS AcquisitionCost
    FROM Marketing.PatientAcquisition pa
    WHERE pa.CampaignID IS NOT NULL
    GROUP BY pa.CampaignID
)
SELECT
    c.CampaignID,
    c.CampaignCode,
    c.CampaignName,
    c.CampaignType,
    c.CampaignObjective,
    c.StartDate,
    c.EndDate,
    c.CampaignStatus,
    c.HospitalID,
    h.HospitalName,
    c.BudgetAmount,
    ISNULL(cs.ChannelCount, 0) AS ChannelCount,
    ISNULL(cs.PlannedSpendAmount, 0) AS PlannedSpendAmount,
    ISNULL(cs.ActualSpendAmount, 0) AS ActualSpendAmount,
    ISNULL(i.TotalInteractions, 0) AS TotalInteractions,
    ISNULL(i.ReachedPatients, 0) AS ReachedPatients,
    ISNULL(i.DeliveredCount, 0) AS DeliveredCount,
    ISNULL(i.OpenedCount, 0) AS OpenedCount,
    ISNULL(i.ClickedCount, 0) AS ClickedCount,
    ISNULL(i.ConvertedCount, 0) AS ConvertedCount,
    ISNULL(a.AcquiredPatientCount, 0) AS AcquiredPatientCount,
    ISNULL(a.AcquisitionCost, 0) AS AcquisitionCost,
    CASE WHEN ISNULL(i.DeliveredCount, 0) = 0 THEN NULL
         ELSE CAST(i.OpenedCount * 100.0 / i.DeliveredCount AS DECIMAL(9,2))
    END AS OpenRatePercent,
    CASE WHEN ISNULL(i.OpenedCount, 0) = 0 THEN NULL
         ELSE CAST(i.ClickedCount * 100.0 / i.OpenedCount AS DECIMAL(9,2))
    END AS ClickThroughRatePercent,
    CASE WHEN ISNULL(i.TotalInteractions, 0) = 0 THEN NULL
         ELSE CAST(i.ConvertedCount * 100.0 / i.TotalInteractions AS DECIMAL(9,2))
    END AS ConversionRatePercent,
    CASE WHEN ISNULL(i.ConvertedCount, 0) = 0 THEN NULL
         ELSE CAST(ISNULL(cs.ActualSpendAmount, 0) / i.ConvertedCount AS DECIMAL(18,2))
    END AS CostPerConversion
FROM Marketing.Campaign c
LEFT JOIN Hospital.Hospital h
  ON h.HospitalID = c.HospitalID
LEFT JOIN ChannelSpend cs
  ON cs.CampaignID = c.CampaignID
LEFT JOIN InteractionSummary i
  ON i.CampaignID = c.CampaignID
LEFT JOIN AcquisitionSummary a
  ON a.CampaignID = c.CampaignID;
GO


/*==========================================================
  VIEW 9: Analytics.vw_AIPredictionPerformance
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_AIPredictionPerformance
AS
SELECT
    pr.PredictionID,
    m.ModelID,
    m.ModelCode,
    m.ModelName,
    mv.ModelVersionID,
    mv.VersionNumber,
    mv.AlgorithmName,
    pr.PatientID,
    pr.EncounterID,
    pr.PredictionDateTimeUTC,
    pr.PredictionType,
    pr.PredictedClass,
    pr.PredictedValue,
    pr.ProbabilityScore,
    pr.RiskScore,
    pr.ThresholdUsed,
    pr.PredictionStatus,
    po.PredictionOutcomeID,
    po.OutcomeType,
    po.ActualClass,
    po.ActualValue,
    po.OutcomeDateTimeUTC,
    po.IsFinalOutcome,
    CASE
        WHEN po.PredictionOutcomeID IS NULL THEN NULL
        WHEN pr.PredictedClass = po.ActualClass THEN 1
        ELSE 0
    END AS IsCorrectPrediction,
    CASE
        WHEN po.PredictionOutcomeID IS NULL THEN NULL
        WHEN pr.PredictedClass = N'High Risk'
         AND po.ActualClass = N'High Risk' THEN 'True Positive'
        WHEN pr.PredictedClass = N'High Risk'
         AND po.ActualClass <> N'High Risk' THEN 'False Positive'
        WHEN pr.PredictedClass <> N'High Risk'
         AND po.ActualClass = N'High Risk' THEN 'False Negative'
        ELSE 'True Negative'
    END AS ConfusionMatrixCategory
FROM AI.Prediction pr
JOIN AI.ModelVersion mv
  ON mv.ModelVersionID = pr.ModelVersionID
JOIN AI.Model m
  ON m.ModelID = mv.ModelID
LEFT JOIN AI.PredictionOutcome po
  ON po.PredictionID = pr.PredictionID
 AND po.IsFinalOutcome = 1;
GO


/*==========================================================
  VIEW 10: Analytics.vw_HospitalExecutiveSummary
==========================================================*/
CREATE OR ALTER VIEW Analytics.vw_HospitalExecutiveSummary
AS
WITH EncounterMetrics AS
(
    SELECT
        e.HospitalID,
        COUNT_BIG(*) AS TotalEncounters,
        COUNT(DISTINCT e.PatientID) AS UniquePatients,
        SUM(CASE WHEN e.IsTelehealth = 1 THEN 1 ELSE 0 END) AS TelehealthEncounters,
        SUM(CASE WHEN e.EncounterType = 'Emergency' THEN 1 ELSE 0 END) AS EmergencyEncounters,
        AVG(CAST(DATEDIFF(MINUTE, e.AdmissionDateTimeUTC, e.DischargeDateTimeUTC)
            AS DECIMAL(18,2))) AS AverageEncounterDurationMinutes
    FROM Clinical.Encounter e
    GROUP BY e.HospitalID
),
ClaimMetrics AS
(
    SELECT
        c.HospitalID,
        COUNT_BIG(*) AS TotalClaims,
        SUM(CASE WHEN c.ClaimStatus = 'Denied' THEN 1 ELSE 0 END) AS DeniedClaims,
        SUM(cl.ChargeAmount) AS TotalChargeAmount,
        SUM(cl.PaidAmount) AS TotalPaidAmount
    FROM Insurance.Claim c
    LEFT JOIN Insurance.ClaimLine cl
      ON cl.ClaimID = c.ClaimID
    GROUP BY c.HospitalID
),
TelehealthMetrics AS
(
    SELECT
        vv.HospitalID,
        COUNT_BIG(*) AS TotalVirtualVisits,
        SUM(CASE WHEN vv.VisitStatus = 'Completed' THEN 1 ELSE 0 END) AS CompletedVirtualVisits,
        SUM(CASE WHEN vv.VisitStatus = 'No Show' THEN 1 ELSE 0 END) AS NoShowVirtualVisits
    FROM Telehealth.VirtualVisit vv
    GROUP BY vv.HospitalID
),
ProviderMetrics AS
(
    SELECT
        p.HospitalID,
        COUNT_BIG(*) AS ActiveProviderCount
    FROM Hospital.Provider p
    WHERE p.IsActive = 1
    GROUP BY p.HospitalID
)
SELECT
    h.HospitalID,
    h.HospitalCode,
    h.HospitalName,
    h.HospitalType,
    h.NumberOfBeds,
    h.IsTeachingHospital,
    h.HasEmergencyDepartment,
    ISNULL(pm.ActiveProviderCount, 0) AS ActiveProviderCount,
    ISNULL(em.TotalEncounters, 0) AS TotalEncounters,
    ISNULL(em.UniquePatients, 0) AS UniquePatients,
    ISNULL(em.TelehealthEncounters, 0) AS TelehealthEncounters,
    ISNULL(em.EmergencyEncounters, 0) AS EmergencyEncounters,
    em.AverageEncounterDurationMinutes,
    ISNULL(cm.TotalClaims, 0) AS TotalClaims,
    ISNULL(cm.DeniedClaims, 0) AS DeniedClaims,
    CASE WHEN ISNULL(cm.TotalClaims, 0) = 0 THEN NULL
         ELSE CAST(cm.DeniedClaims * 100.0 / cm.TotalClaims AS DECIMAL(9,2))
    END AS ClaimDenialRatePercent,
    ISNULL(cm.TotalChargeAmount, 0) AS TotalChargeAmount,
    ISNULL(cm.TotalPaidAmount, 0) AS TotalPaidAmount,
    CASE WHEN ISNULL(cm.TotalChargeAmount, 0) = 0 THEN NULL
         ELSE CAST(cm.TotalPaidAmount * 100.0 / cm.TotalChargeAmount AS DECIMAL(9,2))
    END AS CollectionRatePercent,
    ISNULL(tm.TotalVirtualVisits, 0) AS TotalVirtualVisits,
    ISNULL(tm.CompletedVirtualVisits, 0) AS CompletedVirtualVisits,
    ISNULL(tm.NoShowVirtualVisits, 0) AS NoShowVirtualVisits,
    CASE WHEN ISNULL(tm.TotalVirtualVisits, 0) = 0 THEN NULL
         ELSE CAST(tm.NoShowVirtualVisits * 100.0 / tm.TotalVirtualVisits AS DECIMAL(9,2))
    END AS TelehealthNoShowRatePercent
FROM Hospital.Hospital h
LEFT JOIN EncounterMetrics em
  ON em.HospitalID = h.HospitalID
LEFT JOIN ClaimMetrics cm
  ON cm.HospitalID = h.HospitalID
LEFT JOIN TelehealthMetrics tm
  ON tm.HospitalID = h.HospitalID
LEFT JOIN ProviderMetrics pm
  ON pm.HospitalID = h.HospitalID;
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
ORDER BY v.name;
GO

SELECT TOP (10) * FROM Analytics.vw_Patient360 ORDER BY PatientID;
SELECT TOP (10) * FROM Analytics.vw_EncounterDetails ORDER BY EncounterID;
SELECT TOP (10) * FROM Analytics.vw_TelehealthPerformance ORDER BY VirtualVisitID;
SELECT TOP (10) * FROM Analytics.vw_ClaimFinancials ORDER BY ClaimID;
SELECT TOP (10) * FROM Analytics.vw_HospitalExecutiveSummary ORDER BY HospitalID;
GO

PRINT 'Script 013 complete: Analytics views created and validated.';
GO