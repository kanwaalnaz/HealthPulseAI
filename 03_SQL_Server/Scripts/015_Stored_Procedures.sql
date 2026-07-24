/*==========================================================
  HealthPulse AI
  Script: 015_Stored_Procedures.sql
  Purpose: Create reusable, parameterized stored procedures
           for executive reporting, patient analytics,
           claims, revenue cycle, telehealth, providers,
           and AI model monitoring.

  Prerequisites:
    013_Analytics_Views.sql
    014_Executive_KPI_Views.sql
==========================================================*/

USE HealthPulseAI;
GO

SET NOCOUNT ON;
GO

IF SCHEMA_ID('Analytics') IS NULL
    EXEC('CREATE SCHEMA Analytics AUTHORIZATION dbo;');
GO


/*==========================================================
  PROCEDURE 1: Enterprise Executive Dashboard
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_EnterpriseExecutiveDashboard
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM Analytics.vw_KPI_EnterpriseScorecard;
END;
GO


/*==========================================================
  PROCEDURE 2: Patient 360
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_GetPatient360
    @PatientID INT = NULL,
    @MedicalRecordNumber VARCHAR(50) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @PatientID IS NULL AND @MedicalRecordNumber IS NULL
    BEGIN
        THROW 51001, 'Provide either @PatientID or @MedicalRecordNumber.', 1;
    END;

    SELECT *
    FROM Analytics.vw_Patient360
    WHERE (@PatientID IS NULL OR PatientID = @PatientID)
      AND (@MedicalRecordNumber IS NULL OR MedicalRecordNumber = @MedicalRecordNumber);
END;
GO


/*==========================================================
  PROCEDURE 3: Hospital Performance
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_HospitalPerformance
    @HospitalID INT = NULL,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @StartDate = ISNULL(@StartDate, '19000101');
    SET @EndDate   = ISNULL(@EndDate, '99991231');

    IF @EndDate < @StartDate
        THROW 51002, '@EndDate must be greater than or equal to @StartDate.', 1;

    SELECT *
    FROM Analytics.vw_KPI_HospitalMonthlyPerformance
    WHERE (@HospitalID IS NULL OR HospitalID = @HospitalID)
      AND KPI_Month >= DATEFROMPARTS(YEAR(@StartDate), MONTH(@StartDate), 1)
      AND KPI_Month <= DATEFROMPARTS(YEAR(@EndDate), MONTH(@EndDate), 1)
    ORDER BY KPI_Month, HospitalID;
END;
GO


/*==========================================================
  PROCEDURE 4: Provider Productivity
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_ProviderProductivity
    @HospitalID INT = NULL,
    @DepartmentID INT = NULL,
    @MinimumEncounters INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @MinimumEncounters < 0
        THROW 51003, '@MinimumEncounters cannot be negative.', 1;

    SELECT *
    FROM Analytics.vw_KPI_ProviderProductivity
    WHERE (@HospitalID IS NULL OR HospitalID = @HospitalID)
      AND (@DepartmentID IS NULL OR DepartmentID = @DepartmentID)
      AND TotalEncounters >= @MinimumEncounters
    ORDER BY TotalEncounters DESC, ProviderID;
END;
GO


/*==========================================================
  PROCEDURE 5: Claim Denial Report
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_ClaimDenialReport
    @StartDate DATE = NULL,
    @EndDate DATE = NULL,
    @HospitalName NVARCHAR(200) = NULL,
    @PayerName NVARCHAR(200) = NULL,
    @MinimumDenialRatePercent DECIMAL(9,2) = 0
AS
BEGIN
    SET NOCOUNT ON;

    SET @StartDate = ISNULL(@StartDate, '19000101');
    SET @EndDate   = ISNULL(@EndDate, '99991231');

    IF @EndDate < @StartDate
        THROW 51004, '@EndDate must be greater than or equal to @StartDate.', 1;

    IF @MinimumDenialRatePercent < 0 OR @MinimumDenialRatePercent > 100
        THROW 51005, '@MinimumDenialRatePercent must be between 0 and 100.', 1;

    SELECT *
    FROM Analytics.vw_KPI_ClaimDenialMonthly
    WHERE KPI_Month >= DATEFROMPARTS(YEAR(@StartDate), MONTH(@StartDate), 1)
      AND KPI_Month <= DATEFROMPARTS(YEAR(@EndDate), MONTH(@EndDate), 1)
      AND (@HospitalName IS NULL OR HospitalName = @HospitalName)
      AND (@PayerName IS NULL OR PayerName = @PayerName)
      AND ISNULL(DenialRatePercent, 0) >= @MinimumDenialRatePercent
    ORDER BY KPI_Month, DenialRatePercent DESC, DeniedChargeAmount DESC;
END;
GO


/*==========================================================
  PROCEDURE 6: Monthly Revenue Cycle
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_MonthlyRevenueCycle
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @StartDate = ISNULL(@StartDate, '19000101');
    SET @EndDate   = ISNULL(@EndDate, '99991231');

    IF @EndDate < @StartDate
        THROW 51006, '@EndDate must be greater than or equal to @StartDate.', 1;

    SELECT *
    FROM Analytics.vw_KPI_RevenueCycleMonthly
    WHERE KPI_Month >= DATEFROMPARTS(YEAR(@StartDate), MONTH(@StartDate), 1)
      AND KPI_Month <= DATEFROMPARTS(YEAR(@EndDate), MONTH(@EndDate), 1)
    ORDER BY KPI_Month;
END;
GO


/*==========================================================
  PROCEDURE 7: Telehealth Operations
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_TelehealthOperations
    @StartDate DATE = NULL,
    @EndDate DATE = NULL,
    @HospitalID INT = NULL,
    @DepartmentID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @StartDate = ISNULL(@StartDate, '19000101');
    SET @EndDate   = ISNULL(@EndDate, '99991231');

    IF @EndDate < @StartDate
        THROW 51007, '@EndDate must be greater than or equal to @StartDate.', 1;

    SELECT *
    FROM Analytics.vw_KPI_TelehealthMonthly
    WHERE KPI_Month >= DATEFROMPARTS(YEAR(@StartDate), MONTH(@StartDate), 1)
      AND KPI_Month <= DATEFROMPARTS(YEAR(@EndDate), MONTH(@EndDate), 1)
      AND (@HospitalID IS NULL OR HospitalID = @HospitalID)
      AND (@DepartmentID IS NULL OR DepartmentID = @DepartmentID)
    ORDER BY KPI_Month, HospitalID, DepartmentID;
END;
GO


/*==========================================================
  PROCEDURE 8: High-Risk Patient Worklist
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_HighRiskPatientWorklist
    @RiskTier VARCHAR(20) = NULL,
    @MinimumOutstandingAmount DECIMAL(18,2) = 0,
    @NeedsReviewOnly BIT = 1
AS
BEGIN
    SET NOCOUNT ON;

    IF @RiskTier IS NOT NULL
       AND @RiskTier NOT IN ('High', 'Medium', 'Low')
        THROW 51008, '@RiskTier must be High, Medium, Low, or NULL.', 1;

    SELECT *
    FROM Analytics.vw_KPI_PatientRiskPopulation
    WHERE (@RiskTier IS NULL OR DerivedPatientRiskTier = @RiskTier)
      AND EstimatedOutstandingAmount >= @MinimumOutstandingAmount
      AND (@NeedsReviewOnly = 0 OR NeedsCareManagementReview = 1)
    ORDER BY
        CASE DerivedPatientRiskTier
            WHEN 'High' THEN 1
            WHEN 'Medium' THEN 2
            ELSE 3
        END,
        LatestProbabilityScore DESC,
        EmergencyEncounters DESC,
        TotalEncounters DESC;
END;
GO


/*==========================================================
  PROCEDURE 9: AI Model Performance
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_AIModelPerformance
    @ModelCode VARCHAR(100) = NULL,
    @MinimumPredictionCount INT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @MinimumPredictionCount < 0
        THROW 51009, '@MinimumPredictionCount cannot be negative.', 1;

    SELECT *
    FROM Analytics.vw_KPI_AIModelPerformance
    WHERE (@ModelCode IS NULL OR ModelCode = @ModelCode)
      AND TotalPredictions >= @MinimumPredictionCount
    ORDER BY ModelName, VersionNumber;
END;
GO


/*==========================================================
  PROCEDURE 10: Patient Encounter History
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_PatientEncounterHistory
    @PatientID INT,
    @StartDate DATE = NULL,
    @EndDate DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @PatientID IS NULL
        THROW 51010, '@PatientID is required.', 1;

    SET @StartDate = ISNULL(@StartDate, '19000101');
    SET @EndDate   = ISNULL(@EndDate, '99991231');

    IF @EndDate < @StartDate
        THROW 51011, '@EndDate must be greater than or equal to @StartDate.', 1;

    SELECT *
    FROM Analytics.vw_EncounterDetails
    WHERE PatientID = @PatientID
      AND CAST(AdmissionDateTimeUTC AS DATE) BETWEEN @StartDate AND @EndDate
    ORDER BY AdmissionDateTimeUTC DESC, EncounterID DESC;
END;
GO


/*==========================================================
  PROCEDURE 11: Patient Billing Detail
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_PatientBillingDetail
    @PatientID INT = NULL,
    @MedicalRecordNumber VARCHAR(50) = NULL,
    @OnlyOutstanding BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF @PatientID IS NULL AND @MedicalRecordNumber IS NULL
        THROW 51012, 'Provide either @PatientID or @MedicalRecordNumber.', 1;

    SELECT *
    FROM Analytics.vw_PatientBillingSummary
    WHERE (@PatientID IS NULL OR PatientID = @PatientID)
      AND (@MedicalRecordNumber IS NULL OR MedicalRecordNumber = @MedicalRecordNumber)
      AND (@OnlyOutstanding = 0 OR OutstandingAmount > 0)
    ORDER BY InvoiceDate DESC, InvoiceID DESC;
END;
GO


/*==========================================================
  PROCEDURE 12: Top Executive Exceptions
==========================================================*/
CREATE OR ALTER PROCEDURE Analytics.usp_TopExecutiveExceptions
    @TopN INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    IF @TopN IS NULL OR @TopN < 1 OR @TopN > 1000
        THROW 51013, '@TopN must be between 1 and 1000.', 1;

    SELECT TOP (@TopN)
        'High Outstanding Balance' AS ExceptionType,
        PatientID AS EntityID,
        MedicalRecordNumber AS EntityCode,
        CAST(EstimatedOutstandingAmount AS DECIMAL(18,2)) AS ExceptionValue,
        DerivedPatientRiskTier AS AdditionalContext
    FROM Analytics.vw_KPI_PatientRiskPopulation
    WHERE EstimatedOutstandingAmount > 0
    ORDER BY EstimatedOutstandingAmount DESC;

    SELECT TOP (@TopN)
        'Claim Denial' AS ExceptionType,
        ClaimID AS EntityID,
        ClaimNumber AS EntityCode,
        CAST(TotalChargeAmount AS DECIMAL(18,2)) AS ExceptionValue,
        ISNULL(PrimaryDenialReasonCode, 'Unknown') AS AdditionalContext
    FROM Analytics.vw_ClaimDenialAnalysis
    WHERE IsDeniedClaim = 1
    ORDER BY TotalChargeAmount DESC, ClaimID;

    SELECT TOP (@TopN)
        'Telehealth No Show' AS ExceptionType,
        VirtualVisitID AS EntityID,
        VisitNumber AS EntityCode,
        CAST(ISNULL(PatientJoinDelayMinutes, 0) AS DECIMAL(18,2)) AS ExceptionValue,
        HospitalName AS AdditionalContext
    FROM Analytics.vw_TelehealthPerformance
    WHERE IsNoShow = 1
    ORDER BY ScheduledStartDateTimeUTC DESC;
END;
GO


/*==========================================================
  VALIDATION
==========================================================*/
SELECT
    s.name AS SchemaName,
    p.name AS ProcedureName
FROM sys.procedures p
JOIN sys.schemas s
  ON s.schema_id = p.schema_id
WHERE s.name = 'Analytics'
ORDER BY p.name;
GO

EXEC Analytics.usp_EnterpriseExecutiveDashboard;
EXEC Analytics.usp_GetPatient360 @PatientID = 1;
EXEC Analytics.usp_HospitalPerformance @HospitalID = 1;
EXEC Analytics.usp_ProviderProductivity @MinimumEncounters = 1;
EXEC Analytics.usp_MonthlyRevenueCycle;
EXEC Analytics.usp_AIModelPerformance;
GO

PRINT 'Script 015 complete: Analytics stored procedures created and validated.';
GO