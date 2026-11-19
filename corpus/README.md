# Corpus

Sample documents for ingestion and evaluation, added from Milestone 1.

- Aim for 100-300 documents across four or five departments.
- Mix public documents (for example GOV.UK guidance) with synthetic "internal" ones.
- Include awkward formats on purpose: a scanned PDF, tables, long DOCX files, and two versions of the same policy.

Each document has a sidecar `<file>.metadata.json`:

```json
{
  "metadataAttributes": {
    "department": "hr",
    "allowed_groups": ["hr", "all-staff"],
    "version": 3,
    "effective_date": "2026-04-01",
    "classification": "internal"
  }
}
```

If you include GOV.UK material, keep this attribution in the repository:
"Contains public sector information licensed under the Open Government Licence v3.0."
