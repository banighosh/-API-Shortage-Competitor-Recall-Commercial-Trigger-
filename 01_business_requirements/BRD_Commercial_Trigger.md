# Business Requirements Document (BRD)
## API Shortage & Competitor Recall Commercial Trigger

| Document control | |
|---|---|
| **Document ID** | BRD-CT-001 |
| **Copyright** | © 2026 Banibrata. All rights reserved. See [LICENSE](../LICENSE). |
| **Version** | 1.0 |
| **Date** | 04-Nov-2026 |
| **Author** | Banibrata, Business Analyst |
| **Business sponsor** | VP, Commercial Operations (fictitious role for portfolio purposes) |
| **Status** | Baselined for build (portfolio demonstration) |
| **Related artifacts** | `02_n8n_workflows/pharma_recall_commercial_trigger.json`, `03_database_schema/schema.sql` |

| Version | Date | Author | Change |
|---|---|---|---|
| 0.1 | 20-Oct-2026 | Banibrata | Initial draft from discovery workshops |
| 0.9 | 29-Oct-2026 | Banibrata | Added AI governance, QA gates, FTS rule after Supply Chain review |
| 1.0 | 04-Nov-2026 | Banibrata | Baselined; UAT scenarios and traceability added |

> All organizations, accounts, products, prices and FDA records referenced here are fictitious. "Meridian Generics" (NDC labeler code 71999) is the fictional company that owns this process.

---

## 1. Executive summary

Meridian Generics manufactures sterile generic injectables and inhalation products sold through GPO contracts to hospitals and IDNs. When a competitor recalls a product, or a supply disruption (frequently an active pharmaceutical ingredient, **API**, constraint) places a molecule on the FDA shortage list, affected hospitals urgently need backup supply. Today the company detects these events late and sizes responses inconsistently.

This initiative automates detection, qualification and sizing of these **spot-buy opportunities** with an n8n workflow that combines public openFDA data, LLM-based information extraction, deterministic quality gates, ERP inventory and GPO demand data. Qualified opportunities (≥ $50,000 net) are pushed to key-account managers (KAMs) in Slack within one business day of FDA publication, while contracted supply is protected by a 15% Failure-to-Supply (FTS) buffer.

---

## 2. Business problem & opportunity

| # | Pain point (As-Is) | Business consequence |
|---|---|---|
| P1 | An analyst reads the FDA Enforcement Report and shortage list once a week | Competitors and distributors fill the gap first; pitches land 3–5 days late |
| P2 | NDCs appear in free text in mixed 10-digit formats (4-4-2, 5-3-2, 5-4-1) | Manual conversion errors; products mismatched to our SKUs |
| P3 | Spot quantities are promised without a formal check against GPO commitments | FTS penalties and damage to awarded-contract relationships |
| P4 | Sizing lives in personal Excel files with no consistent price rule | Inconsistent pricing, pricing-governance risk, no audit trail |
| P5 | Bandwidth limits coverage to Class I recalls on top molecules | Long-tail opportunities missed entirely |

**Opportunity.** Large shortages, such as the 2023 US platinum-chemotherapy shortage that followed one supplier's quality-related production halt, show how one competitor's disruption can shift significant demand within days. Faster, disciplined response converts that demand into revenue and positions Meridian for the next GPO award cycle.

---

## 3. Objectives & success metrics

| ID | Objective | KPI | Baseline (modeled) | Target |
|---|---|---|---|---|
| OBJ-1 | Respond faster to competitor supply failures | Lead time from openFDA publication to KAM alert | 3–5 business days | < 24 hours |
| OBJ-2 | Protect contracted supply | % of spot quantities sized after the FTS buffer | Not measured | 100% |
| OBJ-3 | Reduce manual analyst effort | Analyst hours per week on signal triage | ~6 hrs | ≤ 1 hr (exception review) |
| OBJ-4 | Improve identifier data quality | % of NDCs passing 5-4-2 validation and grounding before use | Not measured | 100% (failures quarantined) |
| OBJ-5 | Focus sales effort on material deals | % of alerts meeting the ≥ $50k net threshold | n/a | 100% |
| OBJ-6 | Make decisions auditable | % of decisions with logged inputs and outcome | ~0% | 100% |

---

## 4. Scope

