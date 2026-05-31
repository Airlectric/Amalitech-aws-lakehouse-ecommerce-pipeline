output "state_machine_arn" {
  description = "ARN of the lakehouse pipeline state machine"
  value       = aws_sfn_state_machine.lakehouse_pipeline.arn
}

output "state_machine_name" {
  description = "Name of the lakehouse pipeline state machine"
  value       = aws_sfn_state_machine.lakehouse_pipeline.name
}
