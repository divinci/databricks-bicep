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

Describe "Databricks Workspace Info Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should get comprehensive workspace information" {
            $templateFile = "$PSScriptRoot/../modules/workspace-info.bicep"
            $parameters = @{
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.WorkspaceUrl.Value | Should -Be $script:TestWorkspaceUrl
            $deployment.Outputs.CurrentUserId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CurrentUserName.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.WorkspaceConfiguration.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.RootObjectId.Value | Should -BeGreaterThan 0
            $deployment.Outputs.RootObjectType.Value | Should -Be "DIRECTORY"
            $deployment.Outputs.IsAccessible.Value | Should -Be $true
            
            # Validate workspace configuration is valid JSON
            $config = $deployment.Outputs.WorkspaceConfiguration.Value | ConvertFrom-Json
            $config | Should -Not -BeNullOrEmpty
        }
        
        It "Should get consistent workspace information on multiple calls" {
            $templateFile = "$PSScriptRoot/../modules/workspace-info.bicep"
            $parameters = @{
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            # First call
            $deployment1 = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            # Second call
            $deployment2 = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            # Both should succeed
            $deployment1.ProvisioningState | Should -Be "Succeeded"
            $deployment2.ProvisioningState | Should -Be "Succeeded"
            
            # Workspace info should be consistent
            $deployment1.Outputs.WorkspaceUrl.Value | Should -Be $deployment2.Outputs.WorkspaceUrl.Value
            $deployment1.Outputs.CurrentUserId.Value | Should -Be $deployment2.Outputs.CurrentUserId.Value
            $deployment1.Outputs.RootObjectId.Value | Should -Be $deployment2.Outputs.RootObjectId.Value
        }
        
        It "Should validate workspace accessibility" {
            $templateFile = "$PSScriptRoot/../modules/workspace-info.bicep"
            $parameters = @{
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.IsAccessible.Value | Should -Be $true
            $deployment.Outputs.CurrentUserId.Value | Should -Match "^[0-9]+$"
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid workspace URL" {
            $templateFile = "$PSScriptRoot/../modules/workspace-info.bicep"
            $parameters = @{
                DatabricksToken = $script:TestToken
                WorkspaceUrl = "https://invalid-workspace.cloud.databricks.com"
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
        
        It "Should fail with invalid token" {
            $templateFile = "$PSScriptRoot/../modules/workspace-info.bicep"
            $parameters = @{
                DatabricksToken = "invalid-token-12345"
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