**In scope**
- Daily polling of openFDA `/drug/enforcement.json` and `/drug/shortages.json`.
- LLM extraction of molecule, strength, dosage form, NDCs and US distribution states.
- Deterministic QA gates (NDC grounding, normalization, regex, USPS validation).
- Matching to ERP inventory snapshot and GPO account demand (PostgreSQL).
- Opportunity sizing (WAC − 12%, 15% FTS buffer, one month of demand) and threshold filter (≥ $50k).
- Slack alert to KAMs; decision logging, de-duplication and QA quarantine.

**Out of scope (this release)**
- Automatic customer-facing outreach, quotes or order creation.
- Pricing approval workflow (remains with Pricing & Contracts).
- ASHP shortage data, FDA "To Be Discontinued" listings, international markets.
- CRM write-back and win/loss tracking (roadmap).

---

## 5. Stakeholders & RACI

| Activity | Commercial Ops (Sponsor) | KAMs / National Accounts | Supply Chain Planning | Pricing & Contracts | Regulatory / Compliance (incl. MLR) | Data & IT | Business Analyst |
|---|---|---|---|---|---|---|---|
| Define business rules (buffer, discount, threshold) | **A** | C | R | R | C | I | R |
| Maintain inventory & commitment data | I | I | **A/R** | I | I | R | I |
| Maintain GPO account demand data | A | R | I | C | I | R | I |
| Act on Slack opportunity alerts | I | **A/R** | C | R | C | I | I |
| Approve spot pricing per deal | I | C | I | **A/R** | C | I | I |
| Approve outreach templates | I | C | I | C | **A/R** | I | I |
| Review QA quarantine queue | I | I | C | I | C | R | **A/R** |
| Operate and monitor the workflow | I | I | I | I | I | **A/R** | C |

R = Responsible, A = Accountable, C = Consulted, I = Informed.

---

## 6. Process overview

### 6.1 As-Is (manual)
1. Analyst opens the weekly FDA Enforcement Report and the FDA shortage page.
2. Analyst scans for molecules Meridian sells and copies NDCs into Excel.
3. Analyst converts NDCs by hand and looks up stock in ERP.
4. Analyst estimates a quantity and price, then emails the regional KAM.
5. KAM decides whether to pursue. No central record is kept.

### 6.2 To-Be (automated)
1. **06:30 ET daily:** n8n builds a 7-day query window and loads active portfolio molecules.
2. n8n calls the openFDA Enforcement and Shortages APIs.
3. Code filters to Class I/II, ongoing, in-window, in-portfolio events (no LLM cost for irrelevant records).
4. The LLM extracts structured product and distribution data using a strict JSON schema.
5. The QA gate validates every field deterministically. Failures go to quarantine for analyst review.
6. SQL matches passing signals to active SKUs (molecule + strength) and to competitor-held GPO accounts in affected states, excluding our own NDCs and previously pitched events.
7. Code sizes each SKU opportunity and assigns a decision status.
8. Opportunities ≥ $50k net are posted to Slack. All decisions are logged.

See the Mermaid architecture diagram in `README.md`.

---

## 7. Functional requirements

Priority uses MoSCoW (M = Must, S = Should, C = Could).

### 7.1 Data acquisition (openFDA daily polling)

| ID | Requirement | Priority | Acceptance criteria |
|---|---|---|---|
| FR-01 | The system shall run automatically once per day at 06:30 America/New_York. | M | Schedule trigger fires daily; workflow timezone set to America/New_York. |
| FR-02 | The system shall query openFDA `/drug/enforcement.json` for records whose `report_date` falls in the last 7 days. | M | Query uses `report_date:[YYYYMMDD TO YYYYMMDD]`, `limit=1000`. |
| FR-03 | The system shall query openFDA `/drug/shortages.json` for `status:"Current"` and keep records updated within the look-back window. | M | `update_date` (MM/DD/YYYY) parsed; records older than the window are excluded in production runs. |
| FR-04 | A "no matches" response (HTTP 404 from openFDA) shall be treated as zero events, not as a failure. | M | HTTP node set to never error on status; run completes with zero events. |
| FR-05 | API calls shall retry up to 3 times on transient failure. | S | `retryOnFail=true`, `maxTries=3`. |

### 7.2 Relevance pre-filter

| ID | Requirement | Priority | Acceptance criteria |
|---|---|---|---|
| FR-06 | Only Class I and Class II recalls with status "Ongoing" shall proceed. | M | Class III and Completed/Terminated recalls are dropped. |
| FR-07 | Only events that mention a molecule in the active portfolio shall be sent to the LLM. | M | Word-boundary match against `internal_sku_inventory.molecule_name` where `is_active`. |
| FR-08 | No more than 40 events per run shall be sent to the LLM. | S | Cap configurable as `MAX_EVENTS_PER_RUN`. |

