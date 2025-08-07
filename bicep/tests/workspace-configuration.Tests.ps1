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

Describe "Databricks Workspace Configuration Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should set workspace configuration for enableIpAccessLists" {
            $templateFile = "$PSScriptRoot/../modules/workspace-configuration.bicep"
            $parameters = @{
                ConfigurationKey = "enableIpAccessLists"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConfigurationValue = "true"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ConfigurationKey.Value | Should -Be "enableIpAccessLists"
            $deployment.Outputs.ConfigurationValue.Value | Should -Be "true"
            
            $script:ConfiguredIpAccessLists = $true
        }
        
        It "Should set workspace configuration for enableTokensConfig" {
            $templateFile = "$PSScriptRoot/../modules/workspace-configuration.bicep"
            $parameters = @{
                ConfigurationKey = "enableTokensConfig"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConfigurationValue = "false"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ConfigurationKey.Value | Should -Be "enableTokensConfig"
            $deployment.Outputs.ConfigurationValue.Value | Should -Be "false"
            
            $script:ConfiguredTokensConfig = $true
        }
        
        It "Should set workspace configuration for maxTokenLifetimeDays" {
            $templateFile = "$PSScriptRoot/../modules/workspace-configuration.bicep"
            $parameters = @{
                ConfigurationKey = "maxTokenLifetimeDays"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConfigurationValue = "90"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ConfigurationKey.Value | Should -Be "maxTokenLifetimeDays"
            $deployment.Outputs.ConfigurationValue.Value | Should -Be "90"
            
            $script:ConfiguredMaxTokenLifetime = $true
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty configuration key" {
            $templateFile = "$PSScriptRoot/../modules/workspace-configuration.bicep"
            $parameters = @{
                ConfigurationKey = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConfigurationValue = "true"
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
        
        It "Should fail with empty configuration value" {
            $templateFile = "$PSScriptRoot/../modules/workspace-configuration.bicep"
            $parameters = @{
                ConfigurationKey = "enableIpAccessLists"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConfigurationValue = ""
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
        # Reset workspace configurations to default values
        if ($script:ConfiguredIpAccessLists) {
            Write-Host "Resetting enableIpAccessLists configuration"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "PATCH" `
                    -UrlPath "/api/2.0/workspace-conf" `
                    -Body (@{ enableIpAccessLists = "false" } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to reset enableIpAccessLists configuration: $($_.Exception.Message)"
            }
        }
        
        if ($script:ConfiguredTokensConfig) {
            Write-Host "Resetting enableTokensConfig configuration"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "PATCH" `
                    -UrlPath "/api/2.0/workspace-conf" `
                    -Body (@{ enableTokensConfig = "true" } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to reset enableTokensConfig configuration: $($_.Exception.Message)"
            }
        }
        
        if ($script:ConfiguredMaxTokenLifetime) {
            Write-Host "Resetting maxTokenLifetimeDays configuration"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "PATCH" `
                    -UrlPath "/api/2.0/workspace-conf" `
                    -Body (@{ maxTokenLifetimeDays = "0" } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to reset maxTokenLifetimeDays configuration: $($_.Exception.Message)"
            }
        }
    }
}
