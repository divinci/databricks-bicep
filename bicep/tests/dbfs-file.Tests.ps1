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

Describe "Databricks DBFS File Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a DBFS file with default content" {
            $templateFile = "$PSScriptRoot/../modules/dbfs-file.bicep"
            $testFilePath = "/tmp/test-file-$(Get-Random).txt"
            $parameters = @{
                FilePath = $testFilePath
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.FilePath.Value | Should -Be $testFilePath
            $deployment.Outputs.FileSize.Value | Should -BeGreaterThan 0
            $deployment.Outputs.IsDirectory.Value | Should -Be $false
            $deployment.Outputs.ModificationTime.Value | Should -BeGreaterThan 0
            
            $script:CreatedFilePath = $deployment.Outputs.FilePath.Value
        }
        
        It "Should create a DBFS file with custom content" {
            $templateFile = "$PSScriptRoot/../modules/dbfs-file.bicep"
            $testFilePath = "/tmp/test-custom-file-$(Get-Random).txt"
            $customContent = "This is custom content for testing DBFS file creation."
            $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($customContent))
            
            $parameters = @{
                FilePath = $testFilePath
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Content = $encodedContent
                Overwrite = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.FilePath.Value | Should -Be $testFilePath
            $deployment.Outputs.FileSize.Value | Should -BeGreaterThan 0
            
            $script:CreatedCustomFilePath = $deployment.Outputs.FilePath.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty file path" {
            $templateFile = "$PSScriptRoot/../modules/dbfs-file.bicep"
            $parameters = @{
                FilePath = ""
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
    if ($script:CreatedFilePath) {
        Write-Host "Cleaning up DBFS file: $($script:CreatedFilePath)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $deleteBody = @{
                path = $script:CreatedFilePath
            } | ConvertTo-Json
            
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/dbfs/delete" `
                -Body $deleteBody `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup DBFS file $($script:CreatedFilePath): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedCustomFilePath) {
        Write-Host "Cleaning up custom DBFS file: $($script:CreatedCustomFilePath)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            $deleteBody = @{
                path = $script:CreatedCustomFilePath
            } | ConvertTo-Json
            
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/dbfs/delete" `
                -Body $deleteBody `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup custom DBFS file $($script:CreatedCustomFilePath): $($_.Exception.Message)"
        }
    }
}