### 7.3 AI information extraction

| ID | Requirement | Priority | Acceptance criteria |
|---|---|---|---|
| FR-09 | An LLM Information Extractor shall return output conforming to a strict JSON schema: products[] (generic_name, strength_norm, dosage_form, ndc_raw, ndc_11, ndc_source_format), distribution (nationwide, us_state_codes[]), supply_impact_summary. | M | Output validates against the schema in the workflow node. |
| FR-10 | The system prompt shall instruct the model to convert 10-digit NDCs to 11-digit 5-4-2 format per BR-01 and to leave unhyphenated 10-digit NDCs blank as `AMBIGUOUS_UNHYPHENATED`. | M | Prompt contains the BR-01 conversion table and ambiguity rule. |
| FR-11 | The system prompt shall instruct the model to return 2-letter USPS codes, converting full state names (e.g., "Washington" → WA) and ignoring non-US locations. | M | Verified in UAT TS-02. |
| FR-12 | The model shall run at temperature 0. | M | Model sub-node temperature = 0. |
| FR-13 | If extraction fails for an event, the run shall continue and the event shall be quarantined as `LLM_EXTRACTION_FAILED`. | M | Extractor node `onError = continueRegularOutput`; QA gate handles missing output. |

### 7.4 Deterministic QA gates (post-LLM)

| ID | Requirement | Priority | Acceptance criteria |
|---|---|---|---|
| FR-14 | **G1 Grounding:** each `ndc_raw` must appear in the source FDA text (ignoring spaces and hyphens). | M | Hallucinated NDC → `NDC_NOT_GROUNDED_IN_SOURCE` → quarantine. |
| FR-15 | **G2 Rebuild:** the NDC-11 shall be recomputed in code from `ndc_raw` using BR-01. The LLM's `ndc_11` is compared, never trusted. | M | Mismatch logged as `LLM_NDC_CORRECTED:<llm>-><rule>`; rule value used downstream. |
| FR-16 | **G2 Regex:** the final NDC shall match `^\d{5}-\d{4}-\d{2}$`. Unresolvable or ambiguous NDCs are quarantined. | M | `5512345678` → `NDC_UNRESOLVABLE:AMBIGUOUS_UNHYPHENATED`. |
| FR-17 | **G3 States:** only codes in the USPS whitelist (50 states + DC + PR) are kept; at least one valid state (or nationwide) is required. | M | Invalid codes dropped and noted; zero valid states → quarantine. |
| FR-18 | **G4 Product:** molecule must be present; strength must match the normalized pattern (e.g., `1MG/ML`, `2.5MG/3ML`). | M | Unparseable strength → quarantine. |
| FR-19 | Multiple NDCs of the same molecule and strength in one event shall form one commercial signal. | M | Cisplatin 50 mL and 100 mL NDCs → one signal, two SKU matches. |
| FR-20 | Quarantined records shall be written to `shortage_opportunity_log` with status `QA_QUARANTINE` and reasons. | M | Row present with `qa_notes`. |

### 7.5 Inventory & demand matching

| ID | Requirement | Priority | Acceptance criteria |
|---|---|---|---|
| FR-21 | Signals shall match active SKUs on molecule (case-insensitive) and normalized strength. | M | Inactive SKUs excluded. |
| FR-22 | Target demand shall include only `SECONDARY` and `NOT_AWARDED` accounts located in the affected states. | M | `AWARDED` accounts and out-of-footprint accounts excluded (TS-02). |
| FR-23 | Events whose NDC labeler code belongs to Meridian shall not create opportunities. | M | Own-product shortage returns zero matches (TS-05). |
| FR-24 | An event × SKU already logged as `PITCH_DISPATCHED` shall not be matched again. | M | Second run sends no duplicate pitch (TS-07). |
| FR-25 | All SQL shall use bound query parameters; no FDA or LLM text is concatenated into SQL. | M | Postgres nodes use Query Parameters. |

### 7.6 BA sizing (WAC − 12%, 15% FTS buffer)

