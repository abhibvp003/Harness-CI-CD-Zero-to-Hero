# ═══════════════════════════════════════════════════════════════════
# OPA Policy: Production Governance (Episode 8 pattern)
# Evaluated: On Run (blocks pipeline execution if rules violated)
# ═══════════════════════════════════════════════════════════════════

package pipeline

# Rule 1: No deployments on Friday after 5 PM or weekends
#deny[msg] {
#    input.pipeline.stages[_].stage.type == "Deployment"
#    time.now_ns() / 1000000000 > 0
#    day := time.weekday(time.now_ns())
#    day == "Friday"
#    msg := "Deployments to production are not allowed on Friday. Deploy on Monday-Thursday."
#}

#deny[msg] {
#    input.pipeline.stages[_].stage.type == "Deployment"
#    time.now_ns() / 1000000000 > 0
#    day := time.weekday(time.now_ns())
#    day == "Saturday"
#    msg := "Deployments are not allowed on weekends."
#}

#deny[msg] {
#    input.pipeline.stages[_].stage.type == "Deployment"
#    time.now_ns() / 1000000000 > 0
#    day := time.weekday(time.now_ns())
#    day == "Sunday"
#    msg := "Deployments are not allowed on weekends."
#}

# Rule 2: Production deployments MUST have an approval step
deny[msg] {
    stage := input.pipeline.stages[_].stage
    stage.type == "Deployment"
    not has_approval_step(stage)
    msg := "Production deployments must include a HarnessApproval step."
}

has_approval_step(stage) {
    stage.spec.execution.steps[_].step.type == "HarnessApproval"
}

# Rule 3: Pipeline must have rollback steps defined
deny[msg] {
    stage := input.pipeline.stages[_].stage
    stage.type == "Deployment"
    not stage.spec.execution.rollbackSteps
    msg := "Deployment stages must have rollback steps defined."
}

# Rule 4: No hardcoded AWS account IDs
deny[msg] {
    stage := input.pipeline.stages[_].stage
    contains(sprintf("%v", [stage]), "713939171080")
    msg := "Hardcoded AWS account ID found. Use <+variable.aws_account_id> instead."
}

# Rule 5: CI stages must use KubernetesDirect (not Harness Cloud) for Episode 10
deny[msg] {
    stage := input.pipeline.stages[_].stage
    stage.type == "CI"
    stage.spec.platform
    msg := "Episode 10 CI stages must use KubernetesDirect infrastructure, not Harness Cloud (platform)."
}
