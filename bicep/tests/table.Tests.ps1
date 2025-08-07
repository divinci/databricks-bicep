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
    $script:TestCatalogName = "test_table_catalog_$(Get-Random)"
    $script:TestSchemaName = "test_table_schema_$(Get-Random)"
}

Describe "Databricks Table Bicep Module Tests" {
    BeforeAll {
        # Create a test catalog first
        Write-Host "Creating test catalog: $($script:TestCatalogName)"
        $catalogConfig = @{
            name = $script:TestCatalogName
            comment = "Test catalog for table tests"
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
                comment = "Test schema for table tests"
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
        It "Should create a managed Unity Catalog table" {
            $templateFile = "$PSScriptRoot/../modules/table.bicep"
            $parameters = @{
                TableName = "test_managed_table_$(Get-Random)"
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                TableType = "MANAGED"
                DataSourceFormat = "DELTA"
                Comment = "Test managed table created by Bicep module"
                Columns = @(
                    @{
                        name = "id"
                        type_text = "INT"
                        type_name = "INT"
                        nullable = $false
                        comment = "Primary key"
                    },
                    @{
                        name = "name"
                        type_text = "STRING"
                        type_name = "STRING"
                        nullable = $true
                        comment = "Name field"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.TableName.Value | Should -Be $parameters.TableName
            $deployment.Outputs.CatalogName.Value | Should -Be $script:TestCatalogName
            $deployment.Outputs.SchemaName.Value | Should -Be $script:TestSchemaName
            $deployment.Outputs.FullName.Value | Should -Be "$($script:TestCatalogName).$($script:TestSchemaName).$($parameters.TableName)"
            $deployment.Outputs.TableType.Value | Should -Be "MANAGED"
            $deployment.Outputs.DataSourceFormat.Value | Should -Be "DELTA"
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.TableId.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedTableFullName = $deployment.Outputs.FullName.Value
        }
        
        It "Should create an external Unity Catalog table" {
            $templateFile = "$PSScriptRoot/../modules/table.bicep"
            $parameters = @{
                TableName = "test_external_table_$(Get-Random)"
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                TableType = "EXTERNAL"
                DataSourceFormat = "PARQUET"
                StorageLocation = "s3://test-table-bucket-$(Get-Random)/table/"
                Comment = "External table with storage location"
                Columns = @(
                    @{
                        name = "timestamp"
                        type_text = "TIMESTAMP"
                        type_name = "TIMESTAMP"
                        nullable = $false
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.TableType.Value | Should -Be "EXTERNAL"
            $deployment.Outputs.DataSourceFormat.Value | Should -Be "PARQUET"
            $deployment.Outputs.StorageLocation.Value | Should -Be $parameters.StorageLocation
            
            $script:CreatedExternalTableFullName = $deployment.Outputs.FullName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty table name" {
            $templateFile = "$PSScriptRoot/../modules/table.bicep"
            $parameters = @{
                TableName = ""
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                TableType = "MANAGED"
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
        # Cleanup tables
        if ($script:CreatedTableFullName) {
            Write-Host "Cleaning up table: $($script:CreatedTableFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/tables/$($script:CreatedTableFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup table $($script:CreatedTableFullName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedExternalTableFullName) {
            Write-Host "Cleaning up external table: $($script:CreatedExternalTableFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/tables/$($script:CreatedExternalTableFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup external table $($script:CreatedExternalTableFullName): $($_.Exception.Message)"
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
