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

Describe "Databricks Notebook Bicep Module Tests" {
    Context "Positive Path Tests" {
        It "Should create a Python notebook with default content" {
            $templateFile = "$PSScriptRoot/../modules/notebook.bicep"
            $parameters = @{
                NotebookPath = "/Shared/test-python-notebook-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Language = "PYTHON"
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.NotebookPath.Value | Should -Be $parameters.NotebookPath
            $deployment.Outputs.Language.Value | Should -Be "PYTHON"
            $deployment.Outputs.ObjectType.Value | Should -Be "NOTEBOOK"
            
            $script:CreatedPythonNotebookPath = $deployment.Outputs.NotebookPath.Value
        }
        
        It "Should create a SQL notebook with custom content" {
            $templateFile = "$PSScriptRoot/../modules/notebook.bicep"
            $customContent = "-- Databricks notebook source`n`nSELECT 'Custom SQL Content' as message"
            $encodedContent = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($customContent))
            
            $parameters = @{
                NotebookPath = "/Shared/test-sql-notebook-$(Get-Random)"
                DatabricksToken = $script:TestToken
                WorkspaceUrl = $script:TestWorkspaceUrl
                Language = "SQL"
                Content = $encodedContent
                Overwrite = $true
            }
            
            $deployment = New-AzResourceGroupDeployment `
                -ResourceGroupName $script:TestResourceGroup `
                -TemplateFile $templateFile `
                -TemplateParameterObject $parameters `
                -Mode Incremental
            
            $deployment.ProvisioningState | Should -Be "Succeeded"
            $deployment.Outputs.Language.Value | Should -Be "SQL"
            
            $script:CreatedSqlNotebookPath = $deployment.Outputs.NotebookPath.Value
        }
    }
    
    Context "Negative Path Tests" {
        It "Should fail with invalid notebook path" {
            $templateFile = "$PSScriptRoot/../modules/notebook.bicep"
            $parameters = @{
                NotebookPath = "invalid-path-without-leading-slash"
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
    if ($script:CreatedPythonNotebookPath) {
        Write-Host "Cleaning up Python notebook: $($script:CreatedPythonNotebookPath)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/workspace/delete" `
                -Body "{`"path`": `"$($script:CreatedPythonNotebookPath)`", `"recursive`": false}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup Python notebook $($script:CreatedPythonNotebookPath): $($_.Exception.Message)"
        }
    }
    
    if ($script:CreatedSqlNotebookPath) {
        Write-Host "Cleaning up SQL notebook: $($script:CreatedSqlNotebookPath)"
        try {
            $secureToken = ConvertTo-SecureString $script:TestToken -AsPlainText -Force
            & "$PSScriptRoot/../helpers/Invoke-DatabricksApi.ps1" `
                -Method "POST" `
                -UrlPath "/api/2.0/workspace/delete" `
                -Body "{`"path`": `"$($script:CreatedSqlNotebookPath)`", `"recursive`": false}" `
                -DatabricksToken $secureToken `
                -WorkspaceUrl $script:TestWorkspaceUrl
        }
        catch {
            Write-Warning "Failed to cleanup SQL notebook $($script:CreatedSqlNotebookPath): $($_.Exception.Message)"
        }
    }
}
