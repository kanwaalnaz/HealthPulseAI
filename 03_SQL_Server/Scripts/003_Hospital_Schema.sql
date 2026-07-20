/*==========================================================
  HealthPulse AI
  Script: 003_Hospital_Schema.sql
  Purpose: Create the core Hospital schema tables.

  Tables:
    1. Hospital.Hospital
    2. Hospital.Location
    3. Hospital.Department
    4. Hospital.Specialty
    5. Hospital.Provider
    6. Hospital.ProviderSpecialty

  Design standards:
    - INT IDENTITY surrogate primary keys
    - UTC audit timestamps
    - Referential integrity through foreign keys
    - Filtered unique indexes for nullable identifiers
    - Data-quality validation through CHECK constraints
    - Cross-hospital consistency enforcement
==========================================================*/

USE HealthPulseAI;
GO

SET XACT_ABORT ON;
GO

/*==========================================================
  1. Hospital.Hospital
  Master record for each hospital or healthcare facility.
==========================================================*/

IF OBJECT_ID('Hospital.Hospital', 'U') IS NULL
BEGIN
    CREATE TABLE Hospital.Hospital
    (
        HospitalID             INT IDENTITY(1,1) NOT NULL,
        HospitalCode           VARCHAR(20) NOT NULL,
        HospitalName           NVARCHAR(150) NOT NULL,
        LegalName              NVARCHAR(200) NULL,
        TaxID                  VARCHAR(20) NULL,

        HospitalType           VARCHAR(30) NOT NULL
            CONSTRAINT DF_Hospital_HospitalType
            DEFAULT ('General'),

        TraumaLevel            VARCHAR(20) NULL,
        NumberOfBeds           INT NULL,

        IsTeachingHospital     BIT NOT NULL
            CONSTRAINT DF_Hospital_IsTeachingHospital
            DEFAULT (0),

        HasEmergencyDepartment BIT NOT NULL
            CONSTRAINT DF_Hospital_HasEmergencyDepartment
            DEFAULT (0),

        TimeZoneName           VARCHAR(100) NOT NULL
            CONSTRAINT DF_Hospital_TimeZoneName
            DEFAULT ('Pacific Standard Time'),

        PhoneNumber            VARCHAR(25) NULL,
        Email                  NVARCHAR(150) NULL,
        Website                NVARCHAR(250) NULL,
        OpenedDate             DATE NULL,

        IsActive               BIT NOT NULL
            CONSTRAINT DF_Hospital_IsActive
            DEFAULT (1),

        CreatedDateUTC         DATETIME2(3) NOT NULL
            CONSTRAINT DF_Hospital_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC        DATETIME2(3) NOT NULL
            CONSTRAINT DF_Hospital_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Hospital
            PRIMARY KEY CLUSTERED (HospitalID),

        CONSTRAINT UQ_Hospital_HospitalCode
            UNIQUE (HospitalCode),

        CONSTRAINT CK_Hospital_HospitalType
            CHECK
            (
                HospitalType IN
                (
                    'General',
                    'Specialty',
                    'Teaching',
                    'Community',
                    'Critical Access',
                    'Childrens',
                    'Rehabilitation'
                )
            ),

        CONSTRAINT CK_Hospital_TraumaLevel
            CHECK
            (
                TraumaLevel IS NULL
                OR TraumaLevel IN
                (
                    'Level I',
                    'Level II',
                    'Level III',
                    'Level IV',
                    'Level V',
                    'Not Designated'
                )
            ),

        CONSTRAINT CK_Hospital_NumberOfBeds
            CHECK
            (
                NumberOfBeds IS NULL
                OR NumberOfBeds >= 0
            ),

        CONSTRAINT CK_Hospital_OpenedDate
            CHECK
            (
                OpenedDate IS NULL
                OR OpenedDate <= CAST(GETDATE() AS DATE)
            )
    );

    CREATE INDEX IX_Hospital_HospitalName
        ON Hospital.Hospital (HospitalName);

    CREATE INDEX IX_Hospital_HospitalType_IsActive
        ON Hospital.Hospital (HospitalType, IsActive);

    CREATE UNIQUE INDEX UX_Hospital_TaxID
        ON Hospital.Hospital (TaxID)
        WHERE TaxID IS NOT NULL;

    PRINT 'Created Hospital.Hospital.';
END
ELSE
BEGIN
    PRINT 'Skipped Hospital.Hospital because it already exists.';
END;
GO


