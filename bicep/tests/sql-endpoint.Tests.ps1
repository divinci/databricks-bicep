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

Describe "Databricks SQL Endpoint Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic SQL endpoint" {
            $templateFile = "$PSScriptRoot/../modules/sql-endpoint.bicep"
            $parameters = @{
                EndpointName = "test-sql-endpoint-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ClusterSize = "2X-Small"
                MinNumClusters = 1
                MaxNumClusters = 1
                AutoStopMins = 60
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.EndpointId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.EndpointName.Value | Should -Be $parameters.EndpointName
            $deployment.Outputs.ClusterSize.Value | Should -Be "2X-Small"
            $deployment.Outputs.JdbcUrl.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedSqlEndpointId = $deployment.Outputs.EndpointId.Value
        }
        
        It "Should create an autoscaling SQL endpoint" {
            $templateFile = "$PSScriptRoot/../modules/sql-endpoint.bicep"
            $parameters = @{
                EndpointName = "test-autoscale-sql-endpoint-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ClusterSize = "Small"
                MinNumClusters = 1
                MaxNumClusters = 3
                EnablePhoton = $true
                SpotInstancePolicy = "COST_OPTIMIZED"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ClusterSize.Value | Should -Be "Small"
            
            $script:CreatedAutoscaleSqlEndpointId = $deployment.Outputs.EndpointId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid cluster size" {
            $templateFile = "$PSScriptRoot/../modules/sql-endpoint.bicep"
            $parameters = @{
                EndpointName = "test-invalid-sql-endpoint"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ClusterSize = "Invalid-Size"
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
    if ($script:CreatedSqlEndpointId) {
        Write-Host "Cleaning up SQL endpoint: $($script:CreatedSqlEndpointId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/sql/warehouses/$($script:CreatedSqlEndpointId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup SQL endpoint $($script:CreatedSqlEndpointId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedAutoscaleSqlEndpointId) {
        Write-Host "Cleaning up autoscale SQL endpoint: $($script:CreatedAutoscaleSqlEndpointId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/sql/warehouses/$($script:CreatedAutoscaleSqlEndpointId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup autoscale SQL endpoint $($script:CreatedAutoscaleSqlEndpointId): $($_.Exception.Message)"
        }
    }
}
