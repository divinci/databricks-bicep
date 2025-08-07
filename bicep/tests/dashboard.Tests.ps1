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

Describe "Databricks Dashboard Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic Lakeview dashboard" {
            $templateFile = "$PSScriptRoot/../modules/dashboard.bicep"
            $dashboardDefinition = @{
                pages = @(
                    @{
                        name = "Page 1"
                        displayName = "Overview"
                        layout = @(
                            @{
                                widget = @{
                                    name = "widget1"
                                    textbox = @{
                                        content = "# Welcome to Test Dashboard"
                                    }
                                }
                                position = @{
                                    x = 0
                                    y = 0
                                    width = 6
                                    height = 2
                                }
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 10
            
            $parameters = @{
                DashboardName = "test-dashboard-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                SerializedDashboard = $dashboardDefinition
                Parent = "/Shared/test-dashboards"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.DashboardId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.DisplayName.Value | Should -Be $parameters.DashboardName
            $deployment.Outputs.SerializedDashboard.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.ParentPath.Value | Should -Be "/Shared/test-dashboards"
            $deployment.Outputs.CreatedAt.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.UpdatedAt.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Etag.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.Path.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedDashboardId = $deployment.Outputs.DashboardId.Value
        }
        
        It "Should create a dashboard with multiple widgets" {
            $templateFile = "$PSScriptRoot/../modules/dashboard.bicep"
            $complexDashboard = @{
                pages = @(
                    @{
                        name = "analytics"
                        displayName = "Analytics"
                        layout = @(
                            @{
                                widget = @{
                                    name = "title"
                                    textbox = @{
                                        content = "# Analytics Dashboard"
                                    }
                                }
                                position = @{
                                    x = 0
                                    y = 0
                                    width = 12
                                    height = 1
                                }
                            },
                            @{
                                widget = @{
                                    name = "metrics"
                                    textbox = @{
                                        content = "Key metrics and KPIs"
                                    }
                                }
                                position = @{
                                    x = 0
                                    y = 1
                                    width = 6
                                    height = 3
                                }
                            }
                        )
                    }
                )
            } | ConvertTo-Json -Depth 10
            
            $parameters = @{
                DashboardName = "test-complex-dashboard-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                SerializedDashboard = $complexDashboard
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.DisplayName.Value | Should -Be $parameters.DashboardName
            
            $script:CreatedComplexDashboardId = $deployment.Outputs.DashboardId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty dashboard name" {
            $templateFile = "$PSScriptRoot/../modules/dashboard.bicep"
            $parameters = @{
                DashboardName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                SerializedDashboard = "{}"
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
        # Cleanup dashboards
        if ($script:CreatedDashboardId) {
            Write-Host "Cleaning up dashboard: $($script:CreatedDashboardId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/lakeview/dashboards/$($script:CreatedDashboardId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup dashboard $($script:CreatedDashboardId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedComplexDashboardId) {
            Write-Host "Cleaning up complex dashboard: $($script:CreatedComplexDashboardId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/lakeview/dashboards/$($script:CreatedComplexDashboardId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup complex dashboard $($script:CreatedComplexDashboardId): $($_.Exception.Message)"
            }
        }
    }
}
