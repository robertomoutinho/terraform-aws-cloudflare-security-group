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
  description = <<-EOT
    S3 buckets whose bucket policy the updater lambda should keep current with
    Cloudflare's published IP ranges. Empty by default, so this feature is
    strictly opt-in and upgrading to this module version changes nothing for
    existing consumers.

    Security groups hold many discrete rules the lambda can add and revoke
    individually, but an S3 bucket has exactly one policy document. There is no
    incremental API, so whoever writes it writes all of it. This input resolves
    that by splitting ownership: you own the document's shape, the lambda owns
    only the IP list inside it.

    Each entry needs:
      bucket          - the bucket name.
      policy_template - the complete bucket policy as a JSON string, with the
                        sentinel string "__CLOUDFLARE_IP_RANGES__" wherever the
                        list of CIDRs belongs. The lambda replaces that sentinel
                        with a JSON array of Cloudflare's current ranges (IPv4
                        and IPv6) and PUTs the result.

    Because the lambda is the sole writer, do NOT also manage the policy in
    terraform -- set `attach_policy = false` (or equivalent) on the bucket, or
    the two will overwrite each other on every apply and every lambda run.

    The template is delivered via a lambda environment variable, and AWS caps
    the combined size of all environment variables at 4 KB. One or two policies
    fit comfortably; a long list of buckets will not, and will surface as an
    InvalidParameterValueException at apply time.

    Note the cold start: between the bucket being created and the lambda's next
    scheduled run, the bucket has no policy at all. That fails closed (reads are
    denied, nothing is exposed), but it does mean broken images until the lambda
    runs. Invoke it once by hand after the first apply:

      aws lambda invoke --function-name <environment>-UpdateCloudflareIps /dev/null
  EOT

  type = list(object({
    bucket          = string
    policy_template = string
  }))
  default = []
}