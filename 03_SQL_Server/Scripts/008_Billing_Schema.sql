/*==========================================================
  HealthPulse AI
  Script: 008_Billing_Schema.sql
  Purpose: Create the core Billing schema tables.

  Tables:
    1. Billing.PatientAccount
    2. Billing.Invoice
    3. Billing.InvoiceLine
    4. Billing.Payment
    5. Billing.PaymentAllocation
    6. Billing.Adjustment
    7. Billing.Refund
    8. Billing.AccountBalanceHistory

  Design standards:
    - INT IDENTITY surrogate primary keys
    - UTC audit timestamps
    - DATETIME2(3) for timestamps
    - DECIMAL(18,2) for monetary values
    - Trusted foreign keys created WITH CHECK
    - Composite foreign keys enforce patient, account, claim, invoice, and refund consistency
    - Filtered unique indexes for nullable identifiers
    - Calculated balances stored only in historical snapshots
==========================================================*/

USE HealthPulseAI;
GO

SET XACT_ABORT ON;
GO


/*==========================================================
  Prerequisite parent-table constraints
==========================================================*/

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


/*
  Allows Billing.Invoice to verify that a claim belongs
  to the same patient as the invoice.
*/
IF OBJECT_ID('Insurance.Claim', 'U') IS NOT NULL
   AND NOT EXISTS
   (
       SELECT 1
       FROM sys.key_constraints
       WHERE name = 'UQ_Claim_ClaimID_PatientID'
         AND parent_object_id = OBJECT_ID('Insurance.Claim')
   )
BEGIN
    ALTER TABLE Insurance.Claim
    ADD CONSTRAINT UQ_Claim_ClaimID_PatientID
        UNIQUE (ClaimID, PatientID);

    PRINT 'Added UQ_Claim_ClaimID_PatientID.';
END
ELSE
BEGIN
    PRINT 'Skipped UQ_Claim_ClaimID_PatientID because it already exists.';
END;
GO


/*==========================================================
  Create Billing schema
==========================================================*/

IF NOT EXISTS
(
    SELECT 1
    FROM sys.schemas
    WHERE name = 'Billing'
)
BEGIN
    EXEC ('CREATE SCHEMA Billing;');

    PRINT 'Created schema Billing.';
END
ELSE
BEGIN
    PRINT 'Skipped schema Billing because it already exists.';
END;
GO


/*==========================================================
  1. Billing.PatientAccount
==========================================================*/

IF OBJECT_ID('Billing.PatientAccount', 'U') IS NULL
BEGIN
    CREATE TABLE Billing.PatientAccount
    (
        PatientAccountID              INT IDENTITY(1,1) NOT NULL,
        AccountNumber                 VARCHAR(30) NOT NULL,
        PatientID                     INT NOT NULL,

        AccountStatus                 VARCHAR(15) NOT NULL
            CONSTRAINT DF_PatientAccount_AccountStatus
            DEFAULT ('Active'),

        BillingPreference             VARCHAR(15) NOT NULL
            CONSTRAINT DF_PatientAccount_BillingPreference
            DEFAULT ('Electronic'),

        PreferredCommunicationMethod  VARCHAR(15) NOT NULL
            CONSTRAINT DF_PatientAccount_CommunicationMethod
            DEFAULT ('Email'),

        IsFinancialAssistanceEligible BIT NOT NULL
            CONSTRAINT DF_PatientAccount_FinancialAssistance
            DEFAULT (0),

        IsActive                      BIT NOT NULL
            CONSTRAINT DF_PatientAccount_IsActive
            DEFAULT (1),

        CreatedDateUTC                DATETIME2(3) NOT NULL
            CONSTRAINT DF_PatientAccount_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC               DATETIME2(3) NOT NULL
            CONSTRAINT DF_PatientAccount_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_PatientAccount
            PRIMARY KEY CLUSTERED (PatientAccountID),

        CONSTRAINT UQ_PatientAccount_AccountNumber
            UNIQUE (AccountNumber),

        CONSTRAINT UQ_PatientAccount_AccountID_PatientID
            UNIQUE (PatientAccountID, PatientID),

        CONSTRAINT CK_PatientAccount_AccountStatus
            CHECK
            (
                AccountStatus IN
                (
                    'Active',
                    'Inactive',
                    'Collections',
                    'Closed',
                    'Deceased'
                )
            ),

        CONSTRAINT CK_PatientAccount_BillingPreference
            CHECK
            (
                BillingPreference IN
                (
                    'Paper',
                    'Electronic',
                    'Both'
                )
            ),

        CONSTRAINT CK_PatientAccount_CommunicationMethod
            CHECK
            (
                PreferredCommunicationMethod IN
                (
                    'Mail',
                    'Email',
                    'SMS',
                    'Portal',
                    'Phone'
                )
            ),

        CONSTRAINT CK_PatientAccount_ActiveStatusConsistency
            CHECK
            (
                (IsActive = 1 AND AccountStatus = 'Active')
                OR
                (IsActive = 0 AND AccountStatus <> 'Active')
            )
    );

    ALTER TABLE Billing.PatientAccount WITH CHECK
    ADD CONSTRAINT FK_PatientAccount_Patient
        FOREIGN KEY (PatientID)
        REFERENCES Clinical.Patient (PatientID);

    ALTER TABLE Billing.PatientAccount
        CHECK CONSTRAINT FK_PatientAccount_Patient;

    CREATE INDEX IX_PatientAccount_PatientID
        ON Billing.PatientAccount (PatientID);

    CREATE INDEX IX_PatientAccount_AccountStatus
        ON Billing.PatientAccount (AccountStatus);

    CREATE UNIQUE INDEX UX_PatientAccount_ActivePatient
        ON Billing.PatientAccount (PatientID)
        WHERE IsActive = 1;

    PRINT 'Created Billing.PatientAccount.';
