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

Describe "Databricks Service Principal Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic service principal" {
            $templateFile = "$PSScriptRoot/../modules/service-principal.bicep"
            $testAppId = "12345678-1234-1234-1234-$(Get-Random)"
            $parameters = @{
                ApplicationId = $testAppId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                DisplayName = "Test Service Principal $(Get-Random)"
                Active = $true
                Entitlements = @("allow-cluster-create")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ServicePrincipalId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.ApplicationId.Value | Should -Be $testAppId
            $deployment.Outputs.DisplayName.Value | Should -Be $parameters.DisplayName
            $deployment.Outputs.Active.Value | Should -Be $true
            
            $script:CreatedServicePrincipalId = $deployment.Outputs.ServicePrincipalId.Value
        }
        
        It "Should create an inactive service principal with external ID" {
            $templateFile = "$PSScriptRoot/../modules/service-principal.bicep"
            $testAppId = "87654321-4321-4321-4321-$(Get-Random)"
            $parameters = @{
                ApplicationId = $testAppId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                DisplayName = "Inactive Test SP $(Get-Random)"
                Active = $false
                ExternalId = "external-$(Get-Random)"
                Entitlements = @("allow-instance-pool-create")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Active.Value | Should -Be $false
            $deployment.Outputs.ExternalId.Value | Should -Be $parameters.ExternalId
            
            $script:CreatedInactiveServicePrincipalId = $deployment.Outputs.ServicePrincipalId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty application ID" {
            $templateFile = "$PSScriptRoot/../modules/service-principal.bicep"
            $parameters = @{
                ApplicationId = ""
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
    if ($script:CreatedServicePrincipalId) {
        Write-Host "Cleaning up service principal: $($script:CreatedServicePrincipalId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/preview/scim/v2/ServicePrincipals/$($script:CreatedServicePrincipalId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup service principal $($script:CreatedServicePrincipalId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedInactiveServicePrincipalId) {
        Write-Host "Cleaning up inactive service principal: $($script:CreatedInactiveServicePrincipalId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/preview/scim/v2/ServicePrincipals/$($script:CreatedInactiveServicePrincipalId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup inactive service principal $($script:CreatedInactiveServicePrincipalId): $($_.Exception.Message)"
        }
    }
}
