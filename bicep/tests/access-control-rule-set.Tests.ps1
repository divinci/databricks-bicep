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

Describe "Databricks Access Control Rule Set Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create an access control rule set with grant rules" {
            $templateFile = "$PSScriptRoot/../modules/access-control-rule-set.bicep"
            $parameters = @{
                RuleSetName = "test-rule-set-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                GrantRules = @(
                    @{
                        principals = @("user@example.com")
                        role = "CAN_MANAGE"
                    },
                    @{
                        principals = @("group-name")
                        role = "CAN_VIEW"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.RuleSetName.Value | Should -Be $parameters.RuleSetName
            $deployment.Outputs.GrantRules.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Etag.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedRuleSetName = $deployment.Outputs.RuleSetName.Value
        }
        
        It "Should create an access control rule set with minimal configuration" {
            $templateFile = "$PSScriptRoot/../modules/access-control-rule-set.bicep"
            $parameters = @{
                RuleSetName = "test-minimal-rule-set-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                GrantRules = @()
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.RuleSetName.Value | Should -Be $parameters.RuleSetName
            
            $script:CreatedMinimalRuleSetName = $deployment.Outputs.RuleSetName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty rule set name" {
            $templateFile = "$PSScriptRoot/../modules/access-control-rule-set.bicep"
            $parameters = @{
                RuleSetName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                GrantRules = @()
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
    
    AfterAll {
        # Cleanup rule sets
        if ($script:CreatedRuleSetName) {
            Write-Host "Cleaning up rule set: $($script:CreatedRuleSetName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/permissions/rule-sets/$($script:CreatedRuleSetName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup rule set $($script:CreatedRuleSetName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedMinimalRuleSetName) {
            Write-Host "Cleaning up minimal rule set: $($script:CreatedMinimalRuleSetName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/permissions/rule-sets/$($script:CreatedMinimalRuleSetName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup minimal rule set $($script:CreatedMinimalRuleSetName): $($_.Exception.Message)"
            }
        }
    }
}