END
ELSE
BEGIN
    PRINT 'Skipped Billing.PatientAccount because it already exists.';
END;
GO


/*==========================================================
  2. Billing.Invoice
==========================================================*/

IF OBJECT_ID('Billing.Invoice', 'U') IS NULL
BEGIN
    CREATE TABLE Billing.Invoice
    (
        InvoiceID          INT IDENTITY(1,1) NOT NULL,
        InvoiceNumber      VARCHAR(40) NOT NULL,

        PatientAccountID   INT NOT NULL,
        PatientID          INT NOT NULL,
        EncounterID        INT NULL,
        ClaimID            INT NULL,

        InvoiceDate        DATE NOT NULL,
        DueDate            DATE NULL,

        InvoiceStatus      VARCHAR(20) NOT NULL
            CONSTRAINT DF_Invoice_InvoiceStatus
            DEFAULT ('Draft'),

        StatementCycle     VARCHAR(20) NOT NULL
            CONSTRAINT DF_Invoice_StatementCycle
            DEFAULT ('Initial'),

        OriginalInvoiceID  INT NULL,

        CreatedDateUTC     DATETIME2(3) NOT NULL
            CONSTRAINT DF_Invoice_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC    DATETIME2(3) NOT NULL
            CONSTRAINT DF_Invoice_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Invoice
            PRIMARY KEY CLUSTERED (InvoiceID),

        CONSTRAINT UQ_Invoice_InvoiceNumber
            UNIQUE (InvoiceNumber),

        /* Supports child-table and patient-consistency validation. */
        CONSTRAINT UQ_Invoice_InvoiceID_EncounterID
            UNIQUE (InvoiceID, EncounterID),

        CONSTRAINT UQ_Invoice_InvoiceID_Account_Patient
            UNIQUE (InvoiceID, PatientAccountID, PatientID),

        CONSTRAINT CK_Invoice_InvoiceStatus
            CHECK
            (
                InvoiceStatus IN
                (
                    'Draft',
                    'Issued',
                    'Partially Paid',
                    'Paid',
                    'Overdue',
                    'Cancelled',
                    'Voided',
                    'Collections'
                )
            ),

        CONSTRAINT CK_Invoice_StatementCycle
            CHECK
            (
                StatementCycle IN
                (
                    'Initial',
                    'First Reminder',
                    'Second Reminder',
                    'Final Notice',
                    'Collections'
                )
            ),

        CONSTRAINT CK_Invoice_DueDate
            CHECK
            (
                DueDate IS NULL
                OR DueDate >= InvoiceDate
            ),

        CONSTRAINT CK_Invoice_OriginalNotSelf
            CHECK
            (
                OriginalInvoiceID IS NULL
                OR OriginalInvoiceID <> InvoiceID
            ),

        CONSTRAINT CK_Invoice_OverdueRequiresDueDate
            CHECK
            (
                InvoiceStatus <> 'Overdue'
                OR DueDate IS NOT NULL
            )
    );

    ALTER TABLE Billing.Invoice WITH CHECK
    ADD CONSTRAINT FK_Invoice_Account_Patient
        FOREIGN KEY (PatientAccountID, PatientID)
        REFERENCES Billing.PatientAccount
        (
            PatientAccountID,
            PatientID
        );

    ALTER TABLE Billing.Invoice WITH CHECK
    ADD CONSTRAINT FK_Invoice_Encounter_Patient
        FOREIGN KEY (EncounterID, PatientID)
        REFERENCES Clinical.Encounter
        (
            EncounterID,
            PatientID
        );

    ALTER TABLE Billing.Invoice WITH CHECK
    ADD CONSTRAINT FK_Invoice_Claim_Patient
        FOREIGN KEY (ClaimID, PatientID)
        REFERENCES Insurance.Claim
        (
            ClaimID,
            PatientID
        );

    ALTER TABLE Billing.Invoice WITH CHECK
    ADD CONSTRAINT FK_Invoice_OriginalInvoice
        FOREIGN KEY (OriginalInvoiceID)
        REFERENCES Billing.Invoice (InvoiceID);

    ALTER TABLE Billing.Invoice
        CHECK CONSTRAINT FK_Invoice_Account_Patient;

    ALTER TABLE Billing.Invoice
        CHECK CONSTRAINT FK_Invoice_Encounter_Patient;

    ALTER TABLE Billing.Invoice
        CHECK CONSTRAINT FK_Invoice_Claim_Patient;

    ALTER TABLE Billing.Invoice
        CHECK CONSTRAINT FK_Invoice_OriginalInvoice;

    CREATE INDEX IX_Invoice_Patient_InvoiceDate
        ON Billing.Invoice
        (
            PatientID,
            InvoiceDate
        );

    CREATE INDEX IX_Invoice_PatientAccountID
        ON Billing.Invoice (PatientAccountID);

    CREATE INDEX IX_Invoice_DueDate
        ON Billing.Invoice (DueDate);

    CREATE INDEX IX_Invoice_ClaimID
        ON Billing.Invoice (ClaimID);

    CREATE INDEX IX_Invoice_EncounterID
        ON Billing.Invoice (EncounterID);

    CREATE INDEX IX_Invoice_OriginalInvoiceID
        ON Billing.Invoice (OriginalInvoiceID);

    CREATE INDEX IX_Invoice_Overdue
        ON Billing.Invoice
        (
            DueDate,
            InvoiceStatus
        )
        WHERE InvoiceStatus = 'Overdue';

    PRINT 'Created Billing.Invoice.';
