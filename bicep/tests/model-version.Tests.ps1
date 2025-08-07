BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create test catalog, schema, and model first
    $script:TestCatalogName = "test_mv_catalog_$(Get-Random)"
    $script:TestSchemaName = "test_mv_schema_$(Get-Random)"
    $script:TestModelName = "test_mv_model_$(Get-Random)"
}

Describe "Databricks Model Version Bicep Module Tests" {
    BeforeAll {
        # Create test catalog for model version
        Write-Host "Creating test catalog: $($script:TestCatalogName)"
        $catalogConfig = @{
            name = $script:TestCatalogName
            comment = "Test catalog for model version tests"
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
                comment = "Test schema for model version tests"
            } | ConvertTo-Json -Depth 10
            
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/unity-catalog/schemas" `
                -Body $schemaConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            Write-Host "Created test schema: $($script:TestSchemaName)"
            
            # Create test model
            Write-Host "Creating test model: $($script:TestModelName)"
            $modelConfig = @{
                name = $script:TestModelName
                catalog_name = $script:TestCatalogName
                schema_name = $script:TestSchemaName
                comment = "Test model for model version tests"
            } | ConvertTo-Json -Depth 10
            
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/unity-catalog/models" `
                -Body $modelConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            Write-Host "Created test model: $($script:TestModelName)"
        }
        catch {
            Write-Warning "Failed to create test catalog/schema/model: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a model version with basic configuration" {
            if (-not $script:TestCatalogName -or -not $script:TestSchemaName -or -not $script:TestModelName) {
                Set-ItResult -Skipped -Because "Test catalog/schema/model creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/model-version.bicep"
            $parameters = @{
                ModelName = $script:TestModelName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                Version = 1
                Source = "dbfs:/mnt/models/test-model-v1"
                RunId = "test-run-id-$(Get-Random)"
                Comment = "Test model version for Bicep module testing"
                Tags = @{
                    environment = "test"
                    version = "1.0.0"
                    framework = "sklearn"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ModelName.Value | Should -Be $script:TestModelName
            $deployment.Outputs.FullName.Value | Should -Be "$($script:TestCatalogName).$($script:TestSchemaName).$($script:TestModelName)"
            $deployment.Outputs.CatalogName.Value | Should -Be $script:TestCatalogName
            $deployment.Outputs.SchemaName.Value | Should -Be $script:TestSchemaName
            $deployment.Outputs.Version.Value | Should -Be 1
            $deployment.Outputs.Source.Value | Should -Be $parameters.Source
            $deployment.Outputs.RunId.Value | Should -Be $parameters.RunId
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.Tags.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Status.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.UpdatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.CreatedBy.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.UpdatedBy.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedModelVersionFullName = $deployment.Outputs.FullName.Value
            $script:CreatedModelVersion = $deployment.Outputs.Version.Value
        }
        
        It "Should create a model version with minimal configuration" {
            if (-not $script:TestCatalogName -or -not $script:TestSchemaName -or -not $script:TestModelName) {
                Set-ItResult -Skipped -Because "Test catalog/schema/model creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/model-version.bicep"
            $parameters = @{
                ModelName = $script:TestModelName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                Version = 2
                Source = "dbfs:/mnt/models/test-model-v2"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Version.Value | Should -Be 2
            $deployment.Outputs.Comment.Value | Should -Be ""
            $deployment.Outputs.RunId.Value | Should -Be ""
            
            $script:CreatedMinimalModelVersionFullName = $deployment.Outputs.FullName.Value
            $script:CreatedMinimalModelVersion = $deployment.Outputs.Version.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty model name" {
            $templateFile = "$PSScriptRoot/../modules/model-version.bicep"
            $parameters = @{
                ModelName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                Version = 1
                Source = "dbfs:/mnt/models/test"
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
        
        It "Should fail with empty source" {
            $templateFile = "$PSScriptRoot/../modules/model-version.bicep"
            $parameters = @{
                ModelName = $script:TestModelName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                Version = 1
                Source = ""
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
        # Cleanup model versions
        if ($script:CreatedModelVersionFullName -and $script:CreatedModelVersion) {
            Write-Host "Cleaning up model version: $($script:CreatedModelVersionFullName) v$($script:CreatedModelVersion)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/models/$($script:CreatedModelVersionFullName)/versions/$($script:CreatedModelVersion)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup model version $($script:CreatedModelVersionFullName) v$($script:CreatedModelVersion): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedMinimalModelVersionFullName -and $script:CreatedMinimalModelVersion) {
            Write-Host "Cleaning up minimal model version: $($script:CreatedMinimalModelVersionFullName) v$($script:CreatedMinimalModelVersion)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/models/$($script:CreatedMinimalModelVersionFullName)/versions/$($script:CreatedMinimalModelVersion)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup minimal model version $($script:CreatedMinimalModelVersionFullName) v$($script:CreatedMinimalModelVersion): $($_.Exception.Message)"
            }
        }
        
        # Cleanup test model
        if ($script:TestModelName) {
            Write-Host "Cleaning up test model: $($script:TestModelName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/models/$($script:TestCatalogName).$($script:TestSchemaName).$($script:TestModelName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test model: $($_.Exception.Message)"
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
