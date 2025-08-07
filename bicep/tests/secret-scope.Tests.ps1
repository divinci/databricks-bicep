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

Describe "Databricks Secret Scope Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a Databricks-backed secret scope" {
            $templateFile = "$PSScriptRoot/../modules/secret-scope.bicep"
            $parameters = @{
                ScopeName = "test-databricks-scope-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                BackendType = "DATABRICKS"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ScopeName.Value | Should -Be $parameters.ScopeName
            $deployment.Outputs.BackendType.Value | Should -Be "DATABRICKS"
            
            $script:CreatedDatabricksScopeId = $deployment.Outputs.ScopeName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty scope name" {
            $templateFile = "$PSScriptRoot/../modules/secret-scope.bicep"
            $parameters = @{
                ScopeName = ""
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
    if ($script:CreatedDatabricksScopeId) {
        Write-Host "Cleaning up secret scope: $($script:CreatedDatabricksScopeId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/secrets/scopes/delete" `
                -Body "{`"scope`": `"$($script:CreatedDatabricksScopeId)`"}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup secret scope $($script:CreatedDatabricksScopeId): $($_.Exception.Message)"
        }
    }
}
