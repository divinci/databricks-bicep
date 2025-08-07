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

Describe "Databricks Budget Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic budget" {
            $templateFile = "$PSScriptRoot/../modules/budget.bicep"
            $parameters = @{
                BudgetName = "test-budget-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Filter = @{
                    workspace_id = @{
                        operator = "IN"
                        values = @("12345")
                    }
                }
                Period = @{
                    start_month = "2024-01"
                    period_type = "MONTH"
                }
                StartDate = "2024-01-01"
                TargetAmount = "1000.00"
                Alerts = @(
                    @{
                        email_notifications = @("admin@example.com")
                        min_percentage = 80
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.BudgetConfigurationId.Value | Should -Be $parameters.BudgetName
            $deployment.Outputs.BudgetName.Value | Should -Be $parameters.BudgetName
            $deployment.Outputs.StartDate.Value | Should -Be "2024-01-01"
            $deployment.Outputs.TargetAmount.Value | Should -Be "1000.00"
            $deployment.Outputs.Filter.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Period.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Alerts.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreationTime.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedBudgetId = $deployment.Outputs.BudgetConfigurationId.Value
        }
        
        It "Should create a budget with quarterly period" {
            $templateFile = "$PSScriptRoot/../modules/budget.bicep"
            $parameters = @{
                BudgetName = "test-quarterly-budget-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Filter = @{
                    tag = @{
                        key = "environment"
                        value = "production"
                    }
                }
                Period = @{
                    start_month = "2024-01"
                    period_type = "QUARTER"
                }
                StartDate = "2024-01-01"
                TargetAmount = "5000.00"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.TargetAmount.Value | Should -Be "5000.00"
            
            $script:CreatedQuarterlyBudgetId = $deployment.Outputs.BudgetConfigurationId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty budget name" {
            $templateFile = "$PSScriptRoot/../modules/budget.bicep"
            $parameters = @{
                BudgetName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Filter = @{}
                Period = @{}
                StartDate = "2024-01-01"
                TargetAmount = "1000.00"
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
        # Cleanup budgets
        if ($script:CreatedBudgetId) {
            Write-Host "Cleaning up budget: $($script:CreatedBudgetId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/budgets/$($script:CreatedBudgetId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup budget $($script:CreatedBudgetId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedQuarterlyBudgetId) {
            Write-Host "Cleaning up quarterly budget: $($script:CreatedQuarterlyBudgetId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/budgets/$($script:CreatedQuarterlyBudgetId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup quarterly budget $($script:CreatedQuarterlyBudgetId): $($_.Exception.Message)"
            }
        }
    }
}
