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

Describe "Databricks Warehouse Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic SQL warehouse" {
            $templateFile = "$PSScriptRoot/../modules/warehouse.bicep"
            $parameters = @{
                WarehouseName = "test-warehouse-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ClusterSize = "X-Small"
                MinNumClusters = 1
                MaxNumClusters = 2
                AutoStopMins = 60
                EnablePhoton = $true
                WarehouseType = "PRO"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.WarehouseId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.WarehouseName.Value | Should -Be $parameters.WarehouseName
            $deployment.Outputs.ClusterSize.Value | Should -Be "X-Small"
            $deployment.Outputs.MinNumClusters.Value | Should -Be 1
            $deployment.Outputs.MaxNumClusters.Value | Should -Be 2
            $deployment.Outputs.AutoStopMins.Value | Should -Be 60
            $deployment.Outputs.EnablePhoton.Value | Should -Be $true
            $deployment.Outputs.WarehouseType.Value | Should -Be "PRO"
            $deployment.Outputs.State.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreatorName.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.JdbcUrl.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedWarehouseId = $deployment.Outputs.WarehouseId.Value
        }
        
        It "Should create a serverless SQL warehouse" {
            $templateFile = "$PSScriptRoot/../modules/warehouse.bicep"
            $parameters = @{
                WarehouseName = "test-serverless-warehouse-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ClusterSize = "Small"
                EnableServerlessCompute = $true
                SpotInstancePolicy = "RELIABILITY_OPTIMIZED"
                Tags = @{
                    "environment" = "test"
                    "team" = "data"
                }
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.EnableServerlessCompute.Value | Should -Be $true
            $deployment.Outputs.SpotInstancePolicy.Value | Should -Be "RELIABILITY_OPTIMIZED"
            
            $script:CreatedServerlessWarehouseId = $deployment.Outputs.WarehouseId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty warehouse name" {
            $templateFile = "$PSScriptRoot/../modules/warehouse.bicep"
            $parameters = @{
                WarehouseName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
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
    if ($script:CreatedWarehouseId) {
        Write-Host "Cleaning up SQL warehouse: $($script:CreatedWarehouseId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/sql/warehouses/$($script:CreatedWarehouseId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup SQL warehouse $($script:CreatedWarehouseId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedServerlessWarehouseId) {
        Write-Host "Cleaning up serverless SQL warehouse: $($script:CreatedServerlessWarehouseId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/sql/warehouses/$($script:CreatedServerlessWarehouseId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup serverless SQL warehouse $($script:CreatedServerlessWarehouseId): $($_.Exception.Message)"
        }
    }
}
