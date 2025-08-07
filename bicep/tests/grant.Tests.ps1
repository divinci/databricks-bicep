BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test catalog for grant tests
    $script:TestCatalogName = "test_grant_catalog_$(Get-Random)"
    $script:TestPrincipal = "test-user@example.com"
}

Describe "Databricks Grant Bicep Module Tests" {
    BeforeAll {
        # Create a test catalog first
        Write-Host "Creating test catalog: $($script:TestCatalogName)"
        $catalogConfig = @{
            name = $script:TestCatalogName
            comment = "Test catalog for grant tests"
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
        }
        catch {
            Write-Warning "Failed to create test catalog: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create a catalog grant" {
            $templateFile = "$PSScriptRoot/../modules/grant.bicep"
            $parameters = @{
                Principal = $script:TestPrincipal
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                SecurableType = "CATALOG"
                SecurableName = $script:TestCatalogName
                Privileges = @("USE_CATALOG", "USE_SCHEMA")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Principal.Value | Should -Be $script:TestPrincipal
            $deployment.Outputs.SecurableType.Value | Should -Be "CATALOG"
            $deployment.Outputs.SecurableName.Value | Should -Be $script:TestCatalogName
            $deployment.Outputs.Privileges.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedGrantPrincipal = $deployment.Outputs.Principal.Value
            $script:CreatedGrantSecurable = $deployment.Outputs.SecurableName.Value
        }
        
        It "Should create a metastore grant" {
            $templateFile = "$PSScriptRoot/../modules/grant.bicep"
            $parameters = @{
                Principal = "test-group"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                SecurableType = "METASTORE"
                SecurableName = "test-metastore"
                Privileges = @("CREATE_CATALOG", "CREATE_EXTERNAL_LOCATION")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.SecurableType.Value | Should -Be "METASTORE"
            
            $script:CreatedMetastoreGrantPrincipal = $deployment.Outputs.Principal.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty principal" {
            $templateFile = "$PSScriptRoot/../modules/grant.bicep"
            $parameters = @{
                Principal = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                SecurableType = "CATALOG"
                SecurableName = $script:TestCatalogName
                Privileges = @("USE_CATALOG")
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
        # Cleanup grants (revoke permissions)
        if ($script:CreatedGrantPrincipal -and $script:CreatedGrantSecurable) {
            Write-Host "Cleaning up grant for principal: $($script:CreatedGrantPrincipal)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                $revokeConfig = @{
                    principal = $script:CreatedGrantPrincipal
                    securable_type = "CATALOG"
                    securable_name = $script:CreatedGrantSecurable
                    privileges = @("USE_CATALOG", "USE_SCHEMA")
                } | ConvertTo-Json -Depth 10
                
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "PATCH" `
                    -UrlPath "/api/2.1/unity-catalog/permissions/CATALOG/$($script:CreatedGrantSecurable)" `
                    -Body $revokeConfig `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup grant for $($script:CreatedGrantPrincipal): $($_.Exception.Message)"
            }
        }
        
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
