# macromerit.com
Official website for Macromerit LLC — Technology Consulting &amp; Software

## Infrastructure

`infra/main.tf` (OpenTofu) provisions S3 + CloudFront, AWS profile
`macromerit-admin`, region `us-east-1`.

State is remote: S3 bucket `macromerit-tfstate`, key
`macromerit.com/terraform.tfstate` (versioned, SSE-S3 encrypted), shared with
the `mealmerit` and `carnaticmusicschool` projects under separate keys — same
account, no reason for three buckets. Locking is native S3
(`use_lockfile = true`, requires OpenTofu/Terraform `>= 1.10`) rather than a
DynamoDB table — same protection against a concurrent `apply`, one fewer
resource to maintain. Before this, state was local-only and gitignored.