| ID | Requirement | Priority | Acceptance criteria |
|---|---|---|---|
| FR-26 | The system shall calculate FTS buffer, spot-eligible units, addressable units, spot price and net revenue per BR-03 to BR-05. | M | Worked example in §8.1 reproduces exactly. |
| FR-27 | All commercial calculations shall be deterministic code; the LLM shall not compute or alter any quantity or price. | M | Sizing node contains no AI calls. |
| FR-28 | Each sized record shall receive a decision status: `PITCH_DISPATCHED`, `BELOW_THRESHOLD` or `FTS_PROTECTED_NO_CAPACITY`. | M | Status matches BR-06. |

### 7.7 Dispatch & audit

| ID | Requirement | Priority | Acceptance criteria |
|---|---|---|---|
| FR-29 | Only opportunities with net revenue ≥ $50,000 shall be posted to Slack. | M | If node: number ≥ 50000. |
| FR-30 | The Slack message shall show trigger, reason, footprint, SKU and NDC, on-hand / committed / buffer, spot-eligible and addressable units, spot price vs WAC, net revenue, target accounts, KAM owners and the compliance next step. | M | Message content verified in UAT. |
| FR-31 | Every sized decision shall be upserted to `shortage_opportunity_log`; a `PITCH_DISPATCHED` row shall never be overwritten. | M | `ON CONFLICT … WHERE decision_status <> 'PITCH_DISPATCHED'`. |
| FR-32 | A reporting view shall summarize decisions and revenue by status. | S | `v_opportunity_pipeline` returns counts and totals. |

---

## 8. Business rules

| ID | Rule |
|---|---|
| **BR-01** | **NDC normalization (HIPAA 11-digit, 5-4-2).** Add one leading zero to the short segment: `4-4-2 → 0XXXX-XXXX-XX`; `5-3-2 → XXXXX-0XXX-XX`; `5-4-1 → XXXXX-XXXX-0X`; `5-4-2` unchanged; 11 digits without hyphens are split 5-4-2. **A 10-digit NDC without hyphens is ambiguous and must never be converted.** |
| **BR-02** | **Geography.** States are 2-letter USPS codes. "Nationwide" and all FDA shortage-list records expand to all 50 states + DC + PR. |
| **BR-03** | **FTS buffer.** `fts_buffer_units = CEIL(committed_units × 15%)`; `protected_units = committed_units + fts_buffer_units`; `spot_eligible_units = MAX(0, on_hand_units − protected_units)`. Committed units are open orders plus 30-day awarded GPO allocation. |
| **BR-04** | **Addressable volume.** `addressable_units = MIN(spot_eligible_units, target_monthly_units × 1 month)`. |
| **BR-05** | **Spot price and revenue.** `spot_price = ROUND(WAC × (1 − 12%), 2)`; `net_spot_revenue = addressable_units × spot_price`. Spot price is always below WAC. |
| **BR-06** | **Decision.** Net ≥ $50,000 → `PITCH_DISPATCHED`; else if spot-eligible = 0 → `FTS_PROTECTED_NO_CAPACITY`; else `BELOW_THRESHOLD`. |
| **BR-07** | **Eligible events.** Recall Class I or II with status Ongoing, or FDA shortage status Current. |
| **BR-08** | **Own-product exclusion.** Any event whose NDC labeler code equals a Meridian labeler code is excluded. |
| **BR-09** | **De-duplication key.** `<source_event_id>|<molecule>|<strength>|<sku_id>`. Shortage event IDs include the FDA update date, so a material FDA update is re-evaluated. |

### 8.1 Worked example (UAT TS-01, SKU-CIS-100)

| Step | Calculation | Result |
|---|---|---|
| On hand | from ERP | 6,500 vials |
| Committed (GPO + open orders) | from ERP | 3,200 vials |
| FTS buffer | CEIL(3,200 × 0.15) | 480 vials |
| Spot-eligible | 6,500 − 3,200 − 480 | 2,820 vials |
| Target demand (4 competitor-held accounts, nationwide) | 650 + 520 + 480 + 410 | 2,060 vials/month |
| Addressable | MIN(2,820, 2,060) | 2,060 vials |
| Spot price | ROUND(41.20 × 0.88, 2) | $36.26 |
| **Net spot revenue** | 2,060 × 36.26 | **$74,695.60 → pitch** |

---

## 9. Data requirements

