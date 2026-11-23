variable "subnet_config" {
  description = "subnets of the architecture"
  type = map(object({
    cidr = string
    az   = string
    type = string
  }))
}

variable "github_runner_token" {
  type = string
  sensitive = true
}

variable "github_actions_role_arn" {
  type = strin
  sensitive = true
}