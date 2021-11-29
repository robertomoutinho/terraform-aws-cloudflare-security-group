AWS CloudFlare security group Terraform module
==============================================

Terraform module that populates a security group with cloudflare ip ranges and keeps it updated daily.

The following resources are created:

* A lambda function that keeps your security group's ingress rules updated with published cloudflare ip ranges.
* A cloudwatch event rule with a schedule to trigger the lambda daily

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
| [aws_iam_role.iam_for_lambda](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_lambda_function.update-ips](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_function) | resource |
| [aws_lambda_permission.allow_cloudwatch](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lambda_permission) | resource |
| [archive_file.lambda_zip](https://registry.terraform.io/providers/hashicorp/archive/latest/docs/data-sources/file) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_allowed_ports"></a> [allowed\_ports](#input\_allowed\_ports) | A list of ports to allow ingress from cloudflare | `list(number)` | <pre>[<br>  80,<br>  443<br>]</pre> | no |
| <a name="input_environment"></a> [environment](#input\_environment) | The name of the environment | `string` | n/a | yes |
| <a name="input_schedule_expression"></a> [schedule\_expression](#input\_schedule\_expression) | The cloudwatch schedule expression used to run the updater lambda. | `string` | `"cron(0 20 * * ? *)"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to use on all resources | `map(string)` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | ID of an existing VPC where resources will be created | `string` | n/a | yes |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | The SG ID where the cloudflare rules will be populated |
<!-- END OF PRE-COMMIT-TERRAFORM DOCS HOOK -->