| Source | Key fields used | Refresh |
|---|---|---|
| openFDA Enforcement | recall_number, classification, status, recalling_firm, product_description, code_info, reason_for_recall, distribution_pattern, report_date | Weekly FDA publication; polled daily |
| openFDA Drug Shortages | generic_name, company_name, status, availability, presentation, package_ndc, shortage_reason, update_date | Polled daily |
| `internal_sku_inventory` (ERP) | sku_id, ndc_11, labeler_code, molecule_name, strength_norm, on_hand_units, committed_units, wac_per_unit, is_active | Nightly ERP sync |
| `regional_gpo_accounts` (CRM + chargeback) | account, GPO, state_code, sku_id, avg_monthly_units, our_contract_status, kam_name | Monthly |
| `shortage_opportunity_log` (output) | dedup_key, source event, NDC, states, sizing inputs/outputs, decision_status, qa_notes | Each run |

Full column definitions and constraints are in `03_database_schema/schema.sql`.

---

## 10. Non-functional requirements

| ID | Category | Requirement |
|---|---|---|
| NFR-01 | Timeliness | End-to-end run completes in under 10 minutes for up to 40 LLM events. |
| NFR-02 | Reliability | Transient API/LLM failures retried 3×; single-event failures do not stop the run. |
| NFR-03 | Security | Credentials stored only in the n8n credential vault; least-privilege DB user (SELECT on reference tables, INSERT/UPDATE on the log). |
| NFR-04 | Privacy | Public FDA data and commercial master data only; no patient data (PHI) is processed. |
| NFR-05 | Auditability | Every decision is traceable to source event, inputs, rule version and QA notes; retained per company record-retention policy. |
| NFR-06 | Cost | LLM calls limited to pre-filtered events; maximum 40 per run. |
| NFR-07 | Maintainability | Business parameters centralized in one configuration block; prompt and schema version-controlled in Git. |

---

## 11. AI governance & controls

| Control | Implementation |
|---|---|
| Purpose limitation | LLM used only to read unstructured FDA text; it makes no commercial decision. |
| Determinism | Temperature 0; strict JSON schema; versioned system prompt. |
| Hallucination control | G1 grounding check; NDC rebuilt by rule (G2); USPS whitelist (G3). |
| Fail-safe routing | Any failed gate goes to `QA_QUARANTINE`, never to Sales. |
| Monitoring | Track weekly: quarantine rate, `LLM_NDC_CORRECTED` rate, events per run, pitches per run. Investigate if the correction rate exceeds 5%. |
| Change control | Model or prompt changes require re-running UAT scenarios TS-01 to TS-08 before activation. |
| Human oversight | KAMs act only after Pricing & Contracts approval; analysts own the quarantine queue. |

---

## 12. Compliance considerations

*For portfolio discussion only, not legal advice.*

- **Pricing governance:** spot price is fixed below WAC, which avoids premium pricing during shortages; state price-gouging laws vary, so Pricing & Contracts approves each quote.
- **Promotional review (MLR):** outreach uses only pre-approved shortage-response templates and stays within approved labeling.
- **Competitor references:** communications cite only the public FDA record and make no other claims about a competitor's product or quality.
- **Competition law:** pricing is set independently from public data and internal costs; no information is exchanged with competitors.
- **Contractual:** the FTS buffer protects obligations under awarded GPO agreements.
- **Data terms:** openFDA data is used under its terms of service and disclaimer (results are unvalidated and not for clinical decisions).

---

## 13. Assumptions, constraints & dependencies

| Type | Item |
|---|---|
| Assumption | ERP inventory and commitments are synced nightly and accurate at run time. |
| Assumption | Account demand (avg monthly units in our sell units) is a reasonable proxy for spot need. |
| Assumption | A competitor's recall affects therapeutically equivalent demand for the same molecule and strength. |
| Constraint | openFDA enforcement data reflects FDA's weekly publication cadence. |
| Constraint | Shortage records carry no geography and are treated as nationwide. |
| Dependency | n8n instance with AI nodes; PostgreSQL; LLM API access; Slack bot with `chat:write`. |

---

## 14. Risks & mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| LLM extracts a wrong or invented NDC | Medium | High | Grounding + rule rebuild + regex; quarantine on failure |
| Over-allocation hurts contracted customers | Low | High | 15% FTS buffer on commitments; deterministic sizing |
| Duplicate pitches annoy customers | Medium | Medium | Database de-dup key; dispatched rows never overwritten |
| openFDA schema or availability changes | Low | Medium | Never-error HTTP handling, retries, run monitoring |
| Stale ERP data overstates stock | Medium | Medium | Nightly sync monitored via `last_erp_sync_at`; KAM confirms availability before quoting |
| Perceived opportunism toward competitors' failures | Low | Medium | Below-WAC pricing, factual MLR-approved messaging, patient-supply framing |

