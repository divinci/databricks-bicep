BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test secret scope first
    $script:TestScopeName = "test-secret-scope-$(Get-Random)"
}

Describe "Databricks Secret Bicep Module Tests" {
    BeforeAll {
        # Create a test secret scope first
        Write-Host "Creating test secret scope: $($script:TestScopeName)"
        $scopeConfig = @{
            scope = $script:TestScopeName
            backend_type = "DATABRICKS"
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/secrets/scopes/create" `
                -Body $scopeConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            Write-Host "Created test secret scope successfully"
        }
        catch {
            Write-Warning "Failed to create test secret scope: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a secret in the test scope" {
            $templateFile = "$PSScriptRoot/../modules/secret.bicep"
            $parameters = @{
                SecretName = "test-secret-$(Get-Random)"
                ScopeName = $script:TestScopeName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                SecretValue = "test-secret-value-$(Get-Random)"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.SecretName.Value | Should -Be $parameters.SecretName
            $deployment.Outputs.ScopeName.Value | Should -Be $script:TestScopeName
            $deployment.Outputs.LastUpdatedTimestamp.Value | Should -BeGreaterThan 0
            
            $script:CreatedSecretName = $deployment.Outputs.SecretName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with non-existent scope" {
            $templateFile = "$PSScriptRoot/../modules/secret.bicep"
            $parameters = @{
                SecretName = "test-secret-invalid"
                ScopeName = "non-existent-scope"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                SecretValue = "test-value"
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
        # Cleanup test secret scope (this will also delete all secrets in it)
        if ($script:TestScopeName) {
            Write-Host "Cleaning up test secret scope: $($script:TestScopeName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/secrets/scopes/delete" `
                    -Body "{`"scope`": `"$($script:TestScopeName)`"}" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test secret scope $($script:TestScopeName): $($_.Exception.Message)"
            }
        }
    }
}
