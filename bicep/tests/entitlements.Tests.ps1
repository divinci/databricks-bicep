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

Describe "Databricks Entitlements Bicep Module Tests" {
    BeforeAll {
        # Create a test user first
        Write-Host "Creating test user for entitlements tests"
        $userConfig = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:User")
            userName = "test-entitlements-user-$(Get-Random)@example.com"
            displayName = "Test Entitlements User"
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
        It "Should set user entitlements with all permissions" {
            if (-not $script:TestUserId) {
                Set-ItResult -Skipped -Because "Test user creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/entitlements.bicep"
            $parameters = @{
                PrincipalId = $script:TestUserId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AllowClusterCreate = $true
                AllowInstancePoolCreate = $true
                DatabricksSqlAccess = $true
                WorkspaceAccess = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.PrincipalId.Value | Should -Be $script:TestUserId
            $deployment.Outputs.AllowClusterCreate.Value | Should -Be $true
            $deployment.Outputs.AllowInstancePoolCreate.Value | Should -Be $true
            $deployment.Outputs.DatabricksSqlAccess.Value | Should -Be $true
            $deployment.Outputs.WorkspaceAccess.Value | Should -Be $true
            $deployment.Outputs.Entitlements.Value | Should -Not -BeNullOrEmpty
        }
        
        It "Should set user entitlements with limited permissions" {
            if (-not $script:TestUserId) {
                Set-ItResult -Skipped -Because "Test user creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/entitlements.bicep"
            $parameters = @{
                PrincipalId = $script:TestUserId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AllowClusterCreate = $false
                AllowInstancePoolCreate = $false
                DatabricksSqlAccess = $true
                WorkspaceAccess = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AllowClusterCreate.Value | Should -Be $false
            $deployment.Outputs.AllowInstancePoolCreate.Value | Should -Be $false
            $deployment.Outputs.DatabricksSqlAccess.Value | Should -Be $true
            $deployment.Outputs.WorkspaceAccess.Value | Should -Be $true
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty principal ID" {
            $templateFile = "$PSScriptRoot/../modules/entitlements.bicep"
            $parameters = @{
                PrincipalId = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                WorkspaceAccess = $true
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
