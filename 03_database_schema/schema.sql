-- =============================================================================
--  API Shortage & Competitor Recall Commercial Trigger
--  03_database_schema/schema.sql
--
--  Target   : PostgreSQL 13+ (tested on PostgreSQL 16)
--  Purpose  : Mock ERP / CRM / audit tables that the n8n workflow queries.
--  Run      : psql "$DATABASE_URL" -f 03_database_schema/schema.sql
--
--  ALL DATA IN THIS FILE IS FICTITIOUS.
--  * "Meridian Generics" and labeler code 71999 represent the fictional
--    company that owns this workflow. Account names, KAM names, NDCs,
--    inventory, WAC prices and demand volumes are invented for demonstration.
--  * GPO names (Vizient, Premier, HealthTrust) are used only as realistic
--    affiliation labels; no real contract terms or pricing are implied.
-- =============================================================================

BEGIN;

DROP VIEW  IF EXISTS v_opportunity_pipeline;
DROP TABLE IF EXISTS shortage_opportunity_log;
DROP TABLE IF EXISTS regional_gpo_accounts;
DROP TABLE IF EXISTS internal_sku_inventory;

-- -----------------------------------------------------------------------------
-- 1. internal_sku_inventory
--    Snapshot of saleable finished-goods inventory, synced nightly from ERP.
--    Quantities are in SELL UNITS (the unit WAC is quoted in: vial, carton...).
--    committed_units = open orders + awarded GPO contract allocation for the
--    next 30 days. This is the volume protected by Failure-to-Supply (FTS)
--    clauses and is never offered as spot supply.
-- -----------------------------------------------------------------------------
CREATE TABLE internal_sku_inventory (
    sku_id            VARCHAR(20)   PRIMARY KEY,
    ndc_11            CHAR(13)      NOT NULL UNIQUE
                      CHECK (ndc_11 ~ '^[0-9]{5}-[0-9]{4}-[0-9]{2}$'),          -- HIPAA 5-4-2
    labeler_code      CHAR(5)       GENERATED ALWAYS AS (left(ndc_11, 5)) STORED,
    molecule_name     VARCHAR(100)  NOT NULL,                                    -- lower case, salt form included
    strength_norm     VARCHAR(40)   NOT NULL,                                    -- e.g. 1MG/ML, 2.5MG/3ML
    dosage_form       VARCHAR(60)   NOT NULL,
    sku_description   VARCHAR(160)  NOT NULL,
    sell_unit         VARCHAR(20)   NOT NULL,                                    -- VIAL, CARTON, BOTTLE
    therapeutic_area  VARCHAR(40)   NOT NULL,
    on_hand_units     INTEGER       NOT NULL CHECK (on_hand_units   >= 0),
    committed_units   INTEGER       NOT NULL CHECK (committed_units >= 0),
    wac_per_unit      NUMERIC(12,2) NOT NULL CHECK (wac_per_unit    >  0),       -- Wholesale Acquisition Cost
    earliest_expiry   DATE          NOT NULL,
    distribution_ctr  VARCHAR(40)   NOT NULL,
    is_active         BOOLEAN       NOT NULL DEFAULT TRUE,
    last_erp_sync_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX ix_sku_molecule_strength
    ON internal_sku_inventory (lower(molecule_name), upper(strength_norm))
    WHERE is_active;

COMMENT ON TABLE  internal_sku_inventory IS 'Mock ERP inventory snapshot (fictitious data).';
COMMENT ON COLUMN internal_sku_inventory.committed_units IS 'Open orders + awarded GPO allocation (30 days). Protected by FTS buffer.';

INSERT INTO internal_sku_inventory
  (sku_id, ndc_11, molecule_name, strength_norm, dosage_form, sku_description,
   sell_unit, therapeutic_area, on_hand_units, committed_units, wac_per_unit,
   earliest_expiry, distribution_ctr, is_active)
VALUES
  ('SKU-CIS-100',  '71999-0101-01', 'cisplatin',         '1MG/ML',    'INJECTION',
   'Cisplatin Injection 1 mg/mL, 100 mL multiple-dose vial',              'VIAL',   'Oncology',        6500,  3200, 41.20, '2028-03-31', 'Memphis DC',    TRUE),
  ('SKU-CIS-050',  '71999-0101-02', 'cisplatin',         '1MG/ML',    'INJECTION',
   'Cisplatin Injection 1 mg/mL, 50 mL multiple-dose vial',               'VIAL',   'Oncology',        1800,  1450, 22.90, '2027-11-30', 'Memphis DC',    TRUE),
  ('SKU-CARB-045', '71999-0102-01', 'carboplatin',       '10MG/ML',   'INJECTION',
   'Carboplatin Injection 10 mg/mL, 45 mL (450 mg) multiple-dose vial',   'VIAL',   'Oncology',        4200,  1900, 58.75, '2028-01-31', 'Memphis DC',    TRUE),
  ('SKU-CARB-005', '71999-0102-05', 'carboplatin',       '10MG/ML',   'INJECTION',
   'Carboplatin Injection 10 mg/mL, 5 mL (50 mg) single-dose vial',       'VIAL',   'Oncology',        3000,  2700,  9.40, '2027-09-30', 'Memphis DC',    TRUE),
  ('SKU-CARB-060', '71999-0102-06', 'carboplatin',       '10MG/ML',   'INJECTION',
   'Carboplatin Injection 10 mg/mL, 60 mL vial (DISCONTINUED)',           'VIAL',   'Oncology',           0,     0, 71.10, '2026-12-31', 'Memphis DC',    FALSE),
  ('SKU-ALB-025',  '71999-0205-25', 'albuterol sulfate', '2.5MG/3ML', 'INHALATION SOLUTION',
   'Albuterol Sulfate Inhalation Solution 0.083% (2.5 mg/3 mL), carton of 25', 'CARTON', 'Respiratory', 42000, 22500, 11.40, '2027-12-31', 'Reno DC',       TRUE),
  ('SKU-MTX-002',  '71999-0310-02', 'methotrexate',      '25MG/ML',   'INJECTION',
   'Methotrexate Injection 25 mg/mL, 2 mL single-dose vial',              'VIAL',   'Oncology',        9000,  4000,  6.85, '2027-08-31', 'Memphis DC',    TRUE),
  ('SKU-FLU-010',  '71999-0311-10', 'fluorouracil',      '50MG/ML',   'INJECTION',
   'Fluorouracil Injection 50 mg/mL, 10 mL pharmacy bulk vial',           'VIAL',   'Oncology',        5000,  3300,  4.10, '2027-10-31', 'Memphis DC',    TRUE),
  ('SKU-LIDO-030', '71999-0420-30', 'lidocaine hydrochloride', '10MG/ML', 'INJECTION',
   'Lidocaine HCl Injection 1% (10 mg/mL), 30 mL multiple-dose vial',     'VIAL',   'Anesthesia',     25000, 18000,  3.25, '2028-06-30', 'Columbus DC',   TRUE),
  ('SKU-AMOX-100', '71999-0530-10', 'amoxicillin',       '400MG/5ML', 'POWDER FOR ORAL SUSPENSION',
   'Amoxicillin for Oral Suspension 400 mg/5 mL, 100 mL bottle',          'BOTTLE', 'Anti-Infective',  60000, 41000,  4.95, '2027-05-31', 'Columbus DC',   TRUE),
  ('SKU-DEX-001',  '71999-0640-01', 'dexamethasone sodium phosphate', '4MG/ML', 'INJECTION',
   'Dexamethasone Sodium Phosphate Injection 4 mg/mL, 1 mL vial',         'VIAL',   'Anti-Inflammatory', 30000, 26500, 1.15, '2027-07-31', 'Columbus DC',   TRUE);

-- -----------------------------------------------------------------------------
-- 2. regional_gpo_accounts
--    Flattened account x product demand view (as typically built from CRM +
--    wholesaler chargeback / EDI 867 data). One row per account per our
--    therapeutically equivalent SKU.
--    our_contract_status:
--      AWARDED      -> we are the primary GPO-awarded supplier (demand already
--                      sits in committed_units; NOT a spot target)
--      SECONDARY    -> we hold a backup award; competitor is primary
--      NOT_AWARDED  -> competitor holds the award; account buys off-contract
--                      from us only during disruptions
-- -----------------------------------------------------------------------------
CREATE TABLE regional_gpo_accounts (
    account_id          VARCHAR(20)  NOT NULL,
    account_name        VARCHAR(120) NOT NULL,
    account_type        VARCHAR(30)  NOT NULL
                        CHECK (account_type IN ('IDN','HOSPITAL','CANCER_CENTER','CHILDRENS_HOSPITAL','PHYSICIAN_GROUP')),
    gpo_name            VARCHAR(40)  NOT NULL,
    state_code          CHAR(2)      NOT NULL CHECK (state_code ~ '^[A-Z]{2}$'),
    sku_id              VARCHAR(20)  NOT NULL REFERENCES internal_sku_inventory (sku_id),
    avg_monthly_units   INTEGER      NOT NULL CHECK (avg_monthly_units >= 0),   -- in our sell units
    our_contract_status VARCHAR(12)  NOT NULL
                        CHECK (our_contract_status IN ('AWARDED','SECONDARY','NOT_AWARDED')),
    incumbent_supplier  VARCHAR(60)  NOT NULL,
    kam_name            VARCHAR(60)  NOT NULL,                                  -- Key Account Manager
    PRIMARY KEY (account_id, sku_id)
);

CREATE INDEX ix_gpo_sku_state ON regional_gpo_accounts (sku_id, state_code);

COMMENT ON TABLE regional_gpo_accounts IS 'Mock GPO-affiliated account demand by SKU and USPS state (fictitious data).';

INSERT INTO regional_gpo_accounts
  (account_id, account_name, account_type, gpo_name, state_code, sku_id,
   avg_monthly_units, our_contract_status, incumbent_supplier, kam_name)
VALUES
  -- Oncology: cisplatin / carboplatin / methotrexate / fluorouracil
  ('ACC-1001', 'Lakeshore Health System',          'IDN',               'Vizient',     'IL', 'SKU-CIS-100',   650, 'NOT_AWARDED', 'Competitor A', 'Dana Whitfield'),
  ('ACC-1001', 'Lakeshore Health System',          'IDN',               'Vizient',     'IL', 'SKU-CIS-050',   300, 'NOT_AWARDED', 'Competitor A', 'Dana Whitfield'),
  ('ACC-1001', 'Lakeshore Health System',          'IDN',               'Vizient',     'IL', 'SKU-CARB-045',  450, 'SECONDARY',   'Competitor A', 'Dana Whitfield'),
  ('ACC-1002', 'Sierra Valley Cancer Institute',   'CANCER_CENTER',     'Premier',     'CA', 'SKU-CIS-100',   520, 'SECONDARY',   'Competitor A', 'Marco Ruiz'),
  ('ACC-1002', 'Sierra Valley Cancer Institute',   'CANCER_CENTER',     'Premier',     'CA', 'SKU-CARB-045',  380, 'NOT_AWARDED', 'Competitor B', 'Marco Ruiz'),
  ('ACC-1003', 'Gulf Coast Regional Medical Center','HOSPITAL',         'HealthTrust', 'TX', 'SKU-CIS-100',   480, 'NOT_AWARDED', 'Competitor A', 'Alicia Grant'),
  ('ACC-1003', 'Gulf Coast Regional Medical Center','HOSPITAL',         'HealthTrust', 'TX', 'SKU-CIS-050',   260, 'NOT_AWARDED', 'Competitor A', 'Alicia Grant'),
  ('ACC-1003', 'Gulf Coast Regional Medical Center','HOSPITAL',         'HealthTrust', 'TX', 'SKU-MTX-002',  1400, 'NOT_AWARDED', 'Competitor C', 'Alicia Grant'),
  ('ACC-1004', 'Piedmont Oncology Partners',       'PHYSICIAN_GROUP',   'Vizient',     'NC', 'SKU-CIS-100',   410, 'NOT_AWARDED', 'Competitor A', 'Dana Whitfield'),
  ('ACC-1004', 'Piedmont Oncology Partners',       'PHYSICIAN_GROUP',   'Vizient',     'NC', 'SKU-CARB-045',  300, 'NOT_AWARDED', 'Competitor B', 'Dana Whitfield'),
  ('ACC-1004', 'Piedmont Oncology Partners',       'PHYSICIAN_GROUP',   'Vizient',     'NC', 'SKU-FLU-010',   900, 'SECONDARY',   'Competitor C', 'Dana Whitfield'),
  ('ACC-1005', 'Keystone Academic Medical Center', 'HOSPITAL',          'Premier',     'PA', 'SKU-CIS-100',   340, 'AWARDED',     'Meridian Generics', 'Marco Ruiz'),
  ('ACC-1005', 'Keystone Academic Medical Center', 'HOSPITAL',          'Premier',     'PA', 'SKU-CARB-005',  900, 'AWARDED',     'Meridian Generics', 'Marco Ruiz'),
  ('ACC-3001', 'Great Plains Oncology Network',    'CANCER_CENTER',     'Vizient',     'NE', 'SKU-CARB-045',  220, 'NOT_AWARDED', 'Competitor B', 'Alicia Grant'),
  ('ACC-3001', 'Great Plains Oncology Network',    'CANCER_CENTER',     'Vizient',     'NE', 'SKU-CARB-005',  600, 'NOT_AWARDED', 'Competitor B', 'Alicia Grant'),
  -- Respiratory: albuterol nebules (West-region heavy)
  ('ACC-2001', 'Pacific Crest Health',             'IDN',               'Vizient',     'CA', 'SKU-ALB-025',  3200, 'NOT_AWARDED', 'Competitor D', 'Marco Ruiz'),
  ('ACC-2002', 'Desert Sun Medical Group',         'IDN',               'HealthTrust', 'AZ', 'SKU-ALB-025',  1900, 'SECONDARY',   'Competitor D', 'Priya Raman'),
  ('ACC-2003', 'Cascade Children''s Network',      'CHILDRENS_HOSPITAL','Premier',     'WA', 'SKU-ALB-025',  1400, 'NOT_AWARDED', 'Competitor D', 'Priya Raman'),
  ('ACC-2004', 'Silver State Hospitals',           'IDN',               'Vizient',     'NV', 'SKU-ALB-025',  1300, 'NOT_AWARDED', 'Competitor D', 'Priya Raman'),
  ('ACC-2005', 'Lone Star Pulmonary Associates',   'PHYSICIAN_GROUP',   'Premier',     'TX', 'SKU-ALB-025',  2100, 'NOT_AWARDED', 'Competitor D', 'Alicia Grant'),
  ('ACC-2006', 'Columbia River Medical Center',    'HOSPITAL',          'HealthTrust', 'OR', 'SKU-ALB-025',   900, 'AWARDED',     'Meridian Generics', 'Priya Raman'),
  -- Hospital injectables / anti-infectives
  ('ACC-4001', 'Bayou State Health Alliance',      'IDN',               'HealthTrust', 'LA', 'SKU-LIDO-030', 2600, 'NOT_AWARDED', 'Competitor E', 'Alicia Grant'),
  ('ACC-4002', 'Great Lakes Pediatric Partners',   'CHILDRENS_HOSPITAL','Vizient',     'MI', 'SKU-AMOX-100', 5200, 'SECONDARY',   'Competitor F', 'Dana Whitfield'),
  ('ACC-4003', 'Front Range Health',               'IDN',               'Premier',     'CO', 'SKU-DEX-001',  3100, 'NOT_AWARDED', 'Competitor E', 'Priya Raman');

-- -----------------------------------------------------------------------------
-- 3. shortage_opportunity_log
--    Audit trail + de-duplication store. One row per decision:
--    (source event x molecule/strength x our SKU), or one row per QA
--    quarantine. dedup_key is built by the workflow:
--       <source_event_id>|<molecule>|<strength>|<sku_id>      (sized decisions)
--       <source_event_id>|<ndc_raw or NO-NDC>|QA              (quarantine)
--    A PITCH_DISPATCHED row is never overwritten (no double pitching);
--    other statuses are re-evaluated on later runs as inventory changes.
-- -----------------------------------------------------------------------------
CREATE TABLE shortage_opportunity_log (
    log_id                 BIGSERIAL     PRIMARY KEY,
    dedup_key              VARCHAR(300)  NOT NULL UNIQUE,
    run_id                 VARCHAR(40)   NOT NULL,
    source_type            VARCHAR(20)   NOT NULL CHECK (source_type IN ('FDA_ENFORCEMENT','FDA_SHORTAGE')),
    source_event_id        VARCHAR(120)  NOT NULL,
    recall_classification  VARCHAR(20),
    recalling_firm         VARCHAR(160),
    external_ndc_11        CHAR(13)      CHECK (external_ndc_11 IS NULL OR external_ndc_11 ~ '^[0-9]{5}-[0-9]{4}-[0-9]{2}$'),
    molecule_name          VARCHAR(100),
    strength_norm          VARCHAR(40),
    affected_states        TEXT[],
    sku_id                 VARCHAR(20)   REFERENCES internal_sku_inventory (sku_id),
    on_hand_units          INTEGER,
    committed_units        INTEGER,
    fts_buffer_units       INTEGER,
    spot_eligible_units    INTEGER,
    target_monthly_units   INTEGER,
    addressable_units      INTEGER,
    wac_per_unit           NUMERIC(12,2),
    spot_price_per_unit    NUMERIC(12,2),
    net_spot_revenue_usd   NUMERIC(14,2),
    target_account_count   INTEGER,
    decision_status        VARCHAR(30)   NOT NULL CHECK (decision_status IN
                           ('PITCH_DISPATCHED','BELOW_THRESHOLD','FTS_PROTECTED_NO_CAPACITY','QA_QUARANTINE')),
    qa_notes               TEXT,
    created_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at             TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE INDEX ix_log_status_created ON shortage_opportunity_log (decision_status, created_at DESC);

COMMENT ON TABLE shortage_opportunity_log IS 'Decision audit trail and de-duplication store for the commercial trigger.';

-- Seed history so dashboards/queries have something to show before the first run
INSERT INTO shortage_opportunity_log
  (dedup_key, run_id, source_type, source_event_id, recall_classification, recalling_firm,
   external_ndc_11, molecule_name, strength_norm, affected_states, sku_id,
   on_hand_units, committed_units, fts_buffer_units, spot_eligible_units, target_monthly_units,
   addressable_units, wac_per_unit, spot_price_per_unit, net_spot_revenue_usd,
   target_account_count, decision_status, qa_notes, created_at, updated_at)
VALUES
  ('D-9042-2026|methotrexate|25MG/ML|SKU-MTX-002', 'RUN-20260916103000', 'FDA_ENFORCEMENT', 'D-9042-2026',
   'Class II', 'MOCK - Harborview Injectables Inc.', '68456-0221-01', 'methotrexate', '25MG/ML',
   ARRAY['TX','LA','OK','AR'], 'SKU-MTX-002', 9800, 3900, 585, 5315, 7400, 5315, 6.85, 6.03, 32049.45,
   3, 'BELOW_THRESHOLD', NULL, '2026-09-16 10:30:00+00', '2026-09-16 10:30:00+00'),
  ('SHORTAGE:68123-0731-10:09/30/2026|fluorouracil|50MG/ML|SKU-FLU-010', 'RUN-20261001103000', 'FDA_SHORTAGE',
   'SHORTAGE:68123-0731-10:09/30/2026', NULL, 'MOCK - Northwind Oncology Generics, LLC', '68123-0731-10',
   'fluorouracil', '50MG/ML', NULL, 'SKU-FLU-010', 21000, 3300, 495, 17205, 15200, 15200, 4.10, 3.61,
   54872.00, 6, 'PITCH_DISPATCHED', NULL, '2026-10-01 10:30:00+00', '2026-10-01 10:30:00+00'),
  ('D-9077-2026|NDC 5512345678|QA', 'RUN-20261021103000', 'FDA_ENFORCEMENT', 'D-9077-2026',
   'Class II', 'MOCK - Keel Pharma Corp.', NULL, 'dexamethasone sodium phosphate', '4MG/ML',
   ARRAY['CO','UT'], NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
   'QA_QUARANTINE', 'NDC_UNRESOLVABLE:AMBIGUOUS_UNHYPHENATED', '2026-10-21 10:30:00+00', '2026-10-21 10:30:00+00');

-- -----------------------------------------------------------------------------
-- 4. Reporting view: commercial pipeline by decision status
-- -----------------------------------------------------------------------------
CREATE VIEW v_opportunity_pipeline AS
SELECT decision_status,
       COUNT(*)                                     AS decisions,
       COUNT(DISTINCT source_event_id)              AS source_events,
       COALESCE(SUM(net_spot_revenue_usd), 0)::NUMERIC(14,2) AS net_spot_revenue_usd,
       MAX(updated_at)                              AS last_decision_at
FROM shortage_opportunity_log
GROUP BY decision_status;

COMMIT;

-- Quick checks:
--   SELECT * FROM v_opportunity_pipeline;
--   SELECT sku_id, labeler_code, on_hand_units, committed_units FROM internal_sku_inventory ORDER BY sku_id;
