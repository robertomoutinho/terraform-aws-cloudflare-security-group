AWS CloudFlare security group Terraform module
==============================================

Terraform module that populates a security group with cloudflare ip ranges and keeps it updated daily.

The following resources are created:

* A lambda function that keeps your security group's ingress rules updated with published cloudflare ip ranges.
* A cloudwatch event rule with a schedule to trigger the lambda daily
* Optionally, IAM allowing that same lambda to keep S3 bucket policies updated with the same ranges (see [S3 bucket policies](#s3-bucket-policies))

Usage
-----

```hcl
module "cloudflare-security-group" {

  source  = "robertomoutinho/cloudflare-security-group/aws"
  
  vpc_id        = "vpc-123456"
  environment   = "staging"
  tags          = {
    Environment = "staging"
    CostCenter  = "devsecops"
  }
  allowed_ports = [80, 443]

}
```

S3 bucket policies
------------------

S3 is not in the VPC, so a security group cannot govern access to a bucket. For a
bucket fronted by Cloudflare, the equivalent control is a bucket policy with an
`aws:SourceIp` condition — and that list needs the same daily refresh the
security group gets. Set `s3_bucket_policy_targets` and the same lambda keeps it
current.

The feature is off by default. Existing consumers that do not set this input get
the same resources and the same lambda environment as before.

### Why a template instead of a bucket name

A security group holds many discrete rules, so the lambda can add and revoke
them one at a time and terraform need not own any of them. An S3 bucket has
exactly one policy document and no incremental API, so whoever writes it writes
all of it — including any statements that have nothing to do with Cloudflare.

Rather than move your whole security posture into this module, you pass the
complete policy with a sentinel where the CIDR list goes. You own the document's
shape and it stays reviewable in your own repo; the lambda owns only the IP list.

```hcl
locals {
  bucket = "my-assets-bucket"

  # The lambda is the sole writer of this document, so every statement the bucket
  # needs has to be here -- not just the Cloudflare one.
  policy_template = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudflareEdgeRead"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::${local.bucket}/*"
        Condition = {
          IpAddress = {
            # Replaced with the current ranges, IPv4 and IPv6.
            "aws:SourceIp" = "__CLOUDFLARE_IP_RANGES__"
          }
        }
      },
      {
        Sid       = "DenyNonTLSRequests"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = ["arn:aws:s3:::${local.bucket}", "arn:aws:s3:::${local.bucket}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}

module "cloudflare-security-group" {
  source = "robertomoutinho/cloudflare-security-group/aws"

  vpc_id      = "vpc-123456"
  environment = "staging"
  tags        = { Environment = "staging" }

  s3_bucket_policy_targets = [
    {
      bucket          = local.bucket
      policy_template = local.policy_template
    }
  ]
}
```

### Things to know

**Do not also manage the policy in terraform.** Set `attach_policy = false` (or
your module's equivalent) on the bucket. If both write it, every apply reverts
the lambda and every lambda run shows up as drift.

**Block Public Access must permit the policy.** A policy granting anonymous read
needs `block_public_policy` and `restrict_public_buckets` off on that bucket,
whoever writes it.

**There is a cold start.** Between bucket creation and the lambda's next
scheduled run the bucket has no policy at all. That fails closed — reads are
denied, nothing is exposed — but it does mean broken reads until the lambda
runs. Invoke it once after the first apply:

```sh
aws lambda invoke --function-name <environment>-UpdateCloudflareIps /dev/null
```

**Environment variables are capped at 4 KB total.** The templates travel to the
lambda that way, so one or two policies are fine and a long list of buckets is
not. Exceeding it surfaces as `InvalidParameterValueException` at apply time.

**Empty upstream responses are refused.** If the Cloudflare API returns no
ranges the lambda raises rather than writing an empty allowlist, which would
otherwise lock Cloudflare out of every configured bucket at once.

**IAM is scoped to the buckets you name**, not `*` — this lambda cannot rewrite
the access policy of any other bucket in the account.

<!-- BEGINNING OF PRE-COMMIT-TERRAFORM DOCS HOOK -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 0.14.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 3.36.0, < 4.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_archive"></a> [archive](#provider\_archive) | n/a |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 3.36.0, < 4.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_security-group"></a> [security-group](#module\_security-group) | terraform-aws-modules/security-group/aws | 4.7.0 |

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_event_rule.cloudflare-update-schedule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.cloudflare-update-schedule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_cloudwatch_log_group.lambda-log-group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_iam_policy.policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_policy.s3_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role.iam_for_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.s3_bucket_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.update-ips](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.allow_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [archive_file.lambda_zip](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_ports"></a> [allowed\_ports](#input\_allowed\_ports) | A list of ports to allow ingress from cloudflare | `list(number)` | <pre>[<br>  80,<br>  443<br>]</pre> | no |
| <a name="input_environment"></a> [environment](#input\_environment) | The name of the environment | `string` | n/a | yes |
| <a name="input_s3_bucket_policy_targets"></a> [s3\_bucket\_policy\_targets](#input\_s3\_bucket\_policy\_targets) | S3 buckets whose bucket policy the updater lambda should keep current with Cloudflare's published IP ranges. Empty by default. See [S3 bucket policies](#s3-bucket-policies). | <pre>list(object({<br>  bucket          = string<br>  policy_template = string<br>}))</pre> | `[]` | no |
| <a name="input_schedule_expression"></a> [schedule\_expression](#input\_schedule\_expression) | The cloudwatch schedule expression used to run the updater lambda. | `string` | `"cron(0 20 * * ? *)"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to use on all resources | `map(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of an existing VPC where resources will be created | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | The SG ID where the cloudflare rules will be populated |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->