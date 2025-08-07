BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create test catalog first
    $script:TestCatalogName = "test_binding_catalog_$(Get-Random)"
    $script:TestWorkspaceId = ""
}

Describe "Databricks Workspace Binding Bicep Module Tests" {
    BeforeAll {
        # Create test catalog for workspace binding
        Write-Host "Creating test catalog: $($script:TestCatalogName)"
        $catalogConfig = @{
            name = $script:TestCatalogName
            comment = "Test catalog for workspace binding tests"
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
            
            # Get current workspace ID
            $workspaceResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "GET" `
                -UrlPath "/api/2.0/workspace/get-status?path=/" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            # Extract workspace ID from URL or use a test value
            $script:TestWorkspaceId = "123456789012345"  # Use a test workspace ID
            
            Write-Host "Created test catalog: $($script:TestCatalogName)"
        }
        catch {
            Write-Warning "Failed to create test catalog: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a workspace binding with read-write access" {
            if (-not $script:TestCatalogName) {
                Set-ItResult -Skipped -Because "Test catalog creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/workspace-binding.bicep"
            $parameters = @{
                CatalogName = $script:TestCatalogName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                WorkspaceId = $script:TestWorkspaceId
                BindingType = "BINDING_TYPE_READ_WRITE"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.CatalogName.Value | Should -Be $script:TestCatalogName
            $deployment.Outputs.WorkspaceId.Value | Should -Be $script:TestWorkspaceId
            $deployment.Outputs.BindingType.Value | Should -Be "BINDING_TYPE_READ_WRITE"
            
            $script:CreatedBindingCatalogName = $deployment.Outputs.CatalogName.Value
            $script:CreatedBindingWorkspaceId = $deployment.Outputs.WorkspaceId.Value
        }
        
        It "Should create a workspace binding with read-only access" {
            if (-not $script:TestCatalogName) {
                Set-ItResult -Skipped -Because "Test catalog creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/workspace-binding.bicep"
            $parameters = @{
                CatalogName = $script:TestCatalogName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                WorkspaceId = "987654321098765"  # Different workspace ID
                BindingType = "BINDING_TYPE_READ_ONLY"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.BindingType.Value | Should -Be "BINDING_TYPE_READ_ONLY"
            
            $script:CreatedReadOnlyBindingWorkspaceId = $deployment.Outputs.WorkspaceId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty catalog name" {
            $templateFile = "$PSScriptRoot/../modules/workspace-binding.bicep"
            $parameters = @{
                CatalogName = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                WorkspaceId = $script:TestWorkspaceId
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
        
        It "Should fail with empty workspace ID" {
            $templateFile = "$PSScriptRoot/../modules/workspace-binding.bicep"
            $parameters = @{
                CatalogName = $script:TestCatalogName
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                WorkspaceId = ""
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
        # Cleanup workspace bindings (they are cleaned up when catalog is deleted)
        # Cleanup test catalog
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
