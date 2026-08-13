resource "aws_cloudwatch_log_group" "lambda-log-group" {
  name = "${var.environment}-UpdateCloudflareIps"
}

resource "aws_iam_role" "iam_for_lambda" {
  name               = "${var.environment}-lambda-cloudflare-sg-role"
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_policy" "policy" {
  name        = "${var.environment}-lambda-cloudflare-sg-policy"
  description = "Allows cloudflare ip updating lambda to change security groups"
  policy      = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
      ],
      "Resource": [
          "arn:aws:logs:*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
          "iam:GetRolePolicy",
          "iam:ListGroupPolicies",
          "ec2:DescribeSecurityGroups",
          "ec2:AuthorizeSecurityGroupIngress",
          "ec2:RevokeSecurityGroupIngress"
      ],
      "Resource": [
          "*"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "policy" {
  role       = aws_iam_role.iam_for_lambda.id
  policy_arn = aws_iam_policy.policy.arn
}

data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/cloudflare-security-group.py"
  output_path = "${path.module}/lambda.zip"
}

resource "aws_lambda_function" "update-ips" {
  function_name    = "${var.environment}-UpdateCloudflareIps"
  filename         = "${path.module}/lambda.zip"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  handler          = "cloudflare-security-group.lambda_handler"
  role             = aws_iam_role.iam_for_lambda.arn
  runtime          = "python3.9"
  timeout          = 60
  environment {
    # The S3 key is omitted entirely rather than set to an empty string when the
    # feature is unused, so a consumer that does not opt in ends up with exactly
    # the variable map it had before this feature existed. The handler reads it
    # with a default, so absent and empty behave identically.
    #
    # Upgrading still redeploys the function regardless, because source_code_hash
    # tracks the handler file and that changed. That is unavoidable and matches
    # what any previous version bump did.
    variables = merge(
      {
        SECURITY_GROUP_ID = module.security-group.security_group_id
        ALLOWED_PORTS     = "[${join(",", var.allowed_ports)}]"
      },
      length(var.s3_bucket_policy_targets) > 0 ? {
        S3_BUCKET_POLICY_TARGETS = jsonencode(var.s3_bucket_policy_targets)
      } : {}
    )
  }
}

##########################################################
## Optional: bucket policy management
##########################################################
# A separate policy rather than extra statements in aws_iam_policy.policy above,
# deliberately: that policy is attached in every existing consumer, and leaving
# it byte-for-byte untouched means upgrading to this version produces no diff on
# the resource that governs their security groups.
#
# Scoped to the named buckets. The EC2 statements above use Resource "*", which
# is not a precedent worth extending to bucket policy writes -- a wildcard here
# would let this lambda rewrite the access policy of every bucket in the account.

resource "aws_iam_policy" "s3_bucket_policy" {
  count = length(var.s3_bucket_policy_targets) > 0 ? 1 : 0

  name        = "${var.environment}-lambda-cloudflare-s3-policy"
  description = "Allows the cloudflare ip updating lambda to manage bucket policies for specific buckets"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetBucketPolicy",
        "s3:PutBucketPolicy",
      ]
      Resource = [
        for target in var.s3_bucket_policy_targets : "arn:aws:s3:::${target.bucket}"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_bucket_policy" {
  count = length(var.s3_bucket_policy_targets) > 0 ? 1 : 0

  role       = aws_iam_role.iam_for_lambda.id
  policy_arn = aws_iam_policy.s3_bucket_policy[0].arn
}

