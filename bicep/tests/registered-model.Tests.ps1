BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create test catalog and schema first
    $script:TestCatalogName = "test_model_catalog_$(Get-Random)"
    $script:TestSchemaName = "test_model_schema_$(Get-Random)"
}

Describe "Databricks Registered Model Bicep Module Tests" {
    BeforeAll {
        # Create test catalog for registered model
        Write-Host "Creating test catalog: $($script:TestCatalogName)"
        $catalogConfig = @{
            name = $script:TestCatalogName
            comment = "Test catalog for registered model tests"
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
            
            Write-Host "Created test catalog: $($script:TestCatalogName)"
            
            # Create test schema
            Write-Host "Creating test schema: $($script:TestSchemaName)"
            $schemaConfig = @{
                name = $script:TestSchemaName
                catalog_name = $script:TestCatalogName
                comment = "Test schema for registered model tests"
            } | ConvertTo-Json -Depth 10
            
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/unity-catalog/schemas" `
                -Body $schemaConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            Write-Host "Created test schema: $($script:TestSchemaName)"
        }
        catch {
            Write-Warning "Failed to create test catalog/schema: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a registered model with basic configuration" {
            if (-not $script:TestCatalogName -or -not $script:TestSchemaName) {
                Set-ItResult -Skipped -Because "Test catalog/schema creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/registered-model.bicep"
            $parameters = @{
                ModelName = "test_model_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                Comment = "Test registered model for Bicep module testing"
                Tags = @{
                    environment = "test"
                    team = "data-science"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ModelName.Value | Should -Be $parameters.ModelName
            $deployment.Outputs.FullName.Value | Should -Be "$($script:TestCatalogName).$($script:TestSchemaName).$($parameters.ModelName)"
            $deployment.Outputs.CatalogName.Value | Should -Be $script:TestCatalogName
            $deployment.Outputs.SchemaName.Value | Should -Be $script:TestSchemaName
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.Tags.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Owner.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.UpdatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.CreatedBy.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.UpdatedBy.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedModelFullName = $deployment.Outputs.FullName.Value
        }
        
        It "Should create a registered model with minimal configuration" {
            if (-not $script:TestCatalogName -or -not $script:TestSchemaName) {
                Set-ItResult -Skipped -Because "Test catalog/schema creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/registered-model.bicep"
            $parameters = @{
                ModelName = "test_minimal_model_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Comment.Value | Should -Be ""
            
            $script:CreatedMinimalModelFullName = $deployment.Outputs.FullName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty model name" {
            $templateFile = "$PSScriptRoot/../modules/registered-model.bicep"
            $parameters = @{
                ModelName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
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
        
        It "Should fail with empty catalog name" {
            $templateFile = "$PSScriptRoot/../modules/registered-model.bicep"
            $parameters = @{
                ModelName = "test_model"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = ""
                SchemaName = $script:TestSchemaName
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
        # Cleanup registered models
        if ($script:CreatedModelFullName) {
            Write-Host "Cleaning up registered model: $($script:CreatedModelFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/models/$($script:CreatedModelFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup registered model $($script:CreatedModelFullName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedMinimalModelFullName) {
            Write-Host "Cleaning up minimal registered model: $($script:CreatedMinimalModelFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/models/$($script:CreatedMinimalModelFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup minimal registered model $($script:CreatedMinimalModelFullName): $($_.Exception.Message)"
            }
        }
        
        # Cleanup test schema
        if ($script:TestSchemaName) {
            Write-Host "Cleaning up test schema: $($script:TestSchemaName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/schemas/$($script:TestCatalogName).$($script:TestSchemaName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test schema: $($_.Exception.Message)"
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
                Write-Warning "Failed to cleanup test catalog: $($_.Exception.Message)"
            }
        }
    }
}
