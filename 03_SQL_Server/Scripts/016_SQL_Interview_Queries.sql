/*==========================================================
  HealthPulse AI
  Script: 016_SQL_Interview_Queries.sql
  Purpose: Advanced SQL analytics and interview preparation
  Prerequisites: Scripts 013, 014 and 015
==========================================================*/

USE HealthPulseAI;
GO
SET NOCOUNT ON;
GO

/* 1. Monthly encounter volume and growth — CTE + LAG */
WITH m AS (
    SELECT DATEFROMPARTS(YEAR(AdmissionDateTimeUTC),MONTH(AdmissionDateTimeUTC),1) EncounterMonth,
           COUNT_BIG(*) TotalEncounters
    FROM Analytics.vw_EncounterDetails
    GROUP BY DATEFROMPARTS(YEAR(AdmissionDateTimeUTC),MONTH(AdmissionDateTimeUTC),1)
), g AS (
    SELECT *, LAG(TotalEncounters) OVER(ORDER BY EncounterMonth) PreviousMonthEncounters
    FROM m
)
SELECT *, TotalEncounters-PreviousMonthEncounters EncounterChange,
       CAST((TotalEncounters-PreviousMonthEncounters)*100.0/NULLIF(PreviousMonthEncounters,0) AS DECIMAL(10,2)) MonthOverMonthGrowthPercent
FROM g ORDER BY EncounterMonth;
GO

/* 2. Hospital ranking — RANK */
SELECT HospitalID,HospitalName,SUM(TotalEncounters) TotalEncounters,
       RANK() OVER(ORDER BY SUM(TotalEncounters) DESC) HospitalRank
FROM Analytics.vw_KPI_HospitalMonthlyPerformance
GROUP BY HospitalID,HospitalName
ORDER BY HospitalRank;
GO

/* 3. Top three providers per hospital — ROW_NUMBER */
WITH r AS (
    SELECT HospitalID,HospitalName,ProviderID,ProviderName,ProviderType,TotalEncounters,
           ROW_NUMBER() OVER(PARTITION BY HospitalID ORDER BY TotalEncounters DESC,ProviderID) ProviderRank
    FROM Analytics.vw_KPI_ProviderProductivity
)
SELECT * FROM r WHERE ProviderRank<=3 ORDER BY HospitalName,ProviderRank;
GO

/* 4. Running total of collections */
SELECT KPI_Month,TotalCollectedAmount,
       SUM(TotalCollectedAmount) OVER(ORDER BY KPI_Month ROWS UNBOUNDED PRECEDING) RunningCollectedAmount
FROM Analytics.vw_KPI_RevenueCycleMonthly
ORDER BY KPI_Month;
GO

