# Costs

| Mode | Cost |
|---|---|
| Local lab (Docker) and Jenkins | $0 |
| GitHub Actions CI | $0 (public repository) |
| AWS lab while up (`aws-up.sh`) | **≈ $0.02/hour**: 2 x t4g.nano (≈ $0.004 each), 2 public IPv4 ($0.005 each), 2 x 8 GB gp3 (≈ $0.001 each) |
| Showcase workflow (create, audit, harden, deploy, delete) | ≈ $0.01 per run |
| AWS lab while down | $0 (state file in S3: fractions of a cent) |

Prices: ap-south-1 (Mumbai), on-demand, rounded, October 2026; Sydney (ap-southeast-2, the demo account) is a
little dearer but still about $0.02/hour. Check the [AWS pricing calculator](https://calculator.aws/) for your region.

Guard rails: `aws-down.sh`, the nightly **Auto-stop** workflow (classic AWS accounts only), `credit_specification =
"standard"` (no surprise CPU-credit charges), and the `aws-foundation` budgets ($1/day, $10/month).
