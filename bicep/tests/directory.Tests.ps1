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

Describe "Databricks Directory Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a new directory" {
            $templateFile = "$PSScriptRoot/../modules/directory.bicep"
            $testDirectoryPath = "/Shared/test-directory-$(Get-Random)"
            $parameters = @{
                DirectoryPath = $testDirectoryPath
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.DirectoryPath.Value | Should -Be $testDirectoryPath
            $deployment.Outputs.ObjectType.Value | Should -Be "DIRECTORY"
            $deployment.Outputs.ObjectId.Value | Should -BeGreaterThan 0
            
            $script:CreatedDirectoryPath = $deployment.Outputs.DirectoryPath.Value
        }
        
        It "Should handle existing directory without delete flag" {
            $templateFile = "$PSScriptRoot/../modules/directory.bicep"
            $testDirectoryPath = "/Shared/test-existing-directory-$(Get-Random)"
            
            # Create directory first manually
            $createBody = @{
                path = $testDirectoryPath
            } | ConvertTo-Json
            
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/workspace/mkdirs" `
                -Body $createBody `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
            
            # Now test the module
            $parameters = @{
                DirectoryPath = $testDirectoryPath
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                DeleteExisting = $false
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.DirectoryPath.Value | Should -Be $testDirectoryPath
            
            $script:CreatedExistingDirectoryPath = $deployment.Outputs.DirectoryPath.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty directory path" {
            $templateFile = "$PSScriptRoot/../modules/directory.bicep"
            $parameters = @{
                DirectoryPath = ""
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
}

AfterAll {
    if ($script:CreatedDirectoryPath) {
        Write-Host "Cleaning up directory: $($script:CreatedDirectoryPath)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $deleteBody = @{
                path = $script:CreatedDirectoryPath
                recursive = $true
            } | ConvertTo-Json
            
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/workspace/delete" `
                -Body $deleteBody `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup directory $($script:CreatedDirectoryPath): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedExistingDirectoryPath) {
        Write-Host "Cleaning up existing directory: $($script:CreatedExistingDirectoryPath)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $deleteBody = @{
                path = $script:CreatedExistingDirectoryPath
                recursive = $true
            } | ConvertTo-Json
            
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/workspace/delete" `
                -Body $deleteBody `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup existing directory $($script:CreatedExistingDirectoryPath): $($_.Exception.Message)"
        }
    }
}
