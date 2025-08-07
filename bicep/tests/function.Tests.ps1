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
    $script:TestCatalogName = "test_function_catalog_$(Get-Random)"
    $script:TestSchemaName = "test_function_schema_$(Get-Random)"
}

Describe "Databricks Function Bicep Module Tests" {
    BeforeAll {
        # Create a test catalog first
        Write-Host "Creating test catalog: $($script:TestCatalogName)"
        $catalogConfig = @{
            name = $script:TestCatalogName
            comment = "Test catalog for function tests"
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
                comment = "Test schema for function tests"
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
        It "Should create a basic Unity Catalog function" {
            $templateFile = "$PSScriptRoot/../modules/function.bicep"
            $parameters = @{
                FunctionName = "test_function_$(Get-Random)"
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                InputParams = @(
                    @{
                        name = "x"
                        type_text = "INT"
                        type_name = "INT"
                    }
                )
                DataType = "INT"
                FullDataType = "INT"
                RoutineBody = "SQL"
                RoutineDefinition = "RETURN x * 2"
                Comment = "Test function created by Bicep module"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.FunctionName.Value | Should -Be $parameters.FunctionName
            $deployment.Outputs.CatalogName.Value | Should -Be $script:TestCatalogName
            $deployment.Outputs.SchemaName.Value | Should -Be $script:TestSchemaName
            $deployment.Outputs.FullName.Value | Should -Be "$($script:TestCatalogName).$($script:TestSchemaName).$($parameters.FunctionName)"
            $deployment.Outputs.DataType.Value | Should -Be "INT"
            $deployment.Outputs.RoutineBody.Value | Should -Be "SQL"
            $deployment.Outputs.RoutineDefinition.Value | Should -Be "RETURN x * 2"
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.FunctionId.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedFunctionFullName = $deployment.Outputs.FullName.Value
        }
        
        It "Should create a deterministic function with multiple parameters" {
            $templateFile = "$PSScriptRoot/../modules/function.bicep"
            $parameters = @{
                FunctionName = "test_multi_param_function_$(Get-Random)"
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                InputParams = @(
                    @{
                        name = "a"
                        type_text = "INT"
                        type_name = "INT"
                    },
                    @{
                        name = "b"
                        type_text = "INT"
                        type_name = "INT"
                    }
                )
                DataType = "INT"
                FullDataType = "INT"
                RoutineBody = "SQL"
                RoutineDefinition = "RETURN a + b"
                IsDeterministic = $true
                SqlDataAccess = "READS_SQL_DATA"
                Comment = "Multi-parameter deterministic function"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.IsDeterministic.Value | Should -Be $true
            $deployment.Outputs.SqlDataAccess.Value | Should -Be "READS_SQL_DATA"
            
            $script:CreatedMultiParamFunctionFullName = $deployment.Outputs.FullName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty function name" {
            $templateFile = "$PSScriptRoot/../modules/function.bicep"
            $parameters = @{
                FunctionName = ""
                CatalogName = $script:TestCatalogName
                SchemaName = $script:TestSchemaName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                InputParams = @()
                DataType = "INT"
                FullDataType = "INT"
                RoutineBody = "SQL"
                RoutineDefinition = "RETURN 1"
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
        # Cleanup functions
        if ($script:CreatedFunctionFullName) {
            Write-Host "Cleaning up function: $($script:CreatedFunctionFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/functions/$($script:CreatedFunctionFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup function $($script:CreatedFunctionFullName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedMultiParamFunctionFullName) {
            Write-Host "Cleaning up multi-param function: $($script:CreatedMultiParamFunctionFullName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.1/unity-catalog/functions/$($script:CreatedMultiParamFunctionFullName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup multi-param function $($script:CreatedMultiParamFunctionFullName): $($_.Exception.Message)"
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
