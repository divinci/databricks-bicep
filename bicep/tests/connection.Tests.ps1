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

Describe "Databricks Connection Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic MySQL connection" {
            $templateFile = "$PSScriptRoot/../modules/connection.bicep"
            $parameters = @{
                ConnectionName = "test_mysql_connection_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConnectionType = "MYSQL"
                Comment = "Test MySQL connection created by Bicep module"
                Options = @{
                    host = "mysql.example.com"
                    port = "3306"
                    user = "testuser"
                    password = "testpass"
                }
                Properties = @{
                    "purpose" = "testing"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ConnectionName.Value | Should -Be $parameters.ConnectionName
            $deployment.Outputs.ConnectionType.Value | Should -Be "MYSQL"
            $deployment.Outputs.Comment.Value | Should -Be $parameters.Comment
            $deployment.Outputs.ReadOnly.Value | Should -Be $false
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.ConnectionId.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedConnectionName = $deployment.Outputs.ConnectionName.Value
        }
        
        It "Should create a read-only PostgreSQL connection" {
            $templateFile = "$PSScriptRoot/../modules/connection.bicep"
            $parameters = @{
                ConnectionName = "test_postgres_connection_$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConnectionType = "POSTGRESQL"
                Comment = "Read-only PostgreSQL connection"
                ReadOnly = $true
                Options = @{
                    host = "postgres.example.com"
                    port = "5432"
                    database = "testdb"
                    user = "readonly"
                    password = "readpass"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ConnectionType.Value | Should -Be "POSTGRESQL"
            $deployment.Outputs.ReadOnly.Value | Should -Be $true
            
            $script:CreatedPostgresConnectionName = $deployment.Outputs.ConnectionName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty connection name" {
            $templateFile = "$PSScriptRoot/../modules/connection.bicep"
            $parameters = @{
                ConnectionName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ConnectionType = "MYSQL"
                Options = @{
                    host = "test.com"
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
}

AfterAll {
    if ($script:CreatedConnectionName) {
        Write-Host "Cleaning up connection: $($script:CreatedConnectionName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/connections/$($script:CreatedConnectionName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup connection $($script:CreatedConnectionName): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedPostgresConnectionName) {
        Write-Host "Cleaning up PostgreSQL connection: $($script:CreatedPostgresConnectionName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.1/unity-catalog/connections/$($script:CreatedPostgresConnectionName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup PostgreSQL connection $($script:CreatedPostgresConnectionName): $($_.Exception.Message)"
        }
    }
}
