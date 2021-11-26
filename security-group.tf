module "security-group" {

  source  = "terraform-aws-modules/security-group/aws"
  version = "4.7.0"

  name        = "${var.environment}-cloudflare-allow-web-access"
  description = "Security group to allow all traffic from cloudflare to ${var.environment}"
  vpc_id      = var.vpc_id

  egress_cidr_blocks = ["0.0.0.0/0"]
  egress_rules       = ["all-all"]

}