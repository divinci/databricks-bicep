BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    $script:TestAccountId = $env:DATABRICKS_ACCOUNT_ID
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken -or -not $script:TestAccountId) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL, DATABRICKS_TOKEN, and DATABRICKS_ACCOUNT_ID must be set"
    }
}

Describe "Databricks MWS Log Delivery Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create an MWS log delivery for audit logs" {
            $templateFile = "$PSScriptRoot/../modules/mws-log-delivery.bicep"
            $parameters = @{
                ConfigName = "test-audit-log-delivery-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                CredentialsId = "12345678-1234-1234-1234-123456789012"
                StorageConfigurationId = "87654321-4321-4321-4321-210987654321"
                WorkspaceIdsFilter = @()
                LogType = "AUDIT_LOGS"
                OutputFormat = "JSON"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ConfigName.Value | Should -Be $parameters.ConfigName
            $deployment.Outputs.ConfigId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CredentialsId.Value | Should -Be $parameters.CredentialsId
            $deployment.Outputs.StorageConfigurationId.Value | Should -Be $parameters.StorageConfigurationId
            $deployment.Outputs.LogType.Value | Should -Be "AUDIT_LOGS"
            $deployment.Outputs.OutputFormat.Value | Should -Be "JSON"
            $deployment.Outputs.Status.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AccountId.Value | Should -Be $script:TestAccountId
            $deployment.Outputs.CreationTime.Value | Should -BeGreaterThan 0
            
            $script:CreatedAuditLogDeliveryId = $deployment.Outputs.ConfigId.Value
        }
        
        It "Should create an MWS log delivery for billable usage" {
            $templateFile = "$PSScriptRoot/../modules/mws-log-delivery.bicep"
            $parameters = @{
                ConfigName = "test-billing-log-delivery-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                CredentialsId = "11111111-2222-3333-4444-555555555555"
                StorageConfigurationId = "66666666-7777-8888-9999-000000000000"
                WorkspaceIdsFilter = @("123456789012345", "543210987654321")
                LogType = "BILLABLE_USAGE"
                OutputFormat = "CSV"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.LogType.Value | Should -Be "BILLABLE_USAGE"
            $deployment.Outputs.OutputFormat.Value | Should -Be "CSV"
            $deployment.Outputs.WorkspaceIdsFilter.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedBillingLogDeliveryId = $deployment.Outputs.ConfigId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty config name" {
            $templateFile = "$PSScriptRoot/../modules/mws-log-delivery.bicep"
            $parameters = @{
                ConfigName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                CredentialsId = "12345678-1234-1234-1234-123456789012"
                StorageConfigurationId = "87654321-4321-4321-4321-210987654321"
                LogType = "AUDIT_LOGS"
                OutputFormat = "JSON"
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
        
        It "Should fail with invalid log type" {
            $templateFile = "$PSScriptRoot/../modules/mws-log-delivery.bicep"
            $parameters = @{
                ConfigName = "test-log-delivery"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                CredentialsId = "12345678-1234-1234-1234-123456789012"
                StorageConfigurationId = "87654321-4321-4321-4321-210987654321"
                LogType = "INVALID"
                OutputFormat = "JSON"
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
        # Cleanup MWS log delivery configurations
        if ($script:CreatedAuditLogDeliveryId) {
            Write-Host "Cleaning up audit MWS log delivery: $($script:CreatedAuditLogDeliveryId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/log-delivery/$($script:CreatedAuditLogDeliveryId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup audit MWS log delivery $($script:CreatedAuditLogDeliveryId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedBillingLogDeliveryId) {
            Write-Host "Cleaning up billing MWS log delivery: $($script:CreatedBillingLogDeliveryId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/log-delivery/$($script:CreatedBillingLogDeliveryId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup billing MWS log delivery $($script:CreatedBillingLogDeliveryId): $($_.Exception.Message)"
            }
        }
    }
}
