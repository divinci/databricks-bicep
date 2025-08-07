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

Describe "Databricks Enhanced Security Monitoring Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should enable enhanced security monitoring with basic configuration" {
            $templateFile = "$PSScriptRoot/../modules/enhanced-security-monitoring.bicep"
            $parameters = @{
                WorkspaceId = $script:TestWorkspaceId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $true
                MonitoringConfig = @{
                    alert_on_suspicious_activity = $true
                    log_retention_days = 90
                    notification_email = "security@example.com"
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
            $deployment.Outputs.MonitoringConfig.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.LastUpdated.Value | Should -BeGreaterThan 0
        }
        
        It "Should disable enhanced security monitoring" {
            $templateFile = "$PSScriptRoot/../modules/enhanced-security-monitoring.bicep"
            $parameters = @{
                WorkspaceId = $script:TestWorkspaceId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $false
                MonitoringConfig = @{}
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.IsEnabled.Value | Should -Be $false
        }
        
        It "Should enable enhanced security monitoring with advanced configuration" {
            $templateFile = "$PSScriptRoot/../modules/enhanced-security-monitoring.bicep"
            $parameters = @{
                WorkspaceId = $script:TestWorkspaceId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsEnabled = $true
                MonitoringConfig = @{
                    alert_on_suspicious_activity = $true
                    alert_on_data_exfiltration = $true
                    log_retention_days = 365
                    notification_email = "security@example.com"
                    slack_webhook_url = "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
                    enable_real_time_alerts = $true
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.MonitoringConfig.Value | Should -Match "alert_on_data_exfiltration"
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty workspace ID" {
            $templateFile = "$PSScriptRoot/../modules/enhanced-security-monitoring.bicep"
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