END
ELSE
BEGIN
    PRINT 'Skipped Billing.Invoice because it already exists.';
END;
GO


/*==========================================================
  3. Billing.InvoiceLine
==========================================================*/

IF OBJECT_ID('Billing.InvoiceLine', 'U') IS NULL
BEGIN
    CREATE TABLE Billing.InvoiceLine
    (
        InvoiceLineID   INT IDENTITY(1,1) NOT NULL,
        InvoiceID       INT NOT NULL,
        LineNumber      INT NOT NULL,

        ClaimLineID     INT NULL,
        EncounterID     INT NULL,

        ServiceDate     DATE NULL,

        LineType        VARCHAR(15) NOT NULL
            CONSTRAINT DF_InvoiceLine_LineType
            DEFAULT ('Charge'),

        [Description]    NVARCHAR(500) NULL,
        ProcedureCode   VARCHAR(20) NULL,

        Quantity        DECIMAL(12,3) NOT NULL
            CONSTRAINT DF_InvoiceLine_Quantity
            DEFAULT (1),

        UnitAmount      DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_InvoiceLine_UnitAmount
            DEFAULT (0),

        LineAmount      DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_InvoiceLine_LineAmount
            DEFAULT (0),

        CreatedDateUTC  DATETIME2(3) NOT NULL
            CONSTRAINT DF_InvoiceLine_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC DATETIME2(3) NOT NULL
            CONSTRAINT DF_InvoiceLine_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_InvoiceLine
            PRIMARY KEY CLUSTERED (InvoiceLineID),

        CONSTRAINT UQ_InvoiceLine_Invoice_LineNumber
            UNIQUE (InvoiceID, LineNumber),

        CONSTRAINT UQ_InvoiceLine_LineID_InvoiceID
            UNIQUE (InvoiceLineID, InvoiceID),

        CONSTRAINT CK_InvoiceLine_Quantity
            CHECK (Quantity > 0),

        CONSTRAINT CK_InvoiceLine_LineType
            CHECK
            (
                LineType IN
                (
                    'Charge',
                    'Copay',
                    'Coinsurance',
                    'Deductible',
                    'Adjustment',
                    'Credit',
                    'Fee',
                    'Other'
                )
            )
    );

    ALTER TABLE Billing.InvoiceLine WITH CHECK
    ADD CONSTRAINT FK_InvoiceLine_Invoice
        FOREIGN KEY (InvoiceID)
        REFERENCES Billing.Invoice (InvoiceID);

    ALTER TABLE Billing.InvoiceLine WITH CHECK
    ADD CONSTRAINT FK_InvoiceLine_ClaimLine
        FOREIGN KEY (ClaimLineID)
        REFERENCES Insurance.ClaimLine (ClaimLineID);

    /*
      When EncounterID is supplied, it must match the encounter
      stored on the parent invoice.
    */
    ALTER TABLE Billing.InvoiceLine WITH CHECK
    ADD CONSTRAINT FK_InvoiceLine_Invoice_Encounter
        FOREIGN KEY (InvoiceID, EncounterID)
        REFERENCES Billing.Invoice
        (
            InvoiceID,
            EncounterID
        );

    ALTER TABLE Billing.InvoiceLine
        CHECK CONSTRAINT FK_InvoiceLine_Invoice;

    ALTER TABLE Billing.InvoiceLine
        CHECK CONSTRAINT FK_InvoiceLine_ClaimLine;

    ALTER TABLE Billing.InvoiceLine
        CHECK CONSTRAINT FK_InvoiceLine_Invoice_Encounter;

    CREATE INDEX IX_InvoiceLine_ClaimLineID
        ON Billing.InvoiceLine (ClaimLineID);

    CREATE INDEX IX_InvoiceLine_EncounterID
        ON Billing.InvoiceLine (EncounterID);

    CREATE INDEX IX_InvoiceLine_ServiceDate
        ON Billing.InvoiceLine (ServiceDate);

    CREATE INDEX IX_InvoiceLine_LineType
        ON Billing.InvoiceLine (LineType);

    CREATE INDEX IX_InvoiceLine_ProcedureCode
        ON Billing.InvoiceLine (ProcedureCode)
        WHERE ProcedureCode IS NOT NULL;

    PRINT 'Created Billing.InvoiceLine.';
