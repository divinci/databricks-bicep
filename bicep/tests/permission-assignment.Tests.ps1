BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test user first
    $script:TestUserId = ""
}

Describe "Databricks Permission Assignment Bicep Module Tests" {
    BeforeAll {
        # Create a test user first
        Write-Host "Creating test user for permission assignment tests"
        $userConfig = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
            userName = "test-permission-user-$(Get-Random)@example.com"
            displayName = "Test Permission User"
            active = $true
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/scim/v2/Users" `
                -Body $userConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            $userResult = $createResponse | ConvertFrom-Json
            $script:TestUserId = $userResult.id
            Write-Host "Created test user with ID: $($script:TestUserId)"
        }
        catch {
            Write-Warning "Failed to create test user: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create permission assignment with workspace admin permissions" {
            if (-not $script:TestUserId) {
                Set-ItResult -Skipped -Because "Test user creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/permission-assignment.bicep"
            $parameters = @{
                PrincipalId = $script:TestUserId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Permissions = @("workspace.admin")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.PrincipalId.Value | Should -Be $script:TestUserId
            $deployment.Outputs.Permissions.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedAssignmentPrincipalId = $deployment.Outputs.PrincipalId.Value
        }
        
        It "Should create permission assignment with multiple permissions" {
            if (-not $script:TestUserId) {
                Set-ItResult -Skipped -Because "Test user creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/permission-assignment.bicep"
            $parameters = @{
                PrincipalId = $script:TestUserId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Permissions = @("clusters.create", "instance-pools.create", "sql.access")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.PrincipalId.Value | Should -Be $script:TestUserId
            
            $script:CreatedMultiplePermissionsPrincipalId = $deployment.Outputs.PrincipalId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty principal ID" {
            $templateFile = "$PSScriptRoot/../modules/permission-assignment.bicep"
            $parameters = @{
                PrincipalId = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Permissions = @("workspace.admin")
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
        
        It "Should fail with empty permissions array" {
            if (-not $script:TestUserId) {
                Set-ItResult -Skipped -Because "Test user creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/permission-assignment.bicep"
            $parameters = @{
                PrincipalId = $script:TestUserId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Permissions = @()
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
        # Note: Permission assignments are typically cleaned up when the principal is deleted
        # Cleanup test user
        if ($script:TestUserId) {
            Write-Host "Cleaning up test user: $($script:TestUserId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/scim/v2/Users/$($script:TestUserId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test user: $($_.Exception.Message)"
            }
        }
    }
}
