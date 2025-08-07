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

Describe "Databricks Custom App Integration Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a custom app integration with redirect URLs" {
            $templateFile = "$PSScriptRoot/../modules/custom-app-integration.bicep"
            $parameters = @{
                IntegrationName = "test-app-integration-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                RedirectUrls = @(
                    "https://example.com/callback",
                    "https://app.example.com/auth/callback"
                )
                Confidential = $true
                TokenAccessPolicy = @{
                    access_token_ttl_in_minutes = 60
                    refresh_token_ttl_in_minutes = 10080
                }
                Scopes = @("all-apis")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.IntegrationId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.IntegrationName.Value | Should -Be $parameters.IntegrationName
            $deployment.Outputs.ClientId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.ClientSecret.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.RedirectUrls.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Confidential.Value | Should -Be $true
            $deployment.Outputs.TokenAccessPolicy.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Scopes.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatedBy.Value | Should -BeGreaterThan 0
            $deployment.Outputs.CreatedTime.Value | Should -BeGreaterThan 0
            
            $script:CreatedIntegrationId = $deployment.Outputs.IntegrationId.Value
        }
        
        It "Should create a public custom app integration" {
            $templateFile = "$PSScriptRoot/../modules/custom-app-integration.bicep"
            $parameters = @{
                IntegrationName = "test-public-app-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                RedirectUrls = @("https://public-app.example.com/callback")
                Confidential = $false
                Scopes = @("sql")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Confidential.Value | Should -Be $false
            
            $script:CreatedPublicIntegrationId = $deployment.Outputs.IntegrationId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty integration name" {
            $templateFile = "$PSScriptRoot/../modules/custom-app-integration.bicep"
            $parameters = @{
                IntegrationName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                RedirectUrls = @("https://example.com/callback")
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
        
        It "Should fail with empty redirect URLs" {
            $templateFile = "$PSScriptRoot/../modules/custom-app-integration.bicep"
            $parameters = @{
                IntegrationName = "test-app"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                RedirectUrls = @()
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
        # Cleanup custom app integrations
        if ($script:CreatedIntegrationId) {
            Write-Host "Cleaning up custom app integration: $($script:CreatedIntegrationId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/oauth2/custom-app-integrations/$($script:CreatedIntegrationId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup custom app integration $($script:CreatedIntegrationId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedPublicIntegrationId) {
            Write-Host "Cleaning up public custom app integration: $($script:CreatedPublicIntegrationId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/oauth2/custom-app-integrations/$($script:CreatedPublicIntegrationId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup public custom app integration $($script:CreatedPublicIntegrationId): $($_.Exception.Message)"
            }
        }
    }
}
