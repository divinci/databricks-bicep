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

Describe "Databricks Model Serving Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a basic model serving endpoint" {
            $templateFile = "$PSScriptRoot/../modules/model-serving.bicep"
            $parameters = @{
                EndpointName = "test-endpoint-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Config = @{
                    served_models = @(
                        @{
                            name = "test-model"
                            model_name = "test-model"
                            model_version = "1"
                            workload_size = "Small"
                            scale_to_zero_enabled = $true
                        }
                    )
                }
                Tags = @(
                    @{
                        key = "environment"
                        value = "test"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.EndpointName.Value | Should -Be $parameters.EndpointName
            $deployment.Outputs.EndpointUrl.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.State.Value | Should -BeIn @("UPDATE_SUCCEEDED", "IN_PROGRESS")
            $deployment.Outputs.CreationTimestamp.Value | Should -BeGreaterThan 0
            $deployment.Outputs.Creator.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedEndpointName = $deployment.Outputs.EndpointName.Value
        }
        
        It "Should create a model serving endpoint with rate limits" {
            $templateFile = "$PSScriptRoot/../modules/model-serving.bicep"
            $parameters = @{
                EndpointName = "test-rate-limited-endpoint-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Config = @{
                    served_models = @(
                        @{
                            name = "rate-limited-model"
                            model_name = "test-model"
                            model_version = "1"
                            workload_size = "Small"
                            scale_to_zero_enabled = $true
                        }
                    )
                }
                RateLimits = @(
                    @{
                        calls = 100
                        renewal_period = "minute"
                        key = "user"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.State.Value | Should -BeIn @("UPDATE_SUCCEEDED", "IN_PROGRESS")
            
            $script:CreatedRateLimitedEndpointName = $deployment.Outputs.EndpointName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty endpoint name" {
            $templateFile = "$PSScriptRoot/../modules/model-serving.bicep"
            $parameters = @{
                EndpointName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Config = @{
                    served_models = @()
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
    if ($script:CreatedEndpointName) {
        Write-Host "Cleaning up model serving endpoint: $($script:CreatedEndpointName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/serving-endpoints/$($script:CreatedEndpointName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup model serving endpoint $($script:CreatedEndpointName): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedRateLimitedEndpointName) {
        Write-Host "Cleaning up rate limited model serving endpoint: $($script:CreatedRateLimitedEndpointName)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/serving-endpoints/$($script:CreatedRateLimitedEndpointName)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup rate limited model serving endpoint $($script:CreatedRateLimitedEndpointName): $($_.Exception.Message)"
        }
    }
}
