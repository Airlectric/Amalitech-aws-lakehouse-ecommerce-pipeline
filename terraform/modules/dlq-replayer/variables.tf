variable "environment" {
  description = "Environment name (e.g. dev, staging, prod)"
  type        = string
}

variable "dlq_arn" {
  description = "ARN of the pipeline dead-letter queue to consume from"
  type        = string
}

variable "state_machine_arn" {
  description = "ARN of the Step Functions state machine to re-trigger"
  type        = string
}
