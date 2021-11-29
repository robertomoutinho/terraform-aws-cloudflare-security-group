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