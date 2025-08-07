BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    $script:TestAccountId = $env:DATABRICKS_ACCOUNT_ID
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken -or -not $script:TestAccountId) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL, DATABRICKS_TOKEN, and DATABRICKS_ACCOUNT_ID must be set"
    }
    
    # Create a test user first
    $script:TestUserId = ""
}

Describe "Databricks MWS Permission Assignment Bicep Module Tests" {
    BeforeAll {
        # Create a test user first
        Write-Host "Creating test user for MWS permission assignment tests"
        $userConfig = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
            userName = "test-mws-permission-user-$(Get-Random)@example.com"
            displayName = "Test MWS Permission User"
            active = $true
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/scim/v2/Users" `
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
        It "Should create MWS permission assignment with account admin permissions" {
            if (-not $script:TestUserId) {
                Set-ItResult -Skipped -Because "Test user creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/mws-permission-assignment.bicep"
            $parameters = @{
                PrincipalId = $script:TestUserId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                Permissions = @("account.admin")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.PrincipalId.Value | Should -Be $script:TestUserId
            $deployment.Outputs.Permissions.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.AccountId.Value | Should -Be $script:TestAccountId
            
            $script:CreatedAssignmentPrincipalId = $deployment.Outputs.PrincipalId.Value
        }
        
        It "Should create MWS permission assignment with workspace creator permissions" {
            if (-not $script:TestUserId) {
                Set-ItResult -Skipped -Because "Test user creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/mws-permission-assignment.bicep"
            $parameters = @{
                PrincipalId = $script:TestUserId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                Permissions = @("workspace.create")
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Permissions.Value | Should -Match "workspace.create"
            
            $script:CreatedWorkspaceCreatorPrincipalId = $deployment.Outputs.PrincipalId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty principal ID" {
            $templateFile = "$PSScriptRoot/../modules/mws-permission-assignment.bicep"
            $parameters = @{
                PrincipalId = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
                Permissions = @("account.admin")
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
            
            $templateFile = "$PSScriptRoot/../modules/mws-permission-assignment.bicep"
            $parameters = @{
                PrincipalId = $script:TestUserId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AccountId = $script:TestAccountId
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
        # Note: MWS permission assignments are typically cleaned up when the principal is deleted
        # Cleanup test user
        if ($script:TestUserId) {
            Write-Host "Cleaning up test user: $($script:TestUserId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/accounts/$($script:TestAccountId)/scim/v2/Users/$($script:TestUserId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup test user: $($_.Exception.Message)"
            }
        }
    }
}
