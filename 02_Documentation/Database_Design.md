# HealthPulse AI — Database Design Document

> **Enterprise Healthcare Intelligence Platform — Microsoft SQL Server Schema Architecture**

This document describes the logical database design for the **HealthPulse AI** platform. The database is organized into **schemas** — logical namespaces within a single SQL Server database — that group related tables by business domain. This separation enforces security boundaries, clarifies ownership, and enables independent evolution of each domain.

---

## Table of Contents

1. [Design Principles](#design-principles)
2. [Schema Overview](#schema-overview)
3. [Hospital Schema](#1-hospital-schema)
4. [Clinical Schema](#2-clinical-schema)
5. [Telehealth Schema](#3-telehealth-schema)
6. [Insurance Schema](#4-insurance-schema)
7. [Billing Schema](#5-billing-schema)
8. [Marketing Schema](#6-marketing-schema)
9. [AI Schema](#7-ai-schema)
10. [Security Schema](#8-security-schema)
11. [Audit Schema](#9-audit-schema)
12. [Cross-Schema Relationships](#cross-schema-relationships)

---

## Design Principles

- **Domain-driven schemas** — Each schema represents a bounded business domain with clear ownership.
- **Master Patient Index (MPI)** — A single canonical patient identity, referenced across all clinical, billing, and telehealth data.
- **Referential integrity** — Foreign keys enforce consistency; surrogate integer/BIGINT keys are used for all primary keys, with natural/business keys retained as unique constraints.
- **Slowly Changing Dimensions** — Reference and organizational data track history where auditability matters.
- **Separation of PHI** — Protected Health Information is isolated and access-controlled via the `Security` schema.
- **Auditability by design** — Every sensitive action is logged in the `Audit` schema.
- **Analytics-ready** — Naming, grain, and keys are designed to feed the data warehouse, dashboards, and ML feature stores cleanly.

---

## Schema Overview

| Schema | Domain | Primary Purpose |
|--------|--------|-----------------|
| **Hospital** | Organizational | Hospitals, locations, departments, specialties, providers |
| **Clinical** | Patient care | Patients, encounters, diagnoses, procedures, vitals, labs, monitoring |
| **Telehealth** | Virtual care | Virtual visits, devices, remote monitoring streams |
| **Insurance** | Coverage | Payers, plans, member coverage, claims, adjudication |
| **Billing** | Revenue cycle | Charges, invoices, payments, denials |
| **Marketing** | Growth | Campaigns, leads, outreach, patient engagement |
| **AI** | Intelligence | Feature store, model registry, predictions, GenAI artifacts |
| **Security** | Access control | Users, roles, permissions, PHI access governance |
| **Audit** | Compliance | Immutable change and access logs |

---

## 1. Hospital Schema

### 1.1 Why This Schema Exists
The `Hospital` schema is the **organizational backbone** of the platform. HealthPulse AI serves many hospitals across many physical locations, each with its own departments, specialties, and provider network. This schema models the *"who and where"* of the organization so that every clinical, financial, and operational fact can be attributed to a specific facility, department, and provider.

### 1.2 Business Problems It Solves
- Enables **multi-hospital, multi-location** operations under one platform.
- Provides consistent organizational hierarchy for roll-up reporting (facility → region → enterprise).
- Standardizes departments and medical specialties for benchmarking across facilities.
- Supports provider credentialing, scheduling, and productivity analysis.

### 1.3 Tables In This Schema

| Table | Description |
|-------|-------------|
| `Hospital.Hospital` | Master record for each hospital/legal entity |
| `Hospital.Location` | Physical sites/campuses belonging to a hospital |
| `Hospital.Building` | Buildings/wings within a location |
| `Hospital.Department` | Clinical and operational departments |
| `Hospital.Specialty` | Reference list of medical specialties |
| `Hospital.Provider` | Doctors, nurses, and clinicians |
| `Hospital.ProviderSpecialty` | Bridge: providers ↔ specialties |
| `Hospital.ProviderDepartment` | Bridge: providers ↔ departments |
| `Hospital.Room` | Rooms/beds for capacity management |
| `Hospital.OperatingHours` | Facility and department schedules |

### 1.4 Interaction With Other Schemas
- **Clinical** — Encounters reference `Provider`, `Department`, and `Location`.
- **Billing** — Charges attributed to facilities and departments.
- **Telehealth** — Virtual visits link to providers and departments.
- **Security** — Provider identities map to platform users.
- **AI** — Facility/department attributes are model features for operational forecasting.

### 1.5 Dashboards That Depend On It
- Executive Enterprise Performance (facility roll-ups)
- Department Utilization & Capacity
- Provider Productivity
- Bed Occupancy & Operational Throughput

### 1.6 AI Features That Depend On It
- Patient-volume and capacity forecasting (per facility/department)
- Staffing optimization models
- Operating-room utilization prediction

---

## 2. Clinical Schema

### 2.1 Why This Schema Exists
The `Clinical` schema is the **heart of patient care data**. It holds the Master Patient Index and every clinical event — encounters, diagnoses, procedures, medications, vitals, labs, and patient monitoring. It is the primary source of PHI and the foundation for quality, safety, and clinical AI.

### 2.2 Business Problems It Solves
- Creates a **single source of truth** for patient identity (MPI) across facilities.
- Consolidates fragmented clinical data (EHR, lab, pharmacy, devices).
- Powers clinical quality measurement, patient safety, and outcomes tracking.
- Provides the labeled data needed for predictive clinical models.

### 2.3 Tables In This Schema

| Table | Description |
|-------|-------------|
| `Clinical.Patient` | Master Patient Index — canonical patient identity |
| `Clinical.PatientAddress` | Patient demographics/contact history |
| `Clinical.Encounter` | Admissions, visits, and episodes of care |
| `Clinical.Diagnosis` | Coded diagnoses (ICD-10) per encounter |
| `Clinical.Procedure` | Coded procedures (CPT/HCPCS) |
| `Clinical.Medication` | Reference list of medications |
| `Clinical.MedicationOrder` | Prescribed/administered medications |
| `Clinical.Vitals` | Vital-sign measurements |
| `Clinical.LabOrder` | Ordered lab tests |
| `Clinical.LabResult` | Lab result values |
| `Clinical.Allergy` | Patient allergies |
| `Clinical.CarePlan` | Care plans and interventions |
| `Clinical.MonitoringReading` | Inpatient device monitoring readings |

### 2.4 Interaction With Other Schemas
- **Hospital** — Every encounter links to provider, department, and location.
- **Telehealth** — Virtual encounters extend the `Encounter` record.
- **Insurance / Billing** — Diagnoses and procedures drive claims and charges.
- **AI** — Primary feature source for clinical risk models.
- **Security / Audit** — All PHI access is governed and logged.

### 2.5 Dashboards That Depend On It
- Clinical Quality & Patient Safety
- Readmissions Analysis
- Length-of-Stay & Mortality
- Chronic Disease Registries

### 2.6 AI Features That Depend On It
- 30-day readmission risk prediction
- Sepsis / clinical deterioration early warning
- Length-of-stay forecasting
- GenAI clinical record summarization

---

## 3. Telehealth Schema

### 3.1 Why This Schema Exists
The `Telehealth` schema models **virtual and remote care** — a distinct operational domain with its own devices, sessions, connectivity data, and remote patient monitoring (RPM) streams. Separating it keeps virtual-care specifics from cluttering the core clinical model while still linking to it.

### 3.2 Business Problems It Solves
- Enables scalable **virtual visit** scheduling, delivery, and tracking.
- Supports **remote patient monitoring** for chronic and post-discharge patients.
- Measures telehealth adoption, quality, and technical reliability.
- Extends care access to rural and home-bound populations.

### 3.3 Tables In This Schema

| Table | Description |
|-------|-------------|
| `Telehealth.VirtualVisit` | Virtual appointment/session records |
| `Telehealth.SessionEvent` | Connection quality and session events |
| `Telehealth.Device` | RPM devices assigned to patients |
| `Telehealth.DeviceReading` | Streamed remote monitoring measurements |
| `Telehealth.Consent` | Telehealth-specific patient consent |
| `Telehealth.WaitlistQueue` | Virtual visit queue/triage |

### 3.4 Interaction With Other Schemas
- **Clinical** — Virtual visits link to `Patient` and can create `Encounter` records.
- **Hospital** — Sessions attributed to providers and departments.
- **Billing / Insurance** — Telehealth visits generate charges and claims.
- **AI** — Device readings feed remote-monitoring risk models.
- **Audit** — Session access and consent are logged.

### 3.5 Dashboards That Depend On It
- Telehealth Adoption & Volume
- Virtual Visit Quality & Connectivity
- Remote Monitoring Compliance
- Access & Equity (rural reach)

### 3.6 AI Features That Depend On It
- Remote deterioration detection from RPM streams
- No-show / drop-off prediction for virtual visits
- Device anomaly detection

---

## 4. Insurance Schema

### 4.1 Why This Schema Exists
The `Insurance` schema manages **payer relationships, coverage, and claims**. It answers *"who pays, under what plan, and how much was approved."* It is essential for revenue integrity and value-based-care reporting.

### 4.2 Business Problems It Solves
- Tracks **member eligibility and coverage** across payers and plans.
- Manages the full **claims lifecycle** (submission → adjudication → remittance).
- Reduces claim denials and revenue leakage.
- Supports payer-mix and reimbursement analysis.

### 4.3 Tables In This Schema

| Table | Description |
|-------|-------------|
| `Insurance.Payer` | Insurance companies / payers |
| `Insurance.Plan` | Insurance plans and product lines |
| `Insurance.Coverage` | Patient ↔ plan coverage periods |
| `Insurance.Claim` | Submitted claims |
| `Insurance.ClaimLine` | Line-level claim detail |
| `Insurance.ClaimStatusHistory` | Adjudication status over time |
| `Insurance.Authorization` | Prior authorizations and referrals |
| `Insurance.Remittance` | Payer remittance/EOB records |

### 4.4 Interaction With Other Schemas
- **Clinical** — Diagnoses/procedures justify claim lines.
- **Billing** — Claims reconcile against charges and payments.
- **Hospital** — Claims attributed to facilities/providers.
- **AI** — Claim data feeds denial-prediction models.

### 4.5 Dashboards That Depend On It
- Claims Denial Analysis
- Payer Mix & Reimbursement
- Prior Authorization Turnaround
- Value-Based-Care Performance

### 4.6 AI Features That Depend On It
- Claim-denial prediction
- Coverage-gap detection
- Reimbursement forecasting

---

## 5. Billing Schema

### 5.1 Why This Schema Exists
The `Billing` schema owns the **revenue cycle** from the provider's side — charges, invoices, patient payments, and adjustments. Where `Insurance` covers the payer side, `Billing` covers the organization's financial ledger for services rendered.

### 5.2 Business Problems It Solves
- Captures **charges** for all services and links them to encounters.
- Manages **patient invoicing, payments, and balances**.
- Tracks **denials, write-offs, and adjustments** for revenue integrity.
- Provides the financial data behind profitability and cost analysis.

### 5.3 Tables In This Schema

| Table | Description |
|-------|-------------|
| `Billing.ChargeItem` | Chargemaster — service/price catalog |
| `Billing.Charge` | Charges posted per encounter |
| `Billing.Invoice` | Patient/payer invoices |
| `Billing.InvoiceLine` | Invoice line items |
| `Billing.Payment` | Payments received |
| `Billing.PaymentAllocation` | Payment applied to invoices/charges |
| `Billing.Adjustment` | Write-offs, discounts, corrections |
| `Billing.AccountBalance` | Running patient/account balances |

### 5.4 Interaction With Other Schemas
- **Clinical** — Charges originate from encounters, procedures, and orders.
- **Insurance** — Invoices and payments reconcile against claims and remittances.
- **Hospital** — Revenue attributed to facilities and departments.
- **AI** — Financial data feeds revenue and payment-risk models.

### 5.5 Dashboards That Depend On It
- Revenue Cycle Performance
- Cost-per-Case & Profitability
- Accounts Receivable Aging
- Cash Collections

### 5.6 AI Features That Depend On It
- Payment default / bad-debt prediction
- Charge-capture leakage detection
- Revenue forecasting

---

## 6. Marketing Schema

### 6.1 Why This Schema Exists
The `Marketing` schema supports **growth, outreach, and patient engagement**. It manages campaigns, leads, and communication so the organization can attract patients, close care gaps, and improve retention — without mixing marketing data into clinical PHI stores.

### 6.2 Business Problems It Solves
- Plans and measures **marketing campaigns** and ROI.
- Manages **leads and referral sources**.
- Drives **patient outreach** for preventive care and care-gap closure.
- Tracks **engagement and retention** across channels.

### 6.3 Tables In This Schema

| Table | Description |
|-------|-------------|
| `Marketing.Campaign` | Marketing/outreach campaigns |
| `Marketing.Channel` | Communication channels (email, SMS, etc.) |
| `Marketing.Lead` | Prospective patients / referrals |
| `Marketing.Outreach` | Individual outreach touchpoints |
| `Marketing.EngagementEvent` | Opens, clicks, responses |
| `Marketing.Segment` | Audience segments for targeting |
| `Marketing.Consent` | Communication consent/opt-out |

### 6.4 Interaction With Other Schemas
- **Clinical** — Care-gap lists (with consent) drive targeted outreach.
- **AI** — Segments and propensity scores personalize campaigns.
- **Security / Audit** — Consent and communication access are governed.

### 6.5 Dashboards That Depend On It
- Campaign Performance & ROI
- Patient Acquisition Funnel
- Outreach & Engagement
- Care-Gap Closure

### 6.6 AI Features That Depend On It
- Patient segmentation & propensity scoring
- Churn / retention prediction
- Next-best-outreach recommendation
- GenAI campaign content generation

---

## 7. AI Schema

### 7.1 Why This Schema Exists
The `AI` schema is the **operational home of machine learning and generative AI**. It stores engineered features, model metadata, generated predictions, and GenAI artifacts. Isolating AI assets keeps model governance, versioning, and reproducibility separate from source transactional data.

### 7.2 Business Problems It Solves
- Provides a governed **feature store** for consistent model inputs.
- Maintains a **model registry** for versioning and lineage.
- Persists **predictions/scores** so they can be surfaced in dashboards and workflows.
- Stores **GenAI outputs** (summaries, drafts) with traceability and grounding.

### 7.3 Tables In This Schema

| Table | Description |
|-------|-------------|
| `AI.FeatureDefinition` | Catalog of engineered features |
| `AI.FeatureValue` | Computed feature values per entity |
| `AI.Model` | Model registry (name, type, version) |
| `AI.ModelVersion` | Trained model artifacts and metrics |
| `AI.Prediction` | Model-generated scores/predictions |
| `AI.ModelMonitoring` | Drift, accuracy, and fairness metrics |
| `AI.GenAIPrompt` | Prompt templates and requests |
| `AI.GenAIResponse` | Generated responses with source grounding |
| `AI.Embedding` | Vector embeddings for retrieval |

### 7.4 Interaction With Other Schemas
- **Clinical / Insurance / Billing / Telehealth / Marketing** — Source data for features.
- **Hospital** — Organizational context for operational models.
- **Security** — Governs which users can view sensitive predictions.
- **Audit** — Logs model access and GenAI usage.

### 7.5 Dashboards That Depend On It
- Risk-Score & Predictive Insights
- Model Performance & Drift Monitoring
- Responsible-AI / Fairness Monitoring
- AI-Generated Executive Briefings

### 7.6 AI Features That Depend On It
- **All** predictive models (readmission, sepsis, denial, no-show, churn)
- GenAI Copilot (summaries, Q&A, documentation drafting)
- Retrieval-augmented generation (RAG) via embeddings

---

## 8. Security Schema

### 8.1 Why This Schema Exists
The `Security` schema enforces **access control and PHI governance**. Healthcare data is highly sensitive and regulated; this schema defines users, roles, permissions, and the rules that determine who can see what — a HIPAA requirement.

### 8.2 Business Problems It Solves
- Implements **role-based access control (RBAC)** across the platform.
- Governs **minimum-necessary PHI access**.
- Maps clinical providers and staff to platform identities.
- Supports authentication, authorization, and data-masking policies.

### 8.3 Tables In This Schema

| Table | Description |
|-------|-------------|
| `Security.User` | Platform user accounts |
| `Security.Role` | Roles (clinician, analyst, admin, etc.) |
| `Security.Permission` | Granular permissions |
| `Security.RolePermission` | Role ↔ permission mapping |
| `Security.UserRole` | User ↔ role assignment |
| `Security.DataAccessPolicy` | Row/column-level access rules |
| `Security.PHIAccessGrant` | Explicit PHI access grants |
| `Security.LoginSession` | Active sessions and tokens |

### 8.4 Interaction With Other Schemas
- **All schemas** — Governs read/write access, especially to `Clinical` PHI.
- **Hospital** — Links providers to user accounts.
- **Audit** — Every access decision is logged.

### 8.5 Dashboards That Depend On It
- Access Governance & Role Review
- PHI Access Monitoring
- User Activity Overview

### 8.6 AI Features That Depend On It
- Enforces which users can view model predictions and GenAI outputs.
- Anomalous-access detection (security AI)

---

## 9. Audit Schema

### 9.1 Why This Schema Exists
The `Audit` schema provides an **immutable record of activity** across the platform. Regulatory compliance (HIPAA, HITECH, SOC 2) requires that data access and changes be traceable. This schema is append-only and independent of the domains it observes.

### 9.2 Business Problems It Solves
- Delivers a **tamper-resistant audit trail** for compliance.
- Enables **breach investigation** and forensic analysis.
- Tracks **who accessed which PHI, when, and why**.
- Records **data changes** for accountability and rollback analysis.

### 9.3 Tables In This Schema

| Table | Description |
|-------|-------------|
| `Audit.AccessLog` | Every read of sensitive data |
| `Audit.ChangeLog` | Insert/update/delete history |
| `Audit.LoginAudit` | Authentication attempts and outcomes |
| `Audit.PHIDisclosure` | Records of PHI disclosure |
| `Audit.AIUsageLog` | GenAI/model invocation history |
| `Audit.SystemEvent` | System-level and job events |

### 9.4 Interaction With Other Schemas
- **All schemas** — Passively receives events from every domain.
- **Security** — Correlates activity with users, roles, and sessions.
- **AI** — Captures model and GenAI usage for governance.

### 9.5 Dashboards That Depend On It
- Compliance & Audit Overview
- PHI Access & Disclosure
- Security Incident Investigation
- AI Usage Governance

### 9.6 AI Features That Depend On It
- Anomalous-access / insider-threat detection
- Compliance-risk scoring
- Usage-pattern analytics

---

## Cross-Schema Relationships

The following summarizes the principal relationships that tie the domains together:

- **Master Patient Index** — `Clinical.Patient` is the canonical patient referenced by `Telehealth`, `Insurance`, `Billing`, and `Marketing`.
- **Organizational context** — `Hospital.Provider`, `Hospital.Department`, and `Hospital.Location` are referenced by `Clinical`, `Telehealth`, and `Billing`.
- **Revenue chain** — `Clinical.Encounter` → `Billing.Charge` → `Insurance.Claim` → `Insurance.Remittance` / `Billing.Payment`.
- **Intelligence layer** — `AI` consumes data from all domains and writes predictions back for dashboards and workflows.
- **Governance layer** — `Security` controls access to every schema; `Audit` records activity across every schema.

### Conceptual Data Flow

```
[Source Systems: EHR / Lab / Devices / Claims]
                     |
              Python ETL / ELT
                     |
   +-----------------------------------------+
   |         SQL Server (schemas)            |
   |  Hospital  Clinical  Telehealth         |
   |  Insurance Billing   Marketing          |
   |            AI                           |
   |  Security (access)  Audit (logging)     |
   +-----------------------------------------+
                     |
        +------------+------------+
        |                         |
  Tableau / Power BI        ML + GenAI Models
   (Dashboards)              (AI schema)
```

---

*© HealthPulse AI. This document is part of the HealthPulse AI enterprise documentation set.*