/*==========================================================
  2. Hospital.Location
  Physical campuses, clinics, and satellite locations.
==========================================================*/

IF OBJECT_ID('Hospital.Location', 'U') IS NULL
BEGIN
    CREATE TABLE Hospital.Location
    (
        LocationID        INT IDENTITY(1,1) NOT NULL,
        HospitalID        INT NOT NULL,

        LocationCode      VARCHAR(20) NOT NULL,
        LocationName      NVARCHAR(150) NOT NULL,
        LocationType      VARCHAR(30) NOT NULL
            CONSTRAINT DF_Location_LocationType
            DEFAULT ('Hospital Campus'),

        AddressLine1      NVARCHAR(200) NOT NULL,
        AddressLine2      NVARCHAR(200) NULL,
        City              NVARCHAR(100) NOT NULL,
        StateProvince     NVARCHAR(100) NOT NULL,
        PostalCode        VARCHAR(20) NOT NULL,
        Country           NVARCHAR(100) NOT NULL
            CONSTRAINT DF_Location_Country
            DEFAULT ('USA'),

        Latitude          DECIMAL(9,6) NULL,
        Longitude         DECIMAL(9,6) NULL,

        PhoneNumber       VARCHAR(25) NULL,

        IsPrimary         BIT NOT NULL
            CONSTRAINT DF_Location_IsPrimary
            DEFAULT (0),

        IsActive          BIT NOT NULL
            CONSTRAINT DF_Location_IsActive
            DEFAULT (1),

        CreatedDateUTC    DATETIME2(3) NOT NULL
            CONSTRAINT DF_Location_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC   DATETIME2(3) NOT NULL
            CONSTRAINT DF_Location_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Location
            PRIMARY KEY CLUSTERED (LocationID),

        CONSTRAINT UQ_Location_Hospital_LocationCode
            UNIQUE (HospitalID, LocationCode),

        /*
          This unique constraint supports composite foreign keys
          that verify LocationID belongs to the specified HospitalID.
        */
        CONSTRAINT UQ_Location_LocationID_HospitalID
            UNIQUE (LocationID, HospitalID),

        CONSTRAINT FK_Location_Hospital
            FOREIGN KEY (HospitalID)
            REFERENCES Hospital.Hospital (HospitalID),

        CONSTRAINT CK_Location_LocationType
            CHECK
            (
                LocationType IN
                (
                    'Hospital Campus',
                    'Outpatient Clinic',
                    'Urgent Care',
                    'Diagnostic Center',
                    'Administrative Office',
                    'Telehealth Center',
                    'Other'
                )
            ),

        CONSTRAINT CK_Location_Latitude
            CHECK
            (
                Latitude IS NULL
                OR Latitude BETWEEN -90 AND 90
            ),

        CONSTRAINT CK_Location_Longitude
            CHECK
            (
                Longitude IS NULL
                OR Longitude BETWEEN -180 AND 180
            ),

        CONSTRAINT CK_Location_Coordinates
            CHECK
            (
                (Latitude IS NULL AND Longitude IS NULL)
                OR
                (Latitude IS NOT NULL AND Longitude IS NOT NULL)
            )
    );

    CREATE INDEX IX_Location_HospitalID
        ON Hospital.Location (HospitalID);

    CREATE INDEX IX_Location_City_StateProvince
        ON Hospital.Location (City, StateProvince);

    CREATE INDEX IX_Location_IsActive
        ON Hospital.Location (IsActive);

    CREATE INDEX IX_Location_Latitude_Longitude
        ON Hospital.Location (Latitude, Longitude)
        WHERE Latitude IS NOT NULL
          AND Longitude IS NOT NULL;

    /*
      Allows only one active primary location per hospital.
    */
    CREATE UNIQUE INDEX UX_Location_OnePrimaryPerHospital
        ON Hospital.Location (HospitalID)
        WHERE IsPrimary = 1
          AND IsActive = 1;

    PRINT 'Created Hospital.Location.';
END
ELSE
BEGIN
    PRINT 'Skipped Hospital.Location because it already exists.';
END;
GO


/*==========================================================
  3. Hospital.Department
  Clinical, operational, administrative, and support units.
==========================================================*/

