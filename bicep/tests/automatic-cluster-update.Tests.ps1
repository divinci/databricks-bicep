BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Extract workspace ID from URL
    $script:TestWorkspaceId = "123456789012345"  # Use a test workspace ID
}

Describe "Databricks Automatic Cluster Update Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should enable automatic cluster update with weekly schedule" {
            $templateFile = "$PSScriptRoot/../modules/automatic-cluster-update.bicep"
            $parameters = @{
                WorkspaceId = $script:TestWorkspaceId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $true
                UpdateSchedule = @{
                    frequency = "WEEKLY"
                    day_of_week = "SUNDAY"
                    hour = 2
                    minute = 0
                }
                MaintenanceWindow = @{
                    start_hour = 1
                    end_hour = 5
                    timezone = "UTC"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.WorkspaceId.Value | Should -Be $script:TestWorkspaceId
            $deployment.Outputs.IsEnabled.Value | Should -Be $true
            $deployment.Outputs.UpdateSchedule.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.MaintenanceWindow.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.LastUpdated.Value | Should -BeGreaterThan 0
        }
        
        It "Should enable automatic cluster update with monthly schedule" {
            $templateFile = "$PSScriptRoot/../modules/automatic-cluster-update.bicep"
            $parameters = @{
                WorkspaceId = $script:TestWorkspaceId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $true
                UpdateSchedule = @{
                    frequency = "MONTHLY"
                    day_of_month = 1
                    hour = 3
                    minute = 30
                }
                MaintenanceWindow = @{
                    start_hour = 2
                    end_hour = 6
                    timezone = "America/New_York"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.UpdateSchedule.Value | Should -Match "MONTHLY"
            $deployment.Outputs.MaintenanceWindow.Value | Should -Match "America/New_York"
        }
        
        It "Should disable automatic cluster update" {
            $templateFile = "$PSScriptRoot/../modules/automatic-cluster-update.bicep"
            $parameters = @{
                WorkspaceId = $script:TestWorkspaceId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $false
                UpdateSchedule = @{}
                MaintenanceWindow = @{}
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.IsEnabled.Value | Should -Be $false
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty workspace ID" {
            $templateFile = "$PSScriptRoot/../modules/automatic-cluster-update.bicep"
            $parameters = @{
                WorkspaceId = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $true
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
