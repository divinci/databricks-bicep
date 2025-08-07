BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create test SQL query first
    $script:TestQueryId = ""
}

Describe "Databricks SQL Visualization Bicep Module Tests" {
    BeforeAll {
        # Create a test SQL query for visualization
        Write-Host "Creating test SQL query for visualization tests"
        $queryConfig = @{
            name = "test-query-for-viz-$(Get-Random)"
            query = "SELECT 'test' as category, 100 as value UNION ALL SELECT 'test2' as category, 200 as value"
            description = "Test query for visualization tests"
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/sql/queries" `
                -Body $queryConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            $queryResult = $createResponse | ConvertFrom-Json
            $script:TestQueryId = $queryResult.id
            Write-Host "Created test query with ID: $($script:TestQueryId)"
        }
        catch {
            Write-Warning "Failed to create test query: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a chart visualization" {
            if (-not $script:TestQueryId) {
                Set-ItResult -Skipped -Because "Test query creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/sql-visualization.bicep"
            $parameters = @{
                VisualizationName = "test-chart-viz-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                QueryId = $script:TestQueryId
                Type = "CHART"
                Options = @{
                    version = 2
                    globalSeriesType = "column"
                    sortX = $true
                    legend = @{
                        enabled = $true
                        placement = "auto"
                        traceorder = "normal"
                    }
                    xAxis = @{
                        type = "-"
                        labels = @{
                            enabled = $true
                        }
                    }
                    yAxis = @{
                        @{
                            type = "linear"
                            labels = @{
                                enabled = $true
                            }
                        }
                    }
                    alignYAxes = $true
                    error_y = @{
                        type = "data"
                        visible = $true
                    }
                    series = @{
                        stacking = $null
                        error_y = @{
                            type = "data"
                            visible = $true
                        }
                    }
                    seriesOptions = @{}
                    valuesOptions = @{}
                    columnMapping = @{
                        category = "x"
                        value = "y"
                    }
                }
                Description = "Test chart visualization for Bicep module testing"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.VisualizationName.Value | Should -Be $parameters.VisualizationName
            $deployment.Outputs.VisualizationId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.QueryId.Value | Should -Be $script:TestQueryId
            $deployment.Outputs.Type.Value | Should -Be "CHART"
            $deployment.Outputs.Options.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Description.Value | Should -Be $parameters.Description
            $deployment.Outputs.CreatedAt.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.UpdatedAt.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedChartVisualizationId = $deployment.Outputs.VisualizationId.Value
        }
        
        It "Should create a counter visualization" {
            if (-not $script:TestQueryId) {
                Set-ItResult -Skipped -Because "Test query creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/sql-visualization.bicep"
            $parameters = @{
                VisualizationName = "test-counter-viz-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                QueryId = $script:TestQueryId
                Type = "COUNTER"
                Options = @{
                    counterLabel = "Total Count"
                    counterColName = "value"
                    rowNumber = 1
                    targetRowNumber = 1
                    stringDecimal = 0
                    stringDecChar = "."
                    stringThouSep = ","
                    tooltipFormat = "0,0.000"
                }
                Description = "Test counter visualization"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Type.Value | Should -Be "COUNTER"
            
            $script:CreatedCounterVisualizationId = $deployment.Outputs.VisualizationId.Value
        }
        
        It "Should create a pivot table visualization" {
            if (-not $script:TestQueryId) {
                Set-ItResult -Skipped -Because "Test query creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/sql-visualization.bicep"
            $parameters = @{
                VisualizationName = "test-pivot-viz-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                QueryId = $script:TestQueryId
                Type = "PIVOT"
                Options = @{
                    controls = @{
                        enabled = $true
                    }
                    rendererName = "Table"
                    aggregators = @{
                        "Sum" = @{
                            "value" = "sum"
                        }
                    }
                    vals = @("value")
                    rows = @("category")
                    cols = @()
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Type.Value | Should -Be "PIVOT"
            $deployment.Outputs.Description.Value | Should -Be ""
            
            $script:CreatedPivotVisualizationId = $deployment.Outputs.VisualizationId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty visualization name" {
            $templateFile = "$PSScriptRoot/../modules/sql-visualization.bicep"
            $parameters = @{
                VisualizationName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                QueryId = $script:TestQueryId
                Type = "CHART"
                Options = @{}
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
        
        It "Should fail with invalid visualization type" {
            $templateFile = "$PSScriptRoot/../modules/sql-visualization.bicep"
            $parameters = @{
                VisualizationName = "test-viz"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                QueryId = $script:TestQueryId
                Type = "INVALID_TYPE"
                Options = @{}
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
        
        It "Should fail with empty query ID" {
            $templateFile = "$PSScriptRoot/../modules/sql-visualization.bicep"
            $parameters = @{
                VisualizationName = "test-viz"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                QueryId = ""
                Type = "CHART"
                Options = @{}
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
        # Cleanup SQL visualizations
        if ($script:CreatedChartVisualizationId) {
            Write-Host "Cleaning up chart visualization: $($script:CreatedChartVisualizationId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/sql/visualizations/$($script:CreatedChartVisualizationId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup chart visualization $($script:CreatedChartVisualizationId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedCounterVisualizationId) {
            Write-Host "Cleaning up counter visualization: $($script:CreatedCounterVisualizationId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/sql/visualizations/$($script:CreatedCounterVisualizationId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup counter visualization $($script:CreatedCounterVisualizationId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedPivotVisualizationId) {
            Write-Host "Cleaning up pivot visualization: $($script:CreatedPivotVisualizationId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/sql/visualizations/$($script:CreatedPivotVisualizationId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup pivot visualization $($script:CreatedPivotVisualizationId): $($_.Exception.Message)"
            }
        }
        
        # Cleanup test query
        if ($script:TestQueryId) {
            Write-Host "Cleaning up test query: $($script:TestQueryId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/sql/queries/$($script:TestQueryId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test query: $($_.Exception.Message)"
            }
        }
    }
}
