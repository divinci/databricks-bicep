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

Describe "Databricks Workspace Asset Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a Python notebook asset" {
            $templateFile = "$PSScriptRoot/../modules/workspace-asset.bicep"
            $notebookContent = @"
# Databricks notebook source
print("Hello from Bicep test notebook!")

# COMMAND ----------

import pandas as pd
df = pd.DataFrame({'test': [1, 2, 3]})
display(df)
"@
            $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($notebookContent))
            
            $parameters = @{
                AssetPath = "/Shared/test-notebook-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AssetType = "NOTEBOOK"
                Content = $encodedContent
                Language = "PYTHON"
                Format = "SOURCE"
                Overwrite = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.AssetPath.Value | Should -Be $parameters.AssetPath
            $deployment.Outputs.ObjectType.Value | Should -Be "NOTEBOOK"
            $deployment.Outputs.ObjectId.Value | Should -BeGreaterThan 0
            $deployment.Outputs.Language.Value | Should -Be "PYTHON"
            $deployment.Outputs.CreatedAt.Value | Should -BeGreaterThan 0
            $deployment.Outputs.ModifiedAt.Value | Should -BeGreaterThan 0
            
            $script:CreatedNotebookPath = $deployment.Outputs.AssetPath.Value
        }
        
        It "Should create a directory asset" {
            $templateFile = "$PSScriptRoot/../modules/workspace-asset.bicep"
            $parameters = @{
                AssetPath = "/Shared/test-directory-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AssetType = "DIRECTORY"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.ObjectType.Value | Should -Be "DIRECTORY"
            
            $script:CreatedDirectoryPath = $deployment.Outputs.AssetPath.Value
        }
        
        It "Should create a SQL notebook asset" {
            $templateFile = "$PSScriptRoot/../modules/workspace-asset.bicep"
            $sqlContent = @"
-- Databricks notebook source
SELECT 'Hello from Bicep SQL test!' as message

-- COMMAND ----------

SELECT current_timestamp() as test_time
"@
            $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($sqlContent))
            
            $parameters = @{
                AssetPath = "/Shared/test-sql-notebook-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AssetType = "NOTEBOOK"
                Content = $encodedContent
                Language = "SQL"
                Format = "SOURCE"
                Overwrite = $false
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Language.Value | Should -Be "SQL"
            
            $script:CreatedSqlNotebookPath = $deployment.Outputs.AssetPath.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with empty asset path" {
            $templateFile = "$PSScriptRoot/../modules/workspace-asset.bicep"
            $parameters = @{
                AssetPath = ""
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AssetType = "NOTEBOOK"
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
        
        It "Should fail with invalid asset type" {
            $templateFile = "$PSScriptRoot/../modules/workspace-asset.bicep"
            $parameters = @{
                AssetPath = "/Shared/test-invalid"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                AssetType = "INVALID_TYPE"
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
        # Cleanup workspace assets
        if ($script:CreatedNotebookPath) {
            Write-Host "Cleaning up notebook: $($script:CreatedNotebookPath)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/workspace/delete" `
                    -Body (@{ path = $script:CreatedNotebookPath; recursive = $false } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup notebook $($script:CreatedNotebookPath): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedDirectoryPath) {
            Write-Host "Cleaning up directory: $($script:CreatedDirectoryPath)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/workspace/delete" `
                    -Body (@{ path = $script:CreatedDirectoryPath; recursive = $true } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup directory $($script:CreatedDirectoryPath): $($_.Exception.Message)"
            }
        }
        
        if ($script:CreatedSqlNotebookPath) {
            Write-Host "Cleaning up SQL notebook: $($script:CreatedSqlNotebookPath)"
            try {
                $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
                & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                    -Method "POST" `
                    -UrlPath "/api/2.0/workspace/delete" `
                    -Body (@{ path = $script:CreatedSqlNotebookPath; recursive = $false } | ConvertTo-Json) `
                    -DatabricksToken $secureToken `
                    -WorkspaceUrl $script:TestWorkspaceUrl
            }
            catch {
                Write-Warning "Failed to cleanup SQL notebook $($script:CreatedSqlNotebookPath): $($_.Exception.Message)"
            }
        }
    }
}
