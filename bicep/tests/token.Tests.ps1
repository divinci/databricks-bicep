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

Describe "Databricks Token Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a personal access token with no expiration" {
            $templateFile = "$PSScriptRoot/../modules/token.bicep"
            $parameters = @{
                Comment = "test-token-no-expiry-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                LifetimeSeconds = 0
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.TokenId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.CreationTime.Value | Should -BeGreaterThan 0
            
            $script:CreatedTokenId = $deployment.Outputs.TokenId.Value
        }
        
        It "Should create a personal access token with expiration" {
            $templateFile = "$PSScriptRoot/../modules/token.bicep"
            $parameters = @{
                Comment = "test-token-with-expiry-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                LifetimeSeconds = 3600
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.TokenId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.ExpiryTime.Value | Should -BeGreaterThan $deployment.Outputs.CreationTime.Value
            
            $script:CreatedExpiringTokenId = $deployment.Outputs.TokenId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty comment" {
            $templateFile = "$PSScriptRoot/../modules/token.bicep"
            $parameters = @{
                Comment = ""
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
    if ($script:CreatedTokenId) {
        Write-Host "Cleaning up token: $($script:CreatedTokenId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/token/delete" `
                -Body "{`"token_id`": `"$($script:CreatedTokenId)`"}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup token $($script:CreatedTokenId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedExpiringTokenId) {
        Write-Host "Cleaning up expiring token: $($script:CreatedExpiringTokenId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/token/delete" `
                -Body "{`"token_id`": `"$($script:CreatedExpiringTokenId)`"}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup expiring token $($script:CreatedExpiringTokenId): $($_.Exception.Message)"
        }
    }
}