IF OBJECT_ID('Hospital.Department', 'U') IS NULL
BEGIN
    CREATE TABLE Hospital.Department
    (
        DepartmentID       INT IDENTITY(1,1) NOT NULL,
        HospitalID         INT NOT NULL,
        LocationID         INT NULL,

        DepartmentCode     VARCHAR(20) NOT NULL,
        DepartmentName     NVARCHAR(150) NOT NULL,

        DepartmentType     VARCHAR(30) NOT NULL
            CONSTRAINT DF_Department_DepartmentType
            DEFAULT ('Clinical'),

        CostCenterCode     VARCHAR(30) NULL,
        FloorNumber        NVARCHAR(20) NULL,
        PhoneExtension     VARCHAR(10) NULL,

        OpensAt            TIME(0) NULL,
        ClosesAt           TIME(0) NULL,

        Description        NVARCHAR(500) NULL,

        IsActive           BIT NOT NULL
            CONSTRAINT DF_Department_IsActive
            DEFAULT (1),

        CreatedDateUTC     DATETIME2(3) NOT NULL
            CONSTRAINT DF_Department_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC    DATETIME2(3) NOT NULL
            CONSTRAINT DF_Department_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Department
            PRIMARY KEY CLUSTERED (DepartmentID),

        CONSTRAINT UQ_Department_Hospital_DepartmentCode
            UNIQUE (HospitalID, DepartmentCode),

        /*
          Supports a composite FK from Provider so that the
          provider's department must belong to the same hospital.
        */
        CONSTRAINT UQ_Department_DepartmentID_HospitalID
            UNIQUE (DepartmentID, HospitalID),

        CONSTRAINT FK_Department_Hospital
            FOREIGN KEY (HospitalID)
            REFERENCES Hospital.Hospital (HospitalID),

        /*
          Prevents a department from referencing a location
          belonging to another hospital.
        */
        CONSTRAINT FK_Department_Location_Hospital
            FOREIGN KEY (LocationID, HospitalID)
            REFERENCES Hospital.Location (LocationID, HospitalID),

        CONSTRAINT CK_Department_DepartmentType
            CHECK
            (
                DepartmentType IN
                (
                    'Clinical',
                    'Operational',
                    'Administrative',
                    'Diagnostic',
                    'Support'
                )
            ),

        CONSTRAINT CK_Department_OperatingHours
            CHECK
            (
                (OpensAt IS NULL AND ClosesAt IS NULL)
                OR
                (OpensAt IS NOT NULL AND ClosesAt IS NOT NULL)
            )
    );

    CREATE INDEX IX_Department_HospitalID
        ON Hospital.Department (HospitalID);

    CREATE INDEX IX_Department_LocationID
        ON Hospital.Department (LocationID);

    CREATE INDEX IX_Department_DepartmentName
        ON Hospital.Department (DepartmentName);

    CREATE INDEX IX_Department_DepartmentType_IsActive
        ON Hospital.Department (DepartmentType, IsActive);

    CREATE INDEX IX_Department_CostCenterCode
        ON Hospital.Department (CostCenterCode)
        WHERE CostCenterCode IS NOT NULL;

    PRINT 'Created Hospital.Department.';
END
ELSE
BEGIN
    PRINT 'Skipped Hospital.Department because it already exists.';
END;
GO


/*==========================================================
  4. Hospital.Specialty
  Standardized medical-specialty reference data.
==========================================================*/

IF OBJECT_ID('Hospital.Specialty', 'U') IS NULL
BEGIN
    CREATE TABLE Hospital.Specialty
    (
        SpecialtyID       INT IDENTITY(1,1) NOT NULL,
        SpecialtyCode     VARCHAR(20) NOT NULL,
        SpecialtyName     NVARCHAR(150) NOT NULL,
        Description       NVARCHAR(500) NULL,

        IsActive          BIT NOT NULL
            CONSTRAINT DF_Specialty_IsActive
            DEFAULT (1),

        CreatedDateUTC    DATETIME2(3) NOT NULL
            CONSTRAINT DF_Specialty_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC   DATETIME2(3) NOT NULL
            CONSTRAINT DF_Specialty_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Specialty
            PRIMARY KEY CLUSTERED (SpecialtyID),

        CONSTRAINT UQ_Specialty_SpecialtyCode
            UNIQUE (SpecialtyCode),

        CONSTRAINT UQ_Specialty_SpecialtyName
            UNIQUE (SpecialtyName)
    );

    CREATE INDEX IX_Specialty_IsActive_SpecialtyName
        ON Hospital.Specialty (IsActive, SpecialtyName);

    PRINT 'Created Hospital.Specialty.';
END
ELSE
BEGIN
    PRINT 'Skipped Hospital.Specialty because it already exists.';
