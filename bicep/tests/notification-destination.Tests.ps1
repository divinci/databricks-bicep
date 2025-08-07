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

Describe "Databricks Notification Destination Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create an email notification destination" {
            $templateFile = "$PSScriptRoot/../modules/notification-destination.bicep"
            $parameters = @{
                DestinationName = "test-email-destination-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                DestinationType = "email"
                Config = @{
                    addresses = @("admin@example.com", "alerts@example.com")
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.DestinationId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.DisplayName.Value | Should -Be $parameters.DestinationName
            $deployment.Outputs.DestinationType.Value | Should -Be "email"
            $deployment.Outputs.Config.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatedBy.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatedAt.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedEmailDestinationId = $deployment.Outputs.DestinationId.Value
        }
        
        It "Should create a Slack notification destination" {
            $templateFile = "$PSScriptRoot/../modules/notification-destination.bicep"
            $parameters = @{
                DestinationName = "test-slack-destination-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                DestinationType = "slack"
                Config = @{
                    url = "https://hooks.slack.com/services/T00000000/B00000000/XXXXXXXXXXXXXXXXXXXXXXXX"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.DestinationType.Value | Should -Be "slack"
            
            $script:CreatedSlackDestinationId = $deployment.Outputs.DestinationId.Value
        }
        
        It "Should create a webhook notification destination" {
            $templateFile = "$PSScriptRoot/../modules/notification-destination.bicep"
            $parameters = @{
                DestinationName = "test-webhook-destination-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                DestinationType = "webhook"
                Config = @{
                    url = "https://example.com/webhook"
                    authorization_header = "Bearer token123"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.DestinationType.Value | Should -Be "webhook"
            
            $script:CreatedWebhookDestinationId = $deployment.Outputs.DestinationId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty destination name" {
            $templateFile = "$PSScriptRoot/../modules/notification-destination.bicep"
            $parameters = @{
                DestinationName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                DestinationType = "email"
                Config = @{
                    addresses = @("test@example.com")
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
        
        It "Should fail with invalid destination type" {
            $templateFile = "$PSScriptRoot/../modules/notification-destination.bicep"
            $parameters = @{
                DestinationName = "test-destination"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                DestinationType = "invalid"
                Config = @{}
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
        # Cleanup notification destinations
        if ($script:CreatedEmailDestinationId) {
            Write-Host "Cleaning up email notification destination: $($script:CreatedEmailDestinationId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/sql/config/notification-destinations/$($script:CreatedEmailDestinationId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup email notification destination $($script:CreatedEmailDestinationId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedSlackDestinationId) {
            Write-Host "Cleaning up Slack notification destination: $($script:CreatedSlackDestinationId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/sql/config/notification-destinations/$($script:CreatedSlackDestinationId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup Slack notification destination $($script:CreatedSlackDestinationId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedWebhookDestinationId) {
            Write-Host "Cleaning up webhook notification destination: $($script:CreatedWebhookDestinationId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/sql/config/notification-destinations/$($script:CreatedWebhookDestinationId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup webhook notification destination $($script:CreatedWebhookDestinationId): $($_.Exception.Message)"
            }
        }
    }
}
