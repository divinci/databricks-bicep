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

Describe "Databricks MWS Customer Managed Keys Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create an MWS customer managed key for storage encryption" {
            $templateFile = "$PSScriptRoot/../modules/mws-customer-managed-keys.bicep"
            $parameters = @{
                CustomerManagedKeyName = "test-cmk-storage-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                AwsKeyInfo = @{
                    key_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
                    key_alias = "alias/databricks-storage-key"
                }
                UseCases = @("STORAGE")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.CustomerManagedKeyName.Value | Should -Be $parameters.CustomerManagedKeyName
            $deployment.Outputs.CustomerManagedKeyId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AwsKeyInfo.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.UseCases.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AccountId.Value | Should -Be $script:TestAccountId
            $deployment.Outputs.CreationTime.Value | Should -BeGreaterThan 0
            
            $script:CreatedStorageCmkId = $deployment.Outputs.CustomerManagedKeyId.Value
        }
        
        It "Should create an MWS customer managed key for managed services encryption" {
            $templateFile = "$PSScriptRoot/../modules/mws-customer-managed-keys.bicep"
            $parameters = @{
                CustomerManagedKeyName = "test-cmk-managed-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                AwsKeyInfo = @{
                    key_arn = "arn:aws:kms:us-west-2:123456789012:key/87654321-4321-4321-4321-210987654321"
                    key_alias = "alias/databricks-managed-key"
                }
                UseCases = @("MANAGED_SERVICES")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.UseCases.Value | Should -Match "MANAGED_SERVICES"
            
            $script:CreatedManagedCmkId = $deployment.Outputs.CustomerManagedKeyId.Value
        }
        
        It "Should create an MWS customer managed key for both storage and managed services" {
            $templateFile = "$PSScriptRoot/../modules/mws-customer-managed-keys.bicep"
            $parameters = @{
                CustomerManagedKeyName = "test-cmk-both-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                AwsKeyInfo = @{
                    key_arn = "arn:aws:kms:eu-west-1:123456789012:key/11111111-2222-3333-4444-555555555555"
                    key_alias = "alias/databricks-both-key"
                }
                UseCases = @("STORAGE", "MANAGED_SERVICES")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.UseCases.Value | Should -Match "STORAGE"
            $deployment.Outputs.UseCases.Value | Should -Match "MANAGED_SERVICES"
            
            $script:CreatedBothCmkId = $deployment.Outputs.CustomerManagedKeyId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty customer managed key name" {
            $templateFile = "$PSScriptRoot/../modules/mws-customer-managed-keys.bicep"
            $parameters = @{
                CustomerManagedKeyName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                AwsKeyInfo = @{
                    key_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
                }
                UseCases = @("STORAGE")
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
        
        It "Should fail with empty use cases" {
            $templateFile = "$PSScriptRoot/../modules/mws-customer-managed-keys.bicep"
            $parameters = @{
                CustomerManagedKeyName = "test-cmk"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                AwsKeyInfo = @{
                    key_arn = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"
                }
                UseCases = @()
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
        # Cleanup MWS customer managed keys
        if ($script:CreatedStorageCmkId) {
            Write-Host "Cleaning up storage MWS customer managed key: $($script:CreatedStorageCmkId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/customer-managed-keys/$($script:CreatedStorageCmkId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup storage MWS customer managed key $($script:CreatedStorageCmkId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedManagedCmkId) {
            Write-Host "Cleaning up managed MWS customer managed key: $($script:CreatedManagedCmkId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/customer-managed-keys/$($script:CreatedManagedCmkId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup managed MWS customer managed key $($script:CreatedManagedCmkId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedBothCmkId) {
            Write-Host "Cleaning up both MWS customer managed key: $($script:CreatedBothCmkId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/customer-managed-keys/$($script:CreatedBothCmkId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup both MWS customer managed key $($script:CreatedBothCmkId): $($_.Exception.Message)"
            }
        }
    }
}
