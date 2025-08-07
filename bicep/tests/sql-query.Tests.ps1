BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
}

Describe "Databricks SQL Query Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic SQL query" {
            $templateFile = "$PSScriptRoot/../modules/sql-query.bicep"
            $parameters = @{
                QueryName = "test-query-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Query = "SELECT 1 as test_column"
                Description = "Test SQL query created by Bicep module"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.QueryId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.QueryName.Value | Should -Be $parameters.QueryName
            $deployment.Outputs.Description.Value | Should -Be $parameters.Description
            $deployment.Outputs.Query.Value | Should -Be $parameters.Query
            $deployment.Outputs.CreatedAt.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.UserId.Value | Should -BeGreaterThan 0
            
            $script:CreatedQueryId = $deployment.Outputs.QueryId.Value
        }
        
        It "Should create a SQL query with parameters" {
            $templateFile = "$PSScriptRoot/../modules/sql-query.bicep"
            $parameters = @{
                QueryName = "test-parameterized-query-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Query = "SELECT * FROM table WHERE date >= '{{start_date}}' AND date <= '{{end_date}}'"
                Description = "Parameterized test query"
                Parameters = @(
                    @{
                        name = "start_date"
                        type = "date"
                        value = "2023-01-01"
                    },
                    @{
                        name = "end_date"
                        type = "date"
                        value = "2023-12-31"
                    }
                )
                Tags = @("test", "parameterized")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Description.Value | Should -Be "Parameterized test query"
            
            $script:CreatedParameterizedQueryId = $deployment.Outputs.QueryId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty query name" {
            $templateFile = "$PSScriptRoot/../modules/sql-query.bicep"
            $parameters = @{
                QueryName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Query = "SELECT 1"
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
        
        It "Should fail with empty query text" {
            $templateFile = "$PSScriptRoot/../modules/sql-query.bicep"
            $parameters = @{
                QueryName = "test-empty-query"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Query = ""
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
}

AfterAll {
    if ($script:CreatedQueryId) {
        Write-Host "Cleaning up SQL query: $($script:CreatedQueryId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/preview/sql/queries/$($script:CreatedQueryId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup SQL query $($script:CreatedQueryId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedParameterizedQueryId) {
        Write-Host "Cleaning up parameterized SQL query: $($script:CreatedParameterizedQueryId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/preview/sql/queries/$($script:CreatedParameterizedQueryId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup parameterized SQL query $($script:CreatedParameterizedQueryId): $($_.Exception.Message)"
        }
    }
}
