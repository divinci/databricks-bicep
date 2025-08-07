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

Describe "Databricks MWS Private Access Settings Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create MWS private access settings with public access disabled" {
            $templateFile = "$PSScriptRoot/../modules/mws-private-access-settings.bicep"
            $parameters = @{
                PrivateAccessSettingsName = "test-private-access-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                Region = "us-east-1"
                PublicAccessEnabled = $false
                PrivateAccessLevel = "ACCOUNT"
                AllowedVpcEndpointIds = @()
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.PrivateAccessSettingsName.Value | Should -Be $parameters.PrivateAccessSettingsName
            $deployment.Outputs.PrivateAccessSettingsId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Region.Value | Should -Be "us-east-1"
            $deployment.Outputs.PublicAccessEnabled.Value | Should -Be $false
            $deployment.Outputs.PrivateAccessLevel.Value | Should -Be "ACCOUNT"
            $deployment.Outputs.AllowedVpcEndpointIds.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AccountId.Value | Should -Be $script:TestAccountId
            
            $script:CreatedPrivateAccessSettingsId = $deployment.Outputs.PrivateAccessSettingsId.Value
        }
        
        It "Should create MWS private access settings with endpoint level access" {
            $templateFile = "$PSScriptRoot/../modules/mws-private-access-settings.bicep"
            $parameters = @{
                PrivateAccessSettingsName = "test-endpoint-private-access-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                Region = "us-west-2"
                PublicAccessEnabled = $true
                PrivateAccessLevel = "ENDPOINT"
                AllowedVpcEndpointIds = @("vpce-12345678901234567", "vpce-98765432109876543")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.PublicAccessEnabled.Value | Should -Be $true
            $deployment.Outputs.PrivateAccessLevel.Value | Should -Be "ENDPOINT"
            $deployment.Outputs.AllowedVpcEndpointIds.Value | Should -Match "vpce-12345678901234567"
            
            $script:CreatedEndpointPrivateAccessSettingsId = $deployment.Outputs.PrivateAccessSettingsId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty private access settings name" {
            $templateFile = "$PSScriptRoot/../modules/mws-private-access-settings.bicep"
            $parameters = @{
                PrivateAccessSettingsName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                Region = "us-east-1"
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
        
        It "Should fail with empty region" {
            $templateFile = "$PSScriptRoot/../modules/mws-private-access-settings.bicep"
            $parameters = @{
                PrivateAccessSettingsName = "test-private-access"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                Region = ""
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
        
        It "Should fail with invalid private access level" {
            $templateFile = "$PSScriptRoot/../modules/mws-private-access-settings.bicep"
            $parameters = @{
                PrivateAccessSettingsName = "test-private-access"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                Region = "us-east-1"
                PrivateAccessLevel = "INVALID"
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
        # Cleanup MWS private access settings
        if ($script:CreatedPrivateAccessSettingsId) {
            Write-Host "Cleaning up MWS private access settings: $($script:CreatedPrivateAccessSettingsId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/private-access-settings/$($script:CreatedPrivateAccessSettingsId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup MWS private access settings $($script:CreatedPrivateAccessSettingsId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedEndpointPrivateAccessSettingsId) {
            Write-Host "Cleaning up endpoint MWS private access settings: $($script:CreatedEndpointPrivateAccessSettingsId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/private-access-settings/$($script:CreatedEndpointPrivateAccessSettingsId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup endpoint MWS private access settings $($script:CreatedEndpointPrivateAccessSettingsId): $($_.Exception.Message)"
            }
        }
    }
}