END
ELSE
BEGIN
    PRINT 'Skipped Billing.InvoiceLine because it already exists.';
END;
GO


/*==========================================================
  4. Billing.Payment
==========================================================*/

IF OBJECT_ID('Billing.Payment', 'U') IS NULL
BEGIN
    CREATE TABLE Billing.Payment
    (
        PaymentID             INT IDENTITY(1,1) NOT NULL,
        PaymentNumber         VARCHAR(40) NOT NULL,

        PatientAccountID      INT NOT NULL,
        PatientID             INT NOT NULL,
        PayerID               INT NULL,

        PaymentDateTimeUTC    DATETIME2(3) NOT NULL
            CONSTRAINT DF_Payment_PaymentDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        PaymentAmount         DECIMAL(18,2) NOT NULL,

        PaymentSource         VARCHAR(15) NOT NULL
            CONSTRAINT DF_Payment_PaymentSource
            DEFAULT ('Patient'),

        PaymentMethod         VARCHAR(20) NOT NULL
            CONSTRAINT DF_Payment_PaymentMethod
            DEFAULT ('Credit Card'),

        PaymentStatus         VARCHAR(15) NOT NULL
            CONSTRAINT DF_Payment_PaymentStatus
            DEFAULT ('Pending'),

        TransactionReference  VARCHAR(100) NULL,
        CheckNumber           VARCHAR(30) NULL,
        Notes                 NVARCHAR(1000) NULL,

        CreatedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_Payment_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_Payment_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Payment
            PRIMARY KEY CLUSTERED (PaymentID),

        CONSTRAINT UQ_Payment_PaymentNumber
            UNIQUE (PaymentNumber),

        CONSTRAINT UQ_Payment_PaymentID_Account_Patient
            UNIQUE (PaymentID, PatientAccountID, PatientID),

        CONSTRAINT CK_Payment_PaymentAmount
            CHECK (PaymentAmount > 0),

        CONSTRAINT CK_Payment_PaymentSource
            CHECK
            (
                PaymentSource IN
                (
                    'Patient',
                    'Insurance',
                    'Employer',
                    'Government',
                    'Charity',
                    'Other'
                )
            ),

        CONSTRAINT CK_Payment_PaymentMethod
            CHECK
            (
                PaymentMethod IN
                (
                    'Credit Card',
                    'Debit Card',
                    'ACH',
                    'Check',
                    'Cash',
                    'Wire Transfer',
                    'Portal',
                    'Lockbox',
                    'Other'
                )
            ),

        CONSTRAINT CK_Payment_PaymentStatus
            CHECK
            (
                PaymentStatus IN
                (
                    'Pending',
                    'Posted',
                    'Reversed',
                    'Failed',
                    'Refunded'
                )
            ),

        CONSTRAINT CK_Payment_PayerSourceConsistency
            CHECK
            (
                (PaymentSource = 'Insurance' AND PayerID IS NOT NULL)
                OR
                (PaymentSource <> 'Insurance')
            ),

        CONSTRAINT CK_Payment_CheckNumber
            CHECK
            (
                PaymentMethod <> 'Check'
                OR NULLIF(LTRIM(RTRIM(CheckNumber)), '') IS NOT NULL
            )
    );

    ALTER TABLE Billing.Payment WITH CHECK
    ADD CONSTRAINT FK_Payment_Account_Patient
        FOREIGN KEY (PatientAccountID, PatientID)
        REFERENCES Billing.PatientAccount
        (
            PatientAccountID,
            PatientID
        );

    ALTER TABLE Billing.Payment WITH CHECK
    ADD CONSTRAINT FK_Payment_Payer
        FOREIGN KEY (PayerID)
        REFERENCES Insurance.Payer (PayerID);

    ALTER TABLE Billing.Payment
        CHECK CONSTRAINT FK_Payment_Account_Patient;

    ALTER TABLE Billing.Payment
        CHECK CONSTRAINT FK_Payment_Payer;

    CREATE INDEX IX_Payment_Patient_PaymentDateTime
        ON Billing.Payment
        (
            PatientID,
            PaymentDateTimeUTC
        );

    CREATE INDEX IX_Payment_PatientAccountID
        ON Billing.Payment (PatientAccountID);

    CREATE INDEX IX_Payment_PayerID
        ON Billing.Payment (PayerID);

    CREATE INDEX IX_Payment_PaymentDateTimeUTC
        ON Billing.Payment (PaymentDateTimeUTC);

    CREATE INDEX IX_Payment_PaymentMethod
        ON Billing.Payment (PaymentMethod);

    CREATE INDEX IX_Payment_PaymentStatus
        ON Billing.Payment (PaymentStatus);

    CREATE UNIQUE INDEX UX_Payment_TransactionReference
        ON Billing.Payment (TransactionReference)
        WHERE TransactionReference IS NOT NULL;

    PRINT 'Created Billing.Payment.';
