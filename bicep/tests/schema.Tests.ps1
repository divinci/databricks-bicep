BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test catalog first
    $script:TestCatalogName = "test-schema-catalog-$(Get-Random)"
}

Describe "Databricks Schema Bicep Module Tests" {
    BeforeAll {
        # Create a test catalog first
        Write-Host "Creating test catalog: $($script:TestCatalogName)"
        $catalogConfig = @{
            name = $script:TestCatalogName
            comment = "Test catalog for schema tests"
            isolation_mode = "OPEN"
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/unity-catalog/catalogs" `
                -Body $catalogConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            Write-Host "Created test catalog successfully"
        }
        catch {
            Write-Warning "Failed to create test catalog: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a basic Unity Catalog schema" {
            $templateFile = "$PSScriptRoot/../modules/schema.bicep"
            $parameters = @{
                SchemaName = "test_schema_$(Get-Random)"
                CatalogName = $script:TestCatalogName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Test schema created by Bicep module"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.SchemaName.Value | Should -Be $parameters.SchemaName
            $deployment.Outputs.CatalogName.Value | Should -Be $script:TestCatalogName
            $deployment.Outputs.FullName.Value | Should -Be "$($script:TestCatalogName).$($parameters.SchemaName)"
            $deployment.Outputs.SchemaId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedSchemaFullName = $deployment.Outputs.FullName.Value
        }
        
        It "Should create a schema with custom properties" {
            $templateFile = "$PSScriptRoot/../modules/schema.bicep"
            $parameters = @{
                SchemaName = "test_advanced_schema_$(Get-Random)"
                CatalogName = $script:TestCatalogName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Advanced test schema"
                Properties = @{
                    "department" = "engineering"
                    "project" = "test"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Comment.Value | Should -Be "Advanced test schema"
            
            $script:CreatedAdvancedSchemaFullName = $deployment.Outputs.FullName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty schema name" {
            $templateFile = "$PSScriptRoot/../modules/schema.bicep"
            $parameters = @{
                SchemaName = ""
                CatalogName = $script:TestCatalogName
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
        
        It "Should fail with non-existent catalog" {
            $templateFile = "$PSScriptRoot/../modules/schema.bicep"
            $parameters = @{
                SchemaName = "test_schema"
                CatalogName = "non-existent-catalog"
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
    
    AfterAll {
        # Cleanup schemas
        if ($script:CreatedSchemaFullName) {
            Write-Host "Cleaning up schema: $($script:CreatedSchemaFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/schemas/$($script:CreatedSchemaFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup schema $($script:CreatedSchemaFullName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedAdvancedSchemaFullName) {
            Write-Host "Cleaning up advanced schema: $($script:CreatedAdvancedSchemaFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/schemas/$($script:CreatedAdvancedSchemaFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup advanced schema $($script:CreatedAdvancedSchemaFullName): $($_.Exception.Message)"
            }
        }
        
        # Cleanup test catalog
        if ($script:TestCatalogName) {
            Write-Host "Cleaning up test catalog: $($script:TestCatalogName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/catalogs/$($script:TestCatalogName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test catalog $($script:TestCatalogName): $($_.Exception.Message)"
            }
        }
    }
}
