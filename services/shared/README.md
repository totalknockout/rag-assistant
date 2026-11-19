# services/shared

Code shared by the ingest and query functions: configuration loading, structured
logging, the vector-store client and the chunk data model. It arrives in Milestones 1-4.
Each function's build step copies this package into its deployment artefact, so
keep it free of heavy dependencies.
