BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create test endpoint, catalog, schema, and table first
    $script:TestEndpointName = "test-index-endpoint-$(Get-Random)"
    $script:TestCatalogName = "test_index_catalog_$(Get-Random)"
    $script:TestSchemaName = "test_index_schema_$(Get-Random)"
    $script:TestTableName = "test_index_table_$(Get-Random)"
    $script:TestFullTableName = ""
}

Describe "Databricks Vector Search Index Bicep Module Tests" {
    BeforeAll {
        # Create test vector search endpoint
        Write-Host "Creating test vector search endpoint: $($script:TestEndpointName)"
        $endpointConfig = @{
            name = $script:TestEndpointName
            endpoint_type = "STANDARD"
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createEndpointResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/vector-search/endpoints" `
                -Body $endpointConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            # Create test catalog, schema, and table for vector search index
            Write-Host "Creating test catalog: $($script:TestCatalogName)"
            $catalogConfig = @{
                name = $script:TestCatalogName
                comment = "Test catalog for vector search index tests"
                isolation_mode = "OPEN"
            } | ConvertTo-Json -Depth 10
            
            $createCatalogResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/unity-catalog/catalogs" `
                -Body $catalogConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            # Create test schema
            Write-Host "Creating test schema: $($script:TestSchemaName)"
            $schemaConfig = @{
                name = $script:TestSchemaName
                catalog_name = $script:TestCatalogName
                comment = "Test schema for vector search index tests"
            } | ConvertTo-Json -Depth 10
            
            $createSchemaResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/unity-catalog/schemas" `
                -Body $schemaConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            # Create test table
            Write-Host "Creating test table: $($script:TestTableName)"
            $script:TestFullTableName = "$($script:TestCatalogName).$($script:TestSchemaName).$($script:TestTableName)"
            $tableConfig = @{
                name = $script:TestTableName
                catalog_name = $script:TestCatalogName
                schema_name = $script:TestSchemaName
                table_type = "MANAGED"
                data_source_format = "DELTA"
                columns = @(
                    @{
                        name = "id"
                        type_text = "INT"
                        type_name = "INT"
                        nullable = $false
                    },
                    @{
                        name = "text"
                        type_text = "STRING"
                        type_name = "STRING"
                        nullable = $true
                    },
                    @{
                        name = "embedding"
                        type_text = "ARRAY<DOUBLE>"
                        type_name = "ARRAY"
                        nullable = $true
                    }
                )
            } | ConvertTo-Json -Depth 10
            
            $createTableResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.1/unity-catalog/tables" `
                -Body $tableConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            Write-Host "Created test resources: endpoint=$($script:TestEndpointName), table=$($script:TestFullTableName)"
        }
        catch {
            Write-Warning "Failed to create test resources: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a delta sync vector search index" {
            if (-not $script:TestEndpointName -or -not $script:TestFullTableName) {
                Set-ItResult -Skipped -Because "Test resources creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/vector-search-index.bicep"
            $parameters = @{
                IndexName = "test-delta-sync-index-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                EndpointName = $script:TestEndpointName
                PrimaryKey = "id"
                IndexType = "DELTA_SYNC"
                DeltaSyncIndexSpec = @{
                    source_table = $script:TestFullTableName
                    pipeline_type = "TRIGGERED"
                    embedding_source_columns = @(
                        @{
                            name = "text"
                            embedding_model_endpoint_name = "databricks-bge-large-en"
                        }
                    )
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.IndexName.Value | Should -Be $parameters.IndexName
            $deployment.Outputs.EndpointName.Value | Should -Be $script:TestEndpointName
            $deployment.Outputs.PrimaryKey.Value | Should -Be "id"
            $deployment.Outputs.IndexType.Value | Should -Be "DELTA_SYNC"
            $deployment.Outputs.IndexStatus.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreationTimestamp.Value | Should -BeGreaterThan 0
            $deployment.Outputs.Creator.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.DeltaSyncIndexSpec.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedDeltaSyncIndexName = $deployment.Outputs.IndexName.Value
        }
        
        It "Should create a direct access vector search index" {
            if (-not $script:TestEndpointName) {
                Set-ItResult -Skipped -Because "Test endpoint creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/vector-search-index.bicep"
            $parameters = @{
                IndexName = "test-direct-access-index-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                EndpointName = $script:TestEndpointName
                PrimaryKey = "id"
                IndexType = "DIRECT_ACCESS"
                DirectAccessIndexSpec = @{
                    embedding_dimension = 1024
                    schema_json = '{"type":"struct","fields":[{"name":"id","type":"string","nullable":false,"metadata":{}},{"name":"text","type":"string","nullable":true,"metadata":{}},{"name":"embedding","type":"array<double>","nullable":true,"metadata":{}}]}'
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.IndexType.Value | Should -Be "DIRECT_ACCESS"
            $deployment.Outputs.DirectAccessIndexSpec.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedDirectAccessIndexName = $deployment.Outputs.IndexName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty index name" {
            $templateFile = "$PSScriptRoot/../modules/vector-search-index.bicep"
            $parameters = @{
                IndexName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                EndpointName = $script:TestEndpointName
                PrimaryKey = "id"
                IndexType = "DELTA_SYNC"
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
        
        It "Should fail with empty primary key" {
            $templateFile = "$PSScriptRoot/../modules/vector-search-index.bicep"
            $parameters = @{
                IndexName = "test-index"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                EndpointName = $script:TestEndpointName
                PrimaryKey = ""
                IndexType = "DELTA_SYNC"
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
        # Cleanup vector search indexes
        if ($script:CreatedDeltaSyncIndexName) {
            Write-Host "Cleaning up delta sync vector search index: $($script:CreatedDeltaSyncIndexName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/vector-search/indexes/$($script:CreatedDeltaSyncIndexName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup delta sync vector search index $($script:CreatedDeltaSyncIndexName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedDirectAccessIndexName) {
            Write-Host "Cleaning up direct access vector search index: $($script:CreatedDirectAccessIndexName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/vector-search/indexes/$($script:CreatedDirectAccessIndexName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup direct access vector search index $($script:CreatedDirectAccessIndexName): $($_.Exception.Message)"
            }
        }
        
        # Cleanup test table, schema, and catalog
        if ($script:TestFullTableName) {
            Write-Host "Cleaning up test table: $($script:TestFullTableName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/tables/$($script:TestFullTableName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test table: $($_.Exception.Message)"
            }
        }
        
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
        
        # Cleanup test vector search endpoint
        if ($script:TestEndpointName) {
            Write-Host "Cleaning up test vector search endpoint: $($script:TestEndpointName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/vector-search/endpoints/$($script:TestEndpointName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test vector search endpoint: $($_.Exception.Message)"
            }
        }
    }
}
