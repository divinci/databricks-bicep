BeforeAll {
    Import-Module Pester -Force
    
    $script:TestResourceGroup = "rg-bicep-databricks-test"
    $script:TestLocation = "East US"
    $script:TestWorkspaceUrl = $env:DATABRICKS_WORKSPACE_URL
    $script:TestToken = $env:DATABRICKS_TOKEN
    
    if (-not $script:TestWorkspaceUrl -or -not $script:TestToken) {
        throw "Required environment variables DATABRICKS_WORKSPACE_URL and DATABRICKS_TOKEN must be set"
    }
    
    # Create a test service principal first
    $script:TestApplicationId = ""
}

Describe "Databricks OBO Token Bicep Module Tests" {
    BeforeAll {
        # Create a test service principal first
        Write-Host "Creating test service principal for OBO token tests"
        $spConfig = @{
            schemas = @("urn:ietf:params:scim:schemas:core:2.0:ServicePrincipal")
            applicationId = [System.Guid]::NewGuid().ToString()
            displayName = "Test SP for OBO Token $(Get-Random)"
            active = $true
        } | ConvertTo-Json -Depth 10
        
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $createResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/scim/v2/ServicePrincipals" `
                -Body $spConfig `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            $spResult = $createResponse | ConvertFrom-Json
            $script:TestApplicationId = $spResult.applicationId
            Write-Host "Created test service principal with application ID: $($script:TestApplicationId)"
        }
        catch {
            Write-Warning "Failed to create test service principal: $($_.Exception.Message)"
        }
    }
    
    Context "Positive Path Tests" {
        It "Should create an OBO token with comment" {
            if (-not $script:TestApplicationId) {
                Set-ItResult -Skipped -Because "Test service principal creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/obo-token.bicep"
            $parameters = @{
                ApplicationId = $script:TestApplicationId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Test OBO token for automated testing"
                LifetimeSeconds = 3600
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.TokenId.Value | Should -Not -BeNullOrEmpty
            $deployment.Outputs.ApplicationId.Value | Should -Be $script:TestApplicationId
            $deployment.Outputs.Comment.Value | Should -Be "Test OBO token for automated testing"
            $deployment.Outputs.CreationTime.Value | Should -BeGreaterThan 0
            $deployment.Outputs.ExpiryTime.Value | Should -BeGreaterThan 0
            $deployment.Outputs.TokenValue.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedTokenId = $deployment.Outputs.TokenId.Value
        }
        
        It "Should create an OBO token without lifetime" {
            if (-not $script:TestApplicationId) {
                Set-ItResult -Skipped -Because "Test service principal creation failed"
                return
            }
            
            $templateFile = "$PSScriptRoot/../modules/obo-token.bicep"
            $parameters = @{
                ApplicationId = $script:TestApplicationId
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Comment = "Test OBO token without expiry"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Comment.Value | Should -Be "Test OBO token without expiry"
            
            $script:CreatedNoExpiryTokenId = $deployment.Outputs.TokenId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty application ID" {
            $templateFile = "$PSScriptRoot/../modules/obo-token.bicep"
            $parameters = @{
                ApplicationId = ""
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
    
    AfterAll {
        # Cleanup OBO tokens
        if ($script:CreatedTokenId) {
            Write-Host "Cleaning up OBO token: $($script:CreatedTokenId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/token/delete" `
                    -Body (@{ token_id = $script:CreatedTokenId } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup OBO token $($script:CreatedTokenId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedNoExpiryTokenId) {
            Write-Host "Cleaning up no-expiry OBO token: $($script:CreatedNoExpiryTokenId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/token/delete" `
                    -Body (@{ token_id = $script:CreatedNoExpiryTokenId } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup no-expiry OBO token $($script:CreatedNoExpiryTokenId): $($_.Exception.Message)"
            }
        }
        
        # Cleanup test service principal
        if ($script:TestApplicationId) {
            Write-Host "Cleaning up test service principal: $($script:TestApplicationId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                # First get the service principal ID
                $listResponse = & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "GET" `
                    -UrlPath "/api/2.0/scim/v2/ServicePrincipals?filter=applicationId eq `"$($script:TestApplicationId)`"" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
                
                $spList = $listResponse | ConvertFrom-Json
                if ($spList.Resources -and $spList.Resources.Count -gt 0) {
                    $spId = $spList.Resources[0].id
                    & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                        -Method "DELETE" `
                        -UrlPath "/api/2.0/scim/v2/ServicePrincipals/$spId" `
                        -DatabricksToken $secureToken `
                        -WorkspaceUrl $script:TestWorkspaceUrl
                }
            }
            catch {
                Write-Warning "Failed to cleanup test service principal: $($_.Exception.Message)"
            }
        }
    }
}
