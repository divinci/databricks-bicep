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

Describe "Databricks Workspace URL Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should parse workspace URL components correctly" {
            $templateFile = "$PSScriptRoot/../modules/workspace-url.bicep"
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
            $deployment.Outputs.WorkspaceId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Region.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Cloud.Value | Should -Match "^(aws|azure|gcp)$"
            $deployment.Outputs.Host.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Scheme.Value | Should -Be "https"
            $deployment.Outputs.Port.Value | Should -BeGreaterThan 0
            $deployment.Outputs.IsValid.Value | Should -Be $true
        }
        
        It "Should identify cloud provider correctly for Azure workspace" {
            # Skip if not Azure workspace
            if ($script:TestWorkspaceUrl -notmatch "azuredatabricks") {
                Set-ItResult -Skipped -Because "Test workspace is not Azure Databricks"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/workspace-url.bicep"
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
            $deployment.Outputs.Cloud.Value | Should -Be "azure"
        }
        
        It "Should handle different workspace URL formats" {
            $templateFile = "$PSScriptRoot/../modules/workspace-url.bicep"
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
            $deployment.Outputs.WorkspaceId.Value | Should -Match "^[a-zA-Z0-9\-]+$"
            $deployment.Outputs.Region.Value | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid workspace URL format" {
            $templateFile = "$PSScriptRoot/../modules/workspace-url.bicep"
            $parameters = @{
                DatabricksToken = $script:TestToken
                WorkspaceUrl = "invalid-url-format"
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
        
        It "Should fail with empty workspace URL" {
            $templateFile = "$PSScriptRoot/../modules/workspace-url.bicep"
            $parameters = @{
                DatabricksToken = $script:TestToken
                WorkspaceUrl = ""
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