/* 5. Three-month moving average */
SELECT KPI_Month,TotalCollectedAmount,
       CAST(AVG(TotalCollectedAmount) OVER(ORDER BY KPI_Month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS DECIMAL(18,2)) ThreeMonthMovingAverage
FROM Analytics.vw_KPI_RevenueCycleMonthly
ORDER BY KPI_Month;
GO

/* 6. Frequent emergency users */
SELECT PatientID,MedicalRecordNumber,FirstName,LastName,EmergencyEncounters,TotalEncounters,
       CAST(EmergencyEncounters*100.0/NULLIF(TotalEncounters,0) AS DECIMAL(10,2)) EmergencyEncounterRatePercent
FROM Analytics.vw_Patient360
WHERE EmergencyEncounters>=2
ORDER BY EmergencyEncounters DESC,TotalEncounters DESC;
GO

/* 7. Patient risk segmentation */
SELECT DerivedPatientRiskTier,COUNT_BIG(*) PatientCount,
       AVG(CAST(TotalEncounters AS DECIMAL(18,2))) AverageEncounters,
       AVG(CAST(EmergencyEncounters AS DECIMAL(18,2))) AverageEmergencyEncounters,
       AVG(CAST(EstimatedOutstandingAmount AS DECIMAL(18,2))) AverageOutstandingAmount
FROM Analytics.vw_KPI_PatientRiskPopulation
GROUP BY DerivedPatientRiskTier;
GO

/* 8. Patients with no encounters — NOT EXISTS */
SELECT p.PatientID,p.MedicalRecordNumber,p.FirstName,p.LastName
FROM Analytics.vw_Patient360 p
WHERE NOT EXISTS (SELECT 1 FROM Analytics.vw_EncounterDetails e WHERE e.PatientID=p.PatientID);
GO

/* 9. Latest encounter per patient — CROSS APPLY */
SELECT p.PatientID,p.MedicalRecordNumber,p.FirstName,p.LastName,x.*
FROM Analytics.vw_Patient360 p
CROSS APPLY (
    SELECT TOP(1) e.EncounterID,e.EncounterType,e.AdmissionDateTimeUTC,e.HospitalName,e.ProviderName
    FROM Analytics.vw_EncounterDetails e
    WHERE e.PatientID=p.PatientID
    ORDER BY e.AdmissionDateTimeUTC DESC,e.EncounterID DESC
) x;
GO

/* 10. Include patients with no encounters — OUTER APPLY */
SELECT p.PatientID,p.MedicalRecordNumber,p.FirstName,p.LastName,x.EncounterID,x.EncounterType,x.AdmissionDateTimeUTC
FROM Analytics.vw_Patient360 p
OUTER APPLY (
    SELECT TOP(1) e.EncounterID,e.EncounterType,e.AdmissionDateTimeUTC
    FROM Analytics.vw_EncounterDetails e
    WHERE e.PatientID=p.PatientID
    ORDER BY e.AdmissionDateTimeUTC DESC,e.EncounterID DESC
) x;
GO

/* 11. Monthly collection rate */
SELECT KPI_Month,TotalChargeAmount,InsurancePaidAmount,PatientPaidAmount,TotalCollectedAmount,
       CAST(TotalCollectedAmount*100.0/NULLIF(TotalChargeAmount,0) AS DECIMAL(10,2)) TotalCollectionRatePercent
FROM Analytics.vw_KPI_RevenueCycleMonthly
ORDER BY KPI_Month;
GO

/* 12. Payer denial ranking */
SELECT PayerName,SUM(TotalClaims) TotalClaims,SUM(DeniedClaims) DeniedClaims,SUM(DeniedChargeAmount) DeniedChargeAmount,
       RANK() OVER(ORDER BY SUM(DeniedChargeAmount) DESC) PayerDenialRank
FROM Analytics.vw_KPI_ClaimDenialMonthly
GROUP BY PayerName
ORDER BY PayerDenialRank;
GO

/* 13. Denial rate vs enterprise average */
SELECT KPI_Month,HospitalName,PayerName,TotalClaims,DeniedClaims,DenialRatePercent,
       (SELECT CAST(SUM(DeniedClaims)*100.0/NULLIF(SUM(TotalClaims),0) AS DECIMAL(10,2))
        FROM Analytics.vw_KPI_ClaimDenialMonthly) EnterpriseDenialRatePercent
FROM Analytics.vw_KPI_ClaimDenialMonthly
ORDER BY DenialRatePercent DESC;
GO

/* 14. Outstanding balances by risk tier */
SELECT DerivedPatientRiskTier,COUNT_BIG(*) PatientCount,
       SUM(EstimatedOutstandingAmount) TotalOutstandingAmount,
       AVG(EstimatedOutstandingAmount) AverageOutstandingAmount,
       MAX(EstimatedOutstandingAmount) MaximumOutstandingAmount
FROM Analytics.vw_KPI_PatientRiskPopulation
GROUP BY DerivedPatientRiskTier;
GO

/* 15. Overdue invoices above average */
SELECT PatientID,MedicalRecordNumber,InvoiceID,InvoiceDate,OutstandingAmount,DerivedPaymentStatus
FROM Analytics.vw_PatientBillingSummary
WHERE DerivedPaymentStatus='Overdue'
  AND OutstandingAmount>(SELECT AVG(OutstandingAmount) FROM Analytics.vw_PatientBillingSummary WHERE DerivedPaymentStatus='Overdue')
ORDER BY OutstandingAmount DESC;
GO

/* 16. Monthly telehealth adoption */
SELECT KPI_Month,SUM(TotalEncounters) TotalEncounters,SUM(TelehealthEncounters) TelehealthEncounters,
       CAST(SUM(TelehealthEncounters)*100.0/NULLIF(SUM(TotalEncounters),0) AS DECIMAL(10,2)) TelehealthAdoptionRatePercent
FROM Analytics.vw_KPI_HospitalMonthlyPerformance
GROUP BY KPI_Month
ORDER BY KPI_Month;
GO

/* 17. Telehealth platform comparison */
SELECT PlatformName,SUM(TotalVirtualVisits) TotalVirtualVisits,SUM(CompletedVisits) CompletedVisits,
       SUM(NoShowVisits) NoShowVisits,SUM(DisconnectedVisits) DisconnectedVisits,
       AVG(AverageVisitDurationMinutes) AverageVisitDurationMinutes
FROM Analytics.vw_KPI_TelehealthMonthly
GROUP BY PlatformName
ORDER BY TotalVirtualVisits DESC;
GO

/* 18. Department no-show ranking */
WITH d AS (
    SELECT DepartmentID,DepartmentName,SUM(TotalVirtualVisits) TotalVirtualVisits,SUM(NoShowVisits) NoShowVisits,
           CAST(SUM(NoShowVisits)*100.0/NULLIF(SUM(TotalVirtualVisits),0) AS DECIMAL(10,2)) NoShowRatePercent
    FROM Analytics.vw_KPI_TelehealthMonthly
    GROUP BY DepartmentID,DepartmentName
)
SELECT *,DENSE_RANK() OVER(ORDER BY NoShowRatePercent DESC) NoShowRank
FROM d ORDER BY NoShowRank;
GO

/* 19. Telehealth technical errors */
SELECT VirtualVisitID,VisitNumber,HospitalName,DepartmentName,PlatformName,PatientDeviceType,
       TechnicalErrorCount,IsDisconnected,ScheduledStartDateTimeUTC
FROM Analytics.vw_TelehealthPerformance
WHERE TechnicalErrorCount>0 OR IsDisconnected=1
ORDER BY TechnicalErrorCount DESC,ScheduledStartDateTimeUTC DESC;
GO

/* 20. Rank AI models by accuracy */
SELECT ModelCode,ModelName,VersionNumber,TotalPredictions,AccuracyPercent,PrecisionPercent,RecallPercent,
       RANK() OVER(ORDER BY AccuracyPercent DESC) AccuracyRank
FROM Analytics.vw_KPI_AIModelPerformance
ORDER BY AccuracyRank;
GO

/* 21. Models where precision is below recall */
SELECT ModelCode,ModelName,VersionNumber,PrecisionPercent,RecallPercent,
       RecallPercent-PrecisionPercent RecallPrecisionGap
FROM Analytics.vw_KPI_AIModelPerformance
WHERE PrecisionPercent<RecallPercent
ORDER BY RecallPrecisionGap DESC;
GO

/* 22. High-risk predictions by model */
SELECT ModelName,VersionNumber,COUNT_BIG(*) TotalPredictions,
       SUM(CASE WHEN PredictedClass='High Risk' THEN 1 ELSE 0 END) HighRiskPredictions,
       CAST(SUM(CASE WHEN PredictedClass='High Risk' THEN 1 ELSE 0 END)*100.0/COUNT_BIG(*) AS DECIMAL(10,2)) HighRiskPredictionRatePercent
FROM Analytics.vw_AIPredictionPerformance
GROUP BY ModelName,VersionNumber
ORDER BY HighRiskPredictionRatePercent DESC;
GO

/* 23. False-negative review list */
SELECT
    PredictionID,
    PatientID,
    ModelName,
    VersionNumber,
    PredictedClass,
    ActualClass,
    ProbabilityScore,
    RiskScore,
    PredictionDateTimeUTC
FROM Analytics.vw_AIPredictionPerformance
WHERE ConfusionMatrixCategory = 'False Negative'
ORDER BY RiskScore DESC, ProbabilityScore DESC;
GO

/* 24. Monthly prediction volume */
SELECT DATEFROMPARTS(YEAR(PredictionDateTimeUTC),MONTH(PredictionDateTimeUTC),1) PredictionMonth,
       ModelName,COUNT_BIG(*) PredictionCount
FROM Analytics.vw_AIPredictionPerformance
GROUP BY DATEFROMPARTS(YEAR(PredictionDateTimeUTC),MONTH(PredictionDateTimeUTC),1),ModelName
ORDER BY PredictionMonth,ModelName;
GO

/* 25. Provider productivity quartiles — NTILE */
SELECT ProviderID,ProviderName,HospitalName,TotalEncounters,
       NTILE(4) OVER(ORDER BY TotalEncounters DESC) ProductivityQuartile
FROM Analytics.vw_KPI_ProviderProductivity;
GO

/* 26. Provider vs hospital average */
SELECT ProviderID,ProviderName,HospitalName,TotalEncounters,
       CAST(AVG(CAST(TotalEncounters AS DECIMAL(18,2))) OVER(PARTITION BY HospitalID) AS DECIMAL(18,2)) HospitalAverageEncounters,
       CAST(TotalEncounters-AVG(CAST(TotalEncounters AS DECIMAL(18,2))) OVER(PARTITION BY HospitalID) AS DECIMAL(18,2)) DifferenceFromHospitalAverage
FROM Analytics.vw_KPI_ProviderProductivity
ORDER BY HospitalName,TotalEncounters DESC;
GO

/* 27. First and latest encounter per patient */
SELECT DISTINCT PatientID,
       FIRST_VALUE(AdmissionDateTimeUTC) OVER(PARTITION BY PatientID ORDER BY AdmissionDateTimeUTC) FirstEncounterDate,
       LAST_VALUE(AdmissionDateTimeUTC) OVER(PARTITION BY PatientID ORDER BY AdmissionDateTimeUTC ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) MostRecentEncounterDate
FROM Analytics.vw_EncounterDetails;
GO

/* 28. Days since previous encounter */
WITH e AS (
    SELECT PatientID,EncounterID,AdmissionDateTimeUTC,
           LAG(AdmissionDateTimeUTC) OVER(PARTITION BY PatientID ORDER BY AdmissionDateTimeUTC,EncounterID) PreviousEncounterDate
    FROM Analytics.vw_EncounterDetails
)
SELECT *,DATEDIFF(DAY,PreviousEncounterDate,AdmissionDateTimeUTC) DaysSincePreviousEncounter
FROM e WHERE PreviousEncounterDate IS NOT NULL
ORDER BY PatientID,AdmissionDateTimeUTC;
GO

/* 29. Potential 30-day readmissions */
WITH e AS (
    SELECT PatientID,EncounterID,HospitalName,AdmissionDateTimeUTC,
           LAG(AdmissionDateTimeUTC) OVER(PARTITION BY PatientID ORDER BY AdmissionDateTimeUTC,EncounterID) PreviousEncounterDate
    FROM Analytics.vw_EncounterDetails
)
SELECT *,DATEDIFF(DAY,PreviousEncounterDate,AdmissionDateTimeUTC) DaysBetweenEncounters
FROM e
WHERE PreviousEncounterDate IS NOT NULL
  AND DATEDIFF(DAY,PreviousEncounterDate,AdmissionDateTimeUTC) BETWEEN 1 AND 30
ORDER BY PatientID,AdmissionDateTimeUTC;
GO

/* 30. Encounter type pivot */
SELECT EncounterMonth,ISNULL([Emergency],0) Emergency,ISNULL([Inpatient],0) Inpatient,
       ISNULL([Outpatient],0) Outpatient,ISNULL([Telehealth],0) Telehealth
FROM (
    SELECT DATEFROMPARTS(YEAR(AdmissionDateTimeUTC),MONTH(AdmissionDateTimeUTC),1) EncounterMonth,
           EncounterType,EncounterID
    FROM Analytics.vw_EncounterDetails
) s
PIVOT(COUNT(EncounterID) FOR EncounterType IN([Emergency],[Inpatient],[Outpatient],[Telehealth])) p
ORDER BY EncounterMonth;
GO

/* 31. Executive KPI unpivot pattern */
SELECT KPIName,KPIValue
FROM Analytics.vw_KPI_EnterpriseScorecard e
CROSS APPLY (VALUES
 ('Total Encounters',CAST(e.TotalEncounters AS DECIMAL(18,2))),
 ('Unique Patients',CAST(e.UniquePatients AS DECIMAL(18,2))),
 ('Total Claims',CAST(e.TotalClaims AS DECIMAL(18,2))),
 ('Denied Claims',CAST(e.DeniedClaims AS DECIMAL(18,2))),
 ('Total Predictions',CAST(e.TotalPredictions AS DECIMAL(18,2))),
 ('Prediction Accuracy Percent',CAST(e.PredictionAccuracyPercent AS DECIMAL(18,2)))
) v(KPIName,KPIValue);
GO

/* 32. Recursive month calendar */
DECLARE @StartMonth DATE=(SELECT MIN(KPI_Month) FROM Analytics.vw_KPI_RevenueCycleMonthly);
DECLARE @EndMonth DATE=(SELECT MAX(KPI_Month) FROM Analytics.vw_KPI_RevenueCycleMonthly);
WITH c AS (
    SELECT @StartMonth CalendarMonth
    UNION ALL
    SELECT DATEADD(MONTH,1,CalendarMonth) FROM c WHERE CalendarMonth<@EndMonth
)
SELECT c.CalendarMonth,ISNULL(r.TotalCollectedAmount,0) TotalCollectedAmount
FROM c LEFT JOIN Analytics.vw_KPI_RevenueCycleMonthly r ON r.KPI_Month=c.CalendarMonth
ORDER BY c.CalendarMonth OPTION(MAXRECURSION 1000);
GO

/* 33. Providers without claims */
SELECT p.ProviderID,p.ProviderName,p.HospitalName,p.TotalEncounters
FROM Analytics.vw_KPI_ProviderProductivity p
WHERE NOT EXISTS (SELECT 1 FROM Analytics.vw_ClaimFinancials c WHERE c.ProviderID=p.ProviderID)
ORDER BY p.TotalEncounters DESC;
GO

/* 34. Hospitals above enterprise denial average */
WITH h AS (
    SELECT HospitalName,SUM(TotalClaims) TotalClaims,SUM(DeniedClaims) DeniedClaims,
           CAST(SUM(DeniedClaims)*100.0/NULLIF(SUM(TotalClaims),0) AS DECIMAL(10,2)) HospitalDenialRatePercent
    FROM Analytics.vw_KPI_ClaimDenialMonthly GROUP BY HospitalName
), e AS (
    SELECT CAST(SUM(DeniedClaims)*100.0/NULLIF(SUM(TotalClaims),0) AS DECIMAL(10,2)) EnterpriseDenialRatePercent
    FROM Analytics.vw_KPI_ClaimDenialMonthly
)
SELECT h.*,e.EnterpriseDenialRatePercent
FROM h CROSS JOIN e
WHERE h.HospitalDenialRatePercent>e.EnterpriseDenialRatePercent
ORDER BY h.HospitalDenialRatePercent DESC;
GO

/* 35. Second-highest provider */
WITH r AS (
    SELECT ProviderID,ProviderName,TotalEncounters,
           DENSE_RANK() OVER(ORDER BY TotalEncounters DESC) EncounterRank
    FROM Analytics.vw_KPI_ProviderProductivity
)
SELECT ProviderID,ProviderName,TotalEncounters FROM r WHERE EncounterRank=2;
GO

/* 36. Duplicate MRN check */
SELECT MedicalRecordNumber,COUNT_BIG(*) DuplicateCount
FROM Analytics.vw_Patient360
GROUP BY MedicalRecordNumber
HAVING COUNT_BIG(*)>1;
GO

/* 37. Highest outstanding patient per risk tier */
WITH r AS (
    SELECT PatientID,MedicalRecordNumber,FirstName,LastName,DerivedPatientRiskTier,EstimatedOutstandingAmount,
           ROW_NUMBER() OVER(PARTITION BY DerivedPatientRiskTier ORDER BY EstimatedOutstandingAmount DESC,PatientID) BalanceRank
    FROM Analytics.vw_KPI_PatientRiskPopulation
)
SELECT * FROM r WHERE BalanceRank=1;
GO

/* 38. Hospital share of enterprise encounters */
SELECT HospitalID,HospitalName,SUM(TotalEncounters) HospitalEncounters,
       CAST(SUM(TotalEncounters)*100.0/SUM(SUM(TotalEncounters)) OVER() AS DECIMAL(10,2)) EnterpriseEncounterSharePercent
FROM Analytics.vw_KPI_HospitalMonthlyPerformance
GROUP BY HospitalID,HospitalName
ORDER BY HospitalEncounters DESC;
GO

/* 39. Executive exception score */
SELECT PatientID,MedicalRecordNumber,DerivedPatientRiskTier,EmergencyEncounters,EstimatedOutstandingAmount,LatestProbabilityScore,
       CASE DerivedPatientRiskTier WHEN 'High' THEN 50 WHEN 'Medium' THEN 25 ELSE 5 END
       +CASE WHEN EmergencyEncounters>=3 THEN 25 WHEN EmergencyEncounters=2 THEN 15 WHEN EmergencyEncounters=1 THEN 5 ELSE 0 END
       +CASE WHEN EstimatedOutstandingAmount>=5000 THEN 25 WHEN EstimatedOutstandingAmount>=1000 THEN 10 ELSE 0 END ExecutiveExceptionScore
FROM Analytics.vw_KPI_PatientRiskPopulation
ORDER BY ExecutiveExceptionScore DESC,EstimatedOutstandingAmount DESC;
GO

/* 40. Stored procedure inventory */
SELECT s.name SchemaName,p.name ProcedureName,p.create_date,p.modify_date
FROM sys.procedures p
JOIN sys.schemas s ON s.schema_id=p.schema_id
WHERE s.name='Analytics'
ORDER BY p.name;
GO

PRINT 'Script 016 complete: Advanced SQL interview queries are ready.';
GO