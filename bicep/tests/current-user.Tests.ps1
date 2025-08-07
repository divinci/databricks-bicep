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

Describe "Databricks Current User Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should get current user information" {
            $templateFile = "$PSScriptRoot/../modules/current-user.bicep"
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
            $deployment.Outputs.UserId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.UserName.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.DisplayName.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Active.Value | Should -BeOfType [bool]
            $deployment.Outputs.Active.Value | Should -Be $true
            $deployment.Outputs.Emails.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Groups.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Roles.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Entitlements.Value | Should -Not -BeNullOrEmpty
            
            # Validate that emails contains at least one email
            $emails = $deployment.Outputs.Emails.Value | ConvertFrom-Json
            $emails | Should -Not -BeNullOrEmpty
            $emails.Count | Should -BeGreaterThan 0
            
            # Validate that the user has some entitlements
            $entitlements = $deployment.Outputs.Entitlements.Value | ConvertFrom-Json
            $entitlements | Should -Not -BeNullOrEmpty
        }
        
        It "Should get consistent user information on multiple calls" {
            $templateFile = "$PSScriptRoot/../modules/current-user.bicep"
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
            
            # User ID should be consistent
            $deployment1.Outputs.UserId.Value | Should -Be $deployment2.Outputs.UserId.Value
            $deployment1.Outputs.UserName.Value | Should -Be $deployment2.Outputs.UserName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid workspace URL" {
            $templateFile = "$PSScriptRoot/../modules/current-user.bicep"
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
            $templateFile = "$PSScriptRoot/../modules/current-user.bicep"
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