END
ELSE
BEGIN
    PRINT 'Skipped Billing.Payment because it already exists.';
END;
GO


/*==========================================================
  5. Billing.PaymentAllocation
==========================================================*/

IF OBJECT_ID('Billing.PaymentAllocation', 'U') IS NULL
BEGIN
    CREATE TABLE Billing.PaymentAllocation
    (
        PaymentAllocationID      INT IDENTITY(1,1) NOT NULL,
        PaymentID                INT NOT NULL,
        InvoiceID                INT NOT NULL,
        AllocationSequenceNumber INT NOT NULL,

        AllocatedAmount          DECIMAL(18,2) NOT NULL,

        AllocationDateTimeUTC    DATETIME2(3) NOT NULL
            CONSTRAINT DF_PaymentAllocation_AllocationDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        AllocationStatus         VARCHAR(15) NOT NULL
            CONSTRAINT DF_PaymentAllocation_AllocationStatus
            DEFAULT ('Pending'),

        ReversalReason           NVARCHAR(500) NULL,

        CreatedDateUTC           DATETIME2(3) NOT NULL
            CONSTRAINT DF_PaymentAllocation_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC          DATETIME2(3) NOT NULL
            CONSTRAINT DF_PaymentAllocation_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_PaymentAllocation
            PRIMARY KEY CLUSTERED (PaymentAllocationID),

        CONSTRAINT UQ_PaymentAllocation_Payment_Sequence
            UNIQUE (PaymentID, AllocationSequenceNumber),

        CONSTRAINT CK_PaymentAllocation_AllocatedAmount
            CHECK (AllocatedAmount > 0),

        CONSTRAINT CK_PaymentAllocation_AllocationStatus
            CHECK
            (
                AllocationStatus IN
                (
                    'Pending',
                    'Posted',
                    'Reversed'
                )
            ),

        CONSTRAINT CK_PaymentAllocation_ReversalReason
            CHECK
            (
                AllocationStatus <> 'Reversed'
                OR NULLIF(LTRIM(RTRIM(ReversalReason)), '') IS NOT NULL
            )
    );

    ALTER TABLE Billing.PaymentAllocation WITH CHECK
    ADD CONSTRAINT FK_PaymentAllocation_Payment
        FOREIGN KEY (PaymentID)
        REFERENCES Billing.Payment (PaymentID);

    ALTER TABLE Billing.PaymentAllocation WITH CHECK
    ADD CONSTRAINT FK_PaymentAllocation_Invoice
        FOREIGN KEY (InvoiceID)
        REFERENCES Billing.Invoice (InvoiceID);

    ALTER TABLE Billing.PaymentAllocation
        CHECK CONSTRAINT FK_PaymentAllocation_Payment;

    ALTER TABLE Billing.PaymentAllocation
        CHECK CONSTRAINT FK_PaymentAllocation_Invoice;

    CREATE INDEX IX_PaymentAllocation_InvoiceID
        ON Billing.PaymentAllocation (InvoiceID);

    CREATE INDEX IX_PaymentAllocation_AllocationStatus
        ON Billing.PaymentAllocation (AllocationStatus);

    CREATE INDEX IX_PaymentAllocation_AllocationDateTimeUTC
        ON Billing.PaymentAllocation (AllocationDateTimeUTC);

    PRINT 'Created Billing.PaymentAllocation.';
