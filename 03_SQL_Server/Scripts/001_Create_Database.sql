/*==========================================================
  HealthPulse AI
  Script: 001_Create_Database.sql
  Purpose: Create the primary project database
==========================================================*/

USE master;
GO

IF DB_ID('HealthPulseAI') IS NULL
BEGIN
    CREATE DATABASE HealthPulseAI;
END
GO

USE HealthPulseAI;
GO

PRINT 'HealthPulseAI database created successfully.';