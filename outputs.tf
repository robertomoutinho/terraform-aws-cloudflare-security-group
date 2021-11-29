output "security_group_id" {
  description = "The SG ID where the cloudflare rules will be populated"
  value       = module.security-group.security_group_id
}

