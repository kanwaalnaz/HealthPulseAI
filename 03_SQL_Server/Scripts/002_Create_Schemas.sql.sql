/*==========================================================
  HealthPulse AI
  Script: 002_Create_Schemas.sql
  Purpose: Create database schemas
==========================================================*/

USE HealthPulseAI;
GO

CREATE SCHEMA Hospital;
GO

CREATE SCHEMA Clinical;
GO

CREATE SCHEMA Telehealth;
GO

CREATE SCHEMA Insurance;
GO

CREATE SCHEMA Billing;
GO

CREATE SCHEMA Marketing;
GO

CREATE SCHEMA AI;
GO

CREATE SCHEMA Security;
GO

CREATE SCHEMA Audit;
GO

PRINT 'All schemas created successfully.';