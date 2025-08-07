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
            $templateFile = "$PSScriptRoot/../modules/workspace-conf.bicep"
            $parameters = @{
                ConfigKey = "enableIpAccessLists"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConfigValue = "true"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ConfigKey.Value | Should -Be "enableIpAccessLists"
            $deployment.Outputs.ConfigValue.Value | Should -Be "true"
        }
        
        It "Should set workspace configuration for enableTokensConfig" {
            $templateFile = "$PSScriptRoot/../modules/workspace-conf.bicep"
            $parameters = @{
                ConfigKey = "enableTokensConfig"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConfigValue = "false"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ConfigKey.Value | Should -Be "enableTokensConfig"
            $deployment.Outputs.ConfigValue.Value | Should -Be "false"
        }
        
        It "Should set workspace configuration for maxTokenLifetimeDays" {
            $templateFile = "$PSScriptRoot/../modules/workspace-conf.bicep"
            $parameters = @{
                ConfigKey = "maxTokenLifetimeDays"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConfigValue = "90"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ConfigKey.Value | Should -Be "maxTokenLifetimeDays"
            $deployment.Outputs.ConfigValue.Value | Should -Be "90"
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty config key" {
            $templateFile = "$PSScriptRoot/../modules/workspace-conf.bicep"
            $parameters = @{
                ConfigKey = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConfigValue = "true"
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
        
        It "Should fail with empty config value" {
            $templateFile = "$PSScriptRoot/../modules/workspace-conf.bicep"
            $parameters = @{
                ConfigKey = "enableIpAccessLists"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConfigValue = ""
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