---

## 15. UAT test scenarios

All scenarios run against the pinned demo data and seeded database.

| ID | Scenario | Expected result | Status |
|---|---|---|---|
| TS-01 | Nationwide Class II cisplatin recall, two NDCs in 5-3-2 format | One signal; SKU-CIS-100 $74,695.60 → Slack; SKU-CIS-050 $2,659.80 → `BELOW_THRESHOLD` | Pass |
| TS-02 | Class I albuterol recall in "CA, NV, AZ, OR and Washington", NDC 4-4-2 | States CA, NV, AZ, OR, WA; TX and AWARDED OR accounts excluded; $78,234.00 → Slack | Pass |
| TS-03 | Carboplatin on the FDA shortage list, NDC 5-4-1; injected LLM error pads the wrong segment | Gate corrects `68123-05502-1` → `68123-5502-01`; SKU-CARB-045 $69,795.00 → Slack; SKU-CARB-005 → `FTS_PROTECTED_NO_CAPACITY` | Pass |
| TS-04 | Methotrexate recall printing NDC `5512345678` | `QA_QUARANTINE`, reason `AMBIGUOUS_UNHYPHENATED` | Pass |
| TS-05 | Shortage listing of Meridian's own lidocaine NDC | No opportunity (own-labeler guard) | Pass |
| TS-06 | Class III recall; recall of a non-portfolio molecule | Dropped before the LLM | Pass |
| TS-07 | Re-run with the same events | No duplicate pitches; non-dispatched rows refreshed | Pass |
| TS-08 | LLM returns an NDC not present in the FDA text | `NDC_NOT_GROUNDED_IN_SOURCE` → quarantine | Pass |

---

## 16. Requirements traceability matrix

| Requirement(s) | n8n node / artifact |
|---|---|
| FR-01 | Daily Schedule Trigger |
| FR-02, FR-03 | Build Query Window → OpenFDA Enforcement / OpenFDA Shortages |
| FR-04, FR-05 | HTTP node options (never error, retry) |
| FR-06 – FR-08 | Normalize & Pre-Filter Events; Load Portfolio Molecules |
| FR-09 – FR-13 | AI Information Extractor + Anthropic Chat Model (schema, system prompt) |
| FR-14 – FR-19 | NDC & State QA Gate |
| FR-20 | QA Passed? (false) → Log QA Quarantine |
| FR-21 – FR-25 | Match ERP Inventory & GPO Demand |
| FR-26 – FR-28 | BA Spot-Buy Sizing |
| FR-29, FR-30 | Net Revenue ≥ $50k? → Slack GPO Pitch Alert |
| FR-31 | Log Opportunity Decision; `shortage_opportunity_log` |
| FR-32 | `v_opportunity_pipeline` |

---

## 17. Glossary

| Term | Definition |
|---|---|
| **API** | Active Pharmaceutical Ingredient, the chemically active component of a drug. API supply disruptions are a common cause of finished-dose shortages. (The workflow also calls web APIs; context makes the meaning clear.) |
| **FTS** | Failure-to-Supply: GPO contract provisions under which a supplier that cannot deliver awarded volume may owe penalties or price differences. |
| **GPO** | Group Purchasing Organization, which negotiates contracts on behalf of member hospitals and IDNs. |
| **IDN** | Integrated Delivery Network, a health system that owns multiple hospitals and sites of care. |
| **KAM** | Key Account Manager. |
| **MLR** | Medical, Legal and Regulatory review of promotional materials. |
| **NDC** | National Drug Code: labeler-product-package identifier. FDA lists it as 10 digits; HIPAA billing uses the 11-digit 5-4-2 format. |
| **Recall class** | FDA severity: Class I (serious harm likely), Class II (temporary or reversible harm), Class III (unlikely to cause harm). |
| **WAC** | Wholesale Acquisition Cost, the manufacturer's list price to wholesalers before discounts. |
| **Spot buy** | Off-contract purchase made to cover an immediate supply gap. |

---

## 18. Sign-off

| Role | Name | Decision | Date |
|---|---|---|---|
| Business sponsor (Commercial Ops) | | | |
| Supply Chain Planning | | | |
| Pricing & Contracts | | | |
| Regulatory / Compliance | | | |
| Data & IT | | | |