END;
GO


/*==========================================================
  5. Hospital.Provider
  Physicians, nurses, therapists, technicians, and clinicians.
==========================================================*/

IF OBJECT_ID('Hospital.Provider', 'U') IS NULL
BEGIN
    CREATE TABLE Hospital.Provider
    (
        ProviderID          INT IDENTITY(1,1) NOT NULL,
        HospitalID          INT NOT NULL,
        DepartmentID        INT NULL,

        ProviderCode        VARCHAR(20) NOT NULL,
        NPINumber           VARCHAR(10) NULL,

        FirstName           NVARCHAR(100) NOT NULL,
        MiddleName          NVARCHAR(100) NULL,
        LastName            NVARCHAR(100) NOT NULL,
        PreferredName       NVARCHAR(100) NULL,

        Title               NVARCHAR(50) NULL,
        Gender              CHAR(1) NULL,

        ProviderType        VARCHAR(30) NOT NULL
            CONSTRAINT DF_Provider_ProviderType
            DEFAULT ('Physician'),

        EmploymentStatus    VARCHAR(30) NOT NULL
            CONSTRAINT DF_Provider_EmploymentStatus
            DEFAULT ('Full-Time'),

        MedicalLicenseNumber VARCHAR(50) NULL,
        LicenseState         VARCHAR(50) NULL,
        LicenseExpirationDate DATE NULL,

        DEANumber            VARCHAR(20) NULL,
        BoardCertified       BIT NOT NULL
            CONSTRAINT DF_Provider_BoardCertified
            DEFAULT (0),

        YearsExperience      SMALLINT NULL,

        Email                NVARCHAR(150) NULL,
        PhoneNumber          VARCHAR(25) NULL,
        HireDate             DATE NULL,
        TerminationDate      DATE NULL,

        IsActive             BIT NOT NULL
            CONSTRAINT DF_Provider_IsActive
            DEFAULT (1),

        CreatedDateUTC       DATETIME2(3) NOT NULL
            CONSTRAINT DF_Provider_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC      DATETIME2(3) NOT NULL
            CONSTRAINT DF_Provider_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_Provider
            PRIMARY KEY CLUSTERED (ProviderID),

        /*
          Provider codes are unique within a hospital.
        */
        CONSTRAINT UQ_Provider_Hospital_ProviderCode
            UNIQUE (HospitalID, ProviderCode),

        CONSTRAINT FK_Provider_Hospital
            FOREIGN KEY (HospitalID)
            REFERENCES Hospital.Hospital (HospitalID),

        /*
          Prevents assigning a provider to a department
          belonging to a different hospital.
        */
        CONSTRAINT FK_Provider_Department_Hospital
            FOREIGN KEY (DepartmentID, HospitalID)
            REFERENCES Hospital.Department (DepartmentID, HospitalID),

        CONSTRAINT CK_Provider_Gender
            CHECK
            (
                Gender IS NULL
                OR Gender IN ('M', 'F', 'O', 'U')
            ),

        CONSTRAINT CK_Provider_ProviderType
            CHECK
            (
                ProviderType IN
                (
                    'Physician',
                    'Surgeon',
                    'Specialist',
                    'Nurse',
                    'Nurse Practitioner',
                    'Physician Assistant',
                    'Resident',
                    'Fellow',
                    'Therapist',
                    'Technician',
                    'Pharmacist',
                    'Social Worker',
                    'Other'
                )
            ),

        CONSTRAINT CK_Provider_EmploymentStatus
            CHECK
            (
                EmploymentStatus IN
                (
                    'Full-Time',
                    'Part-Time',
                    'Contract',
                    'Locum Tenens',
                    'Resident',
                    'Fellow',
                    'Inactive'
                )
            ),

        CONSTRAINT CK_Provider_NPINumber
            CHECK
            (
                NPINumber IS NULL
                OR
                (
                    LEN(NPINumber) = 10
                    AND NPINumber NOT LIKE '%[^0-9]%'
                )
            ),

        CONSTRAINT CK_Provider_YearsExperience
            CHECK
            (
                YearsExperience IS NULL
                OR YearsExperience BETWEEN 0 AND 80
            ),

        CONSTRAINT CK_Provider_EmploymentDates
            CHECK
            (
                TerminationDate IS NULL
                OR HireDate IS NULL
                OR TerminationDate >= HireDate
            ),

        CONSTRAINT CK_Provider_LicenseExpirationDate
            CHECK
            (
                LicenseExpirationDate IS NULL
                OR LicenseExpirationDate >= '19000101'
            )
    );

    /*
      Filtered unique indexes allow many NULL values while
      ensuring populated identifiers are unique.
    */
    CREATE UNIQUE INDEX UX_Provider_NPINumber
        ON Hospital.Provider (NPINumber)
        WHERE NPINumber IS NOT NULL;

    CREATE UNIQUE INDEX UX_Provider_MedicalLicense
        ON Hospital.Provider
        (
            MedicalLicenseNumber,
            LicenseState
        )
        WHERE MedicalLicenseNumber IS NOT NULL
          AND LicenseState IS NOT NULL;

    CREATE UNIQUE INDEX UX_Provider_DEANumber
        ON Hospital.Provider (DEANumber)
        WHERE DEANumber IS NOT NULL;

    CREATE INDEX IX_Provider_HospitalID
        ON Hospital.Provider (HospitalID);

    CREATE INDEX IX_Provider_DepartmentID
        ON Hospital.Provider (DepartmentID);

    CREATE INDEX IX_Provider_LastName_FirstName
        ON Hospital.Provider (LastName, FirstName);

    CREATE INDEX IX_Provider_ProviderType_IsActive
        ON Hospital.Provider (ProviderType, IsActive);

    CREATE INDEX IX_Provider_EmploymentStatus
        ON Hospital.Provider (EmploymentStatus);

    PRINT 'Created Hospital.Provider.';
