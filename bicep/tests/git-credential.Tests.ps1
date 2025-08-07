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

Describe "Databricks Git Credential Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a GitHub git credential" {
            $templateFile = "$PSScriptRoot/../modules/git-credential.bicep"
            $parameters = @{
                GitProvider = "gitHub"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                GitUsername = "test-user"
                PersonalAccessToken = "ghp_test_token_$(Get-Random)"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.CredentialId.Value | Should -BeGreaterThan 0
            $deployment.Outputs.GitProvider.Value | Should -Be "gitHub"
            $deployment.Outputs.GitUsername.Value | Should -Be "test-user"
            
            $script:CreatedCredentialId = $deployment.Outputs.CredentialId.Value
        }
        
        It "Should create a GitLab git credential" {
            $templateFile = "$PSScriptRoot/../modules/git-credential.bicep"
            $parameters = @{
                GitProvider = "gitLab"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                GitUsername = "gitlab-user"
                PersonalAccessToken = "glpat-test-token-$(Get-Random)"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.GitProvider.Value | Should -Be "gitLab"
            $deployment.Outputs.GitUsername.Value | Should -Be "gitlab-user"
            
            $script:CreatedGitLabCredentialId = $deployment.Outputs.CredentialId.Value
        }
        
        It "Should create a Bitbucket Cloud git credential without username" {
            $templateFile = "$PSScriptRoot/../modules/git-credential.bicep"
            $parameters = @{
                GitProvider = "bitbucketCloud"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                PersonalAccessToken = "bb_test_token_$(Get-Random)"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.GitProvider.Value | Should -Be "bitbucketCloud"
            
            $script:CreatedBitbucketCredentialId = $deployment.Outputs.CredentialId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid git provider" {
            $templateFile = "$PSScriptRoot/../modules/git-credential.bicep"
            $parameters = @{
                GitProvider = "invalidProvider"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                PersonalAccessToken = "test-token"
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
        
        It "Should fail with empty personal access token" {
            $templateFile = "$PSScriptRoot/../modules/git-credential.bicep"
            $parameters = @{
                GitProvider = "gitHub"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                PersonalAccessToken = ""
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
        # Cleanup git credentials
        if ($script:CreatedCredentialId) {
            Write-Host "Cleaning up git credential: $($script:CreatedCredentialId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/git-credentials/$($script:CreatedCredentialId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup git credential $($script:CreatedCredentialId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedGitLabCredentialId) {
            Write-Host "Cleaning up GitLab git credential: $($script:CreatedGitLabCredentialId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/git-credentials/$($script:CreatedGitLabCredentialId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup GitLab git credential $($script:CreatedGitLabCredentialId): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedBitbucketCredentialId) {
            Write-Host "Cleaning up Bitbucket git credential: $($script:CreatedBitbucketCredentialId)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "DELETE" `
                    -UrlPath "/api/2.0/git-credentials/$($script:CreatedBitbucketCredentialId)" `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup Bitbucket git credential $($script:CreatedBitbucketCredentialId): $($_.Exception.Message)"
            }
        }
    }
}