END
ELSE
BEGIN
    PRINT 'Skipped Billing.PaymentAllocation because it already exists.';
END;
GO


/*==========================================================
  6. Billing.Adjustment
==========================================================*/

IF OBJECT_ID('Billing.Adjustment', 'U') IS NULL
BEGIN
    CREATE TABLE Billing.Adjustment
    (
        AdjustmentID           INT IDENTITY(1,1) NOT NULL,
        AdjustmentNumber       VARCHAR(40) NOT NULL,

        InvoiceID              INT NOT NULL,
        InvoiceLineID          INT NULL,
        ClaimID                INT NULL,

        AdjustmentDateTimeUTC  DATETIME2(3) NOT NULL
            CONSTRAINT DF_Adjustment_AdjustmentDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        AdjustmentType         VARCHAR(15) NOT NULL
            CONSTRAINT DF_Adjustment_AdjustmentType
            DEFAULT ('Administrative'),

        AdjustmentReasonCode   VARCHAR(20) NOT NULL,
        AdjustmentDescription  NVARCHAR(500) NULL,

        AdjustmentAmount       DECIMAL(18,2) NOT NULL,

        ApprovedByProviderID   INT NULL,

        AdjustmentStatus       VARCHAR(15) NOT NULL
            CONSTRAINT DF_Adjustment_AdjustmentStatus
            DEFAULT ('Pending'),

        CreatedDateUTC         DATETIME2(3) NOT NULL
            CONSTRAINT DF_Adjustment_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_Adjustment_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Adjustment
            PRIMARY KEY CLUSTERED (AdjustmentID),

        CONSTRAINT UQ_Adjustment_AdjustmentNumber
            UNIQUE (AdjustmentNumber),

        CONSTRAINT CK_Adjustment_AdjustmentAmount
            CHECK (AdjustmentAmount > 0),

        CONSTRAINT CK_Adjustment_AdjustmentType
            CHECK
            (
                AdjustmentType IN
                (
                    'Contractual',
                    'Administrative',
                    'Charity',
                    'Bad Debt',
                    'Courtesy',
                    'Correction',
                    'Insurance',
                    'Other'
                )
            ),

        CONSTRAINT CK_Adjustment_AdjustmentStatus
            CHECK
            (
                AdjustmentStatus IN
                (
                    'Pending',
                    'Approved',
                    'Posted',
                    'Reversed',
                    'Denied'
                )
            ),

        CONSTRAINT CK_Adjustment_ReasonCode
            CHECK
            (
                NULLIF(LTRIM(RTRIM(AdjustmentReasonCode)), '') IS NOT NULL
            )
    );

    ALTER TABLE Billing.Adjustment WITH CHECK
    ADD CONSTRAINT FK_Adjustment_Invoice
        FOREIGN KEY (InvoiceID)
        REFERENCES Billing.Invoice (InvoiceID);

    /*
      When InvoiceLineID is supplied, it must belong to
      the same InvoiceID stored on the adjustment.
    */
    ALTER TABLE Billing.Adjustment WITH CHECK
    ADD CONSTRAINT FK_Adjustment_InvoiceLine_Invoice
        FOREIGN KEY (InvoiceLineID, InvoiceID)
        REFERENCES Billing.InvoiceLine
        (
            InvoiceLineID,
            InvoiceID
        );

    ALTER TABLE Billing.Adjustment WITH CHECK
    ADD CONSTRAINT FK_Adjustment_Claim
        FOREIGN KEY (ClaimID)
        REFERENCES Insurance.Claim (ClaimID);

    ALTER TABLE Billing.Adjustment WITH CHECK
    ADD CONSTRAINT FK_Adjustment_Provider
        FOREIGN KEY (ApprovedByProviderID)
        REFERENCES Hospital.Provider (ProviderID);

    ALTER TABLE Billing.Adjustment
        CHECK CONSTRAINT FK_Adjustment_Invoice;

    ALTER TABLE Billing.Adjustment
        CHECK CONSTRAINT FK_Adjustment_InvoiceLine_Invoice;

    ALTER TABLE Billing.Adjustment
        CHECK CONSTRAINT FK_Adjustment_Claim;

    ALTER TABLE Billing.Adjustment
        CHECK CONSTRAINT FK_Adjustment_Provider;

    CREATE INDEX IX_Adjustment_InvoiceID
        ON Billing.Adjustment (InvoiceID);

    CREATE INDEX IX_Adjustment_InvoiceLineID
        ON Billing.Adjustment (InvoiceLineID);

    CREATE INDEX IX_Adjustment_ClaimID
        ON Billing.Adjustment (ClaimID);

    CREATE INDEX IX_Adjustment_ApprovedByProviderID
        ON Billing.Adjustment (ApprovedByProviderID);

    CREATE INDEX IX_Adjustment_AdjustmentType
        ON Billing.Adjustment (AdjustmentType);

    CREATE INDEX IX_Adjustment_AdjustmentStatus
        ON Billing.Adjustment (AdjustmentStatus);

    CREATE INDEX IX_Adjustment_AdjustmentDateTimeUTC
        ON Billing.Adjustment (AdjustmentDateTimeUTC);

    PRINT 'Created Billing.Adjustment.';