END
ELSE
BEGIN
    PRINT 'Skipped Hospital.Provider because it already exists.';
END;
GO


/*==========================================================
  6. Hospital.ProviderSpecialty
  Many-to-many bridge between providers and specialties.
==========================================================*/

IF OBJECT_ID('Hospital.ProviderSpecialty', 'U') IS NULL
BEGIN
    CREATE TABLE Hospital.ProviderSpecialty
    (
        ProviderSpecialtyID INT IDENTITY(1,1) NOT NULL,
        ProviderID          INT NOT NULL,
        SpecialtyID         INT NOT NULL,

        IsPrimary           BIT NOT NULL
            CONSTRAINT DF_ProviderSpecialty_IsPrimary
            DEFAULT (0),

        CertificationDate   DATE NULL,
        CertificationExpiryDate DATE NULL,

        IsActive            BIT NOT NULL
            CONSTRAINT DF_ProviderSpecialty_IsActive
            DEFAULT (1),

        CreatedDateUTC      DATETIME2(3) NOT NULL
            CONSTRAINT DF_ProviderSpecialty_CreatedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        ModifiedDateUTC     DATETIME2(3) NOT NULL
            CONSTRAINT DF_ProviderSpecialty_ModifiedDateUTC
            DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT PK_ProviderSpecialty
            PRIMARY KEY CLUSTERED (ProviderSpecialtyID),

        CONSTRAINT UQ_ProviderSpecialty_Provider_Specialty
            UNIQUE (ProviderID, SpecialtyID),

        CONSTRAINT FK_ProviderSpecialty_Provider
            FOREIGN KEY (ProviderID)
            REFERENCES Hospital.Provider (ProviderID),

        CONSTRAINT FK_ProviderSpecialty_Specialty
            FOREIGN KEY (SpecialtyID)
            REFERENCES Hospital.Specialty (SpecialtyID),

        CONSTRAINT CK_ProviderSpecialty_CertificationDates
            CHECK
            (
                CertificationExpiryDate IS NULL
                OR CertificationDate IS NULL
                OR CertificationExpiryDate >= CertificationDate
            )
    );

    CREATE INDEX IX_ProviderSpecialty_ProviderID
        ON Hospital.ProviderSpecialty (ProviderID);

    CREATE INDEX IX_ProviderSpecialty_SpecialtyID
        ON Hospital.ProviderSpecialty (SpecialtyID);

    /*
      Allows only one active primary specialty per provider.
    */
    CREATE UNIQUE INDEX UX_ProviderSpecialty_OnePrimary
        ON Hospital.ProviderSpecialty (ProviderID)
        WHERE IsPrimary = 1
          AND IsActive = 1;

    PRINT 'Created Hospital.ProviderSpecialty.';
END
ELSE
BEGIN
    PRINT 'Skipped Hospital.ProviderSpecialty because it already exists.';
END;
GO


PRINT 'All Hospital schema tables were processed successfully.';
GO