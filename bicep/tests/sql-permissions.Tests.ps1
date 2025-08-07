BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create test SQL query first
    $script:TestQueryId = ""
}

Describe "Databricks SQL Permissions Bicep Module Tests" {
    BeforeAll {
        # Create a test SQL query for permissions testing
        Write-Host "Creating test SQL query for permissions tests"
        $queryConfig = @{
            name = "test-permissions-query-$(Get-Random)"
            query = "SELECT 'test permissions' as message"
            description = "Test query for permissions tests"
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/sql/queries" `
                -Body $queryConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            $queryResult = $createResponse | ConvertFrom-Json
            $script:TestQueryId = $queryResult.id
            Write-Host "Created test query with ID: $($script:TestQueryId)"
        }
        catch {
            Write-Warning "Failed to create test query: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should set SQL query permissions with CAN_VIEW access" {
            if (-not $script:TestQueryId) {
                Set-ItResult -Skipped -Because "Test query creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/sql-permissions.bicep"
            $parameters = @{
                ObjectId = $script:TestQueryId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "queries"
                AccessControlList = @(
                    @{
                        user_name = "test-viewer@example.com"
                        permission_level = "CAN_VIEW"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ObjectId.Value | Should -Be $script:TestQueryId
            $deployment.Outputs.ObjectType.Value | Should -Be "queries"
            $deployment.Outputs.AccessControlList.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AccessControlList.Value | Should -Match "CAN_VIEW"
        }
        
        It "Should set SQL query permissions with CAN_EDIT access" {
            if (-not $script:TestQueryId) {
                Set-ItResult -Skipped -Because "Test query creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/sql-permissions.bicep"
            $parameters = @{
                ObjectId = $script:TestQueryId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "queries"
                AccessControlList = @(
                    @{
                        user_name = "test-editor@example.com"
                        permission_level = "CAN_EDIT"
                    },
                    @{
                        group_name = "sql-users"
                        permission_level = "CAN_VIEW"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AccessControlList.Value | Should -Match "CAN_EDIT"
            $deployment.Outputs.AccessControlList.Value | Should -Match "sql-users"
        }
        
        It "Should set SQL query permissions with CAN_MANAGE access" {
            if (-not $script:TestQueryId) {
                Set-ItResult -Skipped -Because "Test query creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/sql-permissions.bicep"
            $parameters = @{
                ObjectId = $script:TestQueryId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "queries"
                AccessControlList = @(
                    @{
                        user_name = "test-admin@example.com"
                        permission_level = "CAN_MANAGE"
                    }
                )
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AccessControlList.Value | Should -Match "CAN_MANAGE"
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty object ID" {
            $templateFile = "$PSScriptRoot/../modules/sql-permissions.bicep"
            $parameters = @{
                ObjectId = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "queries"
                AccessControlList = @(
                    @{
                        user_name = "test-user@example.com"
                        permission_level = "CAN_VIEW"
                    }
                )
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
        
        It "Should fail with invalid object type" {
            $templateFile = "$PSScriptRoot/../modules/sql-permissions.bicep"
            $parameters = @{
                ObjectId = $script:TestQueryId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "invalid_sql_type"
                AccessControlList = @(
                    @{
                        user_name = "test-user@example.com"
                        permission_level = "CAN_VIEW"
                    }
                )
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
        
        It "Should fail with empty access control list" {
            $templateFile = "$PSScriptRoot/../modules/sql-permissions.bicep"
            $parameters = @{
                ObjectId = $script:TestQueryId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                ObjectType = "queries"
                AccessControlList = @()
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
        # Cleanup test query
        if ($script:TestQueryId) {
            Write-Host "Cleaning up test query: $($script:TestQueryId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/sql/queries/$($script:TestQueryId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test query: $($_.Exception.Message)"
            }
        }
    }
}
