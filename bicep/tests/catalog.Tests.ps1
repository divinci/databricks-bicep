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

Describe "Databricks Catalog Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic Unity Catalog catalog" {
            $templateFile = "$PSScriptRoot/../modules/catalog.bicep"
            $parameters = @{
                CatalogName = "test-catalog-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Test catalog created by Bicep module"
                IsolationMode = "OPEN"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.CatalogName.Value | Should -Be $parameters.CatalogName
            $deployment.Outputs.CatalogId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.IsolationMode.Value | Should -Be "OPEN"
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.UpdatedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedCatalogName = $deployment.Outputs.CatalogName.Value
        }
        
        It "Should create a catalog with custom properties" {
            $templateFile = "$PSScriptRoot/../modules/catalog.bicep"
            $parameters = @{
                CatalogName = "test-advanced-catalog-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Advanced test catalog"
                Properties = @{
                    "custom_property" = "custom_value"
                    "environment" = "test"
                }
                IsolationMode = "ISOLATED"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.IsolationMode.Value | Should -Be "ISOLATED"
            
            $script:CreatedAdvancedCatalogName = $deployment.Outputs.CatalogName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty catalog name" {
            $templateFile = "$PSScriptRoot/../modules/catalog.bicep"
            $parameters = @{
                CatalogName = ""
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
    if ($script:CreatedCatalogName) {
        Write-Host "Cleaning up catalog: $($script:CreatedCatalogName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/catalogs/$($script:CreatedCatalogName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup catalog $($script:CreatedCatalogName): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedAdvancedCatalogName) {
        Write-Host "Cleaning up advanced catalog: $($script:CreatedAdvancedCatalogName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/catalogs/$($script:CreatedAdvancedCatalogName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup advanced catalog $($script:CreatedAdvancedCatalogName): $($_.Exception.Message)"
        }
    }
}