END
ELSE
BEGIN
    PRINT 'Skipped Billing.Adjustment because it already exists.';
END;
GO


/*==========================================================
  7. Billing.Refund
==========================================================*/

IF OBJECT_ID('Billing.Refund', 'U') IS NULL
BEGIN
    CREATE TABLE Billing.Refund
    (
        RefundID              INT IDENTITY(1,1) NOT NULL,
        RefundNumber          VARCHAR(40) NOT NULL,

        PaymentID             INT NOT NULL,
        PatientAccountID      INT NOT NULL,
        PatientID             INT NOT NULL,

        RefundDateTimeUTC     DATETIME2(3) NOT NULL
            CONSTRAINT DF_Refund_RefundDateTimeUTC
            DEFAULT (SYSUTCDATETIME()),

        RefundAmount          DECIMAL(18,2) NOT NULL,

        RefundMethod          VARCHAR(20) NOT NULL
            CONSTRAINT DF_Refund_RefundMethod
            DEFAULT ('Check'),

        RefundStatus          VARCHAR(15) NOT NULL
            CONSTRAINT DF_Refund_RefundStatus
            DEFAULT ('Pending'),

        Reason                NVARCHAR(500) NOT NULL,

        TransactionReference  VARCHAR(100) NULL,
        ApprovedByProviderID  INT NULL,

        CreatedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_Refund_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_Refund_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Refund
            PRIMARY KEY CLUSTERED (RefundID),

        CONSTRAINT UQ_Refund_RefundNumber
            UNIQUE (RefundNumber),

        CONSTRAINT CK_Refund_RefundAmount
            CHECK (RefundAmount > 0),

        CONSTRAINT CK_Refund_RefundMethod
            CHECK
            (
                RefundMethod IN
                (
                    'Credit Card',
                    'Debit Card',
                    'ACH',
                    'Check',
                    'Cash',
                    'Wire Transfer',
                    'Other'
                )
            ),

        CONSTRAINT CK_Refund_RefundStatus
            CHECK
            (
                RefundStatus IN
                (
                    'Pending',
                    'Approved',
                    'Issued',
                    'Failed',
                    'Cancelled'
                )
            ),

        CONSTRAINT CK_Refund_Reason
            CHECK
            (
                NULLIF(LTRIM(RTRIM(Reason)), '') IS NOT NULL
            )
    );

    /*
      The refund must reference a payment from the same
      patient account and patient.
    */
    ALTER TABLE Billing.Refund WITH CHECK
    ADD CONSTRAINT FK_Refund_Payment_Account_Patient
        FOREIGN KEY (PaymentID, PatientAccountID, PatientID)
        REFERENCES Billing.Payment
        (
            PaymentID,
            PatientAccountID,
            PatientID
        );

    ALTER TABLE Billing.Refund WITH CHECK
    ADD CONSTRAINT FK_Refund_Account_Patient
        FOREIGN KEY (PatientAccountID, PatientID)
        REFERENCES Billing.PatientAccount
        (
            PatientAccountID,
            PatientID
        );

    ALTER TABLE Billing.Refund WITH CHECK
    ADD CONSTRAINT FK_Refund_Provider
        FOREIGN KEY (ApprovedByProviderID)
        REFERENCES Hospital.Provider (ProviderID);

    ALTER TABLE Billing.Refund
        CHECK CONSTRAINT FK_Refund_Payment_Account_Patient;

    ALTER TABLE Billing.Refund
        CHECK CONSTRAINT FK_Refund_Account_Patient;

    ALTER TABLE Billing.Refund
        CHECK CONSTRAINT FK_Refund_Provider;

    CREATE INDEX IX_Refund_PaymentID
        ON Billing.Refund (PaymentID);

    CREATE INDEX IX_Refund_PatientAccountID
        ON Billing.Refund (PatientAccountID);

    CREATE INDEX IX_Refund_PatientID
        ON Billing.Refund (PatientID);

    CREATE INDEX IX_Refund_RefundStatus
        ON Billing.Refund (RefundStatus);

    CREATE INDEX IX_Refund_RefundDateTimeUTC
        ON Billing.Refund (RefundDateTimeUTC);

    CREATE INDEX IX_Refund_ApprovedByProviderID
        ON Billing.Refund (ApprovedByProviderID);

    CREATE UNIQUE INDEX UX_Refund_TransactionReference
        ON Billing.Refund (TransactionReference)
        WHERE TransactionReference IS NOT NULL;

    PRINT 'Created Billing.Refund.';
