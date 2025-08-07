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

Describe "Databricks Provider Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic Delta Sharing provider" {
            $templateFile = "$PSScriptRoot/../modules/provider.bicep"
            $parameters = @{
                ProviderName = "test_provider_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Test Delta Sharing provider created by Bicep module"
                AuthenticationType = "TOKEN"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ProviderName.Value | Should -Be $parameters.ProviderName
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.AuthenticationType.Value | Should -Be "TOKEN"
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.UpdatedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedProviderName = $deployment.Outputs.ProviderName.Value
        }
        
        It "Should create a provider with recipient profile" {
            $templateFile = "$PSScriptRoot/../modules/provider.bicep"
            $parameters = @{
                ProviderName = "test_profile_provider_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Provider with recipient profile"
                AuthenticationType = "DATABRICKS"
                RecipientProfileStr = "profile-$(Get-Random)"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AuthenticationType.Value | Should -Be "DATABRICKS"
            $deployment.Outputs.RecipientProfileStr.Value | Should -Be $parameters.RecipientProfileStr
            
            $script:CreatedProfileProviderName = $deployment.Outputs.ProviderName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty provider name" {
            $templateFile = "$PSScriptRoot/../modules/provider.bicep"
            $parameters = @{
                ProviderName = ""
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

AfterAll {
    if ($script:CreatedProviderName) {
        Write-Host "Cleaning up Delta Sharing provider: $($script:CreatedProviderName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/providers/$($script:CreatedProviderName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup Delta Sharing provider $($script:CreatedProviderName): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedProfileProviderName) {
        Write-Host "Cleaning up profile Delta Sharing provider: $($script:CreatedProfileProviderName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/providers/$($script:CreatedProfileProviderName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup profile Delta Sharing provider $($script:CreatedProfileProviderName): $($_.Exception.Message)"
        }
    }
}
