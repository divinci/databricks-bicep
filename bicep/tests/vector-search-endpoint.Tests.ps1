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

Describe "Databricks Vector Search Endpoint Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a standard vector search endpoint" {
            $templateFile = "$PSScriptRoot/../modules/vector-search-endpoint.bicep"
            $parameters = @{
                EndpointName = "test-vector-endpoint-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                EndpointType = "STANDARD"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.EndpointName.Value | Should -Be $parameters.EndpointName
            $deployment.Outputs.EndpointType.Value | Should -Be "STANDARD"
            $deployment.Outputs.EndpointStatus.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.CreationTimestamp.Value | Should -BeGreaterThan 0
            $deployment.Outputs.LastUpdatedTimestamp.Value | Should -BeGreaterThan 0
            $deployment.Outputs.Creator.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.NumIndexes.Value | Should -BeGreaterOrEqual 0
            
            $script:CreatedStandardEndpointName = $deployment.Outputs.EndpointName.Value
        }
        
        It "Should create a Databricks managed embeddings vector search endpoint" {
            $templateFile = "$PSScriptRoot/../modules/vector-search-endpoint.bicep"
            $parameters = @{
                EndpointName = "test-managed-endpoint-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                EndpointType = "DATABRICKS_MANAGED_EMBEDDINGS"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.EndpointType.Value | Should -Be "DATABRICKS_MANAGED_EMBEDDINGS"
            
            $script:CreatedManagedEndpointName = $deployment.Outputs.EndpointName.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty endpoint name" {
            $templateFile = "$PSScriptRoot/../modules/vector-search-endpoint.bicep"
            $parameters = @{
                EndpointName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                EndpointType = "STANDARD"
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
        
        It "Should fail with invalid endpoint type" {
            $templateFile = "$PSScriptRoot/../modules/vector-search-endpoint.bicep"
            $parameters = @{
                EndpointName = "test-endpoint"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                EndpointType = "INVALID"
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
        # Cleanup vector search endpoints
        if ($script:CreatedStandardEndpointName) {
            Write-Host "Cleaning up standard vector search endpoint: $($script:CreatedStandardEndpointName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/vector-search/endpoints/$($script:CreatedStandardEndpointName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup standard vector search endpoint $($script:CreatedStandardEndpointName): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedManagedEndpointName) {
            Write-Host "Cleaning up managed vector search endpoint: $($script:CreatedManagedEndpointName)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/vector-search/endpoints/$($script:CreatedManagedEndpointName)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup managed vector search endpoint $($script:CreatedManagedEndpointName): $($_.Exception.Message)"
            }
        }
    }
}