END
ELSE
BEGIN
    PRINT 'Skipped Billing.Refund because it already exists.';
END;
GO


/*==========================================================
  8. Billing.AccountBalanceHistory
==========================================================*/

IF OBJECT_ID('Billing.AccountBalanceHistory', 'U') IS NULL
BEGIN
    CREATE TABLE Billing.AccountBalanceHistory
    (
        AccountBalanceHistoryID      INT IDENTITY(1,1) NOT NULL,
        PatientAccountID             INT NOT NULL,
        PatientID                    INT NOT NULL,

        SnapshotDate                 DATE NOT NULL,

        CurrentBalance               DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_AccountBalanceHistory_CurrentBalance
            DEFAULT (0),
        Balance0To30Days             DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_AccountBalanceHistory_Balance0To30
            DEFAULT (0),
        Balance31To60Days            DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_AccountBalanceHistory_Balance31To60
            DEFAULT (0),
        Balance61To90Days            DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_AccountBalanceHistory_Balance61To90
            DEFAULT (0),
        Balance91To120Days           DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_AccountBalanceHistory_Balance91To120
            DEFAULT (0),
        BalanceOver120Days           DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_AccountBalanceHistory_BalanceOver120
            DEFAULT (0),

        InsurancePendingAmount       DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_AccountBalanceHistory_InsurancePending
            DEFAULT (0),
        PatientResponsibilityAmount  DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_AccountBalanceHistory_PatientResponsibility
            DEFAULT (0),
        CollectionsAmount            DECIMAL(18,2) NOT NULL
            CONSTRAINT DF_AccountBalanceHistory_Collections
            DEFAULT (0),

        CreatedDateUTC               DATETIME2(3) NOT NULL
            CONSTRAINT DF_AccountBalanceHistory_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_AccountBalanceHistory
            PRIMARY KEY CLUSTERED (AccountBalanceHistoryID),

        CONSTRAINT UQ_AccountBalanceHistory_Account_SnapshotDate
            UNIQUE (PatientAccountID, SnapshotDate),

        CONSTRAINT CK_AccountBalanceHistory_NonNegative
            CHECK
            (
                CurrentBalance >= 0
                AND Balance0To30Days >= 0
                AND Balance31To60Days >= 0
                AND Balance61To90Days >= 0
                AND Balance91To120Days >= 0
                AND BalanceOver120Days >= 0
                AND InsurancePendingAmount >= 0
                AND PatientResponsibilityAmount >= 0
                AND CollectionsAmount >= 0
            )
    );

    ALTER TABLE Billing.AccountBalanceHistory WITH CHECK
    ADD CONSTRAINT FK_AccountBalanceHistory_Account_Patient
        FOREIGN KEY (PatientAccountID, PatientID)
        REFERENCES Billing.PatientAccount
        (
            PatientAccountID,
            PatientID
        );

    ALTER TABLE Billing.AccountBalanceHistory
        CHECK CONSTRAINT FK_AccountBalanceHistory_Account_Patient;

    CREATE INDEX IX_AccountBalanceHistory_PatientID
        ON Billing.AccountBalanceHistory (PatientID);

    CREATE INDEX IX_AccountBalanceHistory_Aging
        ON Billing.AccountBalanceHistory
        (
            SnapshotDate
        )
        INCLUDE
        (
            Balance0To30Days,
            Balance31To60Days,
            Balance61To90Days,
            Balance91To120Days,
            BalanceOver120Days
        );

    CREATE INDEX IX_AccountBalanceHistory_Collections
        ON Billing.AccountBalanceHistory
        (
            SnapshotDate,
            CollectionsAmount
        )
        WHERE CollectionsAmount > 0;

    PRINT 'Created Billing.AccountBalanceHistory.';
END
ELSE
BEGIN
    PRINT 'Skipped Billing.AccountBalanceHistory because it already exists.';
END;
GO


PRINT 'All Billing schema tables were processed successfully.';
GO