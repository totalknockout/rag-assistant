# Architecture

## Reference design (production)

`enterprise-rag-well-architected.drawio` (open in draw.io or app.diagrams.net) and
its PNG export show the full design: three Availability Zones in us-west-2,
private subnets with VPC endpoints, OpenSearch Serverless, Bedrock Guardrails and
Rerank, and a pilot-light DR Region. Each component is annotated against the six
pillars of the AWS Well-Architected Framework.

## Deployed variant (portfolio)

[ADR 0002](../adr/0002-serverless-low-cost-deployment.md) records the low-cost
variant actually deployed: no VPC, GitHub Pages for the front end, LanceDB on S3
for retrieval, and an open-weight model on Bedrock. A diagram of the deployed
variant will be added here as it takes shape.
