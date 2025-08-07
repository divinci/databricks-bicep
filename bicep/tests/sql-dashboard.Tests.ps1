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

Describe "Databricks SQL Dashboard Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic SQL dashboard" {
            $templateFile = "$PSScriptRoot/../modules/sql-dashboard.bicep"
            $parameters = @{
                DashboardName = "test-dashboard-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Tags = @("test", "bicep")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.DashboardId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.DashboardName.Value | Should -Be $parameters.DashboardName
            $deployment.Outputs.Slug.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.IsArchived.Value | Should -Be $false
            $deployment.Outputs.IsDraft.Value | Should -Be $false
            $deployment.Outputs.CreatedAt.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.UserId.Value | Should -BeGreaterThan 0
            
            $script:CreatedDashboardId = $deployment.Outputs.DashboardId.Value
        }
        
        It "Should create a draft SQL dashboard" {
            $templateFile = "$PSScriptRoot/../modules/sql-dashboard.bicep"
            $parameters = @{
                DashboardName = "test-draft-dashboard-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                IsDraft = $true
                Tags = @("test", "draft")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.IsDraft.Value | Should -Be $true
            
            $script:CreatedDraftDashboardId = $deployment.Outputs.DashboardId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty dashboard name" {
            $templateFile = "$PSScriptRoot/../modules/sql-dashboard.bicep"
            $parameters = @{
                DashboardName = ""
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
    if ($script:CreatedDashboardId) {
        Write-Host "Cleaning up SQL dashboard: $($script:CreatedDashboardId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/preview/sql/dashboards/$($script:CreatedDashboardId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup SQL dashboard $($script:CreatedDashboardId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedDraftDashboardId) {
        Write-Host "Cleaning up draft SQL dashboard: $($script:CreatedDraftDashboardId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/preview/sql/dashboards/$($script:CreatedDraftDashboardId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup draft SQL dashboard $($script:CreatedDraftDashboardId): $($_.Exception.Message)"
        }
    }
}
