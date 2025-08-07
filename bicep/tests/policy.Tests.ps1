BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
}

Describe "Databricks Policy Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic cluster policy" {
            $templateFile = "$PSScriptRoot/../modules/policy.bicep"
            $policyDefinition = @{
                "spark_version" = @{
                    "type" = "fixed"
                    "value" = "13.3.x-scala2.12"
                }
                "node_type_id" = @{
                    "type" = "allowlist"
                    "values" = @("Standard_DS3_v2", "Standard_DS4_v2")
                }
                "num_workers" = @{
                    "type" = "range"
                    "minValue" = 1
                    "maxValue" = 10
                }
            }
            
            $parameters = @{
                PolicyName = "test-basic-policy-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Definition = $policyDefinition
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.PolicyId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.PolicyName.Value | Should -Be $parameters.PolicyName
            
            $script:CreatedBasicPolicyId = $deployment.Outputs.PolicyId.Value
        }
        
        It "Should create a policy with user limits and libraries" {
            $templateFile = "$PSScriptRoot/../modules/policy.bicep"
            $policyDefinition = @{
                "spark_version" = @{
                    "type" = "fixed"
                    "value" = "13.3.x-scala2.12"
                }
                "auto_termination_minutes" = @{
                    "type" = "fixed"
                    "value" = 60
                }
            }
            
            $parameters = @{
                PolicyName = "test-restricted-policy-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Definition = $policyDefinition
                MaxClustersPerUser = 3
                Libraries = @(
                    @{
                        pypi = @{
                            package = "pandas"
                        }
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.PolicyName.Value | Should -Be $parameters.PolicyName
            
            $script:CreatedRestrictedPolicyId = $deployment.Outputs.PolicyId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty policy name" {
            $templateFile = "$PSScriptRoot/../modules/policy.bicep"
            $parameters = @{
                PolicyName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Definition = @{
                    "spark_version" = @{
                        "type" = "fixed"
                        "value" = "13.3.x-scala2.12"
                    }
                }
            }
            
            { 
                New-AzResourceGroupDeployment `
                    -ResourceGroupName $script:TestResourceGroup `
                    -TemplateFile $templateFile `
                    -TemplateParameterObject $parameters `
                    -Mode Incremental `
                    -ErrorAction Stop
            } | Should -Throw
        }
    }
}

AfterAll {
    if ($script:CreatedBasicPolicyId) {
        Write-Host "Cleaning up basic policy: $($script:CreatedBasicPolicyId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/policies/clusters/delete" `
                -Body "{`"policy_id`": `"$($script:CreatedBasicPolicyId)`"}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup basic policy $($script:CreatedBasicPolicyId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedRestrictedPolicyId) {
        Write-Host "Cleaning up restricted policy: $($script:CreatedRestrictedPolicyId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/policies/clusters/delete" `
                -Body "{`"policy_id`": `"$($script:CreatedRestrictedPolicyId)`"}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup restricted policy $($script:CreatedRestrictedPolicyId): $($_.Exception.Message)"
        }
    }
}
