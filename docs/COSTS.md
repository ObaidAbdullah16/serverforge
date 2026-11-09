# Costs

| Mode | Cost |
|---|---|
| Local lab (Docker) and Jenkins | $0 |
| GitHub Actions CI | $0 (public repository) |
| AWS lab while up (`aws-up.sh`) | **≈ $0.03/hour**: 2 x t4g.micro (≈ $0.011 each in Sydney), 2 public IPv4 ($0.005 each), 2 x 8 GB gp3 (≈ $0.001 each) |
| Showcase workflow (create, audit, harden, deploy, delete) | ≈ $0.01 per run |
| AWS lab while down | $0 (state file in S3: fractions of a cent) |

Prices: ap-southeast-2 (Sydney, the demo account), on-demand, rounded, November 2026. t4g.micro rather than the
cheaper t4g.nano because accounts on the AWS Free plan can only start "Free tier eligible" types (t4g.micro is one;
it also has 1 GB of memory instead of 0.5). Check the [AWS pricing calculator](https://calculator.aws/) for your region.

Guard rails: `aws-down.sh`, the nightly **Auto-stop** workflow (classic AWS accounts only), `credit_specification =
"standard"` (no surprise CPU-credit charges), and the `aws-foundation` budgets ($1/day, $10/month).
