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

Describe "Databricks Repo Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a GitHub repo" {
            $templateFile = "$PSScriptRoot/../modules/repo.bicep"
            $parameters = @{
                RepoPath = "/Repos/test-github-repo-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Url = "https://github.com/databricks/databricks-cli"
                Provider = "gitHub"
                Branch = "main"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.RepoId.Value | Should -BeGreaterThan 0
            $deployment.Outputs.RepoPath.Value | Should -Be $parameters.RepoPath
            $deployment.Outputs.Url.Value | Should -Be $parameters.Url
            $deployment.Outputs.Provider.Value | Should -Be "gitHub"
            $deployment.Outputs.Branch.Value | Should -Be "main"
            
            $script:CreatedGitHubRepoId = $deployment.Outputs.RepoId.Value
        }
        
        It "Should create a repo with specific tag" {
            $templateFile = "$PSScriptRoot/../modules/repo.bicep"
            $parameters = @{
                RepoPath = "/Repos/test-tag-repo-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Url = "https://github.com/databricks/databricks-cli"
                Provider = "gitHub"
                Tag = "v0.1.0"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.HeadCommitId.Value | Should -Not -BeNullOrEmpty
            
            $script:CreatedTagRepoId = $deployment.Outputs.RepoId.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid repository URL" {
            $templateFile = "$PSScriptRoot/../modules/repo.bicep"
            $parameters = @{
                RepoPath = "/Repos/test-invalid-repo"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Url = "https://invalid-repo-url.com/nonexistent/repo"
                Provider = "gitHub"
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
        
        It "Should fail with empty repo path" {
            $templateFile = "$PSScriptRoot/../modules/repo.bicep"
            $parameters = @{
                RepoPath = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Url = "https://github.com/databricks/databricks-cli"
                Provider = "gitHub"
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
    if ($script:CreatedGitHubRepoId) {
        Write-Host "Cleaning up GitHub repo: $($script:CreatedGitHubRepoId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/repos/$($script:CreatedGitHubRepoId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup GitHub repo $($script:CreatedGitHubRepoId): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedTagRepoId) {
        Write-Host "Cleaning up tag repo: $($script:CreatedTagRepoId)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "DELETE" `
                -UrlPath "/api/2.0/repos/$($script:CreatedTagRepoId)" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup tag repo $($script:CreatedTagRepoId): $($_.Exception.Message)"
        }
    }
}
