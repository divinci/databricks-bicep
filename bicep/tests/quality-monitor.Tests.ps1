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
    $script:TestCatalogName = "test_quality_catalog_$(Get-Random)"
    $script:TestSchemaName = "test_quality_schema_$(Get-Random)"
    $script:TestTableName = "test_quality_table_$(Get-Random)"
    $script:TestFullTableName = ""
}

Describe "Databricks Quality Monitor Bicep Module Tests" {
    BeforeAll {
        # Create test catalog, schema, and table for quality monitor
        Write-Host "Creating test catalog: $($script:TestCatalogName)"
        $catalogConfig = @{
            name = $script:TestCatalogName
            comment = "Test catalog for quality monitor tests"
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
                comment = "Test schema for quality monitor tests"
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
                        name = "quality_score"
                        type_text = "DOUBLE"
                        type_name = "DOUBLE"
                        nullable = $true
                    },
                    @{
                        name = "timestamp"
                        type_text = "TIMESTAMP"
                        type_name = "TIMESTAMP"
                        nullable = $false
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
        It "Should create a basic quality monitor" {
            if (-not $script:TestFullTableName) {
                Set-ItResult -Skipped -Because "Test table creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/quality-monitor.bicep"
            $parameters = @{
                TableName = $script:TestFullTableName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AssetsDir = "/Shared/quality-monitors/test-monitor-$(Get-Random)"
                OutputSchemaName = "$($script:TestCatalogName).$($script:TestSchemaName)"
                Snapshot = @{
                    
                }
                Schedule = @{
                    quartz_cron_expression = "0 0 12 * * ?"
                    timezone_id = "UTC"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.TableName.Value | Should -Be $script:TestFullTableName
            $deployment.Outputs.AssetsDir.Value | Should -Be $parameters.AssetsDir
            $deployment.Outputs.OutputSchemaName.Value | Should -Be $parameters.OutputSchemaName
            $deployment.Outputs.MonitorVersion.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Status.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatedBy.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatedTime.Value | Should -BeGreaterThan 0
            $deployment.Outputs.Schedule.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedQualityMonitorTableName = $deployment.Outputs.TableName.Value
        }
        
        It "Should create a quality monitor with custom metrics" {
            if (-not $script:TestFullTableName) {
                Set-ItResult -Skipped -Because "Test table creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/quality-monitor.bicep"
            $parameters = @{
                TableName = $script:TestFullTableName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AssetsDir = "/Shared/quality-monitors/test-custom-monitor-$(Get-Random)"
                OutputSchemaName = "$($script:TestCatalogName).$($script:TestSchemaName)"
                CustomMetrics = @(
                    @{
                        type = "aggregate"
                        name = "avg_quality_score"
                        input_columns = @("quality_score")
                        definition = "avg(quality_score)"
                        output_data_type = "double"
                    }
                )
                Notifications = @{
                    on_failure = @{
                        email_addresses = @("admin@example.com")
                    }
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.CustomMetrics.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Notifications.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedCustomQualityMonitorTableName = $deployment.Outputs.TableName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty table name" {
            $templateFile = "$PSScriptRoot/../modules/quality-monitor.bicep"
            $parameters = @{
                TableName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AssetsDir = "/Shared/test"
                OutputSchemaName = "test.schema"
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
        # Cleanup quality monitors
        if ($script:CreatedQualityMonitorTableName) {
            Write-Host "Cleaning up quality monitor: $($script:CreatedQualityMonitorTableName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/quality-monitors/$($script:CreatedQualityMonitorTableName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup quality monitor $($script:CreatedQualityMonitorTableName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedCustomQualityMonitorTableName) {
            Write-Host "Cleaning up custom quality monitor: $($script:CreatedCustomQualityMonitorTableName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/quality-monitors/$($script:CreatedCustomQualityMonitorTableName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup custom quality monitor $($script:CreatedCustomQualityMonitorTableName): $($_.Exception.Message)"
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
