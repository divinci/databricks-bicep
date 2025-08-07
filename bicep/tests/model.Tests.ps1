BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test catalog and schema first
    $script:TestCatalogName = "test_model_catalog_$(Get-Random)"
    $script:TestSchemaName = "test_model_schema_$(Get-Random)"
}

Describe "Databricks Model Bicep Module Tests" {
    BeforeAll {
        # Create a test catalog first
        Write-Host "Creating test catalog: $($script:TestCatalogName)"
        $catalogConfig = @{
            name = $script:TestCatalogName
            comment = "Test catalog for model tests"
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
            
            # Create a test schema
            Write-Host "Creating test schema: $($script:TestSchemaName)"
            $schemaConfig = @{
                name = $script:TestSchemaName
                catalog_name = $script:TestCatalogName
                comment = "Test schema for model tests"
            } | ConvertTo-Json -Depth 10
            
            $createSchemaResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/unity-catalog/schemas" `
                -Body $schemaConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            Write-Host "Created test schema successfully"
        }
        catch {
            Write-Warning "Failed to create test catalog/schema: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a basic Unity Catalog model" {
            $templateFile = "$PSScriptRoot/../modules/model.bicep"
            $parameters = @{
                ModelName = "test_model_$(Get-Random)"
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Test model created by Bicep module"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ModelName.Value | Should -Be $parameters.ModelName
            $deployment.Outputs.CatalogName.Value | Should -Be $script:TestCatalogName
            $deployment.Outputs.SchemaName.Value | Should -Be $script:TestSchemaName
            $deployment.Outputs.FullName.Value | Should -Be "$($script:TestCatalogName).$($script:TestSchemaName).$($parameters.ModelName)"
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.ModelId.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedModelFullName = $deployment.Outputs.FullName.Value
        }
        
        It "Should create a model with storage location" {
            $templateFile = "$PSScriptRoot/../modules/model.bicep"
            $parameters = @{
                ModelName = "test_storage_model_$(Get-Random)"
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Model with storage location"
                StorageLocation = "s3://test-model-bucket-$(Get-Random)/model/"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.StorageLocation.Value | Should -Be $parameters.StorageLocation
            
            $script:CreatedStorageModelFullName = $deployment.Outputs.FullName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty model name" {
            $templateFile = "$PSScriptRoot/../modules/model.bicep"
            $parameters = @{
                ModelName = ""
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
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
        # Cleanup models
        if ($script:CreatedModelFullName) {
            Write-Host "Cleaning up model: $($script:CreatedModelFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/models/$($script:CreatedModelFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup model $($script:CreatedModelFullName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedStorageModelFullName) {
            Write-Host "Cleaning up storage model: $($script:CreatedStorageModelFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/models/$($script:CreatedStorageModelFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup storage model $($script:CreatedStorageModelFullName): $($_.Exception.Message)"
            }
        }
        
        # Cleanup test schema and catalog
        if ($script:TestSchemaName -and $script:TestCatalogName) {
            Write-Host "Cleaning up test schema: $($script:TestCatalogName).$($script:TestSchemaName)"
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
