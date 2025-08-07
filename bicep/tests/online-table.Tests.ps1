BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create test catalog, schema, and table first
    $script:TestCatalogName = "test_online_catalog_$(Get-Random)"
    $script:TestSchemaName = "test_online_schema_$(Get-Random)"
    $script:TestTableName = "test_online_table_$(Get-Random)"
    $script:TestFullTableName = ""
}

Describe "Databricks Online Table Bicep Module Tests" {
    BeforeAll {
        # Create test catalog, schema, and table for online table
        Write-Host "Creating test catalog: $($script:TestCatalogName)"
        $catalogConfig = @{
            name = $script:TestCatalogName
            comment = "Test catalog for online table tests"
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
            
            # Create test schema
            Write-Host "Creating test schema: $($script:TestSchemaName)"
            $schemaConfig = @{
                name = $script:TestSchemaName
                catalog_name = $script:TestCatalogName
                comment = "Test schema for online table tests"
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
                        name = "feature1"
                        type_text = "DOUBLE"
                        type_name = "DOUBLE"
                        nullable = $true
                    },
                    @{
                        name = "feature2"
                        type_text = "STRING"
                        type_name = "STRING"
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
            
            Write-Host "Created test table: $($script:TestFullTableName)"
        }
        catch {
            Write-Warning "Failed to create test resources: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a basic online table" {
            if (-not $script:TestFullTableName) {
                Set-ItResult -Skipped -Because "Test table creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/online-table.bicep"
            $parameters = @{
                TableName = "test-online-table-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Spec = @{
                    source_table_full_name = $script:TestFullTableName
                    primary_key_columns = @("id")
                    timeseries_key = "feature1"
                    perform_full_copy = $false
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.TableName.Value | Should -Be $parameters.TableName
            $deployment.Outputs.Spec.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Status.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.TableServingUrl.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedOnlineTableName = $deployment.Outputs.TableName.Value
        }
        
        It "Should create an online table with full copy" {
            if (-not $script:TestFullTableName) {
                Set-ItResult -Skipped -Because "Test table creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/online-table.bicep"
            $parameters = @{
                TableName = "test-full-copy-online-table-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Spec = @{
                    source_table_full_name = $script:TestFullTableName
                    primary_key_columns = @("id")
                    perform_full_copy = $true
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.TableName.Value | Should -Be $parameters.TableName
            
            $script:CreatedFullCopyOnlineTableName = $deployment.Outputs.TableName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty table name" {
            $templateFile = "$PSScriptRoot/../modules/online-table.bicep"
            $parameters = @{
                TableName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Spec = @{
                    source_table_full_name = "test.table"
                    primary_key_columns = @("id")
                }
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
        # Cleanup online tables
        if ($script:CreatedOnlineTableName) {
            Write-Host "Cleaning up online table: $($script:CreatedOnlineTableName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/serving-endpoints/online-tables/$($script:CreatedOnlineTableName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup online table $($script:CreatedOnlineTableName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedFullCopyOnlineTableName) {
            Write-Host "Cleaning up full copy online table: $($script:CreatedFullCopyOnlineTableName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/serving-endpoints/online-tables/$($script:CreatedFullCopyOnlineTableName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup full copy online table $($script:CreatedFullCopyOnlineTableName): $($_.Exception.Message)"
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
    }
}
