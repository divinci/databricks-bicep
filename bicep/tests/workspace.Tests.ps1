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
        It "Should configure workspace with basic settings" {
            $templateFile = "$PSScriptRoot/../modules/workspace.bicep"
            $parameters = @{
                WorkspaceName = "test-workspace-config-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                EnableAutomaticClusterTermination = $true
                MaxTokenLifetimeSeconds = 3600
                MaxClustersPerUser = 5
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.WorkspaceName.Value | Should -Be $parameters.WorkspaceName
            $deployment.Outputs.EnableAutomaticClusterTermination.Value | Should -Be "true"
        }
        
        It "Should configure workspace with custom settings" {
            $templateFile = "$PSScriptRoot/../modules/workspace.bicep"
            $parameters = @{
                WorkspaceName = "test-custom-workspace-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                WorkspaceConf = @{
                    "enableIpAccessLists" = "true"
                    "enableTokensConfig" = "true"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.WorkspaceName.Value | Should -Be $parameters.WorkspaceName
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty workspace name" {
            $templateFile = "$PSScriptRoot/../modules/workspace.bicep"
            $parameters = @{
                WorkspaceName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
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
