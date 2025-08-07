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

Describe "Databricks User Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic user" {
            $templateFile = "$PSScriptRoot/../modules/user.bicep"
            $testEmail = "test-user-$(Get-Random)@example.com"
            $parameters = @{
                UserName = $testEmail
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
            $deployment.Outputs.UserName.Value | Should -Be $testEmail
            $deployment.Outputs.Active.Value | Should -Be $true
            
            $script:CreatedBasicUserId = $deployment.Outputs.UserId.Value
        }
        
        It "Should create a user with display name and entitlements" {
            $templateFile = "$PSScriptRoot/../modules/user.bicep"
            $testEmail = "test-advanced-user-$(Get-Random)@example.com"
            $parameters = @{
                UserName = $testEmail
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                DisplayName = "Test Advanced User"
                Entitlements = @("allow-cluster-create")
                Active = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.DisplayName.Value | Should -Be $parameters.DisplayName
            
            $script:CreatedAdvancedUserId = $deployment.Outputs.UserId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid email format" {
            $templateFile = "$PSScriptRoot/../modules/user.bicep"
            $parameters = @{
                UserName = "invalid-email-format"
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
    if ($script:CreatedBasicUserId) {
        Write-Host "Cleaning up basic user: $($script:CreatedBasicUserId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/preview/scim/v2/Users/$($script:CreatedBasicUserId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup basic user $($script:CreatedBasicUserId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedAdvancedUserId) {
        Write-Host "Cleaning up advanced user: $($script:CreatedAdvancedUserId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/preview/scim/v2/Users/$($script:CreatedAdvancedUserId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup advanced user $($script:CreatedAdvancedUserId): $($_.Exception.Message)"
        }
    }
}
