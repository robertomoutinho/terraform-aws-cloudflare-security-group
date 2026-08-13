variable "vpc_id" {
  description = "ID of an existing VPC where resources will be created"
  type        = string
}

variable "environment" {
  type        = string
  description = "The name of the environment"
}

variable "tags" {
  description = "A map of tags to use on all resources"
  type        = map(string)
}

variable "schedule_expression" {
  description = "The cloudwatch schedule expression used to run the updater lambda."
  type        = string
  default     = "cron(0 20 * * ? *)"
}

variable "allowed_ports" {
  description = "A list of ports to allow ingress from cloudflare"
  type        = list(number)
  default     = [80, 443]
}

variable "s3_bucket_policy_targets" {
  description = "S3 buckets whose policy the updater lambda should keep current with Cloudflare's IP ranges. Each entry needs a `bucket` name and a `policy_template`: the complete bucket policy as JSON, with the sentinel string `__CLOUDFLARE_IP_RANGES__` where the CIDR list belongs. Empty by default. The lambda becomes the policy's sole writer, so do not also manage it in terraform. See the S3 bucket policies section of the README."
  type = list(object({
    bucket          = string
    policy_template = string
  }))
  default = []
